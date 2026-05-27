import 'dart:io';

class LocalAI {
  /// Offline fallback when Gemini is unreachable.
  /// Accepts the image file for signature parity with GeminiVision,
  /// but returns a mock scenario (doesn't actually inspect pixels).
  static Future<Map<String, dynamic>> analyseImage(File imageFile) async {
    final scenarios = [
      {
        'riskScore': 72,
        'severity': 'HIGH',
        'hazardType': 'PPE Non-Compliance',
        'summary': 'Critical PPE violations detected in workplace. Worker observed without mandatory head protection near overhead crane operations. Floor area shows signs of contamination creating additional slip hazards. Immediate supervisor intervention required.',
        'confidence': 91,
        'hazards': [
          {
            'name': 'Missing Hard Hat',
            'severity': 'CRITICAL',
            'desc': 'Worker without ISI-marked hard hat in crane operation zone — head injury risk from falling objects',
            'ref': 'Factories Act §35 · IS 2925 · SAIL SOP PPE-01'
          },
          {
            'name': 'Slip Hazard on Floor',
            'severity': 'MEDIUM',
            'desc': 'Liquid spillage on work floor creating slip and fall risk for personnel',
            'ref': 'Factories Act §21 · SAIL Housekeeping SOP-HK-02'
          },
        ],
        'rules': [
          'Factories Act 1948 §35 — PPE mandatory in hazardous zones',
          'IS 2925 — Industrial Safety Helmets standard',
          'SAIL SOP PPE-01 — Hard hat compulsory in plant operational areas',
          'DGMS Circular 2019/SO/SAFETY — PPE compliance at steel plants',
        ],
        'corrective': [
          'Issue immediate stop-work order until PPE compliance is achieved',
          'Provide ISI-marked hard hat from nearest PPE station',
          'Clean floor spillage and place wet floor warning signs',
          'Supervisor to verify PPE before resuming operations',
        ],
        'preventive': [
          'Install PPE compliance checkpoint at bay entrance',
          'Conduct daily toolbox talk on PPE importance before each shift',
          'Monthly PPE audit by Safety Officer with photographic record',
          'Implement biometric-PPE linked entry system',
        ],
        'wsa': ['3. Improper PPE', '9. Lack of supervision', '8. Poor housekeeping'],
      },
      {
        'riskScore': 81,
        'severity': 'CRITICAL',
        'hazardType': 'Working at Height — Fall Risk',
        'summary': 'Personnel observed working at significant elevation without appropriate fall protection equipment. No safety harness or anchor point visible. This constitutes an immediately dangerous condition under Factories Act §36.',
        'confidence': 92,
        'hazards': [
          {
            'name': 'No Safety Harness at Height',
            'severity': 'CRITICAL',
            'desc': 'Worker at elevation greater than 2 metres without full-body harness or lanyard',
            'ref': 'Factories Act §36 · IS 3521 · SAIL WAH-SOP-05'
          },
          {
            'name': 'Unguarded Edge',
            'severity': 'HIGH',
            'desc': 'Open edge with no guardrail or toe-board visible — fall risk',
            'ref': 'Factories Act §33 · IS 4912'
          },
        ],
        'rules': [
          'Factories Act 1948 §36 — Safety nets/harnesses at height',
          'IS 3521 — Personal Fall Arrest Systems specification',
          'SAIL WAH-SOP-05 — Working at Height permit mandatory',
          'Permit to Work (PTW) system bypassed',
        ],
        'corrective': [
          'Immediate stop-work order — evacuate worker from height',
          'Issue full-body harness with double lanyard',
          'Inspect anchor points before resuming work',
          'Obtain Permit to Work for height operations',
        ],
        'preventive': [
          'Mandatory WAH training every 6 months',
          'PTW system enforcement for all height work',
          'Install permanent anchor points and guardrails',
          'Medical fitness assessment for height workers',
        ],
        'wsa': ['1. Failure to follow procedure', '2. Lack of hazard awareness', '11. Unauthorized operation'],
      },
      {
        'riskScore': 18,
        'severity': 'LOW',
        'hazardType': 'Good Compliance — Minor Observations',
        'summary': 'Work area shows good overall safety compliance. All workers observed wearing mandatory PPE. Minor housekeeping improvements recommended. No critical violations detected at this time.',
        'confidence': 89,
        'hazards': [
          {
            'name': 'Minor Housekeeping Issue',
            'severity': 'LOW',
            'desc': 'Some material stored slightly outside designated storage area',
            'ref': 'SAIL SOP-HK-02 — Housekeeping standards'
          },
        ],
        'rules': [
          'Minor non-conformity: Materials not in designated storage zone',
          'SAIL SOP-HK-02 — Housekeeping standards partial deviation',
        ],
        'corrective': [
          'Relocate stored materials to designated zone',
          'Update area marking for clarity',
        ],
        'preventive': [
          '5S housekeeping audit weekly',
          'Refresh area demarcation markings monthly',
          'Continue current safety practices',
        ],
        'wsa': ['8. Poor housekeeping'],
      },
    ];
    final idx = DateTime.now().second % scenarios.length;
    return scenarios[idx];
  }

  static Map<String, String> processText(String text) {
    final q = text.toLowerCase();
    String wsa = '7. Human error';
    String root = 'Momentary lapse in judgement; task pressure; inadequate hazard recognition training';
    String fix = 'Conduct toolbox talk before resuming work; update Job Safety Analysis (JSA)';
    String title = 'Near Miss / Unsafe Condition Reported';

    if (q.contains('helmet') || q.contains('hard hat') || q.contains('ppe') || q.contains('gloves')) {
      wsa = '3. Improper PPE use';
      root = 'Insufficient enforcement at bay entry; supervisor gap at shift start';
      fix = 'Issue PPE immediately; stop-work until compliant; supervisor sign-off required';
      title = 'PPE Violation — Missing Personal Protective Equipment';
    } else if (q.contains('slip') || q.contains('wet') || q.contains('spill') || q.contains('oil')) {
      wsa = '8. Poor housekeeping';
      root = 'Housekeeping schedule not followed; drainage not inspected regularly';
      fix = 'Clean spillage immediately; place wet floor signs; assign area owner';
      title = 'Slip Hazard — Floor Contamination';
    } else if (q.contains('crane') || q.contains('lifting') || q.contains('load')) {
      wsa = '4. Unsafe positioning';
      root = 'Exclusion zone not established; spotter not deployed during lifting operation';
      fix = 'Establish exclusion zone with barriers; re-brief all crane operators';
      title = 'Crane Operation — Uncontrolled Load Movement';
    } else if (q.contains('electric') || q.contains('loto') || q.contains('shock') || q.contains('live')) {
      wsa = '12. Inadequate isolation';
      root = 'LOTO procedure not followed; energy isolation incomplete';
      fix = 'Immediate LOTO; verify zero energy with voltmeter; authorised personnel only';
      title = 'Electrical Safety Violation — Inadequate Isolation';
    } else if (q.contains('fall') || q.contains('height') || q.contains('harness')) {
      wsa = '11. Unauthorized operation';
      root = 'Work commenced without Working at Height permit; PTW system bypassed';
      fix = 'Stop work; obtain WAH PTW; issue harness and check anchor points';
      title = 'Working at Height — Fall Risk Identified';
    } else if (q.contains('gas') || q.contains('fume') || q.contains('smoke')) {
      wsa = '2. Lack of hazard awareness';
      root = 'Gas detector not used; ventilation inadequate; hazard not recognised';
      fix = 'Evacuate area; use BA set; ventilate before re-entry';
      title = 'Gas Hazard — Possible Toxic Exposure';
    } else if (q.contains('fire') || q.contains('hot') || q.contains('weld')) {
      wsa = '1. Failure to follow procedure';
      root = 'Hot work permit not obtained; fire watch not deployed';
      fix = 'Stop hot work; obtain PTW; deploy fire watch with extinguisher';
      title = 'Hot Work — Fire Hazard';
    } else if (q.contains('supervisor') || q.contains('unsupervised')) {
      wsa = '9. Lack of supervision';
      root = 'Supervisor absent during critical operation; span of control exceeded';
      fix = 'Designate qualified supervisor immediately; review span of control';
      title = 'Supervision Gap During Critical Operation';
    }

    return {
      'title': title,
      'wsa': wsa,
      'root': root,
      'fix': fix,
    };
  }

  static String chat(String question) {
    final q = question.toLowerCase();
    final kb = <List<String>, String>{
      ['ppe', 'helmet', 'hard hat', 'gloves']:
        'Mandatory PPE at SAIL:\n\n• Hard hat — IS 2925 (yellow=visitor, white=officer, blue=worker)\n• Safety shoes — IS 5852 (steel toe cap)\n• Safety gloves — IS 6994 (heat resistant)\n• High-vis vest — vehicle/crane areas\n• Face shield — welding, furnace work\n• Safety harness — IS 3521 for height >2m\n\nRef: Factories Act §35 | SAIL SOP PPE-01',
      ['loto', 'lockout', 'isolation']:
        'LOTO Procedure (SAIL SOP-EL-09):\n\n1. Notify all affected workers\n2. Identify ALL energy sources\n3. Shut down using normal procedure\n4. Isolate each energy source\n5. Apply personal lock (one per worker)\n6. Release stored energy\n7. Verify zero energy with voltmeter\n\nRef: Factories Act §20',
      ['confined', 'vessel', 'tank']:
        'Confined Space Entry:\n\n• PTW from area Safety Officer\n• Atmosphere test: O₂ 19.5–23.5%, CO <25 ppm\n• Forced ventilation running\n• Standby person at entry\n• Radio communication\n• Full-body harness with lifeline\n\nRef: Factories Act §36 | DGMS 2021',
      ['height', 'wah', 'scaffold']:
        'Working at Height (>2m):\n\n• PTW required\n• Full-body harness IS 3521, double lanyard\n• Anchor point rated min 15 kN\n• Scaffolding IS 2750, tagged & inspected\n• Ladders — 3-point contact\n• Guardrails on open edges\n\nRef: Factories Act §36 | SAIL WAH-SOP-05',
      ['fire', 'hot work', 'welding']:
        'Hot Work Permit:\n\n• PTW from Area In-charge + Safety Officer\n• Fire watch present (during + 30 min after)\n• Combustibles cleared 10m radius\n• Fire extinguisher (9kg DCP) at site\n• Gas test for flammable atmosphere\n• Valid maximum 8 hours\n\nRef: Factories Act §38 | SAIL SOP-FP-03',
      ['electric', 'electrocution', 'arc flash']:
        'Electrical Safety:\n\n• Never work on live equipment without PTW + LOTO\n• Min approach: 33kV=0.9m, 11kV=0.6m, LT=0.3m\n• Arc Flash PPE for HV work\n• Earth before AND after isolation\n• Test for dead before touching\n\nRef: IE Rules §51 | IS 732 | Factories Act §36',
      ['gas', 'co', 'carbon monoxide']:
        'Gas Safety:\n\nKnow your gases:\n• BFG (Blast Furnace Gas) — CO ~25%\n• COG (Coke Oven Gas) — H₂ ~55%\n• CO TLV: 25 ppm | IDLH: 1200 ppm\n\n• Personal CO detector mandatory\n• BA set within 30m\n• Buddy system always\n\nEmergency: ECR — Internal 3333',
      ['wsa', '13 causes', 'world steel']:
        'WSA 13 Causes:\n\n1. Failure to follow procedure\n2. Lack of hazard awareness\n3. Improper PPE use\n4. Unsafe positioning\n5. Equipment failure\n6. Communication gaps\n7. Human error\n8. Poor housekeeping\n9. Lack of supervision\n10. Fatigue\n11. Unauthorized operation\n12. Inadequate isolation\n13. Environmental conditions',
      ['factories', 'section', 'regulation']:
        'Key Factories Act 1948 Sections:\n\n§17 — Lighting (min 50 lux)\n§21 — Fencing of machinery\n§28 — Hoists and lifts\n§29 — Lifting machines (6-monthly check)\n§33 — Floors, stairs, passages\n§35 — PPE mandatory\n§36 — Fumes/heights/confined space\n§38 — Fire & explosion precautions\n\nPenalty: ₹1 lakh + 2 years imprisonment',
    };

    for (final entry in kb.entries) {
      for (final keyword in entry.key) {
        if (q.contains(keyword)) return entry.value;
      }
    }
    return 'Ask me about: PPE, LOTO, confined space, working at height, hot work, electrical, gas safety, WSA 13 causes, or Factories Act.';
  }

  /// Demo analysis when Gemini is unavailable (web fallback or no API key).
  /// Returns realistic-looking sample output so the UI can be tested.
  static Map<String, dynamic> demoAnalysis() {
    return {
      'overallRisk': 'HIGH',
      'riskScore': 72,
      'confidence': 0,
      'summary': 'AI analysis not available (no API key or offline). This is a demo response. To get real hazard analysis, add your Gemini API key in lib/services/gemini_vision.dart and ensure internet connectivity.',
      'hazards': [
        {
          'name': 'Sample hazard for demo',
          'description': 'This is a placeholder. Real analysis requires Gemini API.',
          'severity': 'MEDIUM',
          'type': 'Unsafe condition',
          'regulation': 'Factories Act §35',
          'correctiveAction': 'Configure Gemini API key for real AI analysis',
        },
      ],
      'preventive': ['Add Gemini API key', 'Ensure internet connection', 'Try again with real photo'],
      '_source': 'demo_fallback',
    };
  }
}
