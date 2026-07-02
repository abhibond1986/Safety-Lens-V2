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

  /// Available models
  static const List<Map<String, String>> availableModels = [
    {'id': 'gemini-2.0-flash', 'name': 'Gemini 2.0 Flash (Free, fast)'},
    {'id': 'gemini-2.0-flash-lite', 'name': 'Gemini 2.0 Flash Lite (Fastest, free)'},
    {'id': 'gemini-1.5-flash', 'name': 'Gemini 1.5 Flash (Stable)'},
  ];

  /// Analyze image for safety hazards
  /// Returns structured hazard data or null on failure
  static Future<Map<String, dynamic>?> analyzeImage(Uint8List imageBytes) async {
    if (!await isConfigured) return null;

    final apiKey = await getApiKey();
    final model = await getModel();
    final base64Image = base64Encode(imageBytes);

    final url = 'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$apiKey';

    final requestBody = {
      'contents': [
        {
          'parts': [
            {
              'text': '''You are an industrial safety hazard detection AI for SAIL (Steel Authority of India Limited).

Analyze this image for workplace safety hazards.

Respond in STRICT JSON format:
{
  "overallRisk": "LOW" or "MEDIUM" or "HIGH" or "CRITICAL",
  "riskScore": 0-100,
  "confidence": 0-100,
  "people": <number of people visible>,
  "hazards": [
    {
      "type": "PPE Violation" or "Unsafe Condition" or "Unsafe Act" or "Housekeeping" or "Fire Risk" or "Electrical" or "Fall Hazard" or "Chemical" or "Ergonomic" or "Other",
      "description": "specific description of the hazard",
      "severity": "LOW" or "MEDIUM" or "HIGH" or "CRITICAL",
      "location": "where in the image (e.g., foreground, left side, background)",
      "recommendation": "corrective action recommended"
    }
  ],
  "ppeStatus": {
    "helmet": "worn" or "missing" or "not_applicable",
    "vest": "worn" or "missing" or "not_applicable",
    "gloves": "worn" or "missing" or "not_applicable",
    "goggles": "worn" or "missing" or "not_applicable",
    "shoes": "safety" or "missing" or "not_applicable",
    "mask": "worn" or "missing" or "not_applicable"
  },
  "summary": "2-3 sentence summary of overall safety status and key findings"
}

RULES:
- Be thorough — identify ALL visible hazards, no matter how minor
- For each person visible, check PPE compliance
- Consider: housekeeping, ergonomics, guarding, signage, fire safety, electrical safety
- If image is not workplace/industrial, return riskScore 0 with empty hazards and note in summary
- Use SAIL/Indian industrial safety standards as reference
- Be specific in descriptions — avoid vague language

Respond ONLY with JSON — no markdown fences, no explanation outside JSON.'''
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
        'temperature': 0.2,
        'maxOutputTokens': 2048,
      }
    };

    try {
      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(requestBody),
      ).timeout(const Duration(seconds: 45));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final candidates = data['candidates'] as List?;
        if (candidates != null && candidates.isNotEmpty) {
          final content = candidates[0]['content'] as Map<String, dynamic>?;
          final parts = content?['parts'] as List?;
          if (parts != null && parts.isNotEmpty) {
            final text = parts[0]['text']?.toString() ?? '';
            return _parseHazardResponse(text);
          }
        }
        print('GeminiDirectVision: No candidates in response');
        return null;
      } else if (response.statusCode == 429) {
        print('GeminiDirectVision: Rate limited (429) — fallback to Apps Script');
        return null;
      } else if (response.statusCode == 403) {
        print('GeminiDirectVision: API key invalid or quota exceeded (403)');
        return null;
      } else {
        print('GeminiDirectVision: Error ${response.statusCode}: ${response.body.substring(0, response.body.length.clamp(0, 200))}');
        return null;
      }
    } catch (e) {
      print('GeminiDirectVision: Exception: $e');
      return null;
    }
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
