import 'package:flutter_test/flutter_test.dart';

// Test the version comparison logic (extracted for testability)
bool isNewerVersion(String remote, String current) {
  try {
    final remoteParts = remote.split('.').map(int.parse).toList();
    final currentParts = current.split('.').map(int.parse).toList();
    while (remoteParts.length < 3) remoteParts.add(0);
    while (currentParts.length < 3) currentParts.add(0);
    for (int i = 0; i < 3; i++) {
      if (remoteParts[i] > currentParts[i]) return true;
      if (remoteParts[i] < currentParts[i]) return false;
    }
    return false;
  } catch (_) {
    return false;
  }
}

void main() {
  group('Version comparison', () {
    test('higher patch version is newer', () {
      expect(isNewerVersion('1.0.48', '1.0.46'), true);
    });

    test('same version is not newer', () {
      expect(isNewerVersion('1.0.46', '1.0.46'), false);
    });

    test('lower version is not newer', () {
      expect(isNewerVersion('1.0.45', '1.0.46'), false);
    });

    test('higher minor version is newer', () {
      expect(isNewerVersion('1.1.0', '1.0.99'), true);
    });

    test('higher major version is newer', () {
      expect(isNewerVersion('2.0.0', '1.9.9'), true);
    });

    test('handles two-part versions', () {
      expect(isNewerVersion('1.1', '1.0.5'), true);
    });

    test('handles invalid version strings', () {
      expect(isNewerVersion('abc', '1.0.0'), false);
      expect(isNewerVersion('', '1.0.0'), false);
    });
  });
}
