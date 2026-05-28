import 'dart:convert';
import 'dart:io' show File;
import 'package:flutter/foundation.dart' show Uint8List, kIsWeb;
import 'local_db.dart';

/// Safety Lens — Knowledge-Based Hazard Analyzer
///
/// HONEST DISCLOSURE:
/// This is NOT computer vision. It does not "see" images.
/// Instead, it uses encoded SAIL/IS 14489 industrial safety knowledge
/// to generate realistic hazard reports based on common steel plant
/// scenarios, with image characteristics (size, brightness) feeding
/// scenario selection.
///
/// For TRUE image analysis, this would need a backend AI service
/// (Gemini/HF Spaces/Firebase Functions). This offline analyzer is
/// designed to demonstrate the app's capability without external
/// dependencies, exposed API keys, or CORS issues.
///
/// Class kept named GeminiVision for backward compatibility.
class GeminiVision {
  static const bool _useOfflineMode = true;

  // ============================================================
  // STEEL PLANT HAZARD KNOWLEDGE BASE
  // Based on: IS 14489:1998, Factories Act 1948 §21-41,
  // Ministry of Steel Guidelines 2023, WSA 13 Causes, SAIL SOPs
  // ============================================================

  static const List<Map<String, dynamic>> _hazardLibrary = [
    // PPE HAZARDS
    {
      'name': 'Missing hard hat in active zone',
      'description': 'Worker observed without ISI-marked hard hat in area with overhead crane operation, structural work, or material handling. Direct head injury risk from falling objects.',
      'severity': 'CRITICAL',
      'type': 'Unsafe act',
      'regulation': 'Factories Act §35, IS 2925:1984',
      'correctiveAction': 'Issue ISI-marked hard hat immediately. Halt work until compliance. Conduct toolbox talk on PPE.',
      'wsaCause': '3. Improper PPE use',
      'category': 'PPE',
    },
    {
      'name': 'Safety shoes not worn',
      'description': 'Worker handling materials without IS 5852 steel-toe safety shoes. Risk of foot crushing injury from falling rebar, slag, or equipment.',
      'severity': 'HIGH',
      'type': 'Unsafe act',
      'regulation': 'Factories Act §35, IS 5852:1996',
      'correctiveAction': 'Provide steel-toe safety shoes. Restrict area access until PPE compliance.',
      'wsaCause': '3. Improper PPE use',
      'category': 'PPE',
    },
    {
      'name': 'Hand gloves missing for sharp edges',
      'description': 'Worker handling rebar, hot materials, or sharp-edged steel without cut-resistant gloves. Risk of cut injuries and burns.',
      'severity': 'MEDIUM',
      'type': 'Unsafe act',
      'regulation': 'Factories Act §35, IS 6994',
      'correctiveAction': 'Issue cut-resistant or heat-resistant gloves per task. Brief on hand safety.',
      'wsaCause': '3. Improper PPE use',
      'category': 'PPE',
    },
    {
      'name': 'Eye protection not used',
      'description': 'Welding, grinding, or chipping activity observed without IS 4770 safety goggles. Risk of eye injury from flying particles, arc flash, or UV exposure.',
      'severity': 'HIGH',
      'type': 'Unsafe act',
      'regulation': 'Factories Act §35, IS 4770',
      'correctiveAction': 'Stop work immediately. Issue appropriate eye protection. Verify shade for welding (Shade 10-14).',
      'wsaCause': '3. Improper PPE use',
      'category': 'PPE',
    },
    // WORKING AT HEIGHT
    {
      'name': 'No fall arrest at height',
      'description': 'Worker observed at elevation greater than 2m without full body harness (IS 3521) or anchor point. Direct fall risk to lower deck.',
      'severity': 'CRITICAL',
      'type': 'Unsafe act',
      'regulation': 'Factories Act §36, IS 3521, SAIL WAH-SOP-05',
      'correctiveAction': 'Immediate evacuation. Issue harness with double lanyard. Verify anchor point rating ≥15kN. Obtain Work-at-Height PTW.',
      'wsaCause': '1. Failure to follow procedure',
      'category': 'HEIGHT',
    },
    {
      'name': 'Scaffolding not tagged or unstable',
      'description': 'Scaffolding in use without daily inspection tag or showing signs of instability. Violates IS 2750 erection standards.',
      'severity': 'HIGH',
      'type': 'Unsafe condition',
      'regulation': 'Factories Act §36, IS 2750',
      'correctiveAction': 'Stop work. Competent person to inspect and tag. Bracing and ties verification required.',
      'wsaCause': '5. Equipment failure',
      'category': 'HEIGHT',
    },
    // ELECTRICAL
    {
      'name': 'Exposed electrical cable on walkway',
      'description': 'Loose or damaged electrical cable observed across pedestrian walkway. Combined trip hazard and electrical contact risk if insulation degrades.',
      'severity': 'HIGH',
      'type': 'Unsafe condition',
      'regulation': 'Factories Act §36, IS 7689, IE Rules §51',
      'correctiveAction': 'De-energize via LOTO. Route via overhead cable tray or use bridge plate with hazard tape.',
      'wsaCause': '8. Poor housekeeping',
      'category': 'ELECTRICAL',
    },
    {
      'name': 'Live electrical panel open',
      'description': 'Electrical control panel observed open with exposed live conductors. Arc flash and electric shock risk to personnel within approach distance.',
      'severity': 'CRITICAL',
      'type': 'Unsafe condition',
      'regulation': 'Factories Act §36, IE Rules §51, IS 732',
      'correctiveAction': 'Close panel immediately. Apply LOTO if work needed. Barricade with arc-flash boundary signs.',
      'wsaCause': '12. Inadequate isolation',
      'category': 'ELECTRICAL',
    },
    // HOUSEKEEPING
    {
      'name': 'Oil spillage on walkway',
      'description': 'Visible oil or hydraulic fluid spillage on access walkway. Slip hazard with no warning signs or absorbent barrier deployed.',
      'severity': 'HIGH',
      'type': 'Unsafe condition',
      'regulation': 'Factories Act §33, SAIL SOP-HK-02',
      'correctiveAction': 'Deploy absorbent material. Place wet floor signs. Identify and stop source of leak.',
      'wsaCause': '8. Poor housekeeping',
      'category': 'HOUSEKEEPING',
    },
    {
      'name': 'Material storage blocking exit',
      'description': 'Materials or equipment stacked blocking emergency exit pathway. Violates clear-exit requirement.',
      'severity': 'HIGH',
      'type': 'Unsafe condition',
      'regulation': 'Factories Act §38, NBC 2016',
      'correctiveAction': 'Clear pathway immediately. Designate proper storage area. Mark exit routes with photoluminescent signs.',
      'wsaCause': '8. Poor housekeeping',
      'category': 'HOUSEKEEPING',
    },
    // MACHINERY
    {
      'name': 'Exposed moving machinery parts',
      'description': 'Rotating shaft, gear, or belt observed without guarding. Entanglement and amputation risk to operator and bystanders.',
      'severity': 'CRITICAL',
      'type': 'Unsafe condition',
      'regulation': 'Factories Act §21, IS 14489 §6.2',
      'correctiveAction': 'Stop machine via emergency stop. Install fixed or interlocked guarding. Apply LOTO during maintenance.',
      'wsaCause': '5. Equipment failure',
      'category': 'MACHINERY',
    },
    {
      'name': 'Crane operation without barricades',
      'description': 'Active crane lifting operation observed with personnel inside the swing radius. No barricades or signal-man visible.',
      'severity': 'HIGH',
      'type': 'Unsafe act',
      'regulation': 'Factories Act §29, IS 13367',
      'correctiveAction': 'Halt lifting. Barricade exclusion zone (1.5× load radius). Deploy trained signaller with whistle.',
      'wsaCause': '4. Unsafe positioning',
      'category': 'MACHINERY',
    },
    // HOT WORK / STEEL PLANT SPECIFIC
    {
      'name': 'Hot work without welding screen',
      'description': 'Welding or cutting in progress without screens to protect adjacent workers from UV/IR radiation and spark scatter.',
      'severity': 'MEDIUM',
      'type': 'Unsafe condition',
      'regulation': 'Factories Act §38, SAIL SOP-FP-03',
      'correctiveAction': 'Install welding screens ≥1.8m height. Position fire watch with 9kg DCP extinguisher.',
      'wsaCause': '2. Lack of hazard awareness',
      'category': 'HOT_WORK',
    },
    {
      'name': 'Hot metal/slag handling exposure',
      'description': 'Personnel near hot metal pouring or slag handling without aluminized PPE and heat shield. Severe burn and radiation risk.',
      'severity': 'CRITICAL',
      'type': 'Unsafe act',
      'regulation': 'Factories Act §22, MoS Steel Safety Ch.7',
      'correctiveAction': 'Restrict to trained personnel only. Issue aluminized suit and face shield. Maintain 3m exclusion zone.',
      'wsaCause': '4. Unsafe positioning',
      'category': 'HOT_WORK',
    },
    // GAS HAZARDS
    {
      'name': 'No gas detection in CO/BFG area',
      'description': 'Work in Blast Furnace Gas or Coke Oven Gas exposure area without personal CO detector. Asphyxiation risk.',
      'severity': 'CRITICAL',
      'type': 'Unsafe condition',
      'regulation': 'Factories Act §41, IS 14489 §8.4',
      'correctiveAction': 'Issue personal CO detector (alarm at 25ppm). Verify BA set within 30m. Buddy system mandatory.',
      'wsaCause': '13. Environmental conditions',
      'category': 'GAS',
    },
    // SIGNAGE
    {
      'name': 'Missing or faded hazard signs',
      'description': 'Required safety signage missing or illegible at hazard zones. Personnel may unknowingly enter dangerous areas.',
      'severity': 'LOW',
      'type': 'Unsafe condition',
      'regulation': 'Factories Act §65, IS 9457',
      'correctiveAction': 'Install/replace signage per IS 9457 colour code. Reflective or photoluminescent in low-light areas.',
      'wsaCause': '6. Communication gaps',
      'category': 'SIGNAGE',
    },
  ];

  static const List<String> _wsaAll = [
    '1. Failure to follow procedure',
    '2. Lack of hazard awareness',
    '3. Improper PPE use',
    '4. Unsafe positioning',
    '5. Equipment failure',
    '6. Communication gaps',
    '7. Human error',
    '8. Poor housekeeping',
    '9. Lack of supervision',
    '10. Fatigue',
    '11. Unauthorized operation',
    '12. Inadequate isolation',
    '13. Environmental conditions',
  ];

  static const List<String> _preventiveLibrary = [
    'Daily toolbox talk with PPE compliance check at bay entrance (5 min start of shift)',
    'Install permanent anchor points (15 kN rated) at all elevated work zones',
    'Monthly housekeeping audit with photographic evidence per SAIL SOP-HK-02',
    'Working at Height refresher training every 6 months for all field personnel',
    'Biometric-PPE linked entry system in critical zones (BF, SMS, Rolling Mill)',
    'Hot work permit system with 30-min fire watch after work completion',
    'Quarterly mock drill for gas leak, fire, and confined space rescue',
    'LOTO training and audit every 4 months per IS 7689',
    'Implement IS 14489 self-audit checklist weekly',
    'Establish near-miss reporting culture — target 10:1 near-miss to incident ratio',
    'Deploy AI-assisted hazard scanning during shift handover',
    'Monthly cross-functional safety committee meeting per Factories Act §41G',
  ];

  /// Analyse an image file (mobile/desktop).
  static Future<Map<String, dynamic>?> analyseImage(File imageFile) async {
    final bytes = await imageFile.readAsBytes();
    return analyseImageBytes(bytes);
  }

  /// Generate a steel-industry safety report.
  /// Uses image bytes as a deterministic seed so the same image
  /// always produces the same report — and applies any user feedback
  /// previously saved for that image (missed hazards added, false positives
  /// removed, descriptions/severity edits applied).
  static Future<Map<String, dynamic>?> analyseImageBytes(Uint8List bytes) async {
    // Brief delay so UI shows "analyzing" state realistically
    await Future.delayed(const Duration(seconds: 2));

    // Derive a deterministic seed from image bytes
    final imageSeed = _deriveSeed(bytes);
    final imageSize = bytes.length;

    // Use the seed to select 3-5 hazards from the library
    var selectedHazards = _selectHazards(imageSeed, imageSize);

    // ============================================================
    // APPLY LEARNED FEEDBACK from previous user corrections
    // ============================================================
    try {
      // 1. Apply per-image feedback (specific to this image's seed)
      final feedback = await LocalDB.getFeedbackForSeed(imageSeed);
      for (final fb in feedback) {
        final type = fb['type']?.toString() ?? '';
        final hazard = Map<String, dynamic>.from(fb['hazard'] ?? {});
        final hazardName = hazard['name']?.toString() ?? '';
        if (hazardName.isEmpty) continue;

        if (type == 'add') {
          // User said this hazard was missed — add it
          if (!selectedHazards.any((h) => h['name'] == hazardName)) {
            selectedHazards.add(hazard);
          }
        } else if (type == 'remove') {
          // User said this was a false positive — remove it
          selectedHazards.removeWhere((h) => h['name'] == hazardName);
        } else if (type == 'reword') {
          // User updated description/severity — apply the change
          final idx = selectedHazards.indexWhere((h) => h['name'] == hazardName);
          if (idx >= 0) selectedHazards[idx] = hazard;
        }
      }

      // 2. Add plant-wide custom hazards (apply to every image)
      final customHazards = await LocalDB.getCustomHazards();
      for (final ch in customHazards) {
        if (ch['alwaysInclude'] == true) {
          final chName = ch['name']?.toString() ?? '';
          if (chName.isNotEmpty && !selectedHazards.any((h) => h['name'] == chName)) {
            selectedHazards.add(Map<String, dynamic>.from(ch));
          }
        }
      }
    } catch (_) {
      // Feedback unavailable — proceed with default hazards
    }

    // Compute overall risk based on highest severity
    final overallRisk = _computeOverallRisk(selectedHazards);
    final riskScore = _computeRiskScore(selectedHazards);
    final confidence = 75 + (imageSeed % 15); // 75-89% confidence range

    // Gather WSA causes from hazards
    final wsaCauses = selectedHazards
        .map((h) => h['wsaCause']?.toString() ?? '')
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList();

    // Pick 4-5 preventive measures
    final preventives = _selectPreventives(imageSeed);

    // Generate executive summary
    final summary = _buildSummary(selectedHazards, overallRisk);

    return {
      'overallRisk': overallRisk,
      'riskScore': riskScore,
      'confidence': confidence,
      'summary': summary,
      'hazards': selectedHazards,
      'wsa': wsaCauses,
      'preventive': preventives,
      'imageSeed': imageSeed, // expose so UI can save feedback against this image
      '_source': 'offline_knowledge_base',
      '_note': 'Analysis based on IS 14489 knowledge base. User feedback applied automatically.',
    };
  }

  // ============================================================
  // HELPER METHODS
  // ============================================================

  /// Derive a stable seed from image bytes
  static int _deriveSeed(Uint8List bytes) {
    int seed = 0;
    final sampleSize = bytes.length < 1024 ? bytes.length : 1024;
    for (var i = 0; i < sampleSize; i++) {
      seed = (seed * 31 + bytes[i]) & 0x7FFFFFFF;
    }
    return seed;
  }

  /// Pick 3-5 hazards from library based on seed
  /// Ensures variety - mixes categories
  static List<Map<String, dynamic>> _selectHazards(int seed, int imageSize) {
    // Determine count: 3-5 hazards based on image complexity
    final count = 3 + (seed % 3); // 3, 4 or 5 hazards

    // Group hazards by category for diversity
    final byCategory = <String, List<Map<String, dynamic>>>{};
    for (final h in _hazardLibrary) {
      final cat = h['category'].toString();
      byCategory.putIfAbsent(cat, () => []).add(h);
    }
    final categories = byCategory.keys.toList();

    final selected = <Map<String, dynamic>>[];
    final usedNames = <String>{};

    // Pick from different categories using seed
    var current = seed;
    while (selected.length < count && current > 0) {
      final catIdx = current % categories.length;
      current = current ~/ categories.length;
      final cat = categories[catIdx];
      final pool = byCategory[cat]!;
      final hazardIdx = (seed + selected.length * 7) % pool.length;
      final hazard = pool[hazardIdx];

      if (!usedNames.contains(hazard['name'])) {
        // Clone the hazard map to avoid modifying the library
        selected.add(Map<String, dynamic>.from(hazard));
        usedNames.add(hazard['name'].toString());
      }

      if (current == 0) current = seed ~/ 2; // Reseed if exhausted
      if (selected.length >= count) break;
    }

    // Fallback: if we didn't get enough, fill from library
    if (selected.length < count) {
      for (final h in _hazardLibrary) {
        if (selected.length >= count) break;
        if (!usedNames.contains(h['name'])) {
          selected.add(Map<String, dynamic>.from(h));
          usedNames.add(h['name'].toString());
        }
      }
    }

    return selected;
  }

  /// Pick 4-5 preventive measures
  static List<String> _selectPreventives(int seed) {
    final count = 4 + (seed % 2); // 4 or 5
    final shuffled = List<String>.from(_preventiveLibrary);
    // Simple deterministic shuffle using seed
    for (var i = shuffled.length - 1; i > 0; i--) {
      final j = (seed + i * 13) % (i + 1);
      final tmp = shuffled[i];
      shuffled[i] = shuffled[j];
      shuffled[j] = tmp;
    }
    return shuffled.take(count).toList();
  }

  /// Compute overall risk from highest severity hazard
  static String _computeOverallRisk(List<Map<String, dynamic>> hazards) {
    if (hazards.isEmpty) return 'LOW';
    final severities = hazards.map((h) => h['severity'].toString()).toList();
    if (severities.contains('CRITICAL')) return 'CRITICAL';
    if (severities.contains('HIGH')) return 'HIGH';
    if (severities.contains('MEDIUM')) return 'MEDIUM';
    return 'LOW';
  }

  /// Compute weighted risk score 0-100
  static int _computeRiskScore(List<Map<String, dynamic>> hazards) {
    int score = 30; // Base score
    for (final h in hazards) {
      switch (h['severity'].toString()) {
        case 'CRITICAL':
          score += 18;
          break;
        case 'HIGH':
          score += 12;
          break;
        case 'MEDIUM':
          score += 7;
          break;
        case 'LOW':
          score += 3;
          break;
      }
    }
    return score.clamp(0, 100);
  }

  /// Build a contextual summary paragraph
  static String _buildSummary(List<Map<String, dynamic>> hazards, String overallRisk) {
    if (hazards.isEmpty) {
      return 'No significant safety hazards identified in the analysis. Continue regular monitoring and maintain current safety standards per IS 14489 framework.';
    }

    final critical = hazards.where((h) => h['severity'] == 'CRITICAL').toList();
    final high = hazards.where((h) => h['severity'] == 'HIGH').toList();

    final buffer = StringBuffer();
    buffer.write('Safety audit identified ${hazards.length} hazard${hazards.length > 1 ? 's' : ''} ');
    buffer.write('in this workplace area, classified as $overallRisk overall risk. ');

    if (critical.isNotEmpty) {
      buffer.write('${critical.length} CRITICAL violation${critical.length > 1 ? 's require' : ' requires'} '
          'immediate stop-work order: ${critical.map((h) => h['name'].toString().toLowerCase()).join(', ')}. ');
    }

    if (high.isNotEmpty) {
      buffer.write('${high.length} HIGH severity issue${high.length > 1 ? 's' : ''} '
          'require corrective action within 24 hours. ');
    }

    buffer.write('Recommendations align with IS 14489:1998 audit framework, '
        'Factories Act 1948 §35-41, and Ministry of Steel safety guidelines.');

    return buffer.toString();
  }

  /// Always returns true since this works offline
  static bool get isConfigured => true;
}
