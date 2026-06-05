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
      'https://script.google.com/macros/s/AKfycbxLSH2Z-X6iQPw0rY2O7T0SYSDU7bzikpWq-G_ysOT_noU-IwgSHYNr3AKbwPFPZYginw/exec';

  static const int _chunkSize = 3000;
  static bool _pdfJsLoaded = false;

  // ── 1. Load pdf.js from CDN (once per session) ───────────────────────────
  static Future<void> _ensurePdfJs() async {
    if (_pdfJsLoaded) return;
    final completer = Completer<void>();

    // Check if already loaded (e.g. from a previous hot reload)
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
      // Set the worker source immediately after loading
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

  // ── 2. Extract plain text from PDF bytes using pdf.js ────────────────────
  static Future<String> extractTextFromPdf(Uint8List pdfBytes) async {
    await _ensurePdfJs();

    // Convert Dart Uint8List → JS Uint8Array
    final jsUint8Array = js_util.callConstructor(
      js_util.getProperty(js.context, 'Uint8Array'),
      [js_util.jsify(pdfBytes.toList())],
    );

    final pdfjsLib = js_util.getProperty(js.context, 'pdfjsLib');

    // Load PDF document
    final loadingTask = js_util.callMethod(
      pdfjsLib,
      'getDocument',
      [js_util.jsify({'data': jsUint8Array})],
    );
    final pdfDoc = await js_util.promiseToFuture<dynamic>(
        js_util.getProperty(loadingTask, 'promise'));

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

  // ── 3. Split text into ~3000-char chunks at sentence boundaries ──────────
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

  // ── 4. Ask Gemini (via Apps Script) to generate KB entries for one chunk ─
  static Future<String> _generateKbFromChunk(
      String chunk, String bookTitle) async {
    const prompt_prefix =
        'You are a safety knowledge base builder for SAIL (Steel Authority of India Limited).\n\n'
        'Analyze this text and extract key safety knowledge into Dart code entries.\n\n'
        "Follow EXACTLY this format:\n\n"
        "      ['keyword1', 'keyword2']:\n"
        "        'Topic Title:\\n\\n• Point 1\\n• Point 2\\n\\nRef: Source',\n\n"
        'Rules:\n'
        '- 2–5 lowercase keywords per entry\n'
        '- Practical safety info, NOT summaries\n'
        '- Bullet points (•) for lists, numbers for procedures\n'
        '- Include regulation refs (Factories Act, IS, CEA, SMPV, DGMS) where present\n'
        '- Generate 3–6 entries per chunk\n'
        '- Output ONLY Dart map entries — no ``` fences, no explanation\n'
        '- If no safety content: output exactly: // No safety content found in this chunk\n\n';

    final prompt = '${prompt_prefix}Text from "$bookTitle":\n---\n$chunk\n---';

    try {
      final response = await http
          .post(
            Uri.parse(_appsScriptUrl),
            headers: {'Content-Type': 'text/plain'},
            body: jsonEncode({'action': 'gemini', 'prompt': prompt}),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        if (data['success'] == true) {
          return data['result']?.toString() ?? '// No result';
        }
        return '// Gemini error: ${data['error']}';
      }
      return '// HTTP ${response.statusCode}';
    } catch (e) {
      return '// Exception: $e';
    }
  }

  // ── 5. Full pipeline: PDF bytes → ready-to-paste Dart KB code ────────────
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
      return '// ERROR: Could not extract text from PDF.\n'
          '// $e\n'
          '// If this is a scanned PDF, use Admin Panel → Add Text Entry to paste text manually.';
    }

    if (fullText.trim().isEmpty) {
      return '// ERROR: No text found in PDF.\n'
          '// This PDF is likely image-based (scanned).\n'
          '// Use Admin Panel → Add Text Entry to paste text manually.';
    }

    final chunks = _chunkText(fullText);
    onProgress?.call(
        0, chunks.length, 'Text extracted. ${chunks.length} section(s) found…');

    final output = StringBuffer()
      ..writeln('// ═══════════════════════════════════════════════')
      ..writeln('// KB entries generated from: $bookTitle')
      ..writeln('// Date: ${DateTime.now().toIso8601String()}')
      ..writeln('// Paste these inside the `kb` map in local_ai.dart')
      ..writeln('//   Find: final kb = <List<String>, String>{')
      ..writeln('//   Paste before the closing };')
      ..writeln('// ═══════════════════════════════════════════════')
      ..writeln();

    int skipped = 0;
    for (int i = 0; i < chunks.length; i++) {
      onProgress?.call(
          i + 1, chunks.length, 'Generating KB: section ${i + 1} of ${chunks.length}…');

      final result = await _generateKbFromChunk(chunks[i], bookTitle);
      final trimmed = result.trim();

      if (trimmed.startsWith('// No safety content')) {
        skipped++;
        continue;
      }
      output
        ..writeln('      // — Section ${i + 1} ——————————————————————')
        ..writeln(trimmed)
        ..writeln();

      // Slight delay to avoid rate-limiting Apps Script
      await Future.delayed(const Duration(milliseconds: 600));
    }

    output
      ..writeln('// ── Summary ─────────────────────────────────────')
      ..writeln('// Total sections   : ${chunks.length}')
      ..writeln('// With KB content  : ${chunks.length - skipped}')
      ..writeln('// Skipped (no safety content) : $skipped');

    return output.toString();
  }

  // ── 6. Scan output for duplicate keywords and flag them ──────────────────
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
      if (hasDup) {
        result.writeln('// ⚠️  DUPLICATE KEYWORD — review this entry before pasting:');
      }
      result.writeln(line);
    }
    return result.toString();
  }
}
