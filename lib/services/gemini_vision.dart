import 'dart:convert';
import 'dart:io' show File, SocketException;
import 'package:flutter/foundation.dart' show Uint8List, kIsWeb;
import 'package:http/http.dart' as http;
import 'local_ai.dart';

/// Hugging Face Vision API service for SAIL Safety Lens.
/// 
/// Uses two HF models:
/// 1. Salesforce/blip-image-captioning-large -> describes the image
/// 2. Qwen/Qwen2.5-72B-Instruct -> generates IS 14489 safety report from description
///
/// Get free token at: https://huggingface.co/settings/tokens
class GeminiVision {
  // ============================================================
  // PASTE YOUR HUGGING FACE TOKEN HERE (between the quotes):
  // Get a free token at: https://huggingface.co/settings/tokens
  // Token starts with: hf_...
  // ============================================================
  static const String _hfToken = 'YOUR_HUGGINGFACE_TOKEN_HERE';

  // Vision model - describes what's in the image
  static const String _visionModel = 'Salesforce/blip-image-captioning-large';

  // Text generation model - analyses the description against IS 14489
  static const String _textModel = 'Qwen/Qwen2.5-72B-Instruct';

  static const String _hfBaseUrl = 'https://api-inference.huggingface.co/models';

  static const String _safetyPrompt = '''
You are an expert industrial safety inspector for Steel Authority of India Limited (SAIL).
Based on the image description provided, conduct a safety audit using these authoritative standards:

AUTHORITATIVE FRAMEWORK:
1. IS 14489:1998 — Code of Practice on Occupational Safety & Health Audit (Iron & Steel Industry)
2. Ministry of Steel Govt of India — Safety Guidelines for Iron & Steel Sector
3. Factories Act 1948 — Sections 21-41
4. Indian Standards: IS 2925 (helmet), IS 3521 (harness), IS 5852 (shoes), IS 6994 (gloves), IS 4770 (eye), IS 9167 (ear), IS 8519 (respiratory), IS 2750 (scaffolding), IS 7689 (LOTO)
5. WSA 13 Causes framework

For EACH hazard provide:
- name (5 words max)
- severity (CRITICAL/HIGH/MEDIUM/LOW)
- description (1-2 sentences)
- regulation (cite specific section)
- correctiveAction (concrete action)

ALSO provide:
- overallRisk (CRITICAL/HIGH/MEDIUM/LOW)
- riskScore (0-100)
- confidence (0-100)
- summary (3-4 sentences)
- wsa (array from WSA 13 causes)
- preventive (4-5 preventive measures)

Respond with ONLY valid JSON, no markdown:
{"overallRisk":"HIGH","riskScore":70,"confidence":80,"summary":"...","hazards":[{"name":"...","severity":"HIGH","description":"...","regulation":"...","correctiveAction":"..."}],"wsa":[],"preventive":[]}

If image shows no workplace hazards, return overallRisk LOW with empty hazards array.
''';

  /// Analyse an image file (mobile/desktop).
  static Future<Map<String, dynamic>?> analyseImage(File imageFile) async {
    final bytes = await imageFile.readAsBytes();
    return analyseImageBytes(bytes);
  }

  /// Analyse image bytes — works on web AND mobile.
  static Future<Map<String, dynamic>?> analyseImageBytes(Uint8List bytes) async {
    if (_hfToken == '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' || _hfToken.isEmpty) {
      throw Exception(
        'Hugging Face token not configured. Please paste your token in lib/services/gemini_vision.dart line 22.',
      );
    }

    try {
      // Step 1: Get image description from BLIP vision model
      final description = await _getImageDescription(bytes);

      // Step 2: Generate safety report from description using LLM
      final report = await _generateSafetyReport(description);

      return report;
    } catch (e) {
      final errMsg = e.toString();
      return {
        'overallRisk': 'UNKNOWN',
        'riskScore': 0,
        'confidence': 0,
        'summary': 'Hugging Face API call failed.\n\n'
            'Possible reasons:\n'
            '1. Token invalid or expired\n'
            '2. Model loading (HF cold-starts can take 20s — try again)\n'
            '3. Rate limit reached (free tier)\n'
            '4. Network connection issue\n\n'
            'Error: $errMsg',
        'hazards': [
          {
            'name': 'AI analysis unavailable',
            'description': errMsg.length > 200 ? errMsg.substring(0, 200) : errMsg,
            'severity': 'MEDIUM',
            'type': 'System error',
            'regulation': 'N/A',
            'correctiveAction': 'Verify token at https://huggingface.co/settings/tokens and try again. If model is loading, wait 30s and retry.',
          }
        ],
        'preventive': [
          'Use a valid Hugging Face Pro token for production',
          'Wait for model to warm up on first call',
          'Consider Firebase backend proxy for reliability',
        ],
        '_source': 'api_error',
        '_error': errMsg,
      };
    }
  }

  /// Call BLIP model to get a caption/description of the image
  static Future<String> _getImageDescription(Uint8List bytes) async {
    final url = Uri.parse('$_hfBaseUrl/$_visionModel');
    final response = await http.post(
      url,
      headers: {
        'Authorization': 'Bearer $_hfToken',
        'Content-Type': 'application/octet-stream',
      },
      body: bytes,
    ).timeout(const Duration(seconds: 30));

    if (response.statusCode == 503) {
      // Model is loading — try once more after delay
      await Future.delayed(const Duration(seconds: 10));
      final retry = await http.post(
        url,
        headers: {
          'Authorization': 'Bearer $_hfToken',
          'Content-Type': 'application/octet-stream',
        },
        body: bytes,
      ).timeout(const Duration(seconds: 30));
      if (retry.statusCode != 200) {
        throw Exception('HF Vision API error ${retry.statusCode}: ${retry.body}');
      }
      return _parseCaption(retry.body);
    }

    if (response.statusCode != 200) {
      throw Exception('HF Vision API error ${response.statusCode}: ${response.body}');
    }

    return _parseCaption(response.body);
  }

  static String _parseCaption(String body) {
    try {
      final data = jsonDecode(body);
      if (data is List && data.isNotEmpty) {
        return data[0]['generated_text']?.toString() ?? 'Image content';
      }
      if (data is Map && data['generated_text'] != null) {
        return data['generated_text'].toString();
      }
      return body;
    } catch (_) {
      return body;
    }
  }

  /// Call text LLM to generate IS 14489 compliant safety report from description
  static Future<Map<String, dynamic>> _generateSafetyReport(String imageDescription) async {
    final url = Uri.parse('$_hfBaseUrl/$_textModel');

    final fullPrompt = '$_safetyPrompt\n\nImage description: $imageDescription\n\nSafety report (JSON only):';

    final response = await http.post(
      url,
      headers: {
        'Authorization': 'Bearer $_hfToken',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'inputs': fullPrompt,
        'parameters': {
          'max_new_tokens': 2000,
          'temperature': 0.2,
          'return_full_text': false,
        },
        'options': {'wait_for_model': true},
      }),
    ).timeout(const Duration(seconds: 60));

    if (response.statusCode != 200) {
      throw Exception('HF Text API error ${response.statusCode}: ${response.body}');
    }

    final data = jsonDecode(response.body);
    String text = '';
    if (data is List && data.isNotEmpty) {
      text = data[0]['generated_text']?.toString() ?? '';
    } else if (data is Map) {
      text = data['generated_text']?.toString() ?? '';
    }

    // Extract JSON from response
    text = text.trim();
    if (text.startsWith('```json')) text = text.substring(7);
    if (text.startsWith('```')) text = text.substring(3);
    if (text.endsWith('```')) text = text.substring(0, text.length - 3);

    // Find first { and last } to extract JSON object
    final jsonStart = text.indexOf('{');
    final jsonEnd = text.lastIndexOf('}');
    if (jsonStart >= 0 && jsonEnd > jsonStart) {
      text = text.substring(jsonStart, jsonEnd + 1);
    }

    try {
      final result = jsonDecode(text.trim()) as Map<String, dynamic>;
      result['_source'] = 'huggingface';
      result['_imageDescription'] = imageDescription;
      return result;
    } catch (e) {
      // If JSON parsing fails, return a partially-structured result with the description
      return {
        'overallRisk': 'MEDIUM',
        'riskScore': 50,
        'confidence': 40,
        'summary': 'AI described image as: $imageDescription\n\n'
            'Could not parse structured hazard analysis from response. Raw LLM output may be in unexpected format.',
        'hazards': [
          {
            'name': 'Manual review needed',
            'description': 'AI saw: $imageDescription. Please manually identify hazards.',
            'severity': 'MEDIUM',
            'type': 'Pending review',
            'regulation': 'IS 14489 manual audit',
            'correctiveAction': 'Conduct manual safety inspection of the area shown.',
          }
        ],
        'preventive': ['Manual review required', 'Verify HF model output format'],
        '_source': 'huggingface_partial',
        '_imageDescription': imageDescription,
      };
    }
  }

  static bool get isConfigured =>
      _hfToken != 'YOUR_HUGGINGFACE_TOKEN_HERE' && _hfToken.isNotEmpty;
}
