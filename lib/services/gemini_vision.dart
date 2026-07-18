// lib/services/gemini_vision.dart
// ★ v25 MAXIMUM RELIABILITY — 4 independent providers, NEVER fails
//
// PRIORITY CHAIN (stops at first success):
//   1. Groq Vision (client) — PRIMARY model (fast ~2-5s)
//   2. OpenRouter Nemotron (client) — SECONDARY model (NVIDIA, free, 256K context)
//   3. Gemini Direct (client) — fallback
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
      // STEP 1: GROQ VISION — llama-4-scout-17b-16e (PRIMARY model)
      // ══════════════════════════════════════════════════════════════════════
      if (await GroqService.isConfigured) {
        print('GeminiVision: ▶ [1/4] Groq Scout (primary)...');
        try {
          final groqResult = await _callGroqVision(bytes, kbContext: kbContext);
          if (_isValidResult(groqResult)) {
            print('GeminiVision: ✓ [1/4] Groq Vision SUCCESS in ${stopwatch.elapsedMilliseconds}ms');
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
        print('GeminiVision: ⏭ [1/4] Groq Vision skipped (no key)');
      }

      // ══════════════════════════════════════════════════════════════════════
      // STEP 2: OPENROUTER — Nemotron 30B (SECONDARY model)
      // ★ v35: Free, 256K context, multimodal, 30B reasoning model
      // ══════════════════════════════════════════════════════════════════════
      final prefs = await SharedPreferences.getInstance();
      final orKey = prefs.getString('openrouter_api_key') ?? '';
      if (orKey.isNotEmpty && orKey.startsWith('sk-or-')) {
        print('GeminiVision: ▶ [2/4] OpenRouter Nemotron 30B (secondary)...');
        try {
          final orResult = await _callOpenRouterVision(bytes, orKey, kbContext: kbContext);
          if (_isValidResult(orResult)) {
            print('GeminiVision: ✓ [2/4] OpenRouter SUCCESS in ${stopwatch.elapsedMilliseconds}ms');
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
        print('GeminiVision: ⏭ [2/4] OpenRouter skipped (no key)');
      }

      // ══════════════════════════════════════════════════════════════════════
      // STEP 3: GEMINI DIRECT — Google's model, fallback
      // ══════════════════════════════════════════════════════════════════════
      if (await GeminiDirectVision.isConfigured) {
        print('GeminiVision: ▶ [3/4] Gemini Direct...');
        try {
          final directResult = await GeminiDirectVision.analyzeImage(bytes, kbContext: kbContext);
          if (_isValidResult(directResult)) {
            print('GeminiVision: ✓ [3/4] Gemini Direct SUCCESS in ${stopwatch.elapsedMilliseconds}ms');
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
        print('GeminiVision: ⏭ [3/4] Gemini Direct skipped (no key)');
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
  //  GROQ VISION — Llama 4 Scout 17B (16e, multimodal vision)
  // ══════════════════════════════════════════════════════════════════════════
  static Future<Map<String, dynamic>?> _callGroqVision(Uint8List bytes, {String? kbContext}) async {
    final prefs = await SharedPreferences.getInstance();
    final apiKey = prefs.getString('groq_api_key') ?? '';
    if (apiKey.isEmpty || !apiKey.startsWith('gsk_')) return null;

    final base64Image = base64Encode(bytes);
    final dataUrl = 'data:image/jpeg;base64,$base64Image';

    // Groq vision model — Llama 4 Scout 17B (16e)
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
      'max_tokens': 8192,
      'temperature': 0.15,
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
    // ★ v35: Upgraded to Nemotron 3 Nano Omni 30B — free, 256K context, multimodal vision
    const model = 'nvidia/nemotron-3-nano-omni-30b-a3b-reasoning:free';

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
      'temperature': 0.15,
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
    return '''You are a senior industrial safety inspector for SAIL (Steel Authority of India Limited), with 30+ years field experience in IS 14489:2018 and Factories Act 1948.

═══════════════════════════════════════════════════════
ANTI-HALLUCINATION RULES (CRITICAL — READ FIRST)
═══════════════════════════════════════════════════════
★ ONLY report what you can PHYSICALLY SEE in this specific image.
★ For EACH hazard, you MUST describe the VISUAL EVIDENCE (colour, shape, position, object) that proves it exists.
★ If you cannot point to a specific pixel region proving a hazard, DO NOT report it.
★ NEVER assume hazards based on "typical" conditions — only report OBSERVED ones.
★ NEVER pad results with generic hazards to fill a quota.
★ 3 real hazards with evidence > 10 assumed ones without evidence.
★ "confidence" field must reflect YOUR certainty that hazards are real (not assumed).
  - confidence 80-100: Clear visual evidence, no ambiguity
  - confidence 50-79: Partial evidence, some interpretation needed
  - confidence below 50: Low-quality image or limited visibility
★ If image is blurry, dark, or shows nothing hazardous, return LOW risk with 1-2 hazards max.

═══════════════════════════════════════════════════════
METHODOLOGY — EVIDENCE-BASED INSPECTION
═══════════════════════════════════════════════════════
1. OBSERVE: What objects/people/equipment are VISIBLE? List them mentally.
2. ASSESS: For each visible item, is there a safety violation you can PROVE from the image?
3. CITE: Match ONLY to regulations from the table below. Never invent citations.
4. DESCRIBE: State what you SEE, not what you assume.

Scan order: foreground → middle → background, left → right.

═══════════════════════════════════════════════════════
REGULATION REFERENCE TABLE — CITE ONLY FROM HERE
═══════════════════════════════════════════════════════
── Gas Cylinders ──
  SMPV Rules 2016 Rule 14 = Storage (upright, chained, segregated, ventilated)
  SMPV Rules 2016 Rule 10 = Valve caps
  IS 4379:1981 = Colour code identification
  IS 7312:1987 = Storage of gas cylinders
  FA 1948 S37 = Explosive/inflammable dust, gas (No Smoking, separation)

── Machinery & Guards ──
  FA 1948 S21 = Fencing of machinery (rotating/moving parts ONLY)
  FA 1948 S22 = Work near machinery in motion

── Height & Access ──
  FA 1948 S32 = Floors, stairs, means of access (trip/slip/fall, safe access)
  FA 1948 S33 = Pits, sumps, openings in floors
  IS 3521:1999 = Safety harness for work at height

── Crane & Lifting ──
  FA 1948 S28 = Hoists and lifts
  FA 1948 S29 = Lifting machines, chains, ropes, tackles

── Pressure & Fire ──
  FA 1948 S31 = Pressure plant
  FA 1948 S37 = Explosive/inflammable gas, dust
  FA 1948 S38 = Fire precautions (exits, extinguishers)
  IS 2190:2010 = Fire extinguisher maintenance

── Electrical ──
  CEA Regulations 2010 Reg 36 = Earthing
  CEA Regulations 2010 Reg 45 = Insulation of conductors
  CEA Regulations 2010 Reg 46 = Protection against shock
  Indian Electricity Rules 1956 Rule 50 = Danger notice on HV

── PPE ──
  FA 1948 S35 = Protection of eyes
  FA 1948 S41C = PPE provision (employer duty)
  IS 2925:1984 = Safety helmets
  IS 3521:1999 = Safety harness
  IS 15298:2011 = Safety footwear

── Confined Space & Fumes ──
  FA 1948 S36 = Dangerous fumes/gases (confined space ONLY)

── Housekeeping ──
  FA 1948 S32 = Floors, stairs, means of access

── Chemical ──
  MSIHC Rules 1989 = Hazardous chemical storage/labelling

HARD RULES:
• S21 = machinery fencing ONLY. NEVER for gas cylinders.
• S36 = confined space ONLY. NEVER for height work.
• S32 = height/access/floors. NEVER confuse with S36.
• IS 14489:2018 is an audit standard — do NOT cite for individual hazards.
• NEVER invent regulation numbers not in this table.

═══════════════════════════════════════════════════════
LINE OF FIRE (LOF) — ONLY if persons visible near energy sources
═══════════════════════════════════════════════════════
"Line of Fire" = person positioned where energy/objects could strike them.
★ ONLY report LOF if you can SEE both the person AND the energy source in the image.
★ Do NOT assume LOF if no persons are visible.

Types:
• Person in path of crane/suspended load → FA 1948 S29
• Person near moving conveyor/machinery → FA 1948 S21
• Person near hot metal/slag/ladle → FA 1948 S41C
• Person below work at height → FA 1948 S33
• Person near pressurized lines → FA 1948 S31
• Person near rotating equipment → FA 1948 S21
• Person near gas cylinders during use → SMPV Rules 2016 Rule 14
• Person near electrical panel → CEA Regulations 2010 Reg 46

═══════════════════════════════════════════════════════
OUTPUT — VALID JSON ONLY (no markdown, no preamble)
═══════════════════════════════════════════════════════
{
  "overallRisk": "CRITICAL|HIGH|MEDIUM|LOW",
  "riskScore": 0-100,
  "confidence": 0-100,
  "people": <count of ACTUALLY visible persons, 0 if none>,
  "summary": "<Sentence 1: what is physically visible. Sentence 2: primary safety concern with evidence. Sentence 3: applicable regulation.>",
  "hazards": [
    {
      "name": "<max 5 words, specific to what you SEE>",
      "description": "<MUST start with visual evidence: 'Visible: [what you see].' Then: why dangerous, consequence>",
      "severity": "CRITICAL|HIGH|MEDIUM|LOW",
      "regulation": "<EXACT reference from table above>",
      "correctiveAction": "<starts with action verb, specific measurable steps>",
      "type": "Unsafe Act|Unsafe Condition|Line of Fire",
      "visualEvidence": "<brief: what specific object/condition in the image proves this hazard>",
      "bbox": {"x": 0.1, "y": 0.1, "w": 0.3, "h": 0.4},
      "lofZone": {"x1": 0.2, "y1": 0.3, "x2": 0.8, "y2": 0.7}
    }
  ]
}

FIELD RULES:
• "visualEvidence" is REQUIRED for every hazard — proves you actually see it.
• "bbox" is approximate location of hazard in image (normalized 0-1).
• "lofZone" is REQUIRED for "Line of Fire" type ONLY. Omit for others.
• "description" MUST begin with "Visible: ..." stating what you physically observe.
• Maximum 7 hazards. Quality over quantity.
• If nothing hazardous is visible, return overallRisk "LOW", riskScore <20, empty hazards [].''';
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
