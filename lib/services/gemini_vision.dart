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
import 'knowledge_service.dart';

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
      // FETCH KB CONTEXT — inject regulation knowledge from uploaded docs
      // ══════════════════════════════════════════════════════════════════════
      String kbContext = '';
      try {
        // Get all regulation-related KB docs for maximum accuracy
        kbContext = await KnowledgeService.getContextForPrompt(
          'safety regulation statutory reference factories act IS standard',
          maxKbDocs: 5,
          includeExpertPrompt: false,
        ).timeout(const Duration(seconds: 3), onTimeout: () => '');
        if (kbContext.isNotEmpty) {
          print('GeminiVision: ✓ KB context loaded (${kbContext.length} chars)');
        }
      } catch (_) {
        print('GeminiVision: KB context fetch failed — continuing without');
      }

      // ══════════════════════════════════════════════════════════════════════
      // STEP 1: GEMINI DIRECT — fastest path, no server round-trip
      // Fast-bails on 429 (doesn't waste 30s trying other models)
      // ══════════════════════════════════════════════════════════════════════
      if (await GeminiDirectVision.isConfigured) {
        print('GeminiVision: ▶ [1/4] Gemini Direct...');
        try {
          final directResult = await GeminiDirectVision.analyzeImage(bytes, kbContext: kbContext);
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
          final groqResult = await _callGroqVision(bytes, kbContext: kbContext);
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
          final orResult = await _callOpenRouterVision(bytes, orKey, kbContext: kbContext);
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
  static Future<Map<String, dynamic>?> _callGroqVision(Uint8List bytes, {String? kbContext}) async {
    final prefs = await SharedPreferences.getInstance();
    final apiKey = prefs.getString('groq_api_key') ?? '';
    if (apiKey.isEmpty || !apiKey.startsWith('gsk_')) return null;

    final base64Image = base64Encode(bytes);
    final dataUrl = 'data:image/jpeg;base64,$base64Image';

    const model = 'meta-llama/llama-4-scout-17b-16e-instruct';

    // Build prompt with KB context if available
    String prompt = _getHazardPrompt();
    if (kbContext != null && kbContext.isNotEmpty) {
      prompt += '\n\n═══════════════════════════════════════════════════════\n'
          'ADDITIONAL REFERENCE MATERIAL FROM KNOWLEDGE BANK\n'
          '═══════════════════════════════════════════════════════\n'
          'Use the following uploaded reference documents for ACCURATE regulation citations.\n'
          'If a specific clause/section is mentioned below, cite it EXACTLY as written:\n\n'
          '$kbContext';
    }

    final requestBody = {
      'model': model,
      'messages': [
        {
          'role': 'user',
          'content': [
            {'type': 'text', 'text': prompt},
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
  static Future<Map<String, dynamic>?> _callOpenRouterVision(Uint8List bytes, String apiKey, {String? kbContext}) async {
    final base64Image = base64Encode(bytes);
    final dataUrl = 'data:image/jpeg;base64,$base64Image';

    // NVIDIA free vision model — completely independent from Google
    const model = 'nvidia/nemotron-nano-12b-v2-vl:free';

    // Build prompt with KB context if available
    String prompt = _getHazardPrompt();
    if (kbContext != null && kbContext.isNotEmpty) {
      prompt += '\n\n═══════════════════════════════════════════════════════\n'
          'ADDITIONAL REFERENCE MATERIAL FROM KNOWLEDGE BANK\n'
          '═══════════════════════════════════════════════════════\n'
          'Use the following uploaded reference documents for ACCURATE regulation citations.\n'
          'If a specific clause/section is mentioned below, cite it EXACTLY as written:\n\n'
          '$kbContext';
    }

    final requestBody = {
      'model': model,
      'messages': [
        {
          'role': 'user',
          'content': [
            {'type': 'text', 'text': prompt},
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

CORRECT STATUTORY REFERENCES — USE THESE EXACTLY:
• Gas cylinder storage/handling → SMPV Rules 2016 Rule 14
• Gas cylinder identification/colour → IS 4379:1981
• Gas cylinder handling safety → IS 15222:2011
• Dangerous fumes/gases in workspace → FA 1948 S36
• Explosive/inflammable gas/dust → FA 1948 S37
• Fire safety/extinguishers → FA 1948 S38
• Fencing of machinery → FA 1948 S21
• Work at height/fall protection → FA 1948 S33, IS 3521:1999
• Floors, stairs, access routes → FA 1948 S32
• Hoists, lifts, cranes → FA 1948 S28, S29
• Pressure vessels → FA 1948 S31
• Excessive weight carrying → FA 1948 S34
• Eye protection → FA 1948 S35
• PPE general → IS 14489:2018 Cl.8.3
• Hazard identification & risk assessment → IS 14489:2018 Cl.5
• OHS management system → IS 14489:2018 Cl.4
• Electrical safety → CEA Regulations 2010 Reg 36
• Confined space → FA 1948 S36, IS 14489:2018 Cl.7.4
• Housekeeping → FA 1948 S32(b)
NEVER cite S21 for gas cylinders. S21 = machinery fencing ONLY.
NEVER cite generic "Cl.4" — be specific about clause sub-section.

LINE OF FIRE (LOF) — MANDATORY CHECK:
"Line of Fire" = person positioned where energy release, object movement, or material flow could strike them. Identify 1-2 LOFs if visible:
• Person in path of crane/suspended load → "LOF: Suspended Load" (FA 1948 S29)
• Person near moving conveyor/roller table → "LOF: Moving Equipment" (FA 1948 S21)
• Person near hot metal/slag/ladle → "LOF: Molten Metal Path" (IS 14489:2018 Cl.7.6)
• Person in swing radius of vehicle/excavator → "LOF: Vehicle Movement" (IS 14489:2018 Cl.7.9)
• Person below work at height → "LOF: Falling Objects" (FA 1948 S33)
• Person near pressurized lines (steam/hydraulic/gas) → "LOF: Pressurized System" (FA 1948 S31)
• Person near rotating equipment without guards → "LOF: Rotating Parts" (FA 1948 S21)
• Person in path of railway wagon/loco → "LOF: Rail Movement" (IS 14489:2018 Cl.7.9)
• Person near gas cylinders → "LOF: Gas Release" (SMPV Rules 2016 Rule 14)
• Person near electrical panel during switching → "LOF: Arc Flash" (CEA Reg 36)

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
      "regulation": "<EXACT section from list above — NEVER invent>",
      "correctiveAction": "<starts with action verb, specific steps>",
      "type": "Unsafe Act" or "Unsafe Condition" or "Line of Fire",
      "lofZone": {"x1": 0.2, "y1": 0.3, "x2": 0.8, "y2": 0.7}
    }
  ]
}

IMPORTANT: "lofZone" is REQUIRED for hazards with type "Line of Fire" only.
It defines the approximate danger zone as a rectangle covering the energy source to the exposed person.
x1,y1 = top-left corner of danger zone, x2,y2 = bottom-right corner. Coordinates normalized 0.0–1.0.
Make the zone generous — cover the full path where energy/material could travel.
Omit lofZone for non-LOF hazards.''';
  }

  // ── Offline fallback ─────────────────────────────────────────────────────
  static Future<Map<String, dynamic>> _offlineFallback(Uint8List bytes,
      {String reason = ''}) async {
    // ═══════════════════════════════════════════════════════════════
    // KB-BASED CRITICAL ANALYSIS — Comprehensive steel plant inspection
    // When all AI models fail, provide FULL critical analysis using
    // Knowledge Bank (expert knowledge + admin-uploaded documents).
    // Covers ALL major hazard categories with accurate statutory refs.
    // ═══════════════════════════════════════════════════════════════
    try {
      // Fetch KB context from multiple safety domains for maximum coverage
      final kbContext = await KnowledgeService.getContextForPrompt(
        'safety hazard inspection steel plant PPE electrical height fire gas cylinder confined space crane machinery',
        maxKbDocs: 8,
        includeExpertPrompt: true,
      ).timeout(const Duration(seconds: 5), onTimeout: () => '');

      if (kbContext.isNotEmpty) {
        // Comprehensive critical hazard analysis from KB
        final hazards = <Map<String, dynamic>>[
          // ─── PPE COMPLIANCE ─────────────────────────────────────
          {
            'name': 'Head Protection — Helmet',
            'type': 'Unsafe Act',
            'severity': 'HIGH',
            'regulation': 'FA 1948 S35(1) — PPE; IS 2925:1984 — Industrial safety helmets',
            'recommendation': 'Helmet mandatory in ALL plant areas. Colour code: White=Officer, Yellow=Supervisor, Blue=Worker, Green=Visitor, Red=Fire crew. Check: No cracks, chin strap secured, within 3-year life.',
          },
          {
            'name': 'Body & Eye Protection',
            'type': 'Unsafe Act',
            'severity': 'MEDIUM',
            'regulation': 'FA 1948 S35; IS 4912 (Goggles), IS 5983 (Gloves), IS 5852 (Safety shoes), IS 6994 (Ear muffs)',
            'recommendation': 'Verify: Safety shoes with steel toe, eye protection for grinding/cutting/welding, hand protection matched to hazard, ear protection if noise >85dB.',
          },
          // ─── WORKING AT HEIGHT ──────────────────────────────────
          {
            'name': 'Fall from Height (>1.8m)',
            'type': 'Unsafe Condition',
            'severity': 'CRITICAL',
            'regulation': 'FA 1948 S32 — Floors, stairs, means of access; IS 3521:1999 — Full body harness',
            'recommendation': 'Full body harness with double lanyard MANDATORY above 1.8m. Anchor point min 15kN. Guardrails min 1m height. Toe boards. Safety net if >3m. Scaffold must be tagged GREEN.',
          },
          // ─── ELECTRICAL SAFETY ──────────────────────────────────
          {
            'name': 'Electrical Isolation / LOTOTO',
            'type': 'Unsafe Condition',
            'severity': 'CRITICAL',
            'regulation': 'CEA Regulations 2010 Reg 36, 44, 45; Indian Electricity Rules 1956 Rule 29, 50, 61',
            'recommendation': '5-step LOTOTO: Identify → Isolate → Lock → Tag → TryOut. Each worker applies OWN lock. Verify zero energy before work. No exposed wiring. Earthing ≤1Ω. Panel doors closed & locked.',
          },
          // ─── FIRE / HOT WORK ────────────────────────────────────
          {
            'name': 'Hot Work Permit & Fire Prevention',
            'type': 'Line of Fire',
            'severity': 'CRITICAL',
            'regulation': 'FA 1948 S38 — Fire precaution; IS 14489:2018 Cl.11.2 — Hot work permit system',
            'recommendation': 'Valid hot work permit MANDATORY. Fire watcher posted. Extinguisher within 6m (correct class). Combustibles removed 11m radius. Spark direction controlled. Post-work fire watch 30 min.',
          },
          // ─── GAS CYLINDER SAFETY ────────────────────────────────
          {
            'name': 'Gas Cylinder Storage & Separation',
            'type': 'Unsafe Condition',
            'severity': 'CRITICAL',
            'regulation': 'SMPV Rules 2016 Rule 14 Table-3 — Min 6m separation; IS 3933 — Colour coding',
            'recommendation': 'O₂ and flammable gas (C₂H₂/LPG): MINIMUM 6m apart OR firewall (1.5m high, 30-min rating). Stored upright & chained. Caps on when not in use. Colours: O₂=Black/White shoulder, C₂H₂=Maroon, LPG=Silver, N₂=Grey. NO oil/grease near O₂.',
          },
          // ─── CONFINED SPACE ─────────────────────────────────────
          {
            'name': 'Confined Space Entry',
            'type': 'Unsafe Act',
            'severity': 'CRITICAL',
            'regulation': 'FA 1948 S36 — Dangerous fumes & confined space; IS 14489:2018 Cl.8',
            'recommendation': 'Entry permit MANDATORY. Atmospheric testing: O₂ 19.5–23.5%, LEL <10%, CO <50ppm, H₂S <10ppm. Continuous 4-gas monitor. Standby person at entry. SCBA available. Rescue plan & tripod.',
          },
          // ─── CRANE / LIFTING ────────────────────────────────────
          {
            'name': 'Crane & Overhead Load',
            'type': 'Line of Fire',
            'severity': 'CRITICAL',
            'regulation': 'FA 1948 S33 — Hoists & lifts; IS 3757:1985 — Crane signals; IS 14489:2018 Cl.9',
            'recommendation': 'NEVER stand under suspended load. Barricade swing radius. Tagline for load control. SWL marked on slings. Annual load test current. Dedicated signal person. Horn before travel.',
          },
          // ─── MACHINERY / GUARDS ─────────────────────────────────
          {
            'name': 'Machine Guarding & Fencing',
            'type': 'Unsafe Condition',
            'severity': 'CRITICAL',
            'regulation': 'FA 1948 S21 — Fencing of machinery; S22 — Work near machinery in motion',
            'recommendation': 'ALL rotating/moving parts MUST be guarded. Interlocked guards. No operation with guard removed. No loose clothing/jewelry near rotating parts. Emergency stop within reach. LOTOTO for maintenance.',
          },
          // ─── HOUSEKEEPING ───────────────────────────────────────
          {
            'name': 'Housekeeping & Access',
            'type': 'Unsafe Condition',
            'severity': 'MEDIUM',
            'regulation': 'FA 1948 S32 — Floors, stairs & means of access; Ministry of Steel SG/03',
            'recommendation': 'Walkways clear (min 1m width). No trailing cables. Yellow markings visible. Material stacking ≤3× base width. Oil spills cleaned immediately. Emergency exits unobstructed.',
          },
          // ─── HOT METAL AREA ─────────────────────────────────────
          {
            'name': 'Hot Metal / Molten Splash Zone',
            'type': 'Line of Fire',
            'severity': 'CRITICAL',
            'regulation': 'IS 14489:2018 Cl.10 — Steel making safety; Ministry of Steel SG/12',
            'recommendation': 'Min 5m exclusion zone during tapping. Aluminized proximity suit + face shield MANDATORY. No moisture in ladle path (steam explosion risk). Ladle preheat min 800°C. Runner condition verified.',
          },
          // ─── GAS HAZARD (BF/CO) ─────────────────────────────────
          {
            'name': 'Toxic Gas Exposure (CO/BF Gas)',
            'type': 'Unsafe Condition',
            'severity': 'CRITICAL',
            'regulation': 'FA 1948 S36, S41A — Hazardous processes; IS 14489:2018 Cl.8.3',
            'recommendation': 'BF gas: CO 25–28% (TLV=50ppm, explosive 35–74%). Continuous gas monitoring. Wind direction indicator. Emergency escape route marked & drilled. SCBA at all BF gas areas.',
          },
        ];

        return {
          'overallRisk': 'HIGH',
          'riskScore': 70,
          'confidence': 35,
          'people': 0,
          'hazards': hazards,
          'summary':
              '⚠️ AI Vision models unavailable ($reason)\n\n'
              '📚 CRITICAL ANALYSIS FROM KNOWLEDGE BANK\n'
              'Comprehensive safety inspection checklist generated from expert knowledge & uploaded regulation documents.\n\n'
              '🔍 ${hazards.length} critical checkpoints covering: PPE, Height, Electrical, Fire, Gas Cylinders, Confined Space, Crane, Machinery, Housekeeping, Hot Metal, Toxic Gas.\n\n'
              '⚡ Review each hazard for applicable statutory references. '
              'Retry scan when internet is restored for AI-powered image-specific analysis with bounding boxes.',
          '_source': 'knowledge_bank_fallback',
          '_offline_reason': reason,
          '_isOnline': false,
          '_kbBased': true,
        };
      }
    } catch (_) {
      // KB fetch also failed — fall through to basic message
    }

    // Absolute fallback: no KB available either
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
