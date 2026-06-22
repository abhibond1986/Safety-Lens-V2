// lib/services/gemini_direct.dart
// ★ FAILSAFE: Direct Gemini API call from app — bypasses Apps Script entirely
// Used when Apps Script is down, rate-limited, or unreachable.

import 'dart:convert';
import 'package:flutter/foundation.dart' show Uint8List;
import 'package:google_generative_ai/google_generative_ai.dart';

class GeminiDirect {
  // ─── Your Gemini API key (same one used in Apps Script) ─────────────────
  // ★ IMPORTANT: Replace with your actual GOOGLE_AI_KEY
  //   Get it from: https://aistudio.google.com/apikey
  //   It's the same key you have in Apps Script → Script Properties → GOOGLE_AI_KEY
  static const String _apiKey = 'PASTE_YOUR_GOOGLE_AI_KEY_HERE';
  static const String _model = 'gemini-2.5-flash';

  /// Analyse image bytes directly via Gemini — no middleman.
  /// Returns the same JSON structure as Apps Script for compatibility.
  static Future<Map<String, dynamic>?> analyseImageBytes(Uint8List bytes) async {
    try {
      print('GeminiDirect: Starting direct analysis (${bytes.length} bytes)');

      final model = GenerativeModel(
        model: _model,
        apiKey: _apiKey,
        generationConfig: GenerationConfig(
          temperature: 0.2,
          maxOutputTokens: 4096,
          responseMimeType: 'application/json',
        ),
      );

      final prompt = TextPart(_getPrompt());
      final imagePart = DataPart('image/jpeg', bytes);

      final response = await model.generateContent([
        Content.multi([prompt, imagePart])
      ]).timeout(const Duration(seconds: 90));

      final text = response.text;
      if (text == null || text.isEmpty) {
        print('GeminiDirect: Empty response from model');
        return null;
      }

      print('GeminiDirect: Got response (${text.length} chars)');

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
      result['_provider'] = 'gemini_direct';
      result['_model'] = _model;
      result['_source'] = 'gemini_direct';
      result['_isOnline'] = true;

      print('GeminiDirect: SUCCESS — risk=${result['overallRisk']}, '
          'hazards=${(result['hazards'] as List?)?.length ?? 0}');
      return result;
    } catch (e) {
      print('GeminiDirect: FAILED — $e');
      return null;
    }
  }

  static String _getPrompt() {
    return '''You are a senior industrial safety inspector for SAIL (Steel Authority of India Limited), certified under IS 14489:2018. Analyze this workplace photograph for safety hazards.

RULES:
- Only report hazards you can ACTUALLY SEE in the image
- If no workers visible, do NOT report PPE or worker-related hazards
- Better to report 2 real hazards than 7 invented ones
- Bounding box values are normalised 0.0–1.0 (x=left, y=top, w=width, h=height)

OUTPUT FORMAT — valid JSON only:
{
  "overallRisk": "CRITICAL|HIGH|MEDIUM|LOW",
  "riskScore": <0-100>,
  "confidence": <0-100>,
  "people": <count of visible persons, 0 if none>,
  "summary": "What is visible in the photo. Highest priority concern. Regulatory context.",
  "hazards": [
    {
      "name": "max 5 words",
      "severity": "CRITICAL|HIGH|MEDIUM|LOW",
      "description": "What is visible and why dangerous",
      "regulation": "exact section or General safety principles",
      "correctiveAction": "starts with action verb",
      "type": "Unsafe Act|Unsafe Condition",
      "wsaCause": "number. description",
      "bbox": {"x": 0.1, "y": 0.1, "w": 0.3, "h": 0.4}
    }
  ],
  "wsa": ["applicable WSA causes"],
  "preventive": ["long-term measures"],
  "ptw_required": "PTW types or None",
  "nearest_standard": "primary IS standard"
}''';
  }
}
