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

  /// ★ v33: Model fallback chain — smartest models first (2.5-flash proved best results)
  /// Each model has separate quota, so trying all gives us 3x the free-tier capacity
  static const List<String> _modelFallbackChain = [
    'gemini-2.5-flash',    // Best quality — actually produces CRITICAL/HIGH responses
    'gemini-2.0-flash',    // Fast, high quota
    'gemini-2.0-flash-lite', // Last resort — lowest quality but rarely rate-limited
  ];

  // ★ v25: Track if quota is exhausted (429) — all models on same key are blocked
  static bool _quotaExhausted = false;
  static DateTime? _quotaExhaustedAt;

  /// Analyze image for safety hazards
  /// Returns structured hazard data or null on failure
  /// ★ v25: FAST BAIL on 429 — all models share same key/quota, no point trying others
  static Future<Map<String, dynamic>?> analyzeImage(Uint8List imageBytes) async {
    if (!await isConfigured) return null;

    // If quota was exhausted recently (within 60s), skip entirely
    if (_quotaExhausted && _quotaExhaustedAt != null &&
        DateTime.now().difference(_quotaExhaustedAt!).inSeconds < 60) {
      print('GeminiDirectVision: ⏭ Skipping — quota exhausted ${DateTime.now().difference(_quotaExhaustedAt!).inSeconds}s ago');
      return null;
    }
    _quotaExhausted = false;

    final apiKey = await getApiKey();
    final model = await getModel();
    final base64Image = base64Encode(imageBytes);

    // ── Try primary model only — BAIL FAST on 429 ──
    print('GeminiDirectVision: ▶ Model: $model');
    final result = await _callModel(model, apiKey, base64Image);

    // 429 detected — don't try any other model
    if (_quotaExhausted) {
      print('GeminiDirectVision: ⚡ QUOTA EXHAUSTED on $model — bailing immediately (all models blocked)');
      return null;
    }

    if (result != null &&
        result['hazards'] != null &&
        (result['hazards'] as List).isNotEmpty) {
      return result;
    }

    // Only try ONE more fallback (not the whole chain) — and only if NOT quota issue
    final fallback = model == 'gemini-2.0-flash' ? 'gemini-2.0-flash-lite' : 'gemini-2.0-flash';
    print('GeminiDirectVision: ▶ Quick fallback: $fallback');
    final fbResult = await _callModel(fallback, apiKey, base64Image);

    if (_quotaExhausted) {
      print('GeminiDirectVision: ⚡ QUOTA EXHAUSTED — bailing');
      return null;
    }

    if (fbResult != null &&
        fbResult['hazards'] != null &&
        (fbResult['hazards'] as List).isNotEmpty) {
      fbResult['_source'] = 'gemini_direct_$fallback';
      return fbResult;
    }

    print('GeminiDirectVision: ✗ Both models failed');
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
        'maxOutputTokens': 8192,
        'responseMimeType': 'application/json',
      }
    };

    try {
      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(requestBody),
      ).timeout(const Duration(seconds: 15));

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
        print('GeminiDirectVision: [$model] Rate limited (429) — ALL models on this key are blocked');
        _quotaExhausted = true;
        _quotaExhaustedAt = DateTime.now();
        return null;
      } else if (response.statusCode == 403) {
        print('GeminiDirectVision: [$model] API key invalid or quota exceeded (403)');
        _quotaExhausted = true;
        _quotaExhaustedAt = DateTime.now();
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
LINE OF FIRE (LOF) ASSESSMENT — MANDATORY
═══════════════════════════════════════════════════════
"Line of Fire" means a person is positioned where energy release, object movement, or material flow could strike them. You MUST identify 1-2 LOFs if ANY of these are visible:

COMMON LOFs IN STEEL PLANTS:
• Person in path of overhead crane/suspended load → "LOF: Suspended Load"
• Person near moving conveyor belt/roller table → "LOF: Moving Equipment"
• Person near hot metal/slag runner/ladle → "LOF: Molten Metal Path"
• Person in swing radius of excavator/vehicle → "LOF: Vehicle Movement"
• Person below work at height (dropped objects) → "LOF: Falling Objects"
• Person near pressurized lines (steam/hydraulic/gas) → "LOF: Pressurized System"
• Person near rotating equipment without guarding → "LOF: Rotating Parts"
• Person in path of moving railway wagon/loco → "LOF: Rail Movement"
• Person near gas lines/cylinders (CO/O2/acetylene) → "LOF: Gas Release"
• Person in strip/coil pass line in rolling mills → "LOF: Strip Whip"
• Person near electrical panel during switching → "LOF: Arc Flash"
• Person in dumper/tipper reversing zone → "LOF: Reversing Vehicle"

For each LOF identified, set type="Line of Fire" and provide specific action:
  - Define exclusion zone dimensions
  - Specify barricading/signage requirement
  - State communication protocol needed

═══════════════════════════════════════════════════════
CRITICAL RULES — PROFESSIONAL STANDARDS
═══════════════════════════════════════════════════════
1. QUALITY over QUANTITY — report only hazards you can CLEARLY see and justify. Do NOT pad with vague or generic observations. 4-7 specific, well-described hazards are better than 10 vague ones.
2. Cite EXACT regulation sections — never say "applicable regulations".
3. Working at height → FA 1948 S32(c). S36 = confined space ONLY.
4. Every corrective action MUST start with an action verb and be SPECIFIC (not generic like "ensure safety").
5. Bounding box values: normalized 0.0–1.0.
6. If image is too blurry for analysis, return single "Image quality insufficient" hazard.
7. LOF identification is MANDATORY — always check if any person is in a line of fire.

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
      "type": "Unsafe Act|Unsafe Condition|Line of Fire",
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
  /// ★ v33: Added JSON repair for truncated responses
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
      return _validateAndReturn(parsed);
    } catch (e) {
      print('GeminiDirectVision: JSON parse error: $e');
      print('GeminiDirectVision: Raw text: ${text.substring(0, text.length.clamp(0, 300))}');

      // ★ v33: Attempt to repair truncated JSON responses
      final repaired = _repairTruncatedJson(text);
      if (repaired != null) {
        print('GeminiDirectVision: ✓ Repaired truncated JSON — salvaged ${(repaired['hazards'] as List?)?.length ?? 0} hazards');
        return repaired;
      }
      return null;
    }
  }

  /// Validate and add metadata to parsed response
  static Map<String, dynamic> _validateAndReturn(Map<String, dynamic> parsed) {
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
  }

  /// ★ v33: Repair truncated JSON — salvage partial responses
  /// When maxOutputTokens cuts off mid-response, we still have valuable data
  static Map<String, dynamic>? _repairTruncatedJson(String text) {
    try {
      String jsonStr = text.trim();
      // Remove markdown fences
      if (jsonStr.startsWith('```')) {
        jsonStr = jsonStr.replaceAll(RegExp(r'^```\w*\n?'), '').replaceAll(RegExp(r'\n?```$'), '');
      }
      // Must start with {
      final startIdx = jsonStr.indexOf('{');
      if (startIdx < 0) return null;
      jsonStr = jsonStr.substring(startIdx);

      // Strategy 1: Try to close open arrays and objects progressively
      // Find the "hazards" array and try to close it
      final hazardsStart = jsonStr.indexOf('"hazards"');
      if (hazardsStart < 0) {
        // No hazards array found — try to just close the root object
        // Extract top-level fields we can find
        return _extractTopLevelFields(jsonStr);
      }

      // Try closing arrays/objects from the end
      String attempt = jsonStr;
      // Count unclosed brackets
      int braces = 0, brackets = 0;
      bool inString = false;
      bool escaped = false;
      for (int i = 0; i < attempt.length; i++) {
        final c = attempt[i];
        if (escaped) { escaped = false; continue; }
        if (c == '\\') { escaped = true; continue; }
        if (c == '"') { inString = !inString; continue; }
        if (inString) continue;
        if (c == '{') braces++;
        if (c == '}') braces--;
        if (c == '[') brackets++;
        if (c == ']') brackets--;
      }

      // Trim back to last complete object in the hazards array
      // Find the last complete "}" that's part of a hazard object
      int lastCompleteHazard = attempt.lastIndexOf('},');
      if (lastCompleteHazard < 0) lastCompleteHazard = attempt.lastIndexOf('}]');
      if (lastCompleteHazard < 0) {
        // Try to find any complete hazard object
        lastCompleteHazard = attempt.lastIndexOf('}');
      }

      if (lastCompleteHazard > hazardsStart) {
        // Cut after the last complete hazard object and close everything
        attempt = attempt.substring(0, lastCompleteHazard + 1);
        // Close: ], then any remaining }
        attempt += ']';
        // Close remaining braces
        int remainingBraces = 0;
        bool inStr = false;
        bool esc = false;
        for (int i = 0; i < attempt.length; i++) {
          final c = attempt[i];
          if (esc) { esc = false; continue; }
          if (c == '\\') { esc = true; continue; }
          if (c == '"') { inStr = !inStr; continue; }
          if (inStr) continue;
          if (c == '{') remainingBraces++;
          if (c == '}') remainingBraces--;
        }
        for (int i = 0; i < remainingBraces; i++) {
          attempt += '}';
        }

        try {
          final parsed = jsonDecode(attempt) as Map<String, dynamic>;
          if (parsed['hazards'] != null && (parsed['hazards'] as List).isNotEmpty) {
            return _validateAndReturn(parsed);
          }
        } catch (_) {}
      }

      // Strategy 2: Extract fields with regex
      return _extractTopLevelFields(jsonStr);
    } catch (_) {
      return null;
    }
  }

  /// Last-resort field extraction from partial JSON
  static Map<String, dynamic>? _extractTopLevelFields(String json) {
    try {
      final riskMatch = RegExp(r'"overallRisk"\s*:\s*"(\w+)"').firstMatch(json);
      final scoreMatch = RegExp(r'"riskScore"\s*:\s*(\d+)').firstMatch(json);
      final confMatch = RegExp(r'"confidence"\s*:\s*(\d+)').firstMatch(json);
      final peopleMatch = RegExp(r'"people"\s*:\s*(\d+)').firstMatch(json);
      final summaryMatch = RegExp(r'"summary"\s*:\s*"([^"]+)"').firstMatch(json);

      if (riskMatch == null && scoreMatch == null) return null;

      // Try to extract complete hazard objects
      final hazardObjects = <Map<String, dynamic>>[];
      final hazardRegex = RegExp(r'\{\s*"name"\s*:\s*"[^"]+?"[^}]*?"correctiveAction"\s*:\s*"[^"]+?"[^}]*?\}', dotAll: true);
      for (final m in hazardRegex.allMatches(json)) {
        try {
          final h = jsonDecode(m.group(0)!) as Map<String, dynamic>;
          hazardObjects.add(h);
        } catch (_) {}
      }

      if (hazardObjects.isEmpty && riskMatch == null) return null;

      final result = <String, dynamic>{
        'overallRisk': riskMatch?.group(1) ?? 'UNKNOWN',
        'riskScore': int.tryParse(scoreMatch?.group(1) ?? '0') ?? 0,
        'confidence': int.tryParse(confMatch?.group(1) ?? '0') ?? 0,
        'people': int.tryParse(peopleMatch?.group(1) ?? '0') ?? 0,
        'summary': summaryMatch?.group(1) ?? 'Analysis complete (partial response recovered).',
        'hazards': hazardObjects,
        '_source': 'gemini_direct_repaired',
        '_isOnline': true,
      };

      return result;
    } catch (_) {
      return null;
    }
  }
}
