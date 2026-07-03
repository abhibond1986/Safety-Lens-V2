// lib/services/gemini_direct_vision.dart
// ★ v28: Direct Gemini Vision API for hazard image analysis
//
// Uses Google Gemini 2.0 Flash (free tier):
//   - 15 requests per minute
//   - 1 million tokens per day
//   - Supports image input (base64)
//   - No billing required (just an API key from AI Studio)
//
// This is the PRIMARY image analysis provider.
// Falls back to Apps Script if this fails.
//
// Get your free API key: https://aistudio.google.com/apikey

import 'dart:convert';
import 'package:flutter/foundation.dart' show Uint8List;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class GeminiDirectVision {
  static const String _kApiKey = 'gemini_vision_api_key';
  static const String _kModel = 'gemini_vision_model';
  static const String defaultModel = 'gemini-2.0-flash';

  static SharedPreferences? _prefs;

  static Future<void> _ensurePrefs() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  /// Check if Gemini API key is configured
  static Future<bool> get isConfigured async {
    await _ensurePrefs();
    final key = _prefs!.getString(_kApiKey) ?? '';
    return key.isNotEmpty && key.length > 20;
  }

  /// Get stored API key
  static Future<String> getApiKey() async {
    await _ensurePrefs();
    return _prefs!.getString(_kApiKey) ?? '';
  }

  /// Save API key (from Admin panel)
  static Future<void> setApiKey(String key) async {
    await _ensurePrefs();
    await _prefs!.setString(_kApiKey, key.trim());
  }

  /// Get current model
  static Future<String> getModel() async {
    await _ensurePrefs();
    return _prefs!.getString(_kModel) ?? defaultModel;
  }

  /// Set model preference
  static Future<void> setModel(String model) async {
    await _ensurePrefs();
    await _prefs!.setString(_kModel, model);
  }

  /// Available models — ordered by RELIABILITY (fastest + most stable first)
  static const List<Map<String, String>> availableModels = [
    {'id': 'gemini-2.0-flash', 'name': 'Gemini 2.0 Flash (Most reliable, fast)'},
    {'id': 'gemini-2.5-flash', 'name': 'Gemini 2.5 Flash (Smarter, slower)'},
    {'id': 'gemini-2.5-pro', 'name': 'Gemini 2.5 Pro (Most accurate, limited quota)'},
  ];

  /// Fallback model when primary returns low confidence
  static const String _fallbackModel = 'gemini-2.5-pro';

  /// ★ v32: Model fallback chain — reliability order (fastest/highest-quota first)
  static const List<String> _modelFallbackChain = [
    'gemini-2.0-flash',
    'gemini-2.5-flash',
    'gemini-2.0-flash-lite',
  ];

  /// Analyze image for safety hazards
  /// Returns structured hazard data or null on failure
  /// ★ v31: Tries configured model, then falls through entire chain on 429/failure
  static Future<Map<String, dynamic>?> analyzeImage(Uint8List imageBytes) async {
    if (!await isConfigured) return null;

    final apiKey = await getApiKey();
    final model = await getModel();
    final base64Image = base64Encode(imageBytes);

    // ── PRIMARY: Try with configured model ──
    print('GeminiDirectVision: ▶ Primary model: $model');
    final result = await _callModel(model, apiKey, base64Image);

    if (result != null &&
        result['hazards'] != null &&
        (result['hazards'] as List).isNotEmpty) {
      // ── SMART FALLBACK: If confidence < 60 or < 3 hazards, try Pro ──
      final confidence = (result['confidence'] as num?) ?? 0;
      final hazardCount = (result['hazards'] as List).length;
      if ((confidence < 60 || hazardCount < 3) && model != _fallbackModel) {
        print('GeminiDirectVision: ⚠ Low confidence ($confidence) or few hazards ($hazardCount) — trying $_fallbackModel');
        final proResult = await _callModel(_fallbackModel, apiKey, base64Image);
        if (proResult != null) {
          final proHazards = (proResult['hazards'] as List?)?.length ?? 0;
          final proConfidence = (proResult['confidence'] as num?) ?? 0;
          if (proHazards > hazardCount || proConfidence > confidence) {
            proResult['_source'] = 'gemini_direct_pro';
            return proResult;
          }
        }
      }
      return result;
    }

    // ── PRIMARY FAILED: Try fallback models in chain ──
    print('GeminiDirectVision: ✗ Primary failed — trying fallback chain');
    for (final fallbackModel in _modelFallbackChain) {
      if (fallbackModel == model) continue; // already tried
      print('GeminiDirectVision: ▶ Trying fallback: $fallbackModel');
      final fbResult = await _callModel(fallbackModel, apiKey, base64Image);
      if (fbResult != null &&
          fbResult['hazards'] != null &&
          (fbResult['hazards'] as List).isNotEmpty) {
        print('GeminiDirectVision: ✓ Fallback $fallbackModel succeeded');
        fbResult['_source'] = 'gemini_direct_$fallbackModel';
        return fbResult;
      }
    }

    print('GeminiDirectVision: ✗ All models in chain failed');
    return null;
  }

  /// Call a specific Gemini model for image analysis
  static Future<Map<String, dynamic>?> _callModel(String model, String apiKey, String base64Image) async {
    final url = 'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$apiKey';

    final requestBody = {
      'contents': [
        {
          'parts': [
            {
              'text': _getComprehensivePrompt()
            },
            {
              'inline_data': {
                'mime_type': 'image/jpeg',
                'data': base64Image,
              }
            }
          ]
        }
      ],
      'generationConfig': {
        'temperature': 0.3,
        'maxOutputTokens': 4096,
        'responseMimeType': 'application/json',
      }
    };

    try {
      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(requestBody),
      ).timeout(const Duration(seconds: 25));

      if (response.statusCode == 200) {
        // ★ v29 FIX: Force UTF-8 decode for non-English text support
        final responseText = utf8.decode(response.bodyBytes);
        final data = jsonDecode(responseText) as Map<String, dynamic>;
        final candidates = data['candidates'] as List?;
        if (candidates != null && candidates.isNotEmpty) {
          final content = candidates[0]['content'] as Map<String, dynamic>?;
          final parts = content?['parts'] as List?;
          if (parts != null && parts.isNotEmpty) {
            final text = parts[0]['text']?.toString() ?? '';
            return _parseHazardResponse(text);
          }
        }
        print('GeminiDirectVision: [$model] No candidates in response');
        return null;
      } else if (response.statusCode == 429) {
        print('GeminiDirectVision: [$model] Rate limited (429)');
        return null;
      } else if (response.statusCode == 403) {
        print('GeminiDirectVision: [$model] API key invalid or quota exceeded (403)');
        return null;
      } else {
        print('GeminiDirectVision: [$model] Error ${response.statusCode}: ${response.body.substring(0, response.body.length.clamp(0, 200))}');
        return null;
      }
    } catch (e) {
      print('GeminiDirectVision: [$model] Exception: $e');
      return null;
    }
  }

  /// ★ v30: Comprehensive hazard analysis prompt — matches Apps Script quality
  /// Designed to catch ALL visible hazards with proper regulatory citations
  static String _getComprehensivePrompt() {
    return '''You are a senior industrial safety inspector for SAIL (Steel Authority of India Limited), certified under IS 14489:2018 with 20+ years of experience in integrated steel plant safety.

═══════════════════════════════════════════════════════
METHODOLOGY — EXHAUSTIVE SYSTEMATIC INSPECTION
═══════════════════════════════════════════════════════
You MUST conduct a THOROUGH, SYSTEMATIC inspection of the entire image.
Scan the image in zones: foreground → middle ground → background, then left → right.
For EACH zone, check ALL categories below. Do NOT stop after finding 2-3 hazards.
Your goal is to identify EVERY visible hazard — a comprehensive report is expected.

═══════════════════════════════════════════════════════
STEP 1 — OBSERVE THE IMAGE (do this silently first)
═══════════════════════════════════════════════════════
Before listing any hazard, internally describe:
  • What is the scene? (Workshop, storage area, panel room, walkway, etc.)
  • What equipment, structures, or surfaces are visible?
  • Are there any people? How many? What are they doing?
  • What is the lighting and image clarity like?
  • What materials/substances are stored or in use?

═══════════════════════════════════════════════════════
STEP 2 — GROUNDING RULES
═══════════════════════════════════════════════════════
Only report hazards that are ACTUALLY VISIBLE in the image.
However, when you CAN see relevant items (cylinders, drums, extinguishers, wires, etc.), you MUST thoroughly analyze ALL associated hazards.

If gas cylinders ARE visible → check ALL of: securing, segregation, valve caps, colour coding, signage, separation distances, ventilation, storage arrangement.
If fire extinguishers ARE visible → check ALL of: accessibility, obstruction, mounting, inspection tags, appropriate type.
If electrical equipment IS visible → check ALL of: exposed parts, signage, clearances, earthing, insulation.
If storage areas ARE visible → check ALL of: segregation, labelling, containment, housekeeping, access routes.

═══════════════════════════════════════════════════════
HAZARD CHECKLIST — Check EVERY applicable category
═══════════════════════════════════════════════════════

── GAS CYLINDER STORAGE (if any cylinders visible) ──
  • Cylinders not chained/secured against falling → SMPV Rules 2016 Rule 14
  • Full and empty cylinders not segregated → SMPV Rules 2016 Rule 14
  • Oxidizers (O₂) and fuel gases (acetylene, LPG) not separated by 6m or firewall → SMPV Rules 2016 Rule 14 Table-3
  • Valve protection caps missing on idle cylinders → SMPV Rules 2016 Rule 10
  • Cylinders not stored upright → SMPV Rules 2016 Rule 14
  • Cylinder contents not clearly identified/labelled → IS 4379:1981
  • No dedicated ventilated storage area → SMPV Rules 2016 Rule 14
  • Combustible materials stored near cylinders → FA 1948 S37
  • No "No Smoking / No Open Flame" signage → FA 1948 S37 + General safety principles
  • Cylinders exposed to heat sources → SMPV Rules 2016 Rule 14

── FIRE SAFETY (if extinguishers, drums, flammables visible) ──
  • Fire extinguishers obstructed or inaccessible → FA 1948 S38 + IS 2190:2010
  • Extinguisher access path blocked by materials → FA 1948 S38
  • Flammable materials near ignition sources → FA 1948 S37
  • Combustible drums/containers near gas cylinders → FA 1948 S37
  • No fire exit/emergency route signage → FA 1948 S38(1)
  • Missing or expired extinguisher inspection tags → IS 2190:2010
  • Wrong type of extinguisher for hazard class → IS 2190:2010

── HOUSEKEEPING & ACCESS ──
  • Hoses, cables, materials on floor creating trip hazard → FA 1948 S32(b)
  • Congested storage blocking emergency access → FA 1948 S32(a)
  • Spills (oil/water/chemical) creating slip hazard → FA 1948 S32(b)
  • Tools/materials not properly stored → General safety principles
  • Walkways/aisles obstructed → FA 1948 S32(a)

── ELECTRICAL HAZARDS (if panels, wires, equipment visible) ──
  • Exposed/damaged wiring → CEA Regulations 2023 Reg 46
  • Open electrical panels → CEA Regulations 2023 Reg 20
  • Missing DANGER signs on HV apparatus (>250V) → CEA Regulations 2023 Reg 20
  • Missing insulating mats → CEA Regulations 2023 Reg 21
  • Inadequate clearance (<1.0m) before switchboards → CEA Regulations 2023 Reg 39

── IDENTIFICATION & SIGNAGE ──
  • Missing hazard warning signs → General safety principles
  • Equipment ID plates illegible or missing → General safety principles
  • No "No Smoking" signage in hazardous area → FA 1948 S37
  • No emergency contact information displayed → FA 1948 S41B(4)
  • Unlabelled containers/drums → Manufacture, Storage & Import of Hazardous Chemical Rules 1989

── STORAGE & CHEMICAL SEGREGATION ──
  • Incompatible materials stored together → FA 1948 S37 + MSIHC Rules 1989
  • Chemicals without secondary containment → FA 1948 S37
  • Drums/containers without proper labelling → MSIHC Rules 1989
  • Materials stored directly on ground (corrosion risk) → General safety principles

── EQUIPMENT INTEGRITY ──
  • Corroded structural elements → FA 1948 S39 + IS 14489:2018 Clause 4
  • Damaged equipment cladding → FA 1948 S39
  • Missing safety guards on machinery → FA 1948 S21
  • Visible cracks, deformation, or leaks → FA 1948 S39

── WORKER-RELATED (only if workers ACTUALLY visible) ──
  • Missing PPE (helmet IS 2925, footwear IS 5852, goggles IS 5983, gloves IS 5983) → FA 1948 S41C
  • Worker at height without fall arrest → FA 1948 S32(c) + IS 3521:1999
  • Unsafe body positioning → General safety principles

═══════════════════════════════════════════════════════
GAS CYLINDER COLOUR CODES (IS 4379:1981)
═══════════════════════════════════════════════════════
  Oxygen = Black body / White neck
  Acetylene = Maroon
  Nitrogen = Grey body / Black neck
  Hydrogen = Red
  Argon = Peacock Blue
  CO₂ = Aluminium/Silver
  LPG = Dark Red/Silver
  Chlorine = Golden Yellow

═══════════════════════════════════════════════════════
PIPE vs WIRE DIFFERENTIATION
═══════════════════════════════════════════════════════
  If mounted on brackets/clamps/pipe supports → PIPE (IS 2379:1963 colour codes)
  Only label as wire/cable if PVC insulation, cable trays, conduit, or junction boxes visible.

═══════════════════════════════════════════════════════
CRITICAL RULES
═══════════════════════════════════════════════════════
1. Be EXHAUSTIVE — report ALL visible hazards. A thorough report with 8-12 hazards is expected when the scene is complex.
2. Cite EXACT regulation sections — never say "applicable regulations".
3. Working at height → FA 1948 S32(c). S36 = confined space ONLY.
4. Every corrective action MUST start with an action verb.
5. Bounding box values: normalized 0.0–1.0.
6. If image is too blurry for analysis, return single "Image quality insufficient" hazard.

═══════════════════════════════════════════════════════
OUTPUT FORMAT — valid JSON ONLY, no markdown, no preamble
═══════════════════════════════════════════════════════
{
  "overallRisk": "CRITICAL|HIGH|MEDIUM|LOW",
  "riskScore": 0-100,
  "confidence": 0-100,
  "people": <integer count of ACTUALLY VISIBLE persons, 0 if none>,
  "summary": "Sentence 1: literal description of what is visible. Sentence 2: highest-priority concern. Sentence 3: regulatory context.",
  "hazards": [
    {
      "name": "max 5 words describing what is VISIBLE",
      "severity": "CRITICAL|HIGH|MEDIUM|LOW",
      "description": "What is visible, why dangerous, what could happen.",
      "regulation": "exact section e.g. SMPV Rules 2016 Rule 14",
      "correctiveAction": "starts with action verb; specific steps",
      "type": "Unsafe Act|Unsafe Condition",
      "wsaCause": "number. description e.g. 5. Equipment failure",
      "bbox": {"x": 0.1, "y": 0.1, "w": 0.3, "h": 0.4}
    }
  ],
  "wsa": ["list of WSA causes ACTUALLY applicable"],
  "preventive": ["long-term measure with IS standard if applicable"],
  "ptw_required": "PTW types needed or \\"None\\"",
  "nearest_standard": "primary IS standard or \\"General safety principles\\""
}

''';
  }

  /// Parse the AI text response into structured hazard data
  static Map<String, dynamic>? _parseHazardResponse(String text) {
    try {
      String jsonStr = text.trim();
      // Remove markdown fences if present
      if (jsonStr.startsWith('```')) {
        jsonStr = jsonStr.replaceAll(RegExp(r'^```\w*\n?'), '').replaceAll(RegExp(r'\n?```$'), '');
      }
      // Extract JSON object
      final jsonMatch = RegExp(r'\{[\s\S]*\}').firstMatch(jsonStr);
      if (jsonMatch != null) jsonStr = jsonMatch.group(0)!;

      final parsed = jsonDecode(jsonStr) as Map<String, dynamic>;

      // Validate required fields
      if (parsed['hazards'] == null) parsed['hazards'] = [];
      if (parsed['overallRisk'] == null) parsed['overallRisk'] = 'UNKNOWN';
      if (parsed['riskScore'] == null) parsed['riskScore'] = 0;
      if (parsed['confidence'] == null) parsed['confidence'] = 0;
      if (parsed['people'] == null) parsed['people'] = 0;
      if (parsed['summary'] == null) parsed['summary'] = 'Analysis complete.';

      // Add metadata
      parsed['_source'] = 'gemini_direct';
      parsed['_isOnline'] = true;

      return parsed;
    } catch (e) {
      print('GeminiDirectVision: JSON parse error: $e');
      print('GeminiDirectVision: Raw text: ${text.substring(0, text.length.clamp(0, 300))}');
      return null;
    }
  }
}
