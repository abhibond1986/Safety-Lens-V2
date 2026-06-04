// lib/services/pdf_kb_extractor.dart
//
// Zero new dependencies. Zero Apps Script changes.
//
// Strategy:
//   1. Use dart:html to inject pdf.js from CDN
//   2. Pass PDF bytes safely via JS interop (no string size limits)
//   3. Extract plain text page by page
//   4. Chunk text and send to existing Apps Script `gemini` action
//
// Requirements: NO new pubspec.yaml entries.
// Uses only: dart:html, dart:js, dart:convert, dart:typed_data, package:http

// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:async';
import 'dart:convert';
import 'dart:js' as js;
import 'dart:js_util' as js_util;
import 'dart:typed_data';
import 'package:http/http.dart' as http;

class PdfKbExtractor {
  static const String _appsScriptUrl =
      'https://script.google.com/macros/s/AKfycbxLSH2Z-X6iQPw0rY2O7T0SYSDU7bzikpWq-G_ysOT_noU-IwgSHYNr3AKbwPFPZYginw/exec';

  static const int _chunkSize = 3000; // chars per Gemini call

  static bool _pdfJsLoaded = false;

  // ── 1. Load pdf.js from CDN ───────────────────────────────────────────────
  static Future<void> _ensurePdfJs() async {
    if (_pdfJsLoaded) return;

    final completer = Completer<void>();

    final script = html.ScriptElement()
      ..src = 'https://cdnjs.cloudflare.com/ajax/libs/pdf.js/3.11.174/pdf.min.js'
      ..type = 'text/javascript';

    script.onLoad.listen((_) {
      // Set worker source
      js.context.callMethod('eval', [
        "pdfjsLib.GlobalWorkerOptions.workerSrc = "
        "'https://cdnjs.cloudflare.com/ajax/libs/pdf.js/3.11.174/pdf.worker.min.js';"
      ]);
      _pdfJsLoaded = true;
      completer.complete();
    });

    script.onError.listen((_) {
      completer.completeError(
          Exception('Failed to load pdf.js. Check internet connection.'));
    });

    html.document.head!.append(script);
    await completer.future;
  }

  // ── 2. Extract text from PDF bytes ────────────────────────────────────────
  static Future<String> extractTextFromPdf(Uint8List pdfBytes) async {
    await _ensurePdfJs();

    // Convert Dart Uint8List → JS Uint8Array safely via dart:js_util
    final jsUint8Array = js_util.callConstructor(
      js_util.getProperty(js.context, 'Uint8Array'),
      [js_util.jsify(pdfBytes.toList())],
    );

    final pdfjsLib = js_util.getProperty(js.context, 'pdfjsLib');

    // getDocument returns a PDFDocumentLoadingTask with a .promise
    final loadingTask = js_util.callMethod(pdfjsLib, 'getDocument',
        [js_util.jsify({'data': jsUint8Array})]);
    final pdfDoc =
        await js_util.promiseToFuture(js_util.getProperty(loadingTask, 'promise'));

    final int numPages = js_util.getProperty(pdfDoc, 'numPages') as int;
    final StringBuffer buffer = StringBuffer();

    for (int pageNum = 1; pageNum <= numPages; pageNum++) {
      final page = await js_util.promiseToFuture(
          js_util.callMethod(pdfDoc, 'getPage', [pageNum]));
      final textContent = await js_util.promiseToFuture(
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

  // ── 3. Chunk text at sentence boundaries ─────────────────────────────────
  static List<String> _chunkText(String text) {
    final chunks = <String>[];
    int start = 0;
    while (start < text.length) {
      int end = start + _chunkSize;
      if (end < text.length) {
        final boundary = text.lastIndexOf('.', end);
        if (boundary > start) end = boundary + 1;
      } else {
        end = text.length;
      }
      final chunk = text.substring(start, end).trim();
      if (chunk.isNotEmpty) chunks.add(chunk);
      start = end;
    }
    return chunks;
  }

  // ── 4. Send one text chunk to existing Apps Script `gemini` action ────────
  static Future<String> _generateKbFromChunk(
      String chunk, String bookTitle) async {
    final prompt =
        'You are a safety knowledge base builder for SAIL (Steel Authority of India Limited).\n\n'
        'Analyze this text from the safety eBook "$bookTitle" and extract key safety knowledge.\n\n'
        'Generate Dart code entries for a keyword→response map. Follow EXACTLY this format:\n\n'
        "      ['keyword1', 'keyword2', 'keyword3']:\n"
        "        'Topic Title:\\n\\n• Point 1\\n• Point 2\\n• Point 3\\n\\nRef: Source/Standard',\n\n"
        'Rules:\n'
        '- Each entry must have 2–5 relevant lowercase keywords\n'
        '- Response must be practical safety info, NOT a summary\n'
        '- Use bullet points (•) and numbered lists for procedures\n'
        '- Include regulation refs (Factories Act, IS standards, DGMS, SAIL SOPs) where found\n'
        '- Generate 3 to 6 entries per chunk\n'
        '- Output ONLY the Dart map entries — no explanation, no ```dart fences\n'
        '- If no safety content: output exactly: // No safety content found in this chunk\n\n'
        'Text:\n---\n$chunk\n---';

    try {
      final response = await http.post(
        Uri.parse(_appsScriptUrl),
        headers: {'Content-Type': 'text/plain'},
        body: jsonEncode({'action': 'gemini', 'prompt': prompt}),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          return data['result']?.toString() ?? '// No result returned';
        }
        return '// Gemini error: ${data['error']}';
      }
      return '// HTTP error ${response.statusCode}';
    } catch (e) {
      return '// Exception: $e';
    }
  }

  // ── 5. Full pipeline — called from Admin Panel ────────────────────────────
  static Future<String> processEbook({
    required Uint8List pdfBytes,
    required String bookTitle,
    void Function(int current, int total, String message)? onProgress,
  }) async {
    onProgress?.call(0, 1, 'Loading pdf.js and extracting text…');

    final String fullText;
    try {
      fullText = await extractTextFromPdf(pdfBytes);
    } catch (e) {
      return '// ERROR extracting PDF text: $e\n'
          '// PDF may be image-based (scanned). '
          'Use Admin Panel → Add Text Entry to paste text manually.';
    }

    if (fullText.isEmpty) {
      return '// ERROR: No text found in PDF.\n'
          '// PDF may be scanned/image-based. '
          'Use Admin Panel → Add Text Entry to paste text manually.';
    }

    final chunks = _chunkText(fullText);
    onProgress?.call(0, chunks.length,
        'Text extracted. Split into ${chunks.length} section(s)…');

    final output = StringBuffer()
      ..writeln('// ═══════════════════════════════════════════════════════')
      ..writeln('// KB entries generated from: $bookTitle')
      ..writeln('// Generated: ${DateTime.now().toIso8601String()}')
      ..writeln('// Paste entries inside the `kb` map in local_ai.dart')
      ..writeln('// ═══════════════════════════════════════════════════════')
      ..writeln();

    int skipped = 0;
    for (int i = 0; i < chunks.length; i++) {
      onProgress?.call(i + 1, chunks.length,
          'Generating KB: section ${i + 1} of ${chunks.length}…');

      final result = await _generateKbFromChunk(chunks[i], bookTitle);
      final trimmed = result.trim();

      if (trimmed.startsWith('// No safety content')) {
        skipped++;
        continue;
      }

      output
        ..writeln('      // — Section ${i + 1} —')
        ..writeln(trimmed)
        ..writeln();

      await Future.delayed(const Duration(milliseconds: 500));
    }

    output
      ..writeln('// ── Summary ─────────────────────────────────────────────')
      ..writeln('// Total sections : ${chunks.length}')
      ..writeln('// With safety content : ${chunks.length - skipped}')
      ..writeln('// Skipped : $skipped');

    return output.toString();
  }

  // ── 6. Flag duplicate keywords in output ─────────────────────────────────
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
      if (hasDup) result.writeln('// ⚠️ DUPLICATE KEYWORD — review this entry:');
      result.writeln(line);
    }
    return result.toString();
  }
}
