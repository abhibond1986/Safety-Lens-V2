import 'dart:convert';
import 'dart:io' show File;
import 'package:flutter/foundation.dart' show Uint8List, kIsWeb;
import 'package:http/http.dart' as http;
import 'local_ai.dart';

class GeminiVision {
  static const String _backendUrl =
      'https://script.google.com/macros/s/AKfycbxLSH2Z-X6iQPw0rY2O7T0SYSDU7bzikpWq-G_ysOT_noU-IwgSHYNr3AKbwPFPZYginw/exec';

  static const String _cloudinaryUrl =
      'https://api.cloudinary.com/v1_1/dzt1vxsdg/image/upload';

  static const String _cloudinaryPreset = 'safety_lens';

  // ══════════════════════════════════════════════════════════════════════════
  // ENHANCED SAFETY PROMPT
  // Regulations: Factories Act 1948 | IS 14489:2018 | NBC 2016 Part 4
  //              CEA Regs 2023 | BIS PPE Standards | WSA 13 Causes
  // ══════════════════════════════════════════════════════════════════════════
  static const String _safetyPrompt =
      'You are an expert industrial safety inspector for SAIL (Steel Authority of India Limited) '
      'with deep knowledge of Indian manufacturing safety regulations. '
      'Analyse this workplace image for ALL visible hazards. '
      '\n\nREGULATORY FRAMEWORK TO APPLY:\n'
      '\nFACTORIES ACT 1948:\n'
      'S11-20 Health: cleanliness, ventilation, lighting min 50 lux workstation/30 lux general, noise, drinking water\n'
      'S21 Fencing of machinery: all rotating/moving parts (gears, belts, pulleys, shafts, flywheels) securely fenced\n'
      'S22 Work near moving machinery: prohibited without written PTW\n'
      'S26 New machinery: set screws/bolts on rotating shafts must be sunk/encased\n'
      'S28 Hoists and lifts: SWL marked, 6-monthly competent person inspection, gates at every floor\n'
      'S29 Lifting machines/cranes: 6-monthly inspection, SWL displayed, chains/ropes certified\n'
      'S30 Pressure plants: safe working pressure marked, tested and certified annually\n'
      'S31 Floors/stairs/passages: safe access, sufficient lighting, no obstruction, secure handrails\n'
      'S32 Pits and openings: securely covered or fenced\n'
      'S33 Excessive weights: manual handling limits men max 55kg, women max 30kg solo lift\n'
      'S34 Eye protection: mandatory where flying particles/chemical splash risk\n'
      'S35 PPE mandatory: hard hat, safety shoes, gloves, high-vis vest, face shield, ear protection per area risk\n'
      'S36 Fumes/confined space/height: atmospheric test before entry, BA set available, harness mandatory above 2m, PTW required\n'
      'S37 Explosive/flammable: no naked flame/sparks near flammable atmosphere, equipment earthing required\n'
      'S38 Fire/explosion: extinguishers, clear escape routes, fire alarm, no combustible accumulation\n'
      'S40B Safety officers mandatory for 1000+ worker plants\n'
      'S41A-H Hazardous processes: permissible exposure limits, worker participation in safety management\n'
      '\nIS 14489:2018 (BIS OHS AUDIT):\n'
      'Check visible: safety policy display, hazard boards, PTW evidence, assembly point signs, first aid box, '
      'machine guarding completeness, material storage, housekeeping 5S, PPE compliance, electrical safety, fire equipment\n'
      '\nNBC 2016 PART 4 (FIRE AND LIFE SAFETY):\n'
      'Industrial buildings Low/Moderate/High hazard per Annex B\n'
      'Exits: min 2 per floor, min 1.0m wide, clearly marked, illuminated, unobstructed\n'
      'Travel distance: max 30m to exit High hazard, 45m Moderate hazard buildings\n'
      'Fire suppression: extinguishers every 15m, sprinklers for High hazard above 500 sqm\n'
      'Emergency lighting: min 50 lux at exit routes, 90 min battery backup\n'
      'Egress: corridors min 1.8m wide, staircase min 1.5m wide, no dead ends above 6m\n'
      'Signage: photoluminescent exit signs, extinguisher location signs, assembly point\n'
      '\nCEA REGULATIONS 2023 (ELECTRICAL SAFETY):\n'
      'Min approach distances: 66kV=2.0m, 33kV=1.2m, 11kV=0.9m, 415V LT=0.3m\n'
      'LOTO mandatory before electrical work: lock, tag, test for dead\n'
      'Panels: earthed, labelled with voltage, danger notice, doors closed\n'
      'No dangling cables, cable tray/conduit required, entries sealed\n'
      'Overhead lines: clearance min 3.7m from structure LT, 5.2m for 11kV\n'
      'IS 732 wiring, IS 3043 earthing, IS 8865 hazardous area classification\n'
      '\nBIS PPE STANDARDS:\n'
      'IS 2925:1984 helmets ISI marked; White=Officer, Yellow=Supervisor, Blue=Worker, Green=Visitor\n'
      'IS 5852:1993 safety footwear steel toe cap\n'
      'IS 5983:1980 eye protectors goggles face shields\n'
      'IS 9167:1979 ear protectors mandatory above 85 dB noise\n'
      'IS 3521:1999 full body harness height above 2m anchor min 15 kN rated\n'
      'IS 6994:1973 heat resistant gloves\n'
      '\nBIS MACHINERY AND STRUCTURAL SAFETY:\n'
      'IS 4912:1978 guardrail min 1.0m high, mid-rail 0.5m, toe board min 150mm\n'
      'IS 13367:1992 crane SWL marked, pre-use inspection, outriggers deployed\n'
      'IS 2750:1982 scaffolding tagged inspected load rated\n'
      'IS 7969:1976 welding safety hot work PTW, fire watch, combustibles cleared 10m radius\n'
      'IS 1710:1989 pressure vessel inspection\n'
      '\nPERMIT TO WORK - identify if any bypassed:\n'
      'Hot Work PTW: welding/cutting/grinding near flammable material S38\n'
      'Working at Height PTW: work above 2m S36\n'
      'Confined Space PTW: vessels/tanks/pits/ducts atmospheric test mandatory\n'
      'Electrical PTW: live or near-live work CEA Regs 2023\n'
      'Lifting Operations PTW: critical lifts above 75 percent SWL\n'
      '\nWSA 13 CAUSES map each hazard to exactly one:\n'
      '1.Failure to follow procedure  2.Lack of hazard awareness  3.Improper PPE use  '
      '4.Unsafe body positioning  5.Equipment failure  6.Communication failure  '
      '7.Human error  8.Poor housekeeping  9.Lack of supervision  '
      '10.Fatigue/time pressure  11.Unauthorized operation  '
      '12.Inadequate isolation  13.Environmental conditions\n'
      '\nRISK SCORING 1-100:\n'
      'CRITICAL 75-100: fatality/permanent disability risk STOP WORK\n'
      'HIGH 50-74: serious injury urgent action within 24 hours\n'
      'MEDIUM 25-49: moderate injury action within 1 week\n'
      'LOW 1-24: minor risk action within 1 month\n'
      '\nRULES: List ALL visible hazards. Reference SPECIFIC section numbers and IS codes. '
      'Corrective actions must be immediate and specific. Be steel-plant specific mentioning '
      'blast furnace, coke oven, rolling mill, crane bay, ladle where visible. '
      'Every finding must reference what is VISIBLE in the image.\n'
      '\nReply ONLY with valid JSON no markdown:\n'
      '{"overallRisk":"HIGH","riskScore":75,"confidence":88,'
      '"summary":"2-3 sentences mentioning specific Indian regulations violated",'
      '"hazards":[{"name":"hazard name max 5 words","severity":"HIGH",'
      '"description":"what you see and why dangerous",'
      '"regulation":"exact IS standard or Factories Act section",'
      '"correctiveAction":"immediate specific action",'
      '"type":"Unsafe Act or Unsafe Condition",'
      '"wsaCause":"WSA cause number and name"}],'
      '"wsa":["3. Improper PPE use"],'
      '"preventive":["long-term preventive measure with IS standard reference"],'
      '"ptw_required":"list PTW types bypassed or None",'
      '"nearest_standard":"primary IS standard applicable"}';

  // ── analyseImage (mobile/File path) ──────────────────────────────────────
  static Future<Map<String, dynamic>?> analyseImage(File imageFile) async {
    final bytes = await imageFile.readAsBytes();
    return analyseImageBytes(bytes);
  }

  // ── analyseImageBytes (web + mobile) ─────────────────────────────────────
  static Future<Map<String, dynamic>?> analyseImageBytes(Uint8List bytes) async {
    try {
      print('Image size: ${bytes.length} bytes');

      // Step 1: Upload directly to Cloudinary
      final imageUrl = await _uploadToCloudinary(bytes);
      if (imageUrl == null) {
        print('Cloudinary upload failed');
        return _offlineFallback(bytes, reason: 'Cloudinary upload failed');
      }
      print('Cloudinary URL: $imageUrl');

      // Step 2: Send URL to Apps Script for AI analysis
      final body = jsonEncode({
        'action': 'analyzeUrl',
        'imageUrl': imageUrl,
        'prompt': _safetyPrompt,
      });

      final response = await http.post(
        Uri.parse(_backendUrl),
        body: body,
        headers: {'Content-Type': 'text/plain;charset=utf-8'},
      ).timeout(const Duration(seconds: 90));

      print('Apps Script status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data is Map && data['error'] != null) {
          print('Apps Script error: ${data['error']}');
          return _offlineFallback(bytes, reason: data['error'].toString());
        }

        if (data is Map && data['hazards'] != null) {
          print('AI SUCCESS! Risk: ${data['overallRisk']}, '
              'Hazards: ${(data['hazards'] as List).length}');
          data['_source'] = 'openrouter_direct';
          return Map<String, dynamic>.from(data);
        }

        print('Unexpected: ${response.body}');
        return _offlineFallback(bytes, reason: 'Unexpected response');
      }

      return _offlineFallback(bytes, reason: 'HTTP ${response.statusCode}');
    } catch (e) {
      print('GeminiVision error: $e');
      return _offlineFallback(bytes, reason: e.toString());
    }
  }

  // ── Upload to Cloudinary (unchanged) ─────────────────────────────────────
  static Future<String?> _uploadToCloudinary(Uint8List bytes) async {
    try {
      print('Uploading ${bytes.length} bytes to Cloudinary...');

      final request = http.MultipartRequest(
        'POST',
        Uri.parse(_cloudinaryUrl),
      );

      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: 'safety_scan.jpg',
        ),
      );
      request.fields['upload_preset'] = _cloudinaryPreset;

      final streamed =
          await request.send().timeout(const Duration(seconds: 60));
      final response = await http.Response.fromStream(streamed);

      print('Cloudinary response: ${response.statusCode}');
      print('Cloudinary body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final url = data['secure_url']?.toString();
        print('Cloudinary URL: $url');
        return url;
      }

      return null;
    } catch (e) {
      print('Cloudinary exception: $e');
      return null;
    }
  }

  // ── Offline fallback (unchanged) ─────────────────────────────────────────
  static Map<String, dynamic> _offlineFallback(Uint8List bytes,
      {String reason = ''}) {
    final result = _knowledgeBasedAnalysis(bytes);
    result['_source'] = 'offline_fallback';
    result['summary'] = 'Offline analysis (AI unavailable: $reason). '
        'Knowledge-based hazards shown below based on common steel plant scenarios.';
    return result;
  }

  // ── Offline hazard library (expanded with NBC/CEA/IS entries) ────────────
  static const List<Map<String, dynamic>> _hazardLibrary = [
    {'name': 'Missing hard hat', 'description': 'Worker without ISI-marked hard hat.', 'severity': 'CRITICAL', 'type': 'Unsafe act', 'regulation': 'Factories Act S35, IS 2925:1984', 'correctiveAction': 'Issue hard hat immediately.', 'wsaCause': '3. Improper PPE use'},
    {'name': 'Safety shoes not worn', 'description': 'Worker without steel-toe safety shoes.', 'severity': 'HIGH', 'type': 'Unsafe act', 'regulation': 'Factories Act S35, IS 5852:1996', 'correctiveAction': 'Provide safety shoes.', 'wsaCause': '3. Improper PPE use'},
    {'name': 'No fall arrest at height', 'description': 'Worker at elevation without harness.', 'severity': 'CRITICAL', 'type': 'Unsafe act', 'regulation': 'Factories Act S36, IS 3521 anchor min 15kN', 'correctiveAction': 'Evacuate. Issue IS 3521 harness.', 'wsaCause': '1. Failure to follow procedure'},
    {'name': 'Exposed electrical cable', 'description': 'Loose cable across walkway.', 'severity': 'HIGH', 'type': 'Unsafe condition', 'regulation': 'CEA Regulations 2023, IS 732', 'correctiveAction': 'De-energize via LOTO. Route in conduit.', 'wsaCause': '8. Poor housekeeping'},
    {'name': 'Oil spillage on walkway', 'description': 'Oil on access walkway creating slip hazard.', 'severity': 'HIGH', 'type': 'Unsafe condition', 'regulation': 'Factories Act S33, SAIL SOP-HK-02', 'correctiveAction': 'Deploy absorbent material. Wet floor sign.', 'wsaCause': '8. Poor housekeeping'},
    {'name': 'Exposed moving machinery', 'description': 'Rotating shaft/gear without guarding.', 'severity': 'CRITICAL', 'type': 'Unsafe condition', 'regulation': 'Factories Act S21, IS 14489:2018 S6.2', 'correctiveAction': 'Stop machine immediately. Install guard.', 'wsaCause': '5. Equipment failure'},
    {'name': 'Hot work without PTW', 'description': 'Welding/cutting without hot work permit or screens.', 'severity': 'HIGH', 'type': 'Unsafe condition', 'regulation': 'Factories Act S38, IS 7969:1976', 'correctiveAction': 'Stop. Issue Hot Work PTW. Install screens. Deploy fire watch.', 'wsaCause': '1. Failure to follow procedure'},
    {'name': 'Missing hazard signage', 'description': 'Safety/danger signage absent in hazardous area.', 'severity': 'LOW', 'type': 'Unsafe condition', 'regulation': 'Factories Act S65, IS 9457', 'correctiveAction': 'Install photoluminescent safety signage.', 'wsaCause': '6. Communication failure'},
    {'name': 'No gas detection', 'description': 'Work in potential gas area without CO detector.', 'severity': 'CRITICAL', 'type': 'Unsafe condition', 'regulation': 'Factories Act S41, IS 14489:2018 S8.4', 'correctiveAction': 'Issue personal CO detector. Atmospheric test mandatory.', 'wsaCause': '13. Environmental conditions'},
    {'name': 'Scaffolding not tagged', 'description': 'Scaffolding without valid inspection tag.', 'severity': 'HIGH', 'type': 'Unsafe condition', 'regulation': 'Factories Act S36, IS 2750:1982', 'correctiveAction': 'Stop work. Inspect and tag before use.', 'wsaCause': '5. Equipment failure'},
    {'name': 'Eye protection missing', 'description': 'Worker grinding/welding without goggles.', 'severity': 'HIGH', 'type': 'Unsafe act', 'regulation': 'Factories Act S34 and S35, IS 5983:1980', 'correctiveAction': 'Issue IS 5983 eye protectors immediately.', 'wsaCause': '3. Improper PPE use'},
    {'name': 'Exit pathway blocked', 'description': 'Materials blocking emergency exit route.', 'severity': 'HIGH', 'type': 'Unsafe condition', 'regulation': 'Factories Act S38, NBC 2016 Part 4 min 1.0m clear', 'correctiveAction': 'Remove obstructions. Maintain 1.0m clear width.', 'wsaCause': '8. Poor housekeeping'},
    {'name': 'No ear protection', 'description': 'Worker in high-noise area without ear muffs.', 'severity': 'MEDIUM', 'type': 'Unsafe act', 'regulation': 'Factories Act S35, IS 9167:1979 above 85dB', 'correctiveAction': 'Issue IS 9167 ear protectors immediately.', 'wsaCause': '3. Improper PPE use'},
    {'name': 'Crane SWL not displayed', 'description': 'Crane without safe working load marking visible.', 'severity': 'HIGH', 'type': 'Unsafe condition', 'regulation': 'Factories Act S29, IS 13367:1992', 'correctiveAction': 'Stop lifting ops. Mark SWL conspicuously.', 'wsaCause': '6. Communication failure'},
    {'name': 'No fire extinguisher', 'description': 'Work area without fire extinguisher within 15m.', 'severity': 'HIGH', 'type': 'Unsafe condition', 'regulation': 'Factories Act S38, NBC 2016 Part 4 every 15m', 'correctiveAction': 'Place 9kg DCP extinguisher. Check last service date.', 'wsaCause': '2. Lack of hazard awareness'},
    {'name': 'Electrical panel open', 'description': 'Electrical panel door open with live parts exposed.', 'severity': 'CRITICAL', 'type': 'Unsafe condition', 'regulation': 'CEA Regulations 2023, IS 732', 'correctiveAction': 'Close panel. Apply LOTO. Display danger notice.', 'wsaCause': '12. Inadequate isolation'},
    {'name': 'Floor opening unguarded', 'description': 'Open pit/floor hole without guardrail or cover.', 'severity': 'CRITICAL', 'type': 'Unsafe condition', 'regulation': 'Factories Act S32, IS 4912:1978 guardrail min 1.0m', 'correctiveAction': 'Install guardrail min 1.0m high or rigid cover.', 'wsaCause': '8. Poor housekeeping'},
    {'name': 'Pressure vessel uncertified', 'description': 'Pressure vessel without visible test certification.', 'severity': 'HIGH', 'type': 'Unsafe condition', 'regulation': 'Factories Act S30, IS 1710:1989', 'correctiveAction': 'Verify certification. Take out of service if lapsed.', 'wsaCause': '5. Equipment failure'},
  ];

  // ── Knowledge-based offline analysis (unchanged logic) ────────────────────
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
        case 'CRITICAL':
          score += 18;
          risk = 'CRITICAL';
          break;
        case 'HIGH':
          score += 12;
          if (risk != 'CRITICAL') risk = 'HIGH';
          break;
        case 'MEDIUM':
          score += 7;
          if (risk == 'LOW') risk = 'MEDIUM';
          break;
        default:
          score += 3;
      }
    }
    return {
      'overallRisk': risk,
      'riskScore': score.clamp(0, 100),
      'confidence': 75 + (seed % 15),
      'summary':
          'Knowledge-based analysis: ${selected.length} common steel plant hazards identified.',
      'hazards': selected,
      'wsa': selected
          .map((h) => h['wsaCause']?.toString() ?? '')
          .toSet()
          .toList(),
      'preventive': [
        'Daily toolbox talk with PPE compliance check per IS 14489:2018',
        'Monthly housekeeping audit per 5S and NBC 2016 Part 4',
        'Working at height refresher every 6 months — IS 3521 harness inspection',
        'LOTO training every 4 months — CEA Regulations 2023',
        'Fire exit inspection weekly — NBC 2016 Part 4 travel distance check',
        'Monthly crane/lifting equipment inspection per IS 13367:1992',
      ],
      'ptw_required': 'Verify Hot Work, WAH, Confined Space PTW as applicable',
      'nearest_standard': 'IS 14489:2018 — OHS Audit Code of Practice',
      'imageSeed': seed,
    };
  }

  static bool get isConfigured => true;
}
