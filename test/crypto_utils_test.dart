import 'package:flutter_test/flutter_test.dart';
import 'package:safety_lens/services/crypto_utils.dart';

void main() {
  group('CryptoUtils', () {
    test('generateSalt produces 32-char hex string', () {
      final salt = CryptoUtils.generateSalt();
      expect(salt.length, 32);
      expect(RegExp(r'^[0-9a-f]+$').hasMatch(salt), true);
    });

    test('generateToken produces 64-char hex string', () {
      final token = CryptoUtils.generateToken();
      expect(token.length, 64);
      expect(RegExp(r'^[0-9a-f]+$').hasMatch(token), true);
    });

    test('generateSalt produces unique values', () {
      final salts = List.generate(10, (_) => CryptoUtils.generateSalt());
      expect(salts.toSet().length, 10); // All unique
    });

    test('hashPassword produces consistent output', () {
      const password = 'testPassword123';
      const salt = 'abcdef0123456789abcdef0123456789';
      final hash1 = CryptoUtils.hashPassword(password, salt);
      final hash2 = CryptoUtils.hashPassword(password, salt);
      expect(hash1, hash2); // Deterministic
      expect(hash1.length, 64); // SHA-256 = 64 hex chars
    });

    test('hashPassword produces different output with different salts', () {
      const password = 'testPassword123';
      const salt1 = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
      const salt2 = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
      final hash1 = CryptoUtils.hashPassword(password, salt1);
      final hash2 = CryptoUtils.hashPassword(password, salt2);
      expect(hash1, isNot(equals(hash2)));
    });

    test('verifyPassword returns true for correct password', () {
      const password = 'mySecurePass!';
      final salt = CryptoUtils.generateSalt();
      final hash = CryptoUtils.hashPassword(password, salt);
      expect(CryptoUtils.verifyPassword(password, salt, hash), true);
    });

    test('verifyPassword returns false for wrong password', () {
      const password = 'mySecurePass!';
      const wrongPassword = 'wrongPassword';
      final salt = CryptoUtils.generateSalt();
      final hash = CryptoUtils.hashPassword(password, salt);
      expect(CryptoUtils.verifyPassword(wrongPassword, salt, hash), false);
    });

    test('verifyPassword returns false for wrong salt', () {
      const password = 'mySecurePass!';
      final salt = CryptoUtils.generateSalt();
      final wrongSalt = CryptoUtils.generateSalt();
      final hash = CryptoUtils.hashPassword(password, salt);
      expect(CryptoUtils.verifyPassword(password, wrongSalt, hash), false);
    });

    test('SHA-256 known test vector', () {
      // NIST test vector: SHA-256("abc") = ba7816bf...
      final hash = CryptoUtils.hashPassword('bc', 'a'); // salt + password = "abc"
      expect(hash, 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
    });

    test('hmacSha256 produces consistent output', () {
      const key = 'secret-key';
      const msg = 'hello world';
      final hmac1 = CryptoUtils.hmacSha256(key, msg);
      final hmac2 = CryptoUtils.hmacSha256(key, msg);
      expect(hmac1, hmac2);
      expect(hmac1.length, 64);
    });
  });
}
