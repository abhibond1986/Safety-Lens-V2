// lib/services/pdf_kb_extractor_web.dart
//
// WEB ONLY — compiled only for Flutter Web builds.
// Never import this file directly. Import pdf_kb_extractor.dart instead.
//
// Uses pdf.js 3.11.174 (loaded from cdnjs CDN at runtime).
// Zero new pubspec.yaml dependencies.
//
// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:js' as js;
import 'dart:js_util' as js_util;
import 'dart:typed_data';
import 'package:http/http.dart' as http;

class PdfKbExtractor {
  static const String _appsScriptUrl =
      'https://script.google.com/macros/s/AKfycbzDiT4OSvlDUxvcM9DYJ_-SiB1HyDrgXtYflGfmqJRH9wnZZusj5GqX9frCx64rkd61Rg/exec';

  static const int _chunkSize = 3000;
  static bool _pdfJsLoaded = false;

  static Future<void> _ensurePdfJs() async {
    if (_pdfJsLoaded) return;
    final completer = Completer<void>();
    try {
      final existing = js_util.getProperty(js.context, 'pdfjsLib');
      if (existing != null) { _pdfJsLoaded = true; completer.complete(); }
    } catch (_) {}
    if (_pdfJsLoaded) return;

    final script = html.ScriptElement()
      ..src = 'https://cdnjs.cloudflare.com/ajax/libs/pdf.js/3.11.174/pdf.min.js'
      ..type = 'text/javascript'
      ..async = false;

    script.onLoad.listen((_) {
      js.context.callMethod('eval', [
        "pdfjsLib.GlobalWorkerOptions.workerSrc = "
        "'https://cdnjs.cloudflare.com/ajax/libs/pdf.js/3.11.174/pdf.worker.min.js';"
      ]);
      _pdfJsLoaded = true;
      completer.complete();
    });
    script.onError.listen((_) {
      completer.completeError(
          Exception('Failed to load pdf.js — check internet connection.'));
    });
    html.document.head!.append(script);
    await completer.future;
  }

  static Future<String> extractTextFromPdf(Uint8List pdfBytes) async {
    await _ensurePdfJs();
    // ★ v25 FIX: Use a helper JS function to avoid dart2js Uint8Array constructor issues.
    // Inject a tiny helper once, then call it with the byte list.
    js.context.callMethod('eval', ['''
      if (!window.__safetyLensMakeU8) {
        window.__safetyLensMakeU8 = function(arr) { return new Uint8Array(arr); };
      }
    ''']);
    final jsArray = js.JsObject.jsify(pdfBytes.toList());
    final jsUint8Array = js.context.callMethod('__safetyLensMakeU8', [jsArray]);

    final pdfjsLib = js.context['pdfjsLib'];
    final loadingTask = pdfjsLib.callMethod('getDocument', [
      js.JsObject.jsify({'data': jsUint8Array})
    ]);
    final pdfDoc = await js_util.promiseToFuture<dynamic>(
        js_util.getProperty(loadingTask as Object, 'promise'));
    final int numPages = js_util.getProperty(pdfDoc, 'numPages') as int;
    final buffer = StringBuffer();
    for (int pageNum = 1; pageNum <= numPages; pageNum++) {
      final page = await js_util.promiseToFuture<dynamic>(
          js_util.callMethod(pdfDoc, 'getPage', [pageNum]));
      final textContent = await js_util.promiseToFuture<dynamic>(
          js_util.callMethod(page, 'getTextContent', []));
      final items = js_util.getProperty(textContent, 'items');
      final int len = js_util.getProperty(items, 'length') as int;
      for (int i = 0; i < len; i++) {
        final item = js_util.getProperty(items, i);
        final str = js_util.getProperty(item, 'str')?.toString() ?? '';
        buffer.write('$str ');
      }
      buffer.write('\n');
    }
    return buffer.toString().trim();
  }

  static List<String> _chunkText(String text) {
    final chunks = <String>[];
    int start = 0;
    while (start < text.length) {
      int end = (start + _chunkSize).clamp(0, text.length);
      if (end < text.length) {
        final boundary = text.lastIndexOf('.', end);
        if (boundary > start) end = boundary + 1;
      }
      final chunk = text.substring(start, end).trim();
      if (chunk.isNotEmpty) chunks.add(chunk);
      start = end;
    }
    return chunks;
  }

  static Future<String> _generateKbFromChunk(
      String chunk, String bookTitle) async {
    final prompt =
        'You are a safety knowledge base builder for SAIL.\n\n'
        'Analyze this text from "$bookTitle" and extract key safety knowledge.\n\n'
        "Generate Dart code entries for a keyword→response map:\n\n"
        "      ['keyword1', 'keyword2']:\n"
        "        'Topic Title:\\n\\n• Point 1\\n• Point 2\\n\\nRef: Source',\n\n"
        'Rules:\n'
        '- 2–5 lowercase keywords per entry\n'
        '- Practical safety info only\n'
        '- Bullet points for lists, numbers for procedures\n'
        '- Include regulation refs where present\n'
        '- Generate 3–6 entries per chunk\n'
        '- Output ONLY Dart map entries, no ``` fences\n'
        '- If no safety content: output: // No safety content found in this chunk\n\n'
        'Text:\n---\n$chunk\n---';
    try {
      final response = await http.post(
        Uri.parse(_appsScriptUrl),
        headers: {'Content-Type': 'text/plain'},
        body: jsonEncode({'action': 'gemini', 'prompt': prompt}),
      ).timeout(const Duration(seconds: 30));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        if (data['success'] == true) return data['result']?.toString() ?? '// No result';
        return '// Gemini error: ${data['error']}';
      }
      return '// HTTP ${response.statusCode}';
    } catch (e) {
      return '// Exception: $e';
    }
  }

  static Future<String> processEbook({
    required Uint8List pdfBytes,
    required String bookTitle,
    void Function(int current, int total, String message)? onProgress,
  }) async {
    onProgress?.call(0, 1, 'Extracting text from PDF…');
    final String fullText;
    try {
      fullText = await extractTextFromPdf(pdfBytes);
    } catch (e) {
      return '// ERROR: $e\n// Use Admin Panel → Add Text Entry to paste text manually.';
    }
    if (fullText.trim().isEmpty) {
      return '// ERROR: No text found — PDF may be image-based.\n'
          '// Use Admin Panel → Add Text Entry to paste text manually.';
    }
    final chunks = _chunkText(fullText);
    onProgress?.call(0, chunks.length, 'Text extracted. ${chunks.length} sections…');
    final output = StringBuffer()
      ..writeln('// ═══════════════════════════════════════')
      ..writeln('// KB entries from: $bookTitle')
      ..writeln('// Date: ${DateTime.now().toIso8601String()}')
      ..writeln('// Paste inside the kb map in local_ai.dart')
      ..writeln('// ═══════════════════════════════════════')
      ..writeln();
    int skipped = 0;
    for (int i = 0; i < chunks.length; i++) {
      onProgress?.call(i + 1, chunks.length,
          'Generating KB: section ${i + 1} of ${chunks.length}…');
      final result = await _generateKbFromChunk(chunks[i], bookTitle);
      final trimmed = result.trim();
      if (trimmed.startsWith('// No safety content')) { skipped++; continue; }
      output..writeln('      // — Section ${i + 1} —')..writeln(trimmed)..writeln();
      await Future.delayed(const Duration(milliseconds: 600));
    }
    output
      ..writeln('// Total: ${chunks.length} | With content: ${chunks.length - skipped} | Skipped: $skipped');
    return output.toString();
  }

  static String flagDuplicates(String dartCode) {
    final pattern = RegExp(r"\['([^']+)'");
    final seen = <String, int>{};
    final result = StringBuffer();
    for (final line in dartCode.split('\n')) {
      bool hasDup = false;
      for (final m in pattern.allMatches(line)) {
        final kw = m.group(1)!;
        seen[kw] = (seen[kw] ?? 0) + 1;
        if (seen[kw]! > 1) hasDup = true;
      }
      if (hasDup) result.writeln('// ⚠️ DUPLICATE KEYWORD — review:');
      result.writeln(line);
    }
    return result.toString();
  }
}
