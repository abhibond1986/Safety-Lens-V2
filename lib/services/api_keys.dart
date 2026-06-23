// lib/services/api_keys.dart
// ★ v21: API keys are NO LONGER fetched client-side.
// All AI calls go through Apps Script where keys are stored
// securely in Script Properties (never exposed to browser).
//
// This file is kept as a stub for backward compatibility
// with any code that still references ApiKeys.

class ApiKeys {
  // No keys are stored or fetched client-side anymore.
  // All AI processing happens server-side via Apps Script.

  static String get googleKey => '';
  static String get openRouterKey => '';

  static bool get hasGoogleKey => false;
  static bool get hasOpenRouterKey => false;

  /// No-op. Kept for backward compatibility.
  /// Keys are stored only in Apps Script Properties (server-side).
  static Future<void> init() async {
    // Intentionally empty — keys never leave the server.
    print('ApiKeys: v21 — keys are server-side only (secure mode)');
  }
}
