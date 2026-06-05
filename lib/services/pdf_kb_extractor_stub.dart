// lib/services/pdf_kb_extractor_stub.dart
//
// Android/iOS stub — no dart:html, dart:js, or dart:js_util.
// The eBook-to-KB generator is a web-only Admin Panel feature
// (requires pdf.js which only works in a browser context).
//
// All methods compile and run on Android/iOS but return empty/message results.

import 'dart:typed_data';

class PdfKbExtractor {
  /// Always returns empty string on mobile — no pdf.js available.
  static Future<String> extractTextFromPdf(Uint8List pdfBytes) async {
    return '';
  }

  /// Returns a user-friendly message explaining this is web-only.
  static Future<String> processEbook({
    required Uint8List pdfBytes,
    required String bookTitle,
    void Function(int current, int total, String message)? onProgress,
  }) async {
    onProgress?.call(1, 1, 'Not available on mobile');
    return '// eBook → KB generation is a web-only feature.\n'
        '// Open the SAIL Safety Lens web app (PWA) and use\n'
        '// Admin Panel → eBook → Knowledge Base to generate KB entries.';
  }

  /// No-op on mobile — returns the input unchanged.
  static String flagDuplicates(String dartCode) => dartCode;
}
