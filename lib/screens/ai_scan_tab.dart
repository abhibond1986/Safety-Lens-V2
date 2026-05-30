import 'dart:io' show File;
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb, Uint8List;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../main.dart';
import '../services/gemini_vision.dart';
import '../services/local_ai.dart';
import '../services/local_db.dart';
import '../services/sync_service.dart';
import '../services/sync_service.dart';
class AIScanTab extends StatefulWidget {
  const AIScanTab({super.key});

  @override
  State<AIScanTab> createState() => _AIScanTabState();
}

class _AIScanTabState extends State<AIScanTab> {
  XFile? _pickedFile;
  Uint8List? _imageBytes; // For web display
  bool _analyzing = false;
  Map<String, dynamic>? _result;
  String _step = '';

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: source, imageQuality: 85);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    setState(() {
      _pickedFile = picked;
      _imageBytes = bytes;
      _analyzing = true;
      _result = null;
    });
    await _analyze();
  }

  Future<void> _analyze() async {
    final steps = ['Image uploaded', 'Sending to Gemini Vision...', 'Analyzing hazards...', 'Mapping IS 14489 standards...', 'Building report...'];
    for (var i = 0; i < steps.length - 1; i++) {
      setState(() => _step = steps[i]);
      await Future.delayed(const Duration(milliseconds: 700));
    }
    try {
      setState(() => _step = steps.last);
      Map<String, dynamic>? result;
      try {
        if (kIsWeb) {
          // On web, use bytes
          result = await GeminiVision.analyseImageBytes(_imageBytes!);
        } else {
          result = await GeminiVision.analyseImage(File(_pickedFile!.path));
        }
      } catch (e) {
        // Fallback to offline
        if (kIsWeb) {
          result = LocalAI.demoAnalysis();
        } else {
          result = await LocalAI.analyseImage(File(_pickedFile!.path));
        }
      }
      if (mounted) {
        setState(() {
          _result = result;
          _analyzing = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _analyzing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Analysis failed: $e'), backgroundColor: AppColors.red),
        );
      }
    }
  }

  Future<void> _save() async {
  if (_result == null) return;

  final hazards = (_result!['hazards'] as List?) ?? [];
  final firstHazard =
      hazards.isNotEmpty ? hazards.first['name'] : 'AI scan';

  final incident = {
    'title': firstHazard.toString(),
    'plant': 'Unknown',
    'severity': _result!['overallRisk'] ?? 'MEDIUM',
    'wsaCategory': 'Other',
    'desc': _result!['summary']?.toString() ?? '',
    'type': 'AI_SCAN',
    'status': 'OPEN',
    'hazards': jsonEncode(hazards),
  };

  // Save locally
  await LocalDB.saveIncident(incident);

  // Send to Google Sheets
  try {
    final ok = await SyncService.pushIncident(incident);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? 'Saved to Reports & Google Sheet'
                : 'Saved locally. Google Sheet sync pending.',
          ),
          backgroundColor: ok ? AppColors.green : AppColors.amber,
        ),
      );
    }
  } catch (e) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Saved locally. Google Sheet sync failed.'),
          backgroundColor: AppColors.amber,
      ),
    );
  }
}
      );
    }
  }

  void _reset() {
    setState(() {
      _pickedFile = null;
      _imageBytes = null;
      _result = null;
      _analyzing = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          _topBar(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 80),
              child: _analyzing
                  ? _analyzingView()
                  : _result != null
                      ? _resultView()
                      : _emptyView(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _topBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: const BoxDecoration(
        color: AppColors.bg2,
        border: Border(bottom: BorderSide(color: AppColors.border, width: 0.5)),
      ),
      child: const Row(
        children: [
          Expanded(child: Text('AI Hazard Scan',
            style: TextStyle(color: AppColors.text1, fontSize: 15, fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }

  Widget _emptyView() {
    return Column(
      children: [
        GestureDetector(
          onTap: () => _pickImage(ImageSource.camera),
          child: Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.border, width: 2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Column(
              children: [
                Icon(Icons.add_a_photo_outlined, size: 44, color: AppColors.accent),
                SizedBox(height: 10),
                Text('Capture workplace photo',
                  style: TextStyle(color: AppColors.text1, fontSize: 13, fontWeight: FontWeight.w600)),
                SizedBox(height: 4),
                Text('Real camera/gallery picker',
                  style: TextStyle(color: AppColors.text3, fontSize: 10)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _bigBtn(Icons.camera_alt, 'Camera', () => _pickImage(ImageSource.camera))),
          const SizedBox(width: 8),
          Expanded(child: _outlineBtn(Icons.photo_library, 'Gallery', () => _pickImage(ImageSource.gallery))),
        ]),
        const SizedBox(height: 14),
        _infoBox(),
      ],
    );
  }

  Widget _analyzingView() {
    DecorationImage? bgImage;
    if (_imageBytes != null) {
      bgImage = DecorationImage(image: MemoryImage(_imageBytes!), fit: BoxFit.cover);
    }
    return Container(
      height: 160,
      decoration: BoxDecoration(
        color: AppColors.card2,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(10),
        image: bgImage,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.5),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(strokeWidth: 3, valueColor: AlwaysStoppedAnimation<Color>(AppColors.accent)),
              const SizedBox(height: 10),
              Text(_step, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _resultView() {
    final overallRisk = _result!['overallRisk']?.toString() ?? 'MEDIUM';
    final score = _result!['riskScore'] ?? 50;
    final confidence = _result!['confidence'] ?? 75;
    final summary = _result!['summary']?.toString() ?? '';
    final hazards = (_result!['hazards'] as List?) ?? [];
    final riskColor = _severityColor(overallRisk);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_imageBytes != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.memory(_imageBytes!, height: 160, width: double.infinity, fit: BoxFit.cover),
          ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: riskColor.withOpacity(0.08),
            border: Border.all(color: riskColor, width: 2),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Container(
                width: 70, height: 70,
                decoration: BoxDecoration(
                  color: riskColor.withOpacity(0.25),
                  shape: BoxShape.circle,
                  border: Border.all(color: riskColor, width: 3),
                ),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('$score', style: TextStyle(color: riskColor, fontSize: 22, fontWeight: FontWeight.w700)),
                      Text('/100', style: TextStyle(color: riskColor, fontSize: 8)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('OVERALL RISK',
                      style: TextStyle(color: AppColors.text4, fontSize: 9, fontWeight: FontWeight.w600)),
                    Text(overallRisk,
                      style: TextStyle(color: riskColor, fontSize: 18, fontWeight: FontWeight.w700)),
                    Text('${hazards.length} hazards · $confidence% confidence',
                      style: const TextStyle(color: AppColors.text3, fontSize: 10)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.card,
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('SUMMARY',
                style: TextStyle(color: AppColors.text4, fontSize: 9, fontWeight: FontWeight.w600, letterSpacing: 0.9)),
              const SizedBox(height: 6),
              Text(summary, style: const TextStyle(color: AppColors.text2, fontSize: 11, height: 1.5)),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _hazardTable(hazards),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: ElevatedButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save_outlined, size: 14, color: Colors.white),
            label: const Text('Save', style: TextStyle(color: Colors.white, fontSize: 12)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.green,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          )),
          const SizedBox(width: 8),
          Expanded(child: OutlinedButton.icon(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('PDF export from Reports tab')),
              );
            },
            icon: const Icon(Icons.picture_as_pdf, size: 14, color: AppColors.accent),
            label: const Text('PDF', style: TextStyle(color: AppColors.accent, fontSize: 12)),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: AppColors.accent, width: 2),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          )),
        ]),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _reset,
          icon: const Icon(Icons.refresh, size: 14, color: AppColors.accent),
          label: const Text('Scan another', style: TextStyle(color: AppColors.accent)),
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: AppColors.accent, width: 2),
            padding: const EdgeInsets.symmetric(vertical: 12),
            minimumSize: const Size(double.infinity, 0),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      ],
    );
  }

  Widget _hazardTable(List hazards) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 12, 12, 6),
            child: Row(
              children: [
                Icon(Icons.table_view_outlined, size: 14, color: AppColors.red),
                SizedBox(width: 6),
                Text('HAZARD ANALYSIS',
                  style: TextStyle(color: AppColors.text4, fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 0.9)),
              ],
            ),
          ),
          Table(
            border: const TableBorder(
              horizontalInside: BorderSide(color: AppColors.border, width: 0.5),
            ),
            columnWidths: const {
              0: FlexColumnWidth(2.5),
              1: FlexColumnWidth(2.2),
              2: FlexColumnWidth(1.4),
              3: FlexColumnWidth(3),
            },
            children: [
              TableRow(
                decoration: const BoxDecoration(color: AppColors.card2),
                children: [
                  _hth('HAZARD'),
                  _hth('SECTION'),
                  _hth('CRITICALITY', center: true),
                  _hth('RECOMMENDATION'),
                ],
              ),
              ...hazards.map((h) {
                final hMap = Map<String, dynamic>.from(h as Map);
                final sev = (hMap['severity'] ?? 'MEDIUM').toString();
                final sevColor = _severityColor(sev);
                return TableRow(children: [
                  _htd(hMap['name']?.toString() ?? '',
                      sub: hMap['type']?.toString() ?? 'Unsafe condition'),
                  _htd(hMap['regulation']?.toString() ?? ''),
                  Padding(padding: const EdgeInsets.all(7), child: Center(child: _sevPill(sev, sevColor))),
                  _htd(hMap['correctiveAction']?.toString() ?? ''),
                ]);
              }).toList(),
            ],
          ),
        ],
      ),
    );
  }

  Widget _hth(String text, {bool center = false}) => Padding(
    padding: const EdgeInsets.all(7),
    child: Text(text,
      textAlign: center ? TextAlign.center : TextAlign.left,
      style: const TextStyle(color: AppColors.text3, fontSize: 8, fontWeight: FontWeight.w700, letterSpacing: 0.4)),
  );

  Widget _htd(String text, {String? sub}) => Padding(
    padding: const EdgeInsets.all(7),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(text,
          style: const TextStyle(color: AppColors.text1, fontSize: 9.5, fontWeight: FontWeight.w600, height: 1.4)),
        if (sub != null) Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(sub, style: const TextStyle(color: AppColors.text4, fontSize: 8)),
        ),
      ],
    ),
  );

  Widget _sevPill(String sev, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: color.withOpacity(0.2),
      border: Border.all(color: color),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(sev.substring(0, sev.length > 4 ? 4 : sev.length),
      style: TextStyle(color: color, fontSize: 8, fontWeight: FontWeight.w700)),
  );

  Color _severityColor(String sev) {
    switch (sev.toUpperCase()) {
      case 'CRITICAL': return AppColors.crit;
      case 'HIGH': return AppColors.red;
      case 'MEDIUM': return AppColors.cyan;
      case 'LOW': return AppColors.green;
      default: return AppColors.amber;
    }
  }

  Widget _bigBtn(IconData icon, String label, VoidCallback onTap) => ElevatedButton.icon(
    onPressed: onTap,
    icon: Icon(icon, size: 14, color: Colors.white),
    label: Text(label, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
    style: ElevatedButton.styleFrom(
      backgroundColor: AppColors.accent,
      padding: const EdgeInsets.symmetric(vertical: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: const BorderSide(color: AppColors.accentDark, width: 2)),
    ),
  );

  Widget _outlineBtn(IconData icon, String label, VoidCallback onTap) => OutlinedButton.icon(
    onPressed: onTap,
    icon: Icon(icon, size: 14, color: AppColors.accent),
    label: Text(label, style: const TextStyle(color: AppColors.accent, fontSize: 12, fontWeight: FontWeight.w600)),
    style: OutlinedButton.styleFrom(
      side: const BorderSide(color: AppColors.accent, width: 2),
      padding: const EdgeInsets.symmetric(vertical: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
  );

  Widget _infoBox() => Container(
    padding: const EdgeInsets.all(11),
    decoration: BoxDecoration(
      color: AppColors.accent.withOpacity(0.08),
      border: Border.all(color: AppColors.accent),
      borderRadius: BorderRadius.circular(11),
    ),
    child: const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Icon(Icons.table_chart_outlined, size: 13, color: AppColors.accent),
          SizedBox(width: 6),
          Text('Single-view 4-column report',
            style: TextStyle(color: AppColors.text1, fontSize: 11, fontWeight: FontWeight.w600)),
        ]),
        SizedBox(height: 4),
        Text('Hazard → Section → Criticality → Recommendation. All visible at once.',
          style: TextStyle(color: AppColors.text2, fontSize: 10, height: 1.5)),
      ],
    ),
  );
}
