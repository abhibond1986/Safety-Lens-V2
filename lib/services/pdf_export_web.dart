// lib/services/pdf_export_web.dart
// Web-only shim — re-exports the 3 dart:html symbols used in pdf_export.dart.
// Never import this file directly; use the conditional import in pdf_export.dart.
// ignore_for_file: avoid_web_libraries_in_flutter
export 'dart:html' show Blob, AnchorElement, Url;
