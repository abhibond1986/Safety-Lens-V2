// Stub for dart:html — used on mobile platforms where dart:html doesn't exist.
// All methods/classes here just satisfy the type-checker; they're never actually called on mobile.

class Blob {
  Blob(List<dynamic> parts, [String? type]);
}

class Url {
  static String createObjectUrlFromBlob(Blob blob) => '';
  static void revokeObjectUrl(String url) {}
}

class AnchorElement {
  AnchorElement({String? href});
  void setAttribute(String name, String value) {}
  void click() {}
}
