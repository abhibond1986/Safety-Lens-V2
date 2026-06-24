// lib/services/gemini_vision.dart
// ★ v21 SECURE ARCHITECTURE — All AI calls through Apps Script only
//
// PRIORITY CHAIN (stops at first success):
//   1. Apps Script (server-side Gemini/OpenRouter — keys never leave server)
//   2. Offline fallback (instant, knowledge-based)
//
// KEY CHANGES FROM v20:
//   ✅ REMOVED direct Gemini/OpenRouter calls (keys were exposed in browser)
//   ✅ API keys NEVER sent to client — stored only in Script Properties
//   ✅ Single path: App → Apps Script → AI (keys hidden server-side)
//   ✅ Cloudinary upload moved to Apps Script (already supported)
//   ✅ Faster: no wasted time on quota-blocked direct calls

import 'dart:convert';
import 'dart:async';
import 'dart:io' show File;
import 'package:flutter/foundation.dart' show Uint8List, kIsWeb;
import 'package:http/http.dart' as http;
import 'network_checker.dart';
// admin_master_data import removed — no longer needed after offline library removal

class GeminiVision {
  static const String _backendUrl =
      'https://script.google.com/macros/s/AKfycbzDiT4OSvlDUxvcM9DYJ_-SiB1HyDrgXtYflGfmqJRH9wnZZusj5GqX9frCx64rkd61Rg/exec';

  // ✅ FIX: Cooldown to prevent hammering exhausted server
  static DateTime? _lastExhaustionTime;
  static const Duration _exhaustionCooldown = Duration(seconds: 60);

  // ✅ FIX: Track last successful call to apply rate-limiting between analyses
  static DateTime? _lastCallTime;
  static const Duration _minCallInterval = Duration(seconds: 5);

  // ✅ FIX: Prevent concurrent AI calls (second call waits or skips)
  static bool _isAnalyzing = false;

  // ── analyseImage (mobile / File path) ─────────────────────────────────────
  static Future<Map<String, dynamic>?> analyseImage(File imageFile) async {
    final bytes = await imageFile.readAsBytes();
    return analyseImageBytes(bytes);
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  MAIN ENTRY: SECURE SERVER-SIDE ANALYSIS
  // ══════════════════════════════════════════════════════════════════════════
  static Future<Map<String, dynamic>?> analyseImageBytes(Uint8List bytes,
      {int retryCount = 0}) async {
    final stopwatch = Stopwatch()..start();

    try {
      print('GeminiVision: ═══ STARTING ANALYSIS ═══ (${bytes.length} bytes)');

      // ✅ FIX: Prevent concurrent analysis — if one is already running, wait briefly then fallback
      if (_isAnalyzing) {
        print('GeminiVision: ⚠ Another analysis already in progress — waiting...');
        // Wait up to 30s for the other call to finish
        for (int i = 0; i < 60; i++) {
          await Future.delayed(const Duration(milliseconds: 500));
          if (!_isAnalyzing) break;
        }
        if (_isAnalyzing) {
          print('GeminiVision: ⚠ Other analysis still running after 30s — offline fallback');
          return await _offlineFallback(bytes, reason: 'Another analysis in progress');
        }
      }
      _isAnalyzing = true;

      // ✅ FIX: Rate-limit: don't fire again within 5s of last call (quota protection)
      if (_lastCallTime != null &&
          DateTime.now().difference(_lastCallTime!) < _minCallInterval) {
        final wait = _minCallInterval - DateTime.now().difference(_lastCallTime!);
        print('GeminiVision: Rate-limiting — waiting ${wait.inSeconds}s before next call');
        await Future.delayed(wait);
      }

      // ✅ FIX: Skip server if providers were exhausted recently (cooldown)
      if (_lastExhaustionTime != null &&
          DateTime.now().difference(_lastExhaustionTime!) < _exhaustionCooldown) {
        final remaining = _exhaustionCooldown.inSeconds -
            DateTime.now().difference(_lastExhaustionTime!).inSeconds;
        print('GeminiVision: ▶ Server cooldown active (${remaining}s remaining) → offline fallback');
        _isAnalyzing = false;
        return await _offlineFallback(bytes,
            reason: 'AI providers cooling down (retry in ${remaining}s)');
      }

      // ── Network check (mobile only) ──
      if (!kIsWeb) {
        final networkStatus = await NetworkChecker.getNetworkStatus();
        if (!networkStatus['hasInternet']!) {
          print('GeminiVision: No internet → offline fallback');
          _isAnalyzing = false;
          return await _offlineFallback(bytes, reason: 'No internet connection');
        }
      }

      // ══════════════════════════════════════════════════════════════════════
      // APPS SCRIPT: Server-side AI (keys safe in Script Properties)
      // ══════════════════════════════════════════════════════════════════════
      print('GeminiVision: ▶ Sending to Apps Script (server-side AI)...');
      try {
        final appsResult = await _callAppsScript(bytes);
        if (appsResult != null &&
            appsResult['hazards'] != null &&
            (appsResult['hazards'] as List).isNotEmpty &&
            appsResult['error'] == null) {
          print('GeminiVision: ✓ SUCCESS in ${stopwatch.elapsedMilliseconds}ms');
          _lastCallTime = DateTime.now();
          _isAnalyzing = false;
          return appsResult;
        }
        if (appsResult != null && appsResult['error'] != null) {
          print('GeminiVision: ✗ Server returned error: ${appsResult['error']}');
        } else {
          print('GeminiVision: ✗ Server failed (null or no hazards)');
        }
      } catch (e) {
        print('GeminiVision: ✗ Apps Script exception: $e');
      }

      // ══════════════════════════════════════════════════════════════════════
      // NO CLIENT-SIDE RETRY — server already has model fallbacks internally
      // (retrying just doubles wait time from 90s to 180s)
      // ══════════════════════════════════════════════════════════════════════
      print('GeminiVision: ▶ Offline fallback (server unavailable)');
      print('GeminiVision: Total time elapsed: ${stopwatch.elapsedMilliseconds}ms');
      _lastCallTime = DateTime.now();
      _isAnalyzing = false;
      return await _offlineFallback(bytes,
          reason: 'AI server unavailable after ${stopwatch.elapsedMilliseconds}ms');
    } catch (e) {
      print('GeminiVision: Unexpected top-level error: $e');
      _isAnalyzing = false;
      return await _offlineFallback(bytes, reason: e.toString());
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  APPS SCRIPT CALL — all AI processing server-side, keys never exposed
  // ══════════════════════════════════════════════════════════════════════════
  static Future<Map<String, dynamic>?> _callAppsScript(Uint8List bytes) async {
    // Scale timeout: NVIDIA free model needs ~40-70s for vision analysis
    final payloadKB = bytes.length ~/ 1024;
    final timeoutSec = payloadKB > 500 ? 120 : 90;
    print('GeminiVision: Payload ${payloadKB}KB, timeout ${timeoutSec}s');

    final requestBody = {
      'action': 'gemini',
      'imageBase64': base64Encode(bytes),
    };

    final client = http.Client();
    http.Response response;
    try {
      response = await client.post(
        Uri.parse(_backendUrl),
        body: jsonEncode(requestBody),
        headers: {'Content-Type': 'text/plain;charset=utf-8'},
      ).timeout(Duration(seconds: timeoutSec));

      // ✅ FIX: Apps Script redirects POST → GET for the JSON response
      if (response.statusCode == 302 || response.statusCode == 301) {
        final loc = response.headers['location'] ?? '';
        if (loc.isNotEmpty) {
          response = await client.get(
            Uri.parse(loc),
            headers: {'Accept': 'application/json'},
          ).timeout(const Duration(seconds: 30));
        }
      }
    } finally { client.close(); }

    if (response.statusCode != 200) {
      print('GeminiVision: Apps Script HTTP ${response.statusCode}');
      return null;
    }

    final bodyTrimmed = response.body.trim();
    if (bodyTrimmed.isEmpty || bodyTrimmed.startsWith('<!') || bodyTrimmed.startsWith('<html')) {
      print('GeminiVision: Apps Script returned HTML, not JSON');
      return null;
    }

    try {
      final data = jsonDecode(bodyTrimmed) as Map<String, dynamic>;

      // Detect server-side AI failure disguised as success
      // (Apps Script returns hazards with error message in summary/description)
      final summary = data['summary']?.toString().toLowerCase() ?? '';
      final firstHazardDesc = (data['hazards'] is List && (data['hazards'] as List).isNotEmpty)
          ? (data['hazards'] as List).first['description']?.toString().toLowerCase() ?? ''
          : '';
      if (summary.contains('all providers exhausted') ||
          summary.contains('temporarily unavailable') ||
          firstHazardDesc.contains('all providers exhausted') ||
          firstHazardDesc.contains('temporarily unavailable')) {
        print('GeminiVision: Server AI failed (providers exhausted)');
        // ✅ FIX: Set cooldown to prevent hammering exhausted server
        _lastExhaustionTime = DateTime.now();
        data['error'] = 'AI providers exhausted on server';
        return data;
      }

      if (data['hazards'] != null) {
        data['_source'] = 'apps_script';
        data['_isOnline'] = true;
      }
      return data;
    } catch (e) {
      print('GeminiVision: Apps Script JSON parse error: $e');
      return null;
    }
  }

  // ── Offline fallback — clean message, NO fake hazards ─────────────────────
  static Future<Map<String, dynamic>> _offlineFallback(Uint8List bytes,
      {String reason = ''}) async {
    return {
      'overallRisk': 'UNKNOWN',
      'riskScore': 0,
      'confidence': 0,
      'people': 0,
      'hazards': [],  // ✅ NO fake hazards — empty list
      'summary':
          'AI analysis unavailable ($reason).\n\n'
          'Form submission works fully offline. '
          'When you connect to internet later, you can retry for full AI-powered analysis.',
      '_source': 'offline_fallback',
      '_offline_reason': reason,
      '_isOnline': false,
    };
  }

  // NOTE: Offline hazard library removed in v22 — no more fake/random hazards
  // when AI is unavailable. Users now see a clean "AI unavailable" message.

  static bool get isConfigured => true;
}
