// lib/services/pdf_kb_extractor.dart
//
// Platform router — conditional export selects the right implementation:
//
//   Web (Flutter Web PWA, dart.library.html available):
//     → pdf_kb_extractor_web.dart   (uses pdf.js via dart:html / dart:js)
//
//   Mobile (Android / iOS, dart.library.html NOT available):
//     → pdf_kb_extractor_stub.dart  (no-op stubs, compiles cleanly)
//
// Import this file everywhere in the app.
// Never import pdf_kb_extractor_web.dart directly.

// ignore: uri_does_not_exist
export 'pdf_kb_extractor_stub.dart'
    if (dart.library.html) 'pdf_kb_extractor_web.dart';
