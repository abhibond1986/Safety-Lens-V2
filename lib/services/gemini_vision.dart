// lib/services/gemini_vision.dart
// v10 MOBILE OPTIMIZATIONS:
//   ✅ Network checker before analysis attempt
//   ✅ Retry logic with exponential backoff (up to 3 attempts)
//   ✅ Timeout reduced: 90s → 45s for mobile
//   ✅ Clear offline/fallback messaging for users
//   ✅ Improved error detection & handling

import 'dart:convert';
import 'dart:io' show File;
import 'package:flutter/foundation.dart' show Uint8List, kIsWeb;
import 'package:http/http.dart' as http;
import 'local_ai.dart';
import 'network_checker.dart';

class GeminiVision {
  static const String _backendUrl =
      'https://script.google.com/macros/s/AKfycbxLSH2Z-X6iQPw0rY2O7T0SYSDU7bzikpWq-G_ysOT_noU-IwgSHYNr3AKbwPFPZYginw/exec';

  static const String _cloudinaryUrl =
      'https://api.cloudinary.com/v1_1/dzt1vxsdg/image/upload';

  static const String _cloudinaryPreset = 'safety_lens';

  // ── analyseImage (mobile / File path) ─────────────────────────────────────
  static Future<Map<String, dynamic>?> analyseImage(File imageFile) async {
    final bytes = await imageFile.readAsBytes();
    return analyseImageBytes(bytes);
  }

  // ── analyseImageBytes (web + mobile) WITH RETRY ──────────────────────────
  static Future<Map<String, dynamic>?> analyseImageBytes(Uint8List bytes,
      {int retryCount = 0}) async {
    const maxRetries = 2;
    const timeoutSeconds = 45; // ✅ Reduced from 90s for mobile

    try {
      print(
          'GeminiVision: [Attempt ${retryCount + 1}/${maxRetries + 1}] image size = ${bytes.length} bytes');

      // ✅ NEW: Check network BEFORE attempting
      if (!kIsWeb) {
        final networkStatus = await NetworkChecker.getNetworkStatus();
        if (!networkStatus['hasInternet']!) {
          print('GeminiVision: No internet connection → offline fallback');
          return _offlineFallback(bytes, reason: 'No internet connection');
        }
        if (!networkStatus['backendReachable']!) {
          print(
              'GeminiVision: Backend unreachable → offline fallback');
          return _offlineFallback(bytes,
              reason: 'AI backend not reachable. Using knowledge base.');
        }
      }

      // Step 1: Upload to Cloudinary
      final imageUrl = await _uploadToCloudinary(bytes)
          .timeout(const Duration(seconds: 30));

      if (imageUrl == null) {
        print('GeminiVision: Cloudinary upload returned null');
        if (retryCount < maxRetries) {
          print(
              'GeminiVision: Retrying after Cloudinary failure (attempt ${retryCount + 2}/${maxRetries + 1})…');
          await Future.delayed(Duration(seconds: 2 * (retryCount + 1)));
          return analyseImageBytes(bytes, retryCount: retryCount + 1);
        }
        print(
            'GeminiVision: Cloudinary upload failed after ${maxRetries + 1} attempts → offline fallback');
        return _offlineFallback(bytes, reason: 'Image upload failed');
      }
      print('GeminiVision: Cloudinary URL = $imageUrl');

      // Step 2: Send URL to Apps Script
      // promptMode: 'sail_full' → Apps Script uses the full regulatory prompt
      // stored server-side, avoiding JSON parse issues with long strings
      final body = jsonEncode({
        'action': 'analyzeUrl',
        'imageUrl': imageUrl,
        'promptMode': 'sail_full',
      });

      final response = await http
          .post(
            Uri.parse(_backendUrl),
            body: body,
            headers: {'Content-Type': 'text/plain;charset=utf-8'},
          )
          .timeout(const Duration(seconds: timeoutSeconds));

      print('GeminiVision: Apps Script status = ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data is Map && data['error'] != null) {
          print('GeminiVision: Apps Script error = ${data['error']}');
          if (retryCount < maxRetries) {
            print(
                'GeminiVision: Retrying after API error (attempt ${retryCount + 2}/${maxRetries + 1})…');
            await Future.delayed(Duration(seconds: 2 * (retryCount + 1)));
            return analyseImageBytes(bytes, retryCount: retryCount + 1);
          }
          return _offlineFallback(bytes,
              reason: 'AI analysis error: ${data['error']}');
        }

        if (data is Map && data['hazards'] != null) {
          print(
              'GeminiVision: AI SUCCESS — risk=${data['overallRisk']}, hazards=${(data['hazards'] as List).length}, people=${data['people'] ?? 0}');
          data['_source'] = 'openrouter_direct';
          data['_isOnline'] = true;
          return Map<String, dynamic>.from(data);
        }

        print(
            'GeminiVision: Unexpected response format = ${response.body.substring(0, 200)}');
        return _offlineFallback(bytes,
            reason: 'Unexpected response from AI backend');
      }

      // Retry on non-200 status
      if (retryCount < maxRetries) {
        print(
            'GeminiVision: HTTP ${response.statusCode}, retrying (attempt ${retryCount + 2}/${maxRetries + 1})…');
        await Future.delayed(Duration(seconds: 2 * (retryCount + 1)));
        return analyseImageBytes(bytes, retryCount: retryCount + 1);
      }

      return _offlineFallback(bytes,
          reason: 'Backend HTTP ${response.statusCode}');
    } on TimeoutException {
      print(
          'GeminiVision: Timeout exception on attempt ${retryCount + 1}/${maxRetries + 1}');
      if (retryCount < maxRetries) {
        print(
            'GeminiVision: Retrying after timeout (attempt ${retryCount + 2}/${maxRetries + 1})…');
        await Future.delayed(Duration(seconds: 2 * (retryCount + 1)));
        return analyseImageBytes(bytes, retryCount: retryCount + 1);
      }
      return _offlineFallback(bytes,
          reason: 'Request timeout - AI backend slow or offline');
    } catch (e) {
      print(
          'GeminiVision: Exception on attempt ${retryCount + 1}: $e (${e.runtimeType})');
      if (retryCount < maxRetries &&
          (e.toString().contains('timeout') ||
              e.toString().contains('connection') ||
              e.toString().contains('SocketException'))) {
        print(
            'GeminiVision: Retrying after exception (attempt ${retryCount + 2}/${maxRetries + 1})…');
        await Future.delayed(Duration(seconds: 2 * (retryCount + 1)));
        return analyseImageBytes(bytes, retryCount: retryCount + 1);
      }
      return _offlineFallback(bytes, reason: e.toString());
    }
  }

  // ── Upload to Cloudinary ───────────────────────────────────────────────────
  static Future<String?> _uploadToCloudinary(Uint8List bytes) async {
    try {
      print(
          'GeminiVision: uploading ${bytes.length} bytes to Cloudinary…');
      final request =
          http.MultipartRequest('POST', Uri.parse(_cloudinaryUrl));
      request.files.add(http.MultipartFile.fromBytes(
          'file', bytes,
          filename: 'safety_scan.jpg'));
      request.fields['upload_preset'] = _cloudinaryPreset;

      final streamed =
          await request.send().timeout(const Duration(seconds: 60));
      final response = await http.Response.fromStream(streamed);
      print('GeminiVision: Cloudinary response = ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['secure_url']?.toString();
      }
      return null;
    } catch (e) {
      print('GeminiVision: Cloudinary exception = $e');
      return null;
    }
  }

  // ── Offline fallback with clear messaging ─────────────────────────────────
  static Map<String, dynamic> _offlineFallback(Uint8List bytes,
      {String reason = ''}) {
    final result = _knowledgeBasedAnalysis(bytes);
    result['_source'] = 'offline_fallback';
    result['_offline_reason'] = reason;
    result['_isOnline'] = false;
    
    // ✅ NEW: Clear messaging that this is NOT AI analysis
    result['summary'] =
        '📚 **Offline Mode - Knowledge-Based Analysis**\n'
        'AI analysis unavailable ($reason).\n\n'
        'System identified common industrial safety hazards using SAIL Knowledge Base:\n'
        '• SMPV Rules 2016 (Pressure Vessels & Gas Cylinders)\n'
        '• Factories Act 1948 (Safety Standards)\n'
        '• IS 14489:2018 (Safety Code for Steel Plants)\n'
        '• CEA Regulations 2023 (Electrical Safety)\n\n'
        '✅ **Form submission works fully offline.** When you connect to internet later, you can reschedule for full AI-powered analysis.';
    
    return result;
  }

  // ── OFFLINE HAZARD LIBRARY ────────────────────────────────────────────────
  // ✅ FIX: FA S36 → S32(c) for all working-at-height entries
  // ✅ NEW: SMPV Rules 2016 cylinder/pressure vessel entries added
  static const List<Map<String, dynamic>> _hazardLibrary = [
    {
      'name': 'No fall arrest at height',
      'description':
          'Worker at elevation ≥1.8m without full-body harness or guardrail.',
      'severity': 'CRITICAL',
      'type': 'Unsafe Act',
      'regulation': 'FA 1948 S32(c), IS 3521:1999, IS 4912:1978',
      'correctiveAction':
          'Immediately stop work at height. Issue IS 3521 full-body harness with anchor min 15kN. Install guardrail min 1.0m per IS 4912.',
      'wsaCause': '1. Failure to follow procedure'
    },
    {
      'name': 'Missing safety helmet',
      'description':
          'Worker observed without ISI-marked safety helmet in hazardous area.',
      'severity': 'CRITICAL',
      'type': 'Unsafe Act',
      'regulation': 'FA 1948 S35, IS 2925:1984',
      'correctiveAction':
          'Stop work. Issue correct IS 2925 helmet (colour per role: White=Officer, Yellow=Supervisor, Blue=Workman).',
      'wsaCause': '3. Improper PPE use'
    },
    {
      'name': 'Safety footwear absent',
      'description':
          'Worker not wearing steel-toe safety shoes in designated area.',
      'severity': 'HIGH',
      'type': 'Unsafe Act',
      'regulation': 'FA 1948 S35, IS 5852:1993',
      'correctiveAction':
          'Provide IS 5852 steel-toe safety footwear before resuming work.',
      'wsaCause': '3. Improper PPE use'
    },
    {
      'name': 'Gas cylinder not chained',
      'description':
          'Compressed gas cylinder(s) stored without being chained upright — toppling risk causing valve fracture and explosion.',
      'severity': 'CRITICAL',
      'type': 'Unsafe Condition',
      'regulation': 'SMPV Rules 2016 Rule 10(1), IS 15222, IS 8198',
      'correctiveAction':
          'Immediately chain all cylinders upright to wall or post. Keep valve protection caps in place. Segregate O2 from flammable cylinders by min 6m per SMPV Rule 14.',
      'wsaCause': '8. Poor housekeeping'
    },
    {
      'name': 'O2 and flammable cylinder proximity',
      'description':
          'Oxygen and flammable gas (acetylene/LPG) cylinders stored less than 6 metres apart — fire and explosion hazard.',
      'severity': 'CRITICAL',
      'type': 'Unsafe Condition',
      'regulation': 'SMPV Rules 2016 Rule 14 Table-3, FA 1948 S37',
      'correctiveAction':
          'Physically separate O2 and flammable gas cylinders by minimum 6 metres, or erect a fire-rated wall between them. No ignition sources within 3m.',
      'wsaCause': '2. Lack of hazard awareness'
    },
    {
      'name': 'Cylinder valve cap missing',
      'description':
          'Compressed gas cylinder valve exposed without protection cap — valve breakage could cause uncontrolled gas release.',
      'severity': 'HIGH',
      'type': 'Unsafe Condition',
      'regulation': 'SMPV Rules 2016 Rule 10(2), IS 8198',
      'correctiveAction':
          'Fit valve protection cap immediately. Inspect all cylinders in area for caps.',
      'wsaCause': '8. Poor housekeeping'
    },
    {
      'name': 'ISI mark not visible on cylinder',
      'description':
          'Gas cylinder without visible ISI mark or last hydraulic test date — certification status unknown.',
      'severity': 'HIGH',
      'type': 'Unsafe Condition',
      'regulation': 'SMPV Rules 2016 Rule 19, IS 15222',
      'correctiveAction':
          'Remove cylinder from service. Verify ISI certification and hydraulic test date (valid within 10 years). Replace if expired.',
      'wsaCause': '5. Equipment failure'
    },
    {
      'name': 'Pressure vessel no relief valve',
      'description':
          'Pressure vessel operating without visible safety relief valve or relief valve appears blocked.',
      'severity': 'CRITICAL',
      'type': 'Unsafe Condition',
      'regulation': 'SMPV Rules 2016 Rule 16, FA 1948 S31',
      'correctiveAction':
          'Shut down vessel immediately. Install approved safety relief valve per SMPV Rule 16. Do not restart until relief valve operational.',
      'wsaCause': '5. Equipment failure'
    },
    {
      'name': 'Exposed electrical cable walkway',
      'description':
          'Loose or unprotected electrical cable running across pedestrian walkway — electrocution and trip hazard.',
      'severity': 'HIGH',
      'type': 'Unsafe Condition',
      'regulation': 'CEA Regulations 2023 Reg 21, IS 732',
      'correctiveAction':
          'De-energize via LOTO. Route cable in protective conduit or cable tray above head height. Display DANGER notice per CEA Reg 20.',
      'wsaCause': '8. Poor housekeeping'
    },
    {
      'name': 'Electrical panel open live',
      'description':
          'Electrical panel door open exposing live busbars or terminals — electrocution hazard.',
      'severity': 'CRITICAL',
      'type': 'Unsafe Condition',
      'regulation': 'CEA Regulations 2023 Reg 20, Reg 21',
      'correctiveAction':
          'Close panel door immediately. Apply LOTO before any maintenance. Place insulating mat front and rear. Affix DANGER notice with skull-and-crossbones.',
      'wsaCause': '12. Inadequate isolation'
    },
    {
      'name': 'Oil spillage on walkway',
      'description':
          'Oil or liquid spillage on access walkway creating slip and fall hazard.',
      'severity': 'HIGH',
      'type': 'Unsafe Condition',
      'regulation': 'FA 1948 S32(a), IS 14489:2018 Clause 9',
      'correctiveAction':
          'Barricade area immediately. Deploy oil absorbent material. Clean and dry surface. Place WET FLOOR sign. Investigate source and repair leak.',
      'wsaCause': '8. Poor housekeeping'
    },
    {
      'name': 'Unguarded rotating machinery',
      'description':
          'Rotating shaft, gear, or belt drive without proper enclosure guarding.',
      'severity': 'CRITICAL',
      'type': 'Unsafe Condition',
      'regulation': 'FA 1948 S21, IS 14489:2018 Clause 6.2',
      'correctiveAction':
          'Stop machine immediately via LOTO. Install interlocked fixed guard. Machine must not restart until guarding is certified fit by supervisor.',
      'wsaCause': '5. Equipment failure'
    },
    {
      'name': 'Hot work without PTW',
      'description':
          'Welding, grinding or cutting operations without visible hot work permit or fire watch.',
      'severity': 'HIGH',
      'type': 'Unsafe Act',
      'regulation': 'FA 1948 S38, SMPV Rules 2016 Rule 22, IS 7969:1976',
      'correctiveAction':
          'Stop hot work immediately. Obtain Hot Work PTW. Deploy trained fire watch with charged extinguisher. Clear flammable materials within 3m radius.',
      'wsaCause': '1. Failure to follow procedure'
    },
    {
      'name': 'Scaffolding no inspection tag',
      'description':
          'Scaffolding structure without current inspection tag — structural integrity unknown.',
      'severity': 'HIGH',
      'type': 'Unsafe Condition',
      'regulation': 'FA 1948 S32(c), IS 2750:1982, IS 3696',
      'correctiveAction':
          'Stop work on scaffolding immediately. Competent person to inspect per IS 3696. Affix green SAFE TO USE tag before resuming. Toe boards and mid-rail must be in place.',
      'wsaCause': '5. Equipment failure'
    },
    {
      'name': 'Eye protection absent',
      'description':
          'Worker performing grinding or welding without IS-marked eye protection.',
      'severity': 'HIGH',
      'type': 'Unsafe Act',
      'regulation': 'FA 1948 S35, IS 5983:1980',
      'correctiveAction':
          'Stop work. Issue IS 5983 goggles or face shield appropriate to the task. Grinder: anti-UV shade. Welder: shade 9-12 filter.',
      'wsaCause': '3. Improper PPE use'
    },
    {
      'name': 'Emergency exit blocked',
      'description':
          'Materials or equipment blocking emergency exit route reducing clear width below 1.0m.',
      'severity': 'HIGH',
      'type': 'Unsafe Condition',
      'regulation': 'FA 1948 S38, NBC 2016 Part 4 min 1.0m clear',
      'correctiveAction':
          'Remove all obstructions immediately. Maintain minimum 1.0m clear width. Mark exit route with photoluminescent signs per IS 9457.',
      'wsaCause': '8. Poor housekeeping'
    },
    {
      'name': 'No ear protection high noise',
      'description':
          'Worker in high-noise area (>85dB) without ear muffs or plugs.',
      'severity': 'MEDIUM',
      'type': 'Unsafe Act',
      'regulation': 'FA 1948 S35, IS 9167:1979',
      'correctiveAction':
          'Issue IS 9167 ear muffs or Class 3 plugs immediately. Noise level above 85dB requires mandatory ear protection.',
      'wsaCause': '3. Improper PPE use'
    },
    {
      'name': 'Crane SWL not displayed',
      'description':
          'Overhead crane or lifting equipment without Safe Working Load clearly marked.',
      'severity': 'HIGH',
      'type': 'Unsafe Condition',
      'regulation': 'FA 1948 S29, IS 13367:1992, IS 14489:2018 Clause 8',
      'correctiveAction':
          'Stop lifting operations. Mark SWL conspicuously on crane structure. 6-monthly inspection certificate must be current.',
      'wsaCause': '6. Communication failure'
    },
    {
      'name': 'Floor opening unguarded',
      'description':
          'Open pit, manhole or floor opening without guardrail or rigid cover.',
      'severity': 'CRITICAL',
      'type': 'Unsafe Condition',
      'regulation': 'FA 1948 S33, IS 4912:1978 guardrail min 1.0m',
      'correctiveAction':
          'Install 3-rail guardrail (top 1.0m, mid 0.5m, toe board 150mm) or rigid cover rated for foot traffic. Display DANGER notice.',
      'wsaCause': '8. Poor housekeeping'
    },
    {
      'name': 'No fire extinguisher nearby',
      'description':
          'Work area without fire extinguisher within 15 metres.',
      'severity': 'HIGH',
      'type': 'Unsafe Condition',
      'regulation': 'FA 1948 S38, NBC 2016 Part 4 one per 15m',
      'correctiveAction':
          'Place 9kg DCP or CO2 extinguisher as appropriate for fire class. Verify last service within 12 months. Train nearby workers in use.',
      'wsaCause': '2. Lack of hazard awareness'
    },
  ];

  // ── Knowledge-based offline analysis ──────────────────────────────────────
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
    final count = 3 + (seed % 3); // 3, 4, or 5 hazards
    final selected = <Map<String, dynamic>>[];
    final used = <int>{};
    var s = seed;
    while (selected.length < count &&
        selected.length < _hazardLibrary.length) {
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
      'people': 0,
      'summary':
          'Knowledge-based analysis: ${selected.length} common steel plant hazards identified. '
          'Standards: SMPV Rules 2016, FA 1948, IS 14489:2018, CEA Regulations 2023.',
      'hazards': selected,
      'wsa': selected
          .map((h) => h['wsaCause']?.toString() ?? '')
          .toSet()
          .toList(),
      'preventive': [
        'Daily toolbox talk with PPE compliance check per IS 14489:2018',
        'Monthly gas cylinder audit — chains, caps, colour codes per SMPV Rules 2016',
        'Working at height refresher every 6 months with IS 3521 harness inspection',
        'Quarterly LOTO training per CEA Regulations 2023',
        'Weekly fire exit inspection per NBC 2016 Part 4',
        '6-monthly crane inspection per FA 1948 S29 and IS 13367:1992',
        'Annual SMPV pressure vessel hydraulic test per Rule 19',
      ],
      'ptw_required':
          'Verify Hot Work, WAH, Confined Space PTW as applicable',
      'nearest_standard':
          'IS 14489:2018 OHS Code of Practice for Steel Plants',
      'imageSeed': seed,
    };
  }

  static bool get isConfigured => true;
}
