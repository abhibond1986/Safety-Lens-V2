// lib/services/api_keys.dart
// ★ v20: Runtime API key provider — fetches keys from Apps Script once,
// caches in memory. No hardcoding, no --dart-define needed.

import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiKeys {
  static const String _backendUrl =
      'https://script.google.com/macros/s/AKfycbzDiT4OSvlDUxvcM9DYJ_-SiB1HyDrgXtYflGfmqJRH9wnZZusj5GqX9frCx64rkd61Rg/exec';

  // Cached keys (populated on first call or at app startup)
  static String _googleKey = '';
  static String _openRouterKey = '';
  static bool _fetched = false;

  static String get googleKey => _googleKey.isNotEmpty
      ? _googleKey
      : const String.fromEnvironment('GOOGLE_AI_KEY', defaultValue: '');

  static String get openRouterKey => _openRouterKey.isNotEmpty
      ? _openRouterKey
      : const String.fromEnvironment('OPENROUTER_API_KEY', defaultValue: '');

  static bool get hasGoogleKey => googleKey.isNotEmpty;
  static bool get hasOpenRouterKey => openRouterKey.isNotEmpty;

  /// Fetch keys from Apps Script. Call once at app startup (splash screen).
  /// Safe to call multiple times — no-ops after first success.
  static Future<void> init() async {
    if (_fetched) return;

    try {
      print('ApiKeys: Fetching keys from backend...');
      final response = await http.post(
        Uri.parse(_backendUrl),
        body: jsonEncode({'action': 'getApiKeys'}),
        headers: {'Content-Type': 'text/plain;charset=utf-8'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final body = response.body.trim();
        if (body.isNotEmpty && !body.startsWith('<')) {
          final data = jsonDecode(body);
          if (data['googleKey'] != null && data['googleKey'].toString().isNotEmpty) {
            _googleKey = data['googleKey'];
          }
          if (data['openRouterKey'] != null && data['openRouterKey'].toString().isNotEmpty) {
            _openRouterKey = data['openRouterKey'];
          }
          _fetched = true;
          print('ApiKeys: ✓ Keys loaded (google=${_googleKey.isNotEmpty}, openrouter=${_openRouterKey.isNotEmpty})');
        }
      }
    } catch (e) {
      print('ApiKeys: Failed to fetch keys ($e) — will use --dart-define fallback');
    }
  }
}
