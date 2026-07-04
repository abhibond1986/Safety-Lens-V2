// lib/services/gemini_vision.dart
// ★ v25 MAXIMUM RELIABILITY — Uses ALL available API keys
//
// PRIORITY CHAIN (stops at first success):
//   1. Gemini Direct (client-side) — FASTEST, no server round-trip
//   2. Apps Script (server-side Gemini + OpenRouter in parallel)
//   3. Groq Vision (client-side) — completely independent provider & quota
//   4. Offline fallback (clean message, no fake hazards)
//
// API KEYS (all auto-synced from Apps Script Properties on every startup):
//   - GOOGLE_AI_KEY → Gemini Direct (client) + Apps Script Gemini (server)
//   - OPENROUTER_API_KEY → Apps Script OpenRouter (server)
//   - GROQ_API_KEY → Groq Vision (client)

import 'dart:convert';
import 'dart:async';
import 'dart:io' show File;
import 'package:flutter/foundation.dart' show Uint8List, kIsWeb;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'network_checker.dart';
import 'gemini_direct_vision.dart';
import 'groq_service.dart';
import 'admin_master_data.dart';

class GeminiVision {
  static const String _backendUrl =
      'https://script.google.com/macros/s/AKfycbzDiT4OSvlDUxvcM9DYJ_-SiB1HyDrgXtYflGfmqJRH9wnZZusj5GqX9frCx64rkd61Rg/exec';

  // ✅ Cooldown to prevent hammering exhausted server
  static DateTime? _lastExhaustionTime;
  static const Duration _exhaustionCooldown = Duration(seconds: 60);

  // ✅ Track last successful call to apply rate-limiting between analyses
  static DateTime? _lastCallTime;
  static const Duration _minCallInterval = Duration(seconds: 5);

  // ✅ Prevent concurrent AI calls (second call waits or skips)
  static bool _isAnalyzing = false;

  // ── analyseImage (mobile / File path) ─────────────────────────────────────
  static Future<Map<String, dynamic>?> analyseImage(File imageFile) async {
    final bytes = await imageFile.readAsBytes();
    return analyseImageBytes(bytes);
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  MAIN ENTRY: MULTI-PROVIDER ANALYSIS (maximum reliability)
  // ══════════════════════════════════════════════════════════════════════════
  static Future<Map<String, dynamic>?> analyseImageBytes(Uint8List bytes,
      {int retryCount = 0}) async {
    final stopwatch = Stopwatch()..start();

    try {
      print('GeminiVision: ═══ STARTING ANALYSIS ═══ (${bytes.length} bytes)');

      // ✅ Prevent concurrent analysis
      if (_isAnalyzing) {
        print('GeminiVision: ⚠ Another analysis in progress — waiting...');
        for (int i = 0; i < 60; i++) {
          await Future.delayed(const Duration(milliseconds: 500));
          if (!_isAnalyzing) break;
        }
        if (_isAnalyzing) {
          return await _offlineFallback(bytes, reason: 'Another analysis in progress');
        }
      }
      _isAnalyzing = true;

      // ✅ Rate-limit: don't fire again within 5s of last call
      if (_lastCallTime != null &&
          DateTime.now().difference(_lastCallTime!) < _minCallInterval) {
        final wait = _minCallInterval - DateTime.now().difference(_lastCallTime!);
        print('GeminiVision: Rate-limiting — waiting ${wait.inSeconds}s');
        await Future.delayed(wait);
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

      // ── Ensure API keys are on device ──
      if (!await GeminiDirectVision.isConfigured) {
        print('GeminiVision: Keys not on device — syncing from backend...');
        try {
          await AdminMasterData.syncFromBackend()
              .timeout(const Duration(seconds: 8), onTimeout: () => false);
        } catch (_) {}
      }

      // ══════════════════════════════════════════════════════════════════════
      // STEP 1: GEMINI DIRECT (client-side) — FASTEST PATH
      // Uses GOOGLE_AI_KEY synced to device. Separate quota from server.
      // ══════════════════════════════════════════════════════════════════════
      if (await GeminiDirectVision.isConfigured) {
        print('GeminiVision: ▶ [1/3] Gemini Direct (client-side)...');
        try {
          final directResult = await GeminiDirectVision.analyzeImage(bytes);
          if (_isValidResult(directResult)) {
            print('GeminiVision: ✓ Gemini Direct SUCCESS in ${stopwatch.elapsedMilliseconds}ms');
            directResult!['_source'] = 'gemini_direct';
            directResult['_isOnline'] = true;
            _lastCallTime = DateTime.now();
            _isAnalyzing = false;
            return directResult;
          }
          print('GeminiVision: ✗ Gemini Direct failed (no valid hazards)');
        } catch (e) {
          print('GeminiVision: ✗ Gemini Direct exception: $e');
        }
      } else {
        print('GeminiVision: ⏭ Gemini Direct skipped (no client API key)');
      }

      // ══════════════════════════════════════════════════════════════════════
      // STEP 2: APPS SCRIPT (server-side parallel Gemini + OpenRouter)
      // Server has its own GOOGLE_AI_KEY + OPENROUTER_API_KEY
      // ══════════════════════════════════════════════════════════════════════
      final serverCooldownActive = _lastExhaustionTime != null &&
          DateTime.now().difference(_lastExhaustionTime!) < _exhaustionCooldown;

      if (!serverCooldownActive) {
        print('GeminiVision: ▶ [2/3] Apps Script (server parallel)...');
        try {
          final appsResult = await _callAppsScript(bytes);
          if (_isValidResult(appsResult)) {
            print('GeminiVision: ✓ Apps Script SUCCESS in ${stopwatch.elapsedMilliseconds}ms');
            _lastCallTime = DateTime.now();
            _isAnalyzing = false;
            return appsResult;
          }
          if (appsResult != null && appsResult['error'] != null) {
            print('GeminiVision: ✗ Server error: ${appsResult['error']}');
          }
        } catch (e) {
          print('GeminiVision: ✗ Apps Script exception: $e');
        }
      } else {
        final remaining = _exhaustionCooldown.inSeconds -
            DateTime.now().difference(_lastExhaustionTime!).inSeconds;
        print('GeminiVision: ⏭ Apps Script skipped (cooldown ${remaining}s remaining)');
      }

      // ══════════════════════════════════════════════════════════════════════
      // STEP 3: GROQ VISION (client-side) — independent provider & quota
      // Uses GROQ_API_KEY with llama-4-scout (free vision model)
      // ══════════════════════════════════════════════════════════════════════
      if (await GroqService.isConfigured) {
        print('GeminiVision: ▶ [3/3] Groq Vision (independent provider)...');
        try {
          final groqResult = await _callGroqVision(bytes);
          if (_isValidResult(groqResult)) {
            print('GeminiVision: ✓ Groq Vision SUCCESS in ${stopwatch.elapsedMilliseconds}ms');
            groqResult!['_source'] = 'groq_vision';
            groqResult['_isOnline'] = true;
            _lastCallTime = DateTime.now();
            _isAnalyzing = false;
            return groqResult;
          }
          print('GeminiVision: ✗ Groq Vision failed');
        } catch (e) {
          print('GeminiVision: ✗ Groq Vision exception: $e');
        }
      } else {
        print('GeminiVision: ⏭ Groq Vision skipped (no API key)');
      }

      // ══════════════════════════════════════════════════════════════════════
      // ALL PROVIDERS EXHAUSTED → offline fallback
      // ══════════════════════════════════════════════════════════════════════
      print('GeminiVision: ▶ Offline fallback (all 3 providers failed)');
      print('GeminiVision: Total time elapsed: ${stopwatch.elapsedMilliseconds}ms');
      _lastCallTime = DateTime.now();
      _isAnalyzing = false;
      return await _offlineFallback(bytes,
          reason: 'All AI providers unavailable after ${stopwatch.elapsedMilliseconds}ms');
    } catch (e) {
      print('GeminiVision: Unexpected top-level error: $e');
      _isAnalyzing = false;
      return await _offlineFallback(bytes, reason: e.toString());
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  HELPER: Validate result has real hazards
  // ══════════════════════════════════════════════════════════════════════════
  static bool _isValidResult(Map<String, dynamic>? result) {
    if (result == null) return false;
    if (result['error'] != null) return false;
    if (result['hazards'] == null) return false;
    if ((result['hazards'] as List).isEmpty) return false;
    // Check it's not a disguised error
    final summary = result['summary']?.toString().toLowerCase() ?? '';
    if (summary.contains('all providers exhausted') ||
        summary.contains('temporarily unavailable')) {
      _lastExhaustionTime = DateTime.now();
      return false;
    }
    return true;
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  APPS SCRIPT CALL — server-side parallel Gemini + OpenRouter
  // ══════════════════════════════════════════════════════════════════════════
  static Future<Map<String, dynamic>?> _callAppsScript(Uint8List bytes) async {
    final payloadKB = bytes.length ~/ 1024;
    final timeoutSec = payloadKB > 500 ? 60 : 45;
    print('GeminiVision: Payload ${payloadKB}KB, timeout ${timeoutSec}s');

    final requestBody = {
      'action': 'gemini',
      'imageBase64': base64Encode(bytes),
    };

    http.Response response;

    if (kIsWeb) {
      response = await http.post(
        Uri.parse(_backendUrl),
        body: jsonEncode(requestBody),
        headers: {'Content-Type': 'text/plain;charset=utf-8'},
      ).timeout(Duration(seconds: timeoutSec));
    } else {
      final client = http.Client();
      try {
        response = await client.post(
          Uri.parse(_backendUrl),
          body: jsonEncode(requestBody),
          headers: {'Content-Type': 'text/plain;charset=utf-8'},
        ).timeout(Duration(seconds: timeoutSec));

        if (response.statusCode == 302 || response.statusCode == 301) {
          final loc = response.headers['location'] ?? '';
          if (loc.isNotEmpty) {
            response = await client.get(
              Uri.parse(loc),
              headers: {'Accept': 'application/json'},
            ).timeout(Duration(seconds: timeoutSec));
          }
        }
      } finally { client.close(); }
    }

    if (response.statusCode != 200) {
      print('GeminiVision: Apps Script HTTP ${response.statusCode}');
      return null;
    }

    final bodyTrimmed = utf8.decode(response.bodyBytes).trim();
    if (bodyTrimmed.isEmpty || bodyTrimmed.startsWith('<!') || bodyTrimmed.startsWith('<html')) {
      print('GeminiVision: Apps Script returned HTML, not JSON');
      return null;
    }

    try {
      final data = jsonDecode(bodyTrimmed) as Map<String, dynamic>;

      // Detect server-side exhaustion
      final summary = data['summary']?.toString().toLowerCase() ?? '';
      final firstHazardDesc = (data['hazards'] is List && (data['hazards'] as List).isNotEmpty)
          ? (data['hazards'] as List).first['description']?.toString().toLowerCase() ?? ''
          : '';
      if (summary.contains('all providers exhausted') ||
          summary.contains('temporarily unavailable') ||
          firstHazardDesc.contains('all providers exhausted') ||
          firstHazardDesc.contains('temporarily unavailable')) {
        print('GeminiVision: Server AI failed (providers exhausted)');
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

  // ══════════════════════════════════════════════════════════════════════════
  //  GROQ VISION — independent provider (llama-4-scout-17b-16e-instruct)
  //  Completely separate quota from Google/OpenRouter
  // ══════════════════════════════════════════════════════════════════════════
  static Future<Map<String, dynamic>?> _callGroqVision(Uint8List bytes) async {
    final prefs = await SharedPreferences.getInstance();
    final apiKey = prefs.getString('groq_api_key') ?? '';
    if (apiKey.isEmpty || !apiKey.startsWith('gsk_')) return null;

    final base64Image = base64Encode(bytes);
    final dataUrl = 'data:image/jpeg;base64,$base64Image';

    // Use llama-4-scout — Groq's free vision model (30 RPM, very fast)
    const model = 'meta-llama/llama-4-scout-17b-16e-instruct';

    final requestBody = {
      'model': model,
      'messages': [
        {
          'role': 'user',
          'content': [
            {'type': 'text', 'text': _getGroqPrompt()},
            {'type': 'image_url', 'image_url': {'url': dataUrl}},
          ]
        }
      ],
      'max_tokens': 4096,
      'temperature': 0.2,
    };

    try {
      final response = await http.post(
        Uri.parse('https://api.groq.com/openai/v1/chat/completions'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        },
        body: jsonEncode(requestBody),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        final choices = data['choices'] as List?;
        if (choices != null && choices.isNotEmpty) {
          final content = choices[0]['message']?['content']?.toString() ?? '';
          return _parseAIResponse(content);
        }
      } else if (response.statusCode == 429) {
        print('GeminiVision: Groq rate limited (429)');
      } else {
        print('GeminiVision: Groq HTTP ${response.statusCode}: ${response.body.substring(0, response.body.length.clamp(0, 200))}');
      }
    } catch (e) {
      print('GeminiVision: Groq exception: $e');
    }
    return null;
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  PARSE AI RESPONSE — extract JSON from model output
  // ══════════════════════════════════════════════════════════════════════════
  static Map<String, dynamic>? _parseAIResponse(String text) {
    if (text.isEmpty) return null;

    // Try to extract JSON from the response
    String jsonStr = text.trim();

    // Strip markdown code fences if present
    if (jsonStr.contains('```json')) {
      jsonStr = jsonStr.split('```json').last.split('```').first.trim();
    } else if (jsonStr.contains('```')) {
      jsonStr = jsonStr.split('```')[1].split('```').first.trim();
    }

    // Find JSON object boundaries
    final startIdx = jsonStr.indexOf('{');
    final endIdx = jsonStr.lastIndexOf('}');
    if (startIdx < 0 || endIdx < 0 || endIdx <= startIdx) return null;
    jsonStr = jsonStr.substring(startIdx, endIdx + 1);

    try {
      final parsed = jsonDecode(jsonStr) as Map<String, dynamic>;
      // Validate it has the expected structure
      if (parsed['hazards'] is List && (parsed['hazards'] as List).isNotEmpty) {
        return parsed;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  GROQ VISION PROMPT — concise for fast inference
  // ══════════════════════════════════════════════════════════════════════════
  static String _getGroqPrompt() {
    return '''You are an industrial safety inspector for SAIL (Steel Authority of India). Analyze this workplace image for safety hazards.

Return ONLY a JSON object (no markdown, no explanation) with this exact structure:
{
  "overallRisk": "HIGH" or "MEDIUM" or "LOW" or "CRITICAL",
  "riskScore": <number 0-100>,
  "confidence": <number 0-100>,
  "people": <count of people visible>,
  "summary": "<2-3 sentence summary of key hazards>",
  "hazards": [
    {
      "name": "<short hazard name>",
      "description": "<what the hazard is and why it's dangerous>",
      "severity": "HIGH" or "MEDIUM" or "LOW" or "CRITICAL",
      "regulation": "<applicable IS/WSA regulation>",
      "correctiveAction": "<what should be done to fix it>"
    }
  ]
}

Identify ALL visible hazards: PPE violations, housekeeping issues, fire risks, electrical hazards, fall risks, chemical exposure, machine guarding, ergonomic issues, confined space violations, etc. Be thorough — inspect foreground, middle ground, and background.''';
  }

  // ── Offline fallback — clean message, NO fake hazards ─────────────────────
  static Future<Map<String, dynamic>> _offlineFallback(Uint8List bytes,
      {String reason = ''}) async {
    return {
      'overallRisk': 'UNKNOWN',
      'riskScore': 0,
      'confidence': 0,
      'people': 0,
      'hazards': [],
      'summary':
          'AI analysis unavailable ($reason).\n\n'
          'Form submission works fully offline. '
          'When you connect to internet later, you can retry for full AI-powered analysis.',
      '_source': 'offline_fallback',
      '_offline_reason': reason,
      '_isOnline': false,
    };
  }

  static bool get isConfigured => true;
}
