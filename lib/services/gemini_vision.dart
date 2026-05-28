import 'dart:convert';
import 'dart:io' show File, SocketException;
import 'package:flutter/foundation.dart' show Uint8List, kIsWeb;
import 'package:http/http.dart' as http;
import 'local_ai.dart';

/// Gemini Vision API service for SAIL Safety Lens.
/// Uses Google Gemini 1.5 Flash — free tier 1500 req/day.
/// IS 14489:1998 + Ministry of Steel + Factories Act 1948 compliant.
class GeminiVision {
  // ============================================================
  // PASTE YOUR GEMINI API KEY HERE (between the quotes):
  // Get a free key at: https://aistudio.google.com/apikey
  // ============================================================
  static const String _apiKey ='AQ.Ab8RN6KQZBbnQQ21z5jfqIp7mVmWJWRatWidqxvAEqub9cNxBA';

  static const String _endpoint =
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent';

  static const String _safetyPrompt = '''
You are an expert industrial safety inspector for Steel Authority of India Limited (SAIL).
Conduct an EXHAUSTIVE safety audit using these authoritative standards:

AUTHORITATIVE FRAMEWORK:
1. IS 14489:1998 — Code of Practice on Occupational Safety & Health Audit (Iron & Steel Industry)
2. Ministry of Steel Govt of India — Safety Guidelines for Iron & Steel Sector (2023)
3. Factories Act 1948 — Sections 21-41 (machinery, hoists, lifting, PPE, fire, height, gas)
4. SAIL Standard Operating Procedures
5. Indian Standards: IS 2925 (helmet), IS 3521 (harness), IS 5852 (shoes), IS 6994 (gloves), IS 4770 (eye), IS 9167 (ear), IS 8519 (respiratory), IS 2750 (scaffolding), IS 7689 (LOTO), IS 4912 (guardrails)
6. WSA 13 Causes framework
7. DGMS guidelines for confined space and explosive atmospheres

CRITICAL — DO NOT HALLUCINATE:
- Only report hazards ACTUALLY visible in the photo
- DO NOT invent details like "liquid on floor" if no liquid is visible
- DO NOT add generic hazards that are not present
- LOOK CAREFULLY at: worker postures, what they stand on, what is in hands, edges, heights, machinery exposure, PPE worn vs missing, electrical exposures, fire/heat sources, ergonomics

EXHAUSTIVE CHECKLIST (apply to EVERY photo):
1. PPE — helmet (IS 2925), shoes (IS 5852), gloves (IS 6994), eye/face (IS 4770), hi-vis, hearing (IS 9167), respiratory (IS 8519), harness (IS 3521 required for >2m height)
2. Working at Height — anchor points, double lanyard, edge protection, scaffolding tagged (IS 2750), ladder 3-point contact
3. Posture/Ergonomics — twisted spine, stretching, awkward reach, unstable surface
4. Structural — guardrails (IS 4912), toe-boards, edge protection, scaffold integrity
5. Housekeeping (only if VISIBLY present) — actual debris/spills/cables/blocked aisles you can SEE
6. Machinery Guarding (Factories Act §21) — exposed moving parts, pinch points
7. Electrical — exposed conductors, missing covers, no LOTO, IE Rules §51 distances
8. Hot Work — welding screens, fire watch, combustibles cleared, extinguishers
9. Confined Space — PTW, ventilation, atmosphere test
10. Material Handling — improper lifting, unstable stacks, sharp edges, suspended loads
11. Environmental — visible smoke/dust/heat, lighting (§17 — 50 lux min)
12. Signage — missing hazard signs, blocked emergency exits

For EACH hazard ACTUALLY seen provide:
- name (5 words max, specific to what you see)
- severity (CRITICAL/HIGH/MEDIUM/LOW per IS 14489 risk matrix)
- description (1-2 sentences describing EXACTLY what you observe in this photo, no generic content)
- regulation (cite specific: "IS 14489 § / Factories Act § / IS 3521 / MoS Ch.")
- correctiveAction (concrete action per SAIL SOP)
- box: {l, t, w, h} as 0-1 decimals (precise bounding box)

ALSO provide:
- overallRisk (CRITICAL/HIGH/MEDIUM/LOW — highest of all hazards)
- riskScore (0-100 per IS 14489 quantitative matrix)
- confidence (0-100)
- summary (3-4 sentences SPECIFIC to this photo)
- wsa (array from WSA 13: "1. Failure to follow procedure", "2. Lack of hazard awareness", "3. Improper PPE", "4. Unsafe positioning", "5. Equipment failure", "6. Communication gaps", "7. Human error", "8. Poor housekeeping", "9. Lack of supervision", "10. Fatigue", "11. Unauthorized operation", "12. Inadequate isolation", "13. Environmental conditions")
- preventive (4-5 measures referencing IS 14489 audit elements)

Aim for 3-8 distinct hazards in workplace photos. Zero is fine for safe scenes.

Respond with ONLY valid JSON (no markdown):
{"overallRisk":"CRITICAL","riskScore":85,"confidence":92,"summary":"...","hazards":[{"name":"...","severity":"CRITICAL","description":"...","regulation":"...","correctiveAction":"...","box":{"l":0.2,"t":0.1,"w":0.3,"h":0.4}}],"wsa":[...],"preventive":[...]}

If the image is NOT a workplace photo, return overallRisk LOW with empty hazards.
''';

  /// Analyse an image file using Gemini Vision (mobile/desktop).
  static Future<Map<String, dynamic>?> analyseImage(File imageFile) async {
    final bytes = await imageFile.readAsBytes();
    return analyseImageBytes(bytes);
  }

  /// Analyse image bytes — works on web AND mobile.
  static Future<Map<String, dynamic>?> analyseImageBytes(Uint8List bytes) async {
    if (_apiKey == 'YOUR_GEMINI_API_KEY_HERE' || _apiKey.isEmpty) {
      throw Exception(
        'Gemini API key not configured. Please paste your key in lib/services/gemini_vision.dart line 14.',
      );
    }

    try {
      final base64Image = base64Encode(bytes);

      final response = await http.post(
        Uri.parse('$_endpoint?key=$_apiKey'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'contents': [
            {
              'parts': [
                {'text': _safetyPrompt},
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
            'temperature': 0.2,
            'maxOutputTokens': 4000,
            'responseMimeType': 'application/json',
          },
          'safetySettings': [
            {'category': 'HARM_CATEGORY_HARASSMENT', 'threshold': 'BLOCK_NONE'},
            {'category': 'HARM_CATEGORY_HATE_SPEECH', 'threshold': 'BLOCK_NONE'},
            {'category': 'HARM_CATEGORY_SEXUALLY_EXPLICIT', 'threshold': 'BLOCK_NONE'},
            {'category': 'HARM_CATEGORY_DANGEROUS_CONTENT', 'threshold': 'BLOCK_NONE'},
          ],
        }),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) {
        throw Exception('Gemini HTTP ${response.statusCode}: ${response.body}');
      }

      final data = jsonDecode(response.body);
      String text = data['candidates']?[0]?['content']?['parts']?[0]?['text'] ?? '';
      text = text.trim();
      if (text.startsWith('```json')) text = text.substring(7);
      if (text.startsWith('```')) text = text.substring(3);
      if (text.endsWith('```')) text = text.substring(0, text.length - 3);

      final result = jsonDecode(text.trim());
      result['_source'] = 'gemini';
      return result;
    } catch (e) {
      // On network error or any failure: fall back to demo analysis
      if (kIsWeb || e is SocketException) {
        final fallback = LocalAI.demoAnalysis();
        fallback['_source'] = 'offline_fallback';
        return fallback;
      }
      rethrow;
    }
  }

  static bool get isConfigured =>
      _apiKey != 'YOUR_GEMINI_API_KEY_HERE' && _apiKey.isNotEmpty;
}
