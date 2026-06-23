// lib/services/openrouter_direct.dart
// ★ v21: DEPRECATED — Direct client-side API calls REMOVED for security.
// API keys were exposed in browser network traffic and detected/disabled by Google.
//
// All AI analysis now goes through Apps Script (server-side) where keys
// are stored safely in Script Properties and never sent to the client.
//
// This file is kept as a stub to prevent import errors.
// DO NOT re-enable direct API calls from the client.

import 'package:flutter/foundation.dart' show Uint8List;

class OpenRouterDirect {
  /// DEPRECATED: Always returns null. Use GeminiVision.analyseImageBytes() instead.
  static Future<Map<String, dynamic>?> analyseImageBytes(Uint8List bytes) async {
    print('OpenRouterDirect: DEPRECATED — use server-side analysis via Apps Script');
    return null;
  }
}
