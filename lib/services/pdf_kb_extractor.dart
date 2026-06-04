// lib/services/pdf_kb_extractor.dart
//
// Extracts text from an uploaded PDF eBook and uses Gemini (via Apps Script)
// to generate structured KB entries that can be pasted into local_ai.dart.
//
// Dependencies to add in pubspec.yaml:
//   syncfusion_flutter_pdf: ^25.1.41

import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:syncfusion_flutter_pdf/pdf.dart';

class PdfKbExtractor {
  // ── Apps Script endpoint (same one used everywhere else) ──────────────────
  static const String _appsScriptUrl =
      'https://script.google.com/macros/s/AKfycbxLSH2Z-X6iQPw0rY2O7T0SYSDU7bzikpWq-G_ysOT_noU-IwgSHYNr3AKbwPFPZYginw/exec';

  // Max characters per chunk sent to Gemini (keep under token limit)
  static const int _chunkSize = 3000;

  // ── STEP 1 : Extract plain text from PDF bytes ────────────────────────────
  static String extractTextFromPdf(Uint8List pdfBytes) {
    final PdfDocument document = PdfDocument(inputBytes: pdfBytes);
    final StringBuffer buffer = StringBuffer();

    for (int i = 0; i < document.pages.count; i++) {
      final String pageText =
          PdfTextExtractor(document).extractText(startPageIndex: i, endPageIndex: i);
      buffer.write(pageText);
      buffer.write('\n');
    }

    document.dispose();
    return buffer.toString().trim();
  }

  // ── STEP 2 : Split text into manageable chunks ────────────────────────────
  static List<String> _chunkText(String text) {
    final List<String> chunks = [];
    int start = 0;
    while (start < text.length) {
      int end = start + _chunkSize;
      if (end < text.length) {
        // Try to break at a sentence boundary
        final int boundary = text.lastIndexOf('.', end);
        if (boundary > start) end = boundary + 1;
      } else {
        end = text.length;
      }
      chunks.add(text.substring(start, end).trim());
      start = end;
    }
    return chunks.where((c) => c.isNotEmpty).toList();
  }

  // ── STEP 3 : Ask Gemini to generate KB entries from a text chunk ──────────
  static Future<String> _generateKbFromChunk(String chunk, String bookTitle) async {
    final String prompt = '''
You are a safety knowledge base builder for SAIL (Steel Authority of India Limited).

Analyze this text from the eBook titled "$bookTitle" and extract key safety knowledge.

Generate Dart code entries for a keyword→response map. Follow EXACTLY this format:

      ['keyword1', 'keyword2', 'keyword3']:
        'Topic Title:\\n\\n• Point 1\\n• Point 2\\n• Point 3\\n\\nRef: Source/Standard',

Rules:
- Each entry must have 2-5 relevant lowercase keywords (single words or short phrases)
- Response must be practical safety information, NOT a book summary
- Use bullet points (•), numbered lists for procedures
- Include regulation references where present in the text (Factories Act, IS standards, DGMS, etc.)
- Generate 3 to 6 entries per chunk
- Output ONLY the Dart map entries, no explanation, no ```dart fences, no imports
- If the text has no safety-relevant content, output: // No safety content found in this chunk

Text to analyze:
---
$chunk
---
''';

    try {
      final response = await http.post(
        Uri.parse(_appsScriptUrl),
        headers: {'Content-Type': 'text/plain'},
        body: jsonEncode({
          'action': 'gemini',
          'prompt': prompt,
        }),
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

  // ── STEP 4 : Process full PDF and return ready-to-paste Dart code ─────────
  /// [pdfBytes]      — raw bytes of the uploaded PDF
  /// [bookTitle]     — display name of the eBook
  /// [onProgress]    — callback(current, total, message) for UI progress bar
  ///
  /// Returns a String of Dart code ready to paste inside the `kb` map
  /// in `local_ai.dart`  →  static String chat(String question) { ... }
  static Future<String> processEbook({
    required Uint8List pdfBytes,
    required String bookTitle,
    void Function(int current, int total, String message)? onProgress,
  }) async {
    // 1. Extract text
    onProgress?.call(0, 1, 'Extracting text from PDF…');
    final String fullText = extractTextFromPdf(pdfBytes);

    if (fullText.isEmpty) {
      return '// ERROR: Could not extract text. PDF may be image-based (scanned). '
          'Use OCR first or copy-paste text manually via Admin Panel.';
    }

    // 2. Chunk
    final List<String> chunks = _chunkText(fullText);
    onProgress?.call(0, chunks.length, 'Split into ${chunks.length} sections…');

    // 3. Generate KB entries per chunk
    final StringBuffer output = StringBuffer();
    output.writeln('// ═══════════════════════════════════════════════════════');
    output.writeln('// KB entries generated from: $bookTitle');
    output.writeln('// Generated: ${DateTime.now().toIso8601String()}');
    output.writeln('// Paste these entries inside the `kb` map in local_ai.dart');
    output.writeln('// ═══════════════════════════════════════════════════════');
    output.writeln();

    int skipped = 0;
    for (int i = 0; i < chunks.length; i++) {
      onProgress?.call(i + 1, chunks.length, 'Processing section ${i + 1} of ${chunks.length}…');

      final String result = await _generateKbFromChunk(chunks[i], bookTitle);
      final String trimmed = result.trim();

      if (trimmed.startsWith('// No safety content')) {
        skipped++;
        continue;
      }

      output.writeln('      // — Section ${i + 1} —');
      output.writeln(trimmed);
      output.writeln();

      // Small delay to avoid hammering Apps Script
      await Future.delayed(const Duration(milliseconds: 500));
    }

    output.writeln('// ── Summary ─────────────────────────────────────────────');
    output.writeln('// Total chunks processed : ${chunks.length}');
    output.writeln('// Chunks with safety content: ${chunks.length - skipped}');
    output.writeln('// Chunks skipped (no safety content): $skipped');

    return output.toString();
  }

  // ── STEP 5 : Deduplicate keywords across the generated output ─────────────
  /// Scans generated Dart code for duplicate keyword arrays and flags them
  /// so the developer can review before pasting.
  static String flagDuplicates(String dartCode) {
    final RegExp keywordPattern = RegExp(r"\['([^']+)'");
    final Map<String, int> seen = {};
    final List<String> lines = dartCode.split('\n');
    final StringBuffer result = StringBuffer();

    for (final line in lines) {
      final matches = keywordPattern.allMatches(line);
      bool hasDuplicate = false;
      for (final m in matches) {
        final kw = m.group(1)!;
        seen[kw] = (seen[kw] ?? 0) + 1;
        if (seen[kw]! > 1) hasDuplicate = true;
      }
      if (hasDuplicate) {
        result.writeln('// ⚠️ DUPLICATE KEYWORD DETECTED — review this entry:');
      }
      result.writeln(line);
    }
    return result.toString();
  }
}
