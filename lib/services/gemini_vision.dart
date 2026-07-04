// lib/services/gemini_vision.dart
// ★ v25 MAXIMUM RELIABILITY — 4 independent providers, NEVER fails
//
// PRIORITY CHAIN (ordered by speed, stops at first success):
//   1. Gemini Direct (client) — fastest (~3-8s), immediate response
//   2. Groq Vision (client) — fast (~2-5s), independent quota/provider
//   3. OpenRouter (client) — NVIDIA free vision models, independent
//   4. Apps Script (server) — parallel Gemini + OpenRouter (slowest due to round-trip)
//   5. Offline fallback (clean message)
//
// FAST-BAIL: On 429/quota errors, skips remaining models on same key immediately.
// ALL keys auto-sync from Apps Script Properties on every app launch.

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

  // Cooldown to prevent hammering exhausted server
  static DateTime? _lastExhaustionTime;
  static const Duration _exhaustionCooldown = Duration(seconds: 60);

  // Rate-limiting between analyses
  static DateTime? _lastCallTime;
  static const Duration _minCallInterval = Duration(seconds: 5);

  // Prevent concurrent AI calls
  static bool _isAnalyzing = false;

  // ── analyseImage (mobile / File path) ─────────────────────────────────────
  static Future<Map<String, dynamic>?> analyseImage(File imageFile) async {
    final bytes = await imageFile.readAsBytes();
    return analyseImageBytes(bytes);
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  MAIN ENTRY: 4-PROVIDER ANALYSIS (maximum reliability, never fails)
  // ══════════════════════════════════════════════════════════════════════════
  static Future<Map<String, dynamic>?> analyseImageBytes(Uint8List bytes,
      {int retryCount = 0}) async {
    final stopwatch = Stopwatch()..start();

    try {
      print('GeminiVision: ═══ STARTING ANALYSIS ═══ (${bytes.length} bytes)');

      // Prevent concurrent analysis
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

      // Rate-limit
      if (_lastCallTime != null &&
          DateTime.now().difference(_lastCallTime!) < _minCallInterval) {
        final wait = _minCallInterval - DateTime.now().difference(_lastCallTime!);
        print('GeminiVision: Rate-limiting — waiting ${wait.inSeconds}s');
        await Future.delayed(wait);
      }

      // Network check (mobile only)
      if (!kIsWeb) {
        final networkStatus = await NetworkChecker.getNetworkStatus();
        if (!networkStatus['hasInternet']!) {
          print('GeminiVision: No internet → offline fallback');
          _isAnalyzing = false;
          return await _offlineFallback(bytes, reason: 'No internet connection');
        }
      }

      // Ensure API keys are on device (auto-sync from server)
      if (!await GeminiDirectVision.isConfigured) {
        print('GeminiVision: Keys missing — syncing from backend...');
        try {
          await AdminMasterData.syncFromBackend()
              .timeout(const Duration(seconds: 8), onTimeout: () => false);
        } catch (_) {}
      }

      // ══════════════════════════════════════════════════════════════════════
      // STEP 1: GEMINI DIRECT — fastest path, no server round-trip
      // Fast-bails on 429 (doesn't waste 30s trying other models)
      // ══════════════════════════════════════════════════════════════════════
      if (await GeminiDirectVision.isConfigured) {
        print('GeminiVision: ▶ [1/4] Gemini Direct...');
        try {
          final directResult = await GeminiDirectVision.analyzeImage(bytes);
          if (_isValidResult(directResult)) {
            print('GeminiVision: ✓ [1/4] Gemini Direct SUCCESS in ${stopwatch.elapsedMilliseconds}ms');
            directResult!['_source'] = directResult['_source'] ?? 'gemini_direct';
            directResult['_isOnline'] = true;
            _lastCallTime = DateTime.now();
            _isAnalyzing = false;
            return directResult;
          }
        } catch (e) {
          print('GeminiVision: ✗ Gemini Direct exception: $e');
        }
      } else {
        print('GeminiVision: ⏭ [1/4] Gemini Direct skipped (no key)');
      }

      // ══════════════════════════════════════════════════════════════════════
      // STEP 2: GROQ VISION — independent provider, very fast (~2-5s)
      // Uses llama-4-scout-17b (free, vision-capable, separate quota)
      // ══════════════════════════════════════════════════════════════════════
      if (await GroqService.isConfigured) {
        print('GeminiVision: ▶ [2/4] Groq Vision...');
        try {
          final groqResult = await _callGroqVision(bytes);
          if (_isValidResult(groqResult)) {
            print('GeminiVision: ✓ [2/4] Groq Vision SUCCESS in ${stopwatch.elapsedMilliseconds}ms');
            groqResult!['_source'] = 'groq_vision';
            groqResult['_isOnline'] = true;
            _lastCallTime = DateTime.now();
            _isAnalyzing = false;
            return groqResult;
          }
        } catch (e) {
          print('GeminiVision: ✗ Groq Vision exception: $e');
        }
      } else {
        print('GeminiVision: ⏭ [2/4] Groq Vision skipped (no key)');
      }

      // ══════════════════════════════════════════════════════════════════════
      // STEP 3: OPENROUTER (client-side) — NVIDIA free vision models
      // Completely independent from Google quota
      // ══════════════════════════════════════════════════════════════════════
      final prefs = await SharedPreferences.getInstance();
      final orKey = prefs.getString('openrouter_api_key') ?? '';
      if (orKey.isNotEmpty && orKey.startsWith('sk-or-')) {
        print('GeminiVision: ▶ [3/4] OpenRouter (client)...');
        try {
          final orResult = await _callOpenRouterVision(bytes, orKey);
          if (_isValidResult(orResult)) {
            print('GeminiVision: ✓ [3/4] OpenRouter SUCCESS in ${stopwatch.elapsedMilliseconds}ms');
            orResult!['_source'] = 'openrouter_client';
            orResult['_isOnline'] = true;
            _lastCallTime = DateTime.now();
            _isAnalyzing = false;
            return orResult;
          }
        } catch (e) {
          print('GeminiVision: ✗ OpenRouter exception: $e');
        }
      } else {
        print('GeminiVision: ⏭ [3/4] OpenRouter skipped (no key)');
      }

      // ══════════════════════════════════════════════════════════════════════
      // STEP 4: APPS SCRIPT — server-side parallel (slowest, last resort)
      // ══════════════════════════════════════════════════════════════════════
      final serverCooldownActive = _lastExhaustionTime != null &&
          DateTime.now().difference(_lastExhaustionTime!) < _exhaustionCooldown;

      if (!serverCooldownActive) {
        print('GeminiVision: ▶ [4/4] Apps Script (server)...');
        try {
          final appsResult = await _callAppsScript(bytes);
          if (_isValidResult(appsResult)) {
            print('GeminiVision: ✓ [4/4] Apps Script SUCCESS in ${stopwatch.elapsedMilliseconds}ms');
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
        print('GeminiVision: ⏭ [4/4] Apps Script skipped (cooldown)');
      }

      // ══════════════════════════════════════════════════════════════════════
      // ALL 4 PROVIDERS FAILED → offline
      // ══════════════════════════════════════════════════════════════════════
      print('GeminiVision: ✗ ALL 4 providers failed. Total: ${stopwatch.elapsedMilliseconds}ms');
      _lastCallTime = DateTime.now();
      _isAnalyzing = false;
      return await _offlineFallback(bytes,
          reason: 'All AI providers unavailable (${stopwatch.elapsedMilliseconds}ms)');
    } catch (e) {
      print('GeminiVision: Unexpected error: $e');
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
    final summary = result['summary']?.toString().toLowerCase() ?? '';
    if (summary.contains('all providers exhausted') ||
        summary.contains('temporarily unavailable')) {
      _lastExhaustionTime = DateTime.now();
      return false;
    }
    return true;
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  GROQ VISION — llama-4-scout (free, fast, independent)
  // ══════════════════════════════════════════════════════════════════════════
  static Future<Map<String, dynamic>?> _callGroqVision(Uint8List bytes) async {
    final prefs = await SharedPreferences.getInstance();
    final apiKey = prefs.getString('groq_api_key') ?? '';
    if (apiKey.isEmpty || !apiKey.startsWith('gsk_')) return null;

    final base64Image = base64Encode(bytes);
    final dataUrl = 'data:image/jpeg;base64,$base64Image';

    const model = 'meta-llama/llama-4-scout-17b-16e-instruct';

    final requestBody = {
      'model': model,
      'messages': [
        {
          'role': 'user',
          'content': [
            {'type': 'text', 'text': _getHazardPrompt()},
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
      } else {
        print('GeminiVision: Groq HTTP ${response.statusCode}');
      }
    } catch (e) {
      print('GeminiVision: Groq exception: $e');
    }
    return null;
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  OPENROUTER (client) — NVIDIA free vision model
  // ══════════════════════════════════════════════════════════════════════════
  static Future<Map<String, dynamic>?> _callOpenRouterVision(Uint8List bytes, String apiKey) async {
    final base64Image = base64Encode(bytes);
    final dataUrl = 'data:image/jpeg;base64,$base64Image';

    // NVIDIA free vision model — completely independent from Google
    const model = 'nvidia/nemotron-nano-12b-v2-vl:free';

    final requestBody = {
      'model': model,
      'messages': [
        {
          'role': 'user',
          'content': [
            {'type': 'text', 'text': _getHazardPrompt()},
            {'type': 'image_url', 'image_url': {'url': dataUrl}},
          ]
        }
      ],
      'max_tokens': 4096,
      'temperature': 0.2,
    };

    try {
      final response = await http.post(
        Uri.parse('https://openrouter.ai/api/v1/chat/completions'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
          'HTTP-Referer': 'https://abhibond1986.github.io/Safety-Lens-V2/',
          'X-Title': 'SAIL Safety Lens',
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
      } else {
        print('GeminiVision: OpenRouter HTTP ${response.statusCode}');
      }
    } catch (e) {
      print('GeminiVision: OpenRouter exception: $e');
    }
    return null;
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  APPS SCRIPT — server-side parallel Gemini + OpenRouter
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

      final summary = data['summary']?.toString().toLowerCase() ?? '';
      final firstHazardDesc = (data['hazards'] is List && (data['hazards'] as List).isNotEmpty)
          ? (data['hazards'] as List).first['description']?.toString().toLowerCase() ?? ''
          : '';
      if (summary.contains('all providers exhausted') ||
          summary.contains('temporarily unavailable') ||
          firstHazardDesc.contains('all providers exhausted') ||
          firstHazardDesc.contains('temporarily unavailable')) {
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
  //  PARSE AI RESPONSE — extract JSON from model output
  // ══════════════════════════════════════════════════════════════════════════
  static Map<String, dynamic>? _parseAIResponse(String text) {
    if (text.isEmpty) return null;

    String jsonStr = text.trim();

    // Strip markdown code fences
    if (jsonStr.contains('```json')) {
      jsonStr = jsonStr.split('```json').last.split('```').first.trim();
    } else if (jsonStr.contains('```')) {
      final parts = jsonStr.split('```');
      if (parts.length >= 2) jsonStr = parts[1].split('```').first.trim();
    }

    // Find JSON boundaries
    final startIdx = jsonStr.indexOf('{');
    final endIdx = jsonStr.lastIndexOf('}');
    if (startIdx < 0 || endIdx < 0 || endIdx <= startIdx) return null;
    jsonStr = jsonStr.substring(startIdx, endIdx + 1);

    try {
      final parsed = jsonDecode(jsonStr) as Map<String, dynamic>;
      if (parsed['hazards'] is List && (parsed['hazards'] as List).isNotEmpty) {
        return parsed;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  SHARED PROMPT — used by Groq & OpenRouter (client-side)
  // ══════════════════════════════════════════════════════════════════════════
  static String _getHazardPrompt() {
    return '''You are a senior industrial safety inspector for SAIL (Steel Authority of India Limited), with expertise in IS 14489:2018 and Factories Act 1948.

METHODOLOGY: Scan systematically — foreground → middle → background, left → right.

PROFESSIONAL STANDARDS:
- Report only hazards you can CLEARLY see and justify. No vague/generic padding.
- 4-7 specific, well-described hazards are better than 10 vague ones.
- Every corrective action must be SPECIFIC (not generic "ensure safety").

LINE OF FIRE (LOF) — MANDATORY CHECK:
"Line of Fire" = person positioned where energy release, object movement, or material flow could strike them. Identify 1-2 LOFs if visible:
• Person in path of crane/suspended load → "LOF: Suspended Load"
• Person near moving conveyor/roller table → "LOF: Moving Equipment"
• Person near hot metal/slag/ladle → "LOF: Molten Metal Path"
• Person in swing radius of vehicle/excavator → "LOF: Vehicle Movement"
• Person below work at height → "LOF: Falling Objects"
• Person near pressurized lines (steam/hydraulic/gas) → "LOF: Pressurized System"
• Person near rotating equipment without guards → "LOF: Rotating Parts"
• Person in path of railway wagon/loco → "LOF: Rail Movement"
• Person near gas lines/cylinders → "LOF: Gas Release"
• Person near electrical panel during switching → "LOF: Arc Flash"

Return ONLY a JSON object (no markdown, no explanation):
{
  "overallRisk": "CRITICAL" or "HIGH" or "MEDIUM" or "LOW",
  "riskScore": <0-100>,
  "confidence": <0-100>,
  "people": <count of visible persons>,
  "summary": "<2-3 sentences: what is visible, key concern, regulatory context>",
  "hazards": [
    {
      "name": "<max 5 words, specific>",
      "description": "<what is visible, why dangerous, consequence>",
      "severity": "CRITICAL" or "HIGH" or "MEDIUM" or "LOW",
      "regulation": "<exact section e.g. FA 1948 S21, IS 14489 Cl.4>",
      "correctiveAction": "<starts with action verb, specific steps>",
      "type": "Unsafe Act" or "Unsafe Condition" or "Line of Fire"
    }
  ]
}''';
  }

  // ── Offline fallback ─────────────────────────────────────────────────────
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
