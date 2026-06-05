// lib/services/pdf_export_stub.dart
//
// Stub that replaces dart:html on Android/iOS builds.
// Imported as 'html' alias — provides same surface as dart:html
// for the three symbols used in pdf_export.dart.
//
// On web: dart:html is used directly (real implementation).
// On Android/iOS: this file is used (all methods are no-ops).

// ignore_for_file: avoid_classes_with_only_static_members

class Blob {
  Blob(List<dynamic> parts, String type);
}

class Url {
  static String createObjectUrlFromBlob(dynamic blob) => '';
  static void revokeObjectUrl(String url) {}
}

class AnchorElement {
  final String? href;
  AnchorElement({this.href});
  void setAttribute(String name, String value) {}
  void click() {}
}
