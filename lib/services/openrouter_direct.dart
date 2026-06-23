// lib/services/openrouter_direct.dart
// ★ v20: Direct OpenRouter call from app — second failsafe path
// Used when GeminiDirect fails (rate limit, model down, etc.)
// Single network hop: App → OpenRouter → Result

import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart' show Uint8List;
import 'package:http/http.dart' as http;
import 'api_keys.dart';

class OpenRouterDirect {
  // Key is fetched at runtime from Apps Script (see ApiKeys.init())
  // Fallback: --dart-define=OPENROUTER_API_KEY=... at build time
  static String get _apiKey => ApiKeys.openRouterKey;
  static const String _model = 'google/gemini-2.5-flash';
  static const String _fallbackModel = 'google/gemini-2.0-flash-exp';

  static const int _timeoutSeconds = 45;

  /// Analyse image bytes via OpenRouter — direct from app.
  /// Returns standard hazard JSON on success, null on failure.
  static Future<Map<String, dynamic>?> analyseImageBytes(Uint8List bytes) async {
    if (_apiKey.isEmpty) {
      print('OpenRouterDirect: OPENROUTER_API_KEY not set — ensure ApiKeys.init() was called');
      return null;
    }

    print('OpenRouterDirect: Starting analysis (${bytes.length} bytes)');

    // Try primary model first, then fallback
    for (final model in [_model, _fallbackModel]) {
      try {
        final result = await _callModel(model, bytes);
        if (result != null) {
          result['_provider'] = 'openrouter_direct';
          result['_model'] = model;
          result['_source'] = 'openrouter_direct';
          result['_isOnline'] = true;
          print('OpenRouterDirect: SUCCESS with $model — '
              'risk=${result['overallRisk']}, '
              'hazards=${(result['hazards'] as List?)?.length ?? 0}');
          return result;
        }
      } catch (e) {
        print('OpenRouterDirect: $model failed — $e');
        if (e.toString().contains('404') || e.toString().contains('not found')) {
          continue; // try next model
        }
      }
    }

    print('OpenRouterDirect: All models failed');
    return null;
  }

  static Future<Map<String, dynamic>?> _callModel(String model, Uint8List bytes) async {
    final base64Image = base64Encode(bytes);
    final dataUrl = 'data:image/jpeg;base64,$base64Image';

    final payload = jsonEncode({
      'model': model,
      'messages': [
        {
          'role': 'user',
          'content': [
            {'type': 'text', 'text': _getPrompt()},
            {'type': 'image_url', 'image_url': {'url': dataUrl}},
          ]
        }
      ],
      'max_tokens': 2048,
      'temperature': 0.2,
    });

    final response = await http.post(
      Uri.parse('https://openrouter.ai/api/v1/chat/completions'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_apiKey',
        'HTTP-Referer': 'https://abhibond1986.github.io/Safety-Lens-V2/',
        'X-Title': 'SAIL Safety Lens',
      },
      body: payload,
    ).timeout(Duration(seconds: _timeoutSeconds));

    print('OpenRouterDirect: HTTP ${response.statusCode} from $model');

    if (response.statusCode != 200) {
      print('OpenRouterDirect: Error body: ${response.body.substring(0, response.body.length > 300 ? 300 : response.body.length)}');
      return null;
    }

    final data = jsonDecode(response.body);
    String text = data['choices']?[0]?['message']?['content'] ?? '';
    text = text.trim();

    if (text.isEmpty) return null;

    // Parse JSON
    if (text.startsWith('```json')) text = text.substring(7);
    if (text.startsWith('```')) text = text.substring(3);
    if (text.endsWith('```')) text = text.substring(0, text.length - 3);
    final firstBrace = text.indexOf('{');
    final lastBrace = text.lastIndexOf('}');
    if (firstBrace >= 0 && lastBrace > firstBrace) {
      text = text.substring(firstBrace, lastBrace + 1);
    }

    final result = jsonDecode(text.trim()) as Map<String, dynamic>;
    if (result['people'] == null) result['people'] = 0;
    return result;
  }

  static String _getPrompt() {
    // Compact but effective prompt for OpenRouter
    return '''You are a senior industrial safety inspector for SAIL steel plants. Analyze this photograph for safety hazards.

RULES:
- Only report hazards you can ACTUALLY SEE — never invent.
- If no workers visible → NO worker-related hazards.
- Pipes (on brackets, colour-coded, metallic, >6mm) are NOT wires.
- Better 2 real hazards than 7 invented ones.
- FA 1948 S32(c) for height work, NEVER S36 (S36 = confined space only).
- Bounding box: normalised 0.0–1.0 (x=left, y=top, w=width, h=height).

OUTPUT — valid JSON ONLY:
{
  "overallRisk": "CRITICAL|HIGH|MEDIUM|LOW",
  "riskScore": 0-100,
  "confidence": 0-100,
  "people": count_of_visible_persons,
  "summary": "Description of photo. Key concern. Regulation.",
  "hazards": [{"name":"...","severity":"...","description":"...","regulation":"...","correctiveAction":"...","type":"Unsafe Act|Unsafe Condition","wsaCause":"...","bbox":{"x":0.1,"y":0.1,"w":0.3,"h":0.4}}],
  "wsa": ["applicable WSA causes"],
  "preventive": ["measures"],
  "ptw_required": "types or None",
  "nearest_standard": "IS standard"
}''';
  }
}
