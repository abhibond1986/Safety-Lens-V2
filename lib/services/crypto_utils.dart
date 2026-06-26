// lib/services/crypto_utils.dart
// Secure password hashing and token generation for Safety Lens.
// Uses SHA-256 with per-user salt (no external crypto packages needed).

import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart' show kIsWeb;

class CryptoUtils {
  static final _random = Random.secure();

  /// Generate a random 16-byte hex salt
  static String generateSalt() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Generate a secure random session token (32 bytes hex)
  static String generateToken() {
    final bytes = List<int>.generate(32, (_) => _random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Hash a password with the given salt using SHA-256
  /// Format: sha256(salt + password)
  /// Returns hex-encoded hash string
  static String hashPassword(String password, String salt) {
    final input = utf8.encode('$salt$password');
    // Dart's built-in SHA-256 via digest
    return _sha256(input);
  }

  /// Verify a password against stored hash and salt
  static bool verifyPassword(String password, String salt, String storedHash) {
    final computed = hashPassword(password, salt);
    // Constant-time comparison to prevent timing attacks
    if (computed.length != storedHash.length) return false;
    int result = 0;
    for (int i = 0; i < computed.length; i++) {
      result |= computed.codeUnitAt(i) ^ storedHash.codeUnitAt(i);
    }
    return result == 0;
  }

  /// Pure Dart SHA-256 implementation (no package needed)
  /// Based on FIPS 180-4
  static String _sha256(List<int> message) {
    // Initial hash values (first 32 bits of fractional parts of sqrt of first 8 primes)
    final h = <int>[
      0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
      0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
    ];

    // Round constants (first 32 bits of fractional parts of cube roots of first 64 primes)
    const k = <int>[
      0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5,
      0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
      0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
      0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
      0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
      0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
      0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
      0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
      0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
      0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
      0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
      0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
      0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
      0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
      0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
      0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
    ];

    // Pre-processing: adding padding bits
    final bitLen = message.length * 8;
    message = List<int>.from(message);
    message.add(0x80);
    while (message.length % 64 != 56) {
      message.add(0);
    }
    // Append length as 64-bit big-endian
    for (int i = 56; i >= 0; i -= 8) {
      message.add((bitLen >> i) & 0xff);
    }

    // Process each 512-bit (64-byte) block
    for (int offset = 0; offset < message.length; offset += 64) {
      final w = List<int>.filled(64, 0);

      // Copy block into first 16 words
      for (int i = 0; i < 16; i++) {
        w[i] = (message[offset + i * 4] << 24) |
            (message[offset + i * 4 + 1] << 16) |
            (message[offset + i * 4 + 2] << 8) |
            message[offset + i * 4 + 3];
      }

      // Extend the first 16 words into the remaining 48 words
      for (int i = 16; i < 64; i++) {
        final s0 = _rotr(w[i - 15], 7) ^ _rotr(w[i - 15], 18) ^ (w[i - 15] >>> 3);
        final s1 = _rotr(w[i - 2], 17) ^ _rotr(w[i - 2], 19) ^ (w[i - 2] >>> 10);
        w[i] = _add32(w[i - 16], _add32(s0, _add32(w[i - 7], s1)));
      }

      // Initialize working variables
      int a = h[0], b = h[1], c = h[2], d = h[3];
      int e = h[4], f = h[5], g = h[6], hh = h[7];

      // Compression function main loop
      for (int i = 0; i < 64; i++) {
        final s1 = _rotr(e, 6) ^ _rotr(e, 11) ^ _rotr(e, 25);
        final ch = (e & f) ^ ((~e) & g);
        final temp1 = _add32(hh, _add32(s1, _add32(ch, _add32(k[i], w[i]))));
        final s0 = _rotr(a, 2) ^ _rotr(a, 13) ^ _rotr(a, 22);
        final maj = (a & b) ^ (a & c) ^ (b & c);
        final temp2 = _add32(s0, maj);

        hh = g;
        g = f;
        f = e;
        e = _add32(d, temp1);
        d = c;
        c = b;
        b = a;
        a = _add32(temp1, temp2);
      }

      // Add compressed chunk to current hash value
      h[0] = _add32(h[0], a);
      h[1] = _add32(h[1], b);
      h[2] = _add32(h[2], c);
      h[3] = _add32(h[3], d);
      h[4] = _add32(h[4], e);
      h[5] = _add32(h[5], f);
      h[6] = _add32(h[6], g);
      h[7] = _add32(h[7], hh);
    }

    // Produce the final hash (big-endian)
    final result = StringBuffer();
    for (final val in h) {
      result.write(val.toUnsigned(32).toRadixString(16).padLeft(8, '0'));
    }
    return result.toString();
  }

  /// Rotate right (circular shift)
  static int _rotr(int x, int n) {
    return ((x & 0xFFFFFFFF) >>> n) | ((x << (32 - n)) & 0xFFFFFFFF);
  }

  /// Add two 32-bit integers (with overflow wrapping)
  static int _add32(int a, int b) {
    return (a + b) & 0xFFFFFFFF;
  }

  /// Generate HMAC-SHA256 for API token validation
  static String hmacSha256(String key, String message) {
    final keyBytes = utf8.encode(key);
    final msgBytes = utf8.encode(message);

    // If key > 64 bytes, hash it first
    final normalizedKey = keyBytes.length > 64
        ? utf8.encode(_sha256(keyBytes))
        : keyBytes;

    // Pad key to 64 bytes
    final paddedKey = List<int>.filled(64, 0);
    for (int i = 0; i < normalizedKey.length; i++) {
      paddedKey[i] = normalizedKey[i];
    }

    // Inner and outer padding
    final ipad = paddedKey.map((b) => b ^ 0x36).toList();
    final opad = paddedKey.map((b) => b ^ 0x5c).toList();

    // HMAC = hash(opad || hash(ipad || message))
    final innerHash = _sha256([...ipad, ...msgBytes]);
    final innerHashBytes = <int>[];
    for (int i = 0; i < innerHash.length; i += 2) {
      innerHashBytes.add(int.parse(innerHash.substring(i, i + 2), radix: 16));
    }
    return _sha256([...opad, ...innerHashBytes]);
  }
}
