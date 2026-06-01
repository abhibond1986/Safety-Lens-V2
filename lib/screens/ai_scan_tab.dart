import 'dart:io' show File;
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb, Uint8List;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../main.dart';
import '../services/gemini_vision.dart';
import '../services/local_ai.dart';
import '../services/local_db.dart';
import '../services/pdf_export.dart';

class AIScanTab extends StatefulWidget {
  const AIScanTab({super.key});

  @override
  State<AIScanTab> createState() => _AIScanTabState();
}

class _AIScanTabState extends State<AIScanTab> {
  XFile? _pickedFile;
  Uint8List? _imageBytes;
  bool _analyzing = false;
  Map<String, dynamic>? _result;
  String _step = '';

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
  source: source,
  imageQuality: 25,
  maxWidth: 600,
  maxHeight: 600,
);
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
    final steps = ['Image uploaded', 'Analyzing hazards...', 'Mapping IS 14489 standards...', 'Building report...'];
    for (var i = 0; i < steps.length - 1; i++) {
      setState(() => _step = steps[i]);
      await Future.delayed(const Duration(milliseconds: 700));
    }
    try {
      setState(() => _step = steps.last);
      Map<String, dynamic>? result;
      try {
        if (kIsWeb) {
          result = await GeminiVision.analyseImageBytes(_imageBytes!);
        } else {
          result = await GeminiVision.analyseImage(File(_pickedFile!.path));
        }
      } catch (e) {
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
    final firstHazard = hazards.isNotEmpty ? hazards.first['name'] : 'AI scan';
    final user = await LocalDB.getCurrentUser();
    final incident = {
      'id': DateTime.now().millisecondsSinceEpoch.toString(),
      'title': firstHazard.toString(),
      'plant': user?['plant']?.toString() ?? 'Unknown',
      'severity': _result!['overallRisk'] ?? 'MEDIUM',
      'wsaCategory': 'Other',
      'desc': _result!['summary']?.toString() ?? '',
      'type': 'AI_SCAN',
      'status': 'OPEN',
      'hazards': jsonEncode(hazards),
      'imageBase64': _imageBytes != null ? base64Encode(_imageBytes!) : null,
      'date': DateTime.now().toIso8601String(),
      'reportedBy': user?['name'] ?? 'Unknown',
    };
    await LocalDB.saveIncident(incident);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Saved to Reports'), backgroundColor: AppColors.green),
      );
    }
  }

  Future<void> _exportPdf() async {
    if (_result == null) return;
    final hazards = (_result!['hazards'] as List?) ?? [];
    final firstHazard = hazards.isNotEmpty ? hazards.first['name'] : 'AI Hazard Scan';
    final user = await LocalDB.getCurrentUser();

    // Build description with all hazards
    final descBuf = StringBuffer();
    descBuf.writeln('Summary: ${_result!['summary']?.toString() ?? ''}');
    descBuf.writeln('\nOverall Risk: ${_result!['overallRisk']} (Score: ${_result!['riskScore']}/100)');
    descBuf.writeln('Confidence: ${_result!['confidence']}%');
    descBuf.writeln('\n=== HAZARDS IDENTIFIED ===');
    for (var i = 0; i < hazards.length; i++) {
      final h = Map<String, dynamic>.from(hazards[i]);
      descBuf.writeln('\n${i + 1}. ${h['name']} [${h['severity']}]');
      descBuf.writeln('   Description: ${h['description']}');
      descBuf.writeln('   Regulation: ${h['regulation']}');
      descBuf.writeln('   Action: ${h['correctiveAction']}');
    }
    // Preventive measures
    final preventives = (_result!['preventive'] as List?) ?? [];
    if (preventives.isNotEmpty) {
      descBuf.writeln('\n=== PREVENTIVE MEASURES ===');
      for (var i = 0; i < preventives.length; i++) {
        descBuf.writeln('${i + 1}. ${preventives[i]}');
      }
    }

    final firstHazardMap = hazards.isNotEmpty ? Map<String, dynamic>.from(hazards.first) : <String, dynamic>{};

    final incident = {
      'id': DateTime.now().millisecondsSinceEpoch.toString(),
      'title': 'AI Hazard Scan: ${firstHazard.toString()}',
      'plant': user?['plant']?.toString() ?? 'Unknown',
      'dept': user?['department']?.toString() ?? '',
      'location': 'AI scan result',
      'severity': _result!['overallRisk'] ?? 'MEDIUM',
      'wsaCategory': firstHazardMap['wsaCause']?.toString() ?? 'Multiple causes',
      'desc': descBuf.toString(),
      'immediateAction': firstHazardMap['correctiveAction']?.toString() ?? 'See full report',
      'type': 'AI_SCAN',
      'status': 'OPEN',
      'date': DateTime.now().toIso8601String(),
      'reportedBy': user?['name'] ?? 'SAIL Safety Officer',
    };

    try {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Generating PDF...'), duration: Duration(seconds: 1)),
      );
      await PdfExport.downloadOrShareIncident(
        incident: incident,
        reporterName: user?['name']?.toString() ?? 'SAIL Safety Officer',
        reporterPno: user?['pno']?.toString() ?? '',
        imageBytes: _imageBytes,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(kIsWeb ? 'PDF downloaded' : 'PDF ready to share'),
            backgroundColor: AppColors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF failed: $e'), backgroundColor: AppColors.red),
        );
      }
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
      child: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          const Text('AI Hazard Scan',
            style: TextStyle(color: AppColors.text1, fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          const Text('Upload a workplace photo for instant IS 14489 hazard analysis',
            style: TextStyle(color: AppColors.text3, fontSize: 11)),
          const SizedBox(height: 16),

          if (_pickedFile == null && !_analyzing) _pickerView(),
          if (_analyzing) _analyzingView(),
          if (_result != null && !_analyzing) _resultView(),
        ],
      ),
    );
  }

  Widget _pickerView() => Column(children: [
    Container(
      height: 160,
      decoration: BoxDecoration(
        color: AppColors.card2,
        border: Border.all(color: AppColors.border, style: BorderStyle.solid, width: 1.5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Center(child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.add_a_photo_outlined, size: 36, color: AppColors.text4),
          SizedBox(height: 8),
          Text('Upload or capture a workplace photo',
            style: TextStyle(color: AppColors.text3, fontSize: 12)),
          SizedBox(height: 4),
          Text('AI will identify hazards per IS 14489',
            style: TextStyle(color: AppColors.text4, fontSize: 10)),
        ],
      )),
    ),
    const SizedBox(height: 12),
    Row(children: [
      Expanded(child: ElevatedButton.icon(
        onPressed: () => _pickImage(ImageSource.camera),
        icon: const Icon(Icons.camera_alt, color: Colors.white, size: 16),
        label: const Text('Camera', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.accent,
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
      )),
      const SizedBox(width: 8),
      Expanded(child: OutlinedButton.icon(
        onPressed: () => _pickImage(ImageSource.gallery),
        icon: const Icon(Icons.photo_library, color: AppColors.accent, size: 16),
        label: const Text('Gallery', style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w600)),
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: AppColors.accent, width: 2),
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
      )),
    ]),
  ]);

  Widget _analyzingView() {
    DecorationImage? bgImage;
    if (_imageBytes != null) {
      bgImage = DecorationImage(image: MemoryImage(_imageBytes!), fit: BoxFit.cover);
    }
    return Container(
      height: 180,
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
              const CircularProgressIndicator(strokeWidth: 3, color: AppColors.accent),
              const SizedBox(height: 10),
              Text(_step, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _resultView() {
    final hazards = (_result!['hazards'] as List?) ?? [];
    final risk = _result!['overallRisk']?.toString() ?? 'MEDIUM';
    final score = _result!['riskScore'] ?? 50;
    Color riskColor;
    switch (risk) {
      case 'CRITICAL': riskColor = AppColors.crit; break;
      case 'HIGH': riskColor = AppColors.red; break;
      case 'MEDIUM': riskColor = AppColors.cyan; break;
      default: riskColor = AppColors.green;
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (_imageBytes != null)
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.memory(_imageBytes!, height: 160, width: double.infinity, fit: BoxFit.cover),
        ),
      const SizedBox(height: 12),
      // Risk summary card
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: riskColor.withOpacity(0.08),
          border: Border.all(color: riskColor, width: 2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(children: [
          Container(
            width: 70, height: 70,
            decoration: BoxDecoration(
              color: riskColor.withOpacity(0.2),
              shape: BoxShape.circle,
              border: Border.all(color: riskColor, width: 3),
            ),
            child: Center(child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('$score', style: TextStyle(color: riskColor, fontSize: 22, fontWeight: FontWeight.w700)),
                Text('/100', style: TextStyle(color: riskColor, fontSize: 9)),
              ],
            )),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('OVERALL RISK',
                style: TextStyle(color: AppColors.text4, fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 0.6)),
              Text(risk, style: TextStyle(color: riskColor, fontSize: 20, fontWeight: FontWeight.w700)),
              Text('${hazards.length} hazards · ${_result!['confidence']}% confidence',
                style: const TextStyle(color: AppColors.text3, fontSize: 10)),
            ],
          )),
        ]),
      ),
      const SizedBox(height: 12),
      // Summary
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('SUMMARY',
            style: TextStyle(color: AppColors.text4, fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 0.6)),
          const SizedBox(height: 4),
          Text(_result!['summary']?.toString() ?? '',
            style: const TextStyle(color: AppColors.text1, fontSize: 11, height: 1.5)),
        ]),
      ),
      const SizedBox(height: 12),
      // Hazards table
      Container(
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: const BoxDecoration(
              color: AppColors.card2,
              borderRadius: BorderRadius.vertical(top: Radius.circular(10)),
            ),
            child: const Row(children: [
              Expanded(flex: 4, child: Text('HAZARD', style: TextStyle(color: AppColors.text3, fontSize: 8, fontWeight: FontWeight.w700))),
              Expanded(flex: 3, child: Text('REGULATION', style: TextStyle(color: AppColors.text3, fontSize: 8, fontWeight: FontWeight.w700))),
              Expanded(flex: 2, child: Text('SEVERITY', style: TextStyle(color: AppColors.text3, fontSize: 8, fontWeight: FontWeight.w700))),
              Expanded(flex: 4, child: Text('ACTION', style: TextStyle(color: AppColors.text3, fontSize: 8, fontWeight: FontWeight.w700))),
            ]),
          ),
          ...hazards.map((h) {
            final hm = Map<String, dynamic>.from(h as Map);
            final sev = hm['severity']?.toString() ?? 'MEDIUM';
            Color sevColor;
            switch (sev) {
              case 'CRITICAL': sevColor = AppColors.crit; break;
              case 'HIGH': sevColor = AppColors.red; break;
              case 'MEDIUM': sevColor = AppColors.cyan; break;
              default: sevColor = AppColors.green;
            }
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.border, width: 0.5)),
              ),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(flex: 4, child: Text(hm['name']?.toString() ?? '',
                  style: const TextStyle(color: AppColors.text1, fontSize: 9, fontWeight: FontWeight.w600))),
                Expanded(flex: 3, child: Text(hm['regulation']?.toString() ?? '',
                  style: const TextStyle(color: AppColors.text2, fontSize: 8))),
                Expanded(flex: 2, child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  decoration: BoxDecoration(
                    color: sevColor.withOpacity(0.2),
                    border: Border.all(color: sevColor),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(sev.substring(0, sev.length > 4 ? 4 : sev.length),
                    style: TextStyle(color: sevColor, fontSize: 7, fontWeight: FontWeight.w700),
                    textAlign: TextAlign.center),
                )),
                Expanded(flex: 4, child: Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Text(hm['correctiveAction']?.toString() ?? '',
                    style: const TextStyle(color: AppColors.text2, fontSize: 8, height: 1.3)),
                )),
              ]),
            );
          }).toList(),
        ]),
      ),
      const SizedBox(height: 14),
      // ACTION BUTTONS
      Row(children: [
        Expanded(child: ElevatedButton.icon(
          onPressed: _save,
          icon: const Icon(Icons.save, color: Colors.white, size: 14),
          label: const Text('Save', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.green,
            padding: const EdgeInsets.symmetric(vertical: 12),
          ),
        )),
        const SizedBox(width: 6),
        Expanded(child: ElevatedButton.icon(
          onPressed: _exportPdf,
          icon: const Icon(Icons.picture_as_pdf, color: Colors.white, size: 14),
          label: Text(kIsWeb ? 'PDF' : 'Share PDF',
            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.accent,
            padding: const EdgeInsets.symmetric(vertical: 12),
          ),
        )),
        const SizedBox(width: 6),
        Expanded(child: OutlinedButton.icon(
          onPressed: _reset,
          icon: const Icon(Icons.refresh, color: AppColors.accent, size: 14),
          label: const Text('New', style: TextStyle(color: AppColors.accent, fontSize: 11, fontWeight: FontWeight.w600)),
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: AppColors.accent, width: 1.5),
            padding: const EdgeInsets.symmetric(vertical: 12),
          ),
        )),
      ]),
    ]);
  }
}
