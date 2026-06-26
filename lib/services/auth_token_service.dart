// lib/services/auth_token_service.dart
// ★ Session token management for authenticated API calls.
// Generates a token at login, stores it, and attaches to every backend request.
// Server validates token against stored session in the 'sessions' sheet.

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'crypto_utils.dart';

class AuthTokenService {
  static const String _kToken = 'auth_session_token';
  static const String _kTokenExpiry = 'auth_token_expiry';
  static const String _kUserId = 'auth_user_id';

  /// Token validity duration (7 days)
  static const Duration tokenValidity = Duration(days: 7);

  /// Generate and store a new session token after login
  static Future<String> generateToken(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final token = CryptoUtils.generateToken();
    final expiry = DateTime.now().add(tokenValidity).toIso8601String();

    await prefs.setString(_kToken, token);
    await prefs.setString(_kTokenExpiry, expiry);
    await prefs.setString(_kUserId, userId);

    return token;
  }

  /// Get current valid token (null if expired or not present)
  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_kToken);
    final expiryStr = prefs.getString(_kTokenExpiry);

    if (token == null || expiryStr == null) return null;

    try {
      final expiry = DateTime.parse(expiryStr);
      if (DateTime.now().isAfter(expiry)) {
        // Token expired — clear it
        await clearToken();
        return null;
      }
      return token;
    } catch (_) {
      return null;
    }
  }

  /// Get the user ID associated with the current token
  static Future<String?> getUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kUserId);
  }

  /// Clear token on sign-out
  static Future<void> clearToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kToken);
    await prefs.remove(_kTokenExpiry);
    await prefs.remove(_kUserId);
  }

  /// Check if we have a valid (non-expired) token
  static Future<bool> isAuthenticated() async {
    return (await getToken()) != null;
  }

  /// Get auth headers to attach to API requests
  static Future<Map<String, String>> getAuthHeaders() async {
    final token = await getToken();
    final userId = await getUserId();
    if (token == null) return {};
    return {
      'X-Auth-Token': token,
      'X-User-Id': userId ?? '',
    };
  }
}
