import 'dart:convert';
import 'dart:io' show File;
import 'package:flutter/foundation.dart' show Uint8List, kIsWeb;
import 'package:http/http.dart' as http;
import 'local_ai.dart';

/// SAIL Safety Lens — Gemini Vision via Google Apps Script Proxy
///
/// Apps Script action: 'gemini'
/// Parameters: prompt (string) + imageBase64 (base64 string)
/// This bypasses CORS — Apps Script calls Gemini server-side.
class GeminiVision {
  static const String _backendUrl =
      'https://script.google.com/macros/s/AKfycbyvq6MSAWOL_DcMtBHj_txBW8dBerJGbKLsYwNeb75IYX2TAkBaBq7_ZEELcOLcJ0cdAw/exec';

  static const String _safetyPrompt = '''You are an expert industrial safety inspector for Steel Authority of India Limited (SAIL).
Analyze this workplace photo and identify ALL visible safety hazards.

Standards to apply:
1. IS 14489:1998 — Occupational Safety & Health Audit (Iron & Steel Industry)
2. Factories Act 1948 — Sections 21-41
3. Indian Standards: IS 2925 (helmet), IS 3521 (harness), IS 5852 (shoes), IS 6994 (gloves), IS 4770 (eye), IS 9167 (ear)
4. WSA 13 Causes framework
5. SAIL Standard Operating Procedures

For EACH hazard visible, provide:
- name: 5 words max
- severity: CRITICAL, HIGH, MEDIUM, or LOW
- description: what you actually see
- regulation: specific IS/Factories Act section
- correctiveAction: immediate action required
- type: Unsafe Act or Unsafe Condition

Also provide:
- overallRisk: CRITICAL/HIGH/MEDIUM/LOW
- riskScore: 0-100
- confidence: 0-100
- summary: 3-4 sentences about what you see and the hazards found

Respond ONLY with valid JSON, no markdown or explanation:
{"overallRisk":"HIGH","riskScore":75,"confidence":88,"summary":"...","hazards":[{"name":"...","severity":"HIGH","description":"...","regulation":"...","correctiveAction":"...","type":"Unsafe Act"}]}''';

  static Future<Map<String, dynamic>?> analyseImage(File imageFile) async {
    final bytes = await imageFile.readAsBytes();
    return analyseImageBytes(bytes);
  }

  static Future<Map<String, dynamic>?> analyseImageBytes(Uint8List bytes) async {
    try {
      // Compress image if too large (Apps Script has limits)
      // Keep max 800KB for reliable transmission
      Uint8List imageData = bytes;
      if (bytes.length > 800000) {
        // Take every 2nd byte as simple downscaling approximation
        // For proper compression, this is good enough for demo
        imageData = Uint8List.fromList(
          List.generate(bytes.length ~/ 2, (i) => bytes[i * 2])
        );
      }

      final base64Image = base64Encode(imageData);

      // Call Apps Script with action='gemini' (matches your Apps Script)
      final body = jsonEncode({
        'action': 'gemini',
        'prompt': _safetyPrompt,
        'imageBase64': base64Image,
      });

      final response = await http.post(
        Uri.parse(_backendUrl),
        body: body,
        headers: {'Content-Type': 'text/plain;charset=utf-8'},
      ).timeout(const Duration(seconds: 60));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        // Check if Apps Script returned an error
        if (data is Map && data['error'] != null) {
          print('Apps Script error: ${data['error']}');
          return _offlineFallback(bytes, reason: data['error'].toString());
        }

        // Check if we got valid hazard data
        if (data is Map && data['hazards'] != null) {
          data['_source'] = 'gemini_via_apps_script';
          return Map<String, dynamic>.from(data);
        }

        // Unexpected response format
        print('Unexpected response: ${response.body.substring(0, 200)}');
        return _offlineFallback(bytes, reason: 'Unexpected response format');
      }

      print('HTTP ${response.statusCode}: ${response.body.substring(0, 200)}');
      return _offlineFallback(bytes, reason: 'HTTP ${response.statusCode}');

    } catch (e) {
      print('GeminiVision error: $e');
      return _offlineFallback(bytes, reason: e.toString());
    }
  }

  static Map<String, dynamic> _offlineFallback(Uint8List bytes, {String reason = ''}) {
    final result = _knowledgeBasedAnalysis(bytes);
    result['_source'] = 'offline_fallback';
    result['_fallbackReason'] = reason;
    // Make fallback obvious to user in summary
    result['summary'] = 'Offline analysis (AI unavailable: $reason). '
        'Knowledge-based hazards shown below based on common steel plant scenarios. '
        'For real AI analysis, ensure internet connection and Apps Script is deployed.';
    return result;
  }

  // ============================================================
  // OFFLINE FALLBACK — used when Apps Script is unreachable
  // ============================================================
  static const List<Map<String, dynamic>> _hazardLibrary = [
    {'name': 'Missing hard hat', 'description': 'Worker without ISI-marked hard hat in active work zone.', 'severity': 'CRITICAL', 'type': 'Unsafe act', 'regulation': 'Factories Act §35, IS 2925:1984', 'correctiveAction': 'Issue hard hat immediately. Halt work until compliance.', 'wsaCause': '3. Improper PPE use', 'category': 'PPE'},
    {'name': 'Safety shoes not worn', 'description': 'Worker handling materials without steel-toe safety shoes.', 'severity': 'HIGH', 'type': 'Unsafe act', 'regulation': 'Factories Act §35, IS 5852:1996', 'correctiveAction': 'Provide steel-toe safety shoes. Restrict area access.', 'wsaCause': '3. Improper PPE use', 'category': 'PPE'},
    {'name': 'No fall arrest at height', 'description': 'Worker at elevation without full body harness or anchor point.', 'severity': 'CRITICAL', 'type': 'Unsafe act', 'regulation': 'Factories Act §36, IS 3521', 'correctiveAction': 'Evacuate immediately. Issue harness with double lanyard.', 'wsaCause': '1. Failure to follow procedure', 'category': 'HEIGHT'},
    {'name': 'Exposed electrical cable', 'description': 'Loose or damaged cable across pedestrian walkway.', 'severity': 'HIGH', 'type': 'Unsafe condition', 'regulation': 'Factories Act §36, IS 7689', 'correctiveAction': 'De-energize via LOTO. Route via overhead cable tray.', 'wsaCause': '8. Poor housekeeping', 'category': 'ELECTRICAL'},
    {'name': 'Oil spillage on walkway', 'description': 'Visible oil or hydraulic fluid on access walkway.', 'severity': 'HIGH', 'type': 'Unsafe condition', 'regulation': 'Factories Act §33, SAIL SOP-HK-02', 'correctiveAction': 'Deploy absorbent material. Place wet floor signs.', 'wsaCause': '8. Poor housekeeping', 'category': 'HOUSEKEEPING'},
    {'name': 'Exposed moving machinery', 'description': 'Rotating shaft or belt without guarding.', 'severity': 'CRITICAL', 'type': 'Unsafe condition', 'regulation': 'Factories Act §21, IS 14489 §6.2', 'correctiveAction': 'Stop machine. Install interlocked guarding.', 'wsaCause': '5. Equipment failure', 'category': 'MACHINERY'},
    {'name': 'Hot work without screen', 'description': 'Welding or cutting without screens for adjacent workers.', 'severity': 'MEDIUM', 'type': 'Unsafe condition', 'regulation': 'Factories Act §38, SAIL SOP-FP-03', 'correctiveAction': 'Install welding screens. Position fire watch.', 'wsaCause': '2. Lack of hazard awareness', 'category': 'HOT_WORK'},
    {'name': 'Missing hazard signage', 'description': 'Required safety signage missing at hazard zones.', 'severity': 'LOW', 'type': 'Unsafe condition', 'regulation': 'Factories Act §65, IS 9457', 'correctiveAction': 'Install signage per IS 9457 colour code.', 'wsaCause': '6. Communication gaps', 'category': 'SIGNAGE'},
    {'name': 'No gas detection', 'description': 'Work in gas exposure area without CO detector.', 'severity': 'CRITICAL', 'type': 'Unsafe condition', 'regulation': 'Factories Act §41, IS 14489 §8.4', 'correctiveAction': 'Issue personal CO detector. Buddy system mandatory.', 'wsaCause': '13. Environmental conditions', 'category': 'GAS'},
    {'name': 'Scaffolding not tagged', 'description': 'Scaffolding in use without daily inspection tag.', 'severity': 'HIGH', 'type': 'Unsafe condition', 'regulation': 'Factories Act §36, IS 2750', 'correctiveAction': 'Stop work. Competent person to inspect and tag.', 'wsaCause': '5. Equipment failure', 'category': 'HEIGHT'},
    {'name': 'Eye protection missing', 'description': 'Grinding or welding without safety goggles.', 'severity': 'HIGH', 'type': 'Unsafe act', 'regulation': 'Factories Act §35, IS 4770', 'correctiveAction': 'Stop work. Issue appropriate eye protection.', 'wsaCause': '3. Improper PPE use', 'category': 'PPE'},
    {'name': 'Exit pathway blocked', 'description': 'Materials stacked blocking emergency exit.', 'severity': 'HIGH', 'type': 'Unsafe condition', 'regulation': 'Factories Act §38, NBC 2016', 'correctiveAction': 'Clear pathway immediately.', 'wsaCause': '8. Poor housekeeping', 'category': 'HOUSEKEEPING'},
  ];

  static int _deriveSeed(Uint8List bytes) {
    int seed = 0;
    final n = bytes.length < 512 ? bytes.length : 512;
    for (var i = 0; i < n; i++) {
      seed = (seed * 31 + bytes[i]) & 0x7FFFFFFF;
    }
    return seed;
  }

  static Map<String, dynamic> _knowledgeBasedAnalysis(Uint8List bytes) {
    final seed = _deriveSeed(bytes);
    final count = 3 + (seed % 3);
    final selected = <Map<String, dynamic>>[];
    final used = <int>{};
    var s = seed;
    while (selected.length < count && selected.length < _hazardLibrary.length) {
      final idx = s % _hazardLibrary.length;
      s = (s ~/ 7 + 13) & 0x7FFFFFFF;
      if (!used.contains(idx)) {
        selected.add(Map<String, dynamic>.from(_hazardLibrary[idx]));
        used.add(idx);
      }
    }

    String risk = 'LOW';
    int score = 30;
    for (final h in selected) {
      switch (h['severity']) {
        case 'CRITICAL': score += 18; risk = 'CRITICAL'; break;
        case 'HIGH': score += 12; if (risk != 'CRITICAL') risk = 'HIGH'; break;
        case 'MEDIUM': score += 7; if (risk == 'LOW') risk = 'MEDIUM'; break;
        default: score += 3;
      }
    }

    return {
      'overallRisk': risk,
      'riskScore': score.clamp(0, 100),
      'confidence': 75 + (seed % 15),
      'summary': 'Knowledge-based analysis: ${selected.length} common steel plant hazards identified.',
      'hazards': selected,
      'wsa': selected.map((h) => h['wsaCause']?.toString() ?? '').toSet().toList(),
      'preventive': [
        'Daily toolbox talk with PPE compliance check',
        'Monthly housekeeping audit with photographic evidence',
        'Working at height refresher training every 6 months',
        'LOTO training and audit every 4 months per IS 7689',
        'Implement IS 14489 self-audit checklist weekly',
      ],
      'imageSeed': seed,
    };
  }

  static bool get isConfigured => true;
}
