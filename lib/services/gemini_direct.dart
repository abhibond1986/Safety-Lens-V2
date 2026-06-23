// lib/services/gemini_direct.dart
// ★ v20 FAILSAFE: Direct Gemini API call from app — bypasses Apps Script entirely
// FASTEST PATH: App → Google AI (single hop, ~5-15 seconds)
// Used as PRIMARY provider — no middleman, no Cloudinary upload needed first.

import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart' show Uint8List;
import 'package:google_generative_ai/google_generative_ai.dart';
import 'api_keys.dart';

class GeminiDirect {
  // Key is fetched at runtime from Apps Script (see ApiKeys.init())
  // Fallback: --dart-define=GOOGLE_AI_KEY=... at build time
  static String get _googleApiKey => ApiKeys.googleKey;

  // Models to try (newest first, fallback to stable)
  static const List<String> _models = [
    'gemini-2.5-flash',
    'gemini-2.0-flash',
  ];

  // Timeouts — aggressive for speed, fail fast to reach working provider
  static const int _timeoutPerAttempt = 15; // seconds per model attempt
  static const int _maxRetries = 1; // 1 retry per model = 2 attempts total

  /// Primary analysis method — fast, single hop.
  /// Returns the standard hazard JSON structure on success, null on failure.
  static Future<Map<String, dynamic>?> analyseImageBytes(Uint8List bytes) async {
    if (_googleApiKey.isEmpty) {
      print('GeminiDirect: ❌ GOOGLE_AI_KEY is EMPTY — ensure ApiKeys.init() was called');
      print('GeminiDirect: ApiKeys.hasGoogleKey=${ApiKeys.hasGoogleKey}, '
          'ApiKeys.googleKey.length=${ApiKeys.googleKey.length}');
      return null;
    }

    print('GeminiDirect: Starting direct analysis (${bytes.length} bytes, '
        '${_models.length} models available, '
        'key=${_googleApiKey.substring(0, 8)}...${_googleApiKey.substring(_googleApiKey.length - 4)})');

    for (int modelIdx = 0; modelIdx < _models.length; modelIdx++) {
      final modelName = _models[modelIdx];
      print('GeminiDirect: Trying model $modelName (${modelIdx + 1}/${_models.length})');

      for (int attempt = 0; attempt <= _maxRetries; attempt++) {
        try {
          final result = await _callModel(modelName, bytes, attempt);
          if (result != null) {
            result['_provider'] = 'gemini_direct';
            result['_model'] = modelName;
            result['_source'] = 'gemini_direct';
            result['_isOnline'] = true;
            print('GeminiDirect: SUCCESS with $modelName — '
                'risk=${result['overallRisk']}, '
                'hazards=${(result['hazards'] as List?)?.length ?? 0}');
            return result;
          }
        } on TimeoutException {
          print('GeminiDirect: Timeout on $modelName attempt ${attempt + 1}');
          if (attempt < _maxRetries) {
            await Future.delayed(const Duration(seconds: 2));
          }
        } catch (e, stackTrace) {
          final errStr = e.toString();
          print('GeminiDirect: ❌ Error on $modelName attempt ${attempt + 1}: $errStr');

          // Log specific error types for debugging
          if (errStr.contains('API_KEY') || errStr.contains('api key') || errStr.contains('401') || errStr.contains('403')) {
            print('GeminiDirect: 🔑 API KEY ISSUE — key may be invalid, expired, or lacks permissions');
            print('GeminiDirect: Key used: ${_googleApiKey.substring(0, 8)}...${_googleApiKey.substring(_googleApiKey.length - 4)}');
            return null; // No point retrying with same key — bail ALL models
          }

          // QUOTA EXHAUSTION — affects ALL models on this key, bail immediately
          if (errStr.contains('quota') || errStr.contains('Quota exceeded') || errStr.contains('RESOURCE_EXHAUSTED')) {
            print('GeminiDirect: 🚫 QUOTA EXHAUSTED — affects all models, skipping to next provider');
            return null; // Don't waste time trying other models
          }

          // If model not found, skip to next model immediately
          if (errStr.contains('404') || errStr.contains('not found')) {
            print('GeminiDirect: Model $modelName not available, trying next...');
            break;
          }

          // 503 overloaded — worth ONE quick retry, then move to next model
          if (errStr.contains('503') || errStr.contains('overloaded')) {
            if (attempt < _maxRetries) {
              print('GeminiDirect: ⏳ Model overloaded, quick retry in 2s...');
              await Future.delayed(const Duration(seconds: 2));
            } else {
              print('GeminiDirect: ⏳ Model overloaded, moving to next model...');
              break; // Don't waste more time, try next model
            }
          }

          // 429 rate limit — brief wait then move on
          if (errStr.contains('429')) {
            print('GeminiDirect: ⏳ Rate limited, moving to next model...');
            break; // Rate limit usually means "wait minutes", not seconds
          }

          // Log stack trace for unexpected errors
          if (!errStr.contains('429') && !errStr.contains('503') && !errStr.contains('404') && !errStr.contains('quota')) {
            final traceLines = stackTrace.toString().split('\n').take(3).join('\n');
            print('GeminiDirect: Stack: $traceLines');
          }
        }
      }
    }

    print('GeminiDirect: All models failed');
    return null;
  }

  /// Call a specific model with timeout
  static Future<Map<String, dynamic>?> _callModel(
      String modelName, Uint8List bytes, int attempt) async {
    final model = GenerativeModel(
      model: modelName,
      apiKey: _googleApiKey,
      generationConfig: GenerationConfig(
        temperature: 0.2,
        maxOutputTokens: 4096,
        responseMimeType: 'application/json',
      ),
    );

    final prompt = TextPart(_getSailPrompt());
    final imagePart = DataPart('image/jpeg', bytes);

    final response = await model.generateContent([
      Content.multi([prompt, imagePart])
    ]).timeout(Duration(seconds: _timeoutPerAttempt));

    final text = response.text;
    if (text == null || text.isEmpty) {
      print('GeminiDirect: ⚠️ Empty response from $modelName');
      print('GeminiDirect: Response candidates: ${response.candidates?.length ?? 0}');
      if (response.candidates != null && response.candidates!.isNotEmpty) {
        print('GeminiDirect: Finish reason: ${response.candidates!.first.finishReason}');
      }
      if (response.promptFeedback != null) {
        print('GeminiDirect: Prompt feedback: ${response.promptFeedback}');
      }
      return null;
    }

    // Parse JSON — handle markdown wrapping
    String cleaned = text.trim();
    if (cleaned.startsWith('```json')) cleaned = cleaned.substring(7);
    if (cleaned.startsWith('```')) cleaned = cleaned.substring(3);
    if (cleaned.endsWith('```')) cleaned = cleaned.substring(0, cleaned.length - 3);
    final firstBrace = cleaned.indexOf('{');
    final lastBrace = cleaned.lastIndexOf('}');
    if (firstBrace >= 0 && lastBrace > firstBrace) {
      cleaned = cleaned.substring(firstBrace, lastBrace + 1);
    }

    final result = jsonDecode(cleaned.trim()) as Map<String, dynamic>;
    if (result['people'] == null) result['people'] = 0;
    return result;
  }

  /// Full SAIL analysis prompt with pipe/wire differentiation
  static String _getSailPrompt() {
    return 'You are a senior industrial safety inspector for SAIL '
        '(Steel Authority of India Limited), certified under IS 14489:2018 '
        'with 20+ years of experience in integrated steel plant safety. '
        'Your job is to honestly report what is visible in this photograph — '
        'no more, no less.\n\n'
        '═════════════════════════════════════════════════════════\n'
        'STEP 1 — OBSERVE THE IMAGE (do this silently first)\n'
        '═════════════════════════════════════════════════════════\n'
        'Before listing any hazard, internally describe:\n'
        '  • What is the scene? (Workshop, vessel, panel, walkway, etc.)\n'
        '  • What equipment, structures, or surfaces are visible?\n'
        '  • Are there any people? How many? What are they doing?\n'
        '  • What is the lighting and image clarity like?\n\n'
        'Your "summary" field MUST begin with a literal description of '
        'what is visible in the photo — not a generic safety statement.\n\n'
        '═════════════════════════════════════════════════════════\n'
        'STEP 2 — GROUNDING RULES (NEVER violate)\n'
        '═════════════════════════════════════════════════════════\n'
        'A hazard you cannot SEE is a hazard that does NOT EXIST in this image.\n\n'
        'NEVER invent hazards based on what is "typical" for steel plants.\n'
        'NEVER report a hazard category just because it would be common.\n\n'
        'Specifically:\n'
        '  • If NO worker is visible → you may NOT report "fall from height", '
        '"lack of fall protection", "no harness", "no PPE", "improper body position", '
        'or any other worker-related hazard.\n'
        '  • If NO elevated work surface, scaffold, edge, platform, or opening is '
        'visible → you may NOT report fall-from-height risk.\n'
        '  • If NO active machinery operation, energised circuit work, or hot work '
        'is visible → you may NOT report procedural violations (no LOTO, no PTW, '
        'no permit, etc).\n'
        '  • If NO gas cylinders, chemicals, or flammables are visible → you may '
        'NOT report storage/segregation hazards.\n\n'
        'Better to report 2 real hazards than 7 hazards where 5 are inventions.\n\n'
        '═════════════════════════════════════════════════════════\n'
        'STEP 3 — IMAGE QUALITY ESCAPE HATCH\n'
        '═════════════════════════════════════════════════════════\n'
        'If the image is too blurry, dark, pixelated, low-resolution, or '
        'tightly cropped to identify hazards confidently:\n'
        '  • Set "confidence" to a LOW value (30–50).\n'
        '  • Return ONE hazard only with name "Image quality insufficient"\n'
        '  • Do NOT invent additional hazards to fill the list.\n\n'
        '═════════════════════════════════════════════════════════\n'
        'PIPE vs WIRE DIFFERENTIATION (CRITICAL for steel plants)\n'
        '═════════════════════════════════════════════════════════\n'
        'Steel plants have THOUSANDS of pipes but few exposed wires.\n'
        'Before labelling anything as "electrical wire", apply these rules:\n\n'
        '  Rule 1: If it is mounted on brackets/clamps/pipe supports → PIPE\n'
        '  Rule 2: If it is colour-coded (Blue=Air, Yellow=Gas, Green=Water,\n'
        '           Red=Fire, Black=Oil, Silver/Aluminium=Steam) → PIPE\n'
        '  Rule 3: If it runs along pipe racks or between equipment → PIPE\n'
        '  Rule 4: If it has flanges, valves, or threaded joints → PIPE\n'
        '  Rule 5: If diameter is >6mm and material looks metallic → PIPE\n'
        '  Rule 6: Only label as "electrical wire/cable" if you see:\n'
        '           — PVC/rubber insulation sheathing\n'
        '           — Cable trays (perforated metal trays)\n'
        '           — Conduit (corrugated flexible tubing)\n'
        '           — Junction boxes at endpoints\n'
        '           — Multiple thin conductors bundled together\n\n'
        '═════════════════════════════════════════════════════════\n'
        'HAZARD CATEGORIES (match what you actually see)\n'
        '═════════════════════════════════════════════════════════\n\n'
        '── EQUIPMENT INTEGRITY & CORROSION ──\n'
        '  • Corroded structural elements, brackets, supports, vessels, pipework\n'
        '  • Corrosion Under Insulation (CUI)\n'
        '  • Damaged/deteriorated equipment cladding or insulation\n'
        '  • Visible cracks, deformation, or leaks\n'
        '  • Unsecured equipment, plates, panels, covers\n'
        '  • Missing safety guards on machinery (FA 1948 S21)\n'
        '  • Missing pressure relief devices or gauges (FA 1948 S31)\n\n'
        '── ELECTRICAL HAZARDS ──\n'
        '  • Exposed/damaged electrical wiring, cables, junction boxes\n'
        '  • Open electrical panels with exposed live parts\n'
        '  • Missing DANGER notices on apparatus >250V (CEA Reg 20)\n'
        '  • Missing insulating mats in front of panels (CEA Reg 21)\n\n'
        '── HOUSEKEEPING ──\n'
        '  • Debris, scale, or deposits on equipment, floors, walkways\n'
        '  • Oil/water/chemical spills creating slip risk\n'
        '  • Tools, materials, or stored items obstructing access routes\n\n'
        '── WORKER-RELATED (only if workers ACTUALLY visible) ──\n'
        '  • Worker at height without fall arrest — FA 1948 S32(c)\n'
        '  • Worker without required PPE\n'
        '  • Worker in danger zone or unsafe body position\n\n'
        '═════════════════════════════════════════════════════════\n'
        'CITATION RULES\n'
        '═════════════════════════════════════════════════════════\n'
        '1. Working at height → ALWAYS cite FA 1948 S32(c) — NEVER S36.\n'
        '2. S36 = confined space / dangerous fumes ONLY.\n'
        '3. Corrosion → FA 1948 S39 + IS 14489:2018 Clause 4.\n'
        '4. Cite a regulation ONLY if visible. If unsure → "General safety principles".\n'
        '5. Every corrective action MUST start with an action verb.\n'
        '6. Bounding box: normalised 0.0–1.0 (x=left, y=top, w=width, h=height).\n\n'
        '═════════════════════════════════════════════════════════\n'
        'OUTPUT FORMAT — valid JSON ONLY, no markdown, no preamble\n'
        '═════════════════════════════════════════════════════════\n'
        '{\n'
        '  "overallRisk": "CRITICAL|HIGH|MEDIUM|LOW",\n'
        '  "riskScore": <0-100>,\n'
        '  "confidence": <0-100>,\n'
        '  "people": <integer count of ACTUALLY VISIBLE persons, 0 if none>,\n'
        '  "summary": "Literal description of photo. Highest concern. Regulatory context.",\n'
        '  "hazards": [\n'
        '    {\n'
        '      "name": "max 5 words describing what is VISIBLE",\n'
        '      "severity": "CRITICAL|HIGH|MEDIUM|LOW",\n'
        '      "description": "What is visible and why dangerous",\n'
        '      "regulation": "exact section or General safety principles",\n'
        '      "correctiveAction": "starts with action verb",\n'
        '      "type": "Unsafe Act|Unsafe Condition",\n'
        '      "wsaCause": "number. description e.g. 5. Equipment failure",\n'
        '      "bbox": {"x": 0.1, "y": 0.1, "w": 0.3, "h": 0.4}\n'
        '    }\n'
        '  ],\n'
        '  "wsa": ["list of WSA causes ACTUALLY applicable"],\n'
        '  "preventive": ["long-term measure with IS standard if applicable"],\n'
        '  "ptw_required": "PTW types needed or None",\n'
        '  "nearest_standard": "primary IS standard or General safety principles"\n'
        '}\n\n'
        'REMEMBER:\n'
        '  • An empty hazards list is acceptable if truly no hazards.\n'
        '  • A SHORT list of REAL hazards is far better than a LONG list with inventions.\n'
        '  • Your reputation depends on accuracy, not on finding the most hazards.';
  }
}
