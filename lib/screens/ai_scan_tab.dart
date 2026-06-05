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
import '../services/pdf_export.dart';
import '../widgets/hazard_annotated_image.dart';

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

  // Scroll + row highlight for bbox tap → table sync
  final ScrollController _scrollController = ScrollController();
  final List<GlobalKey> _hazardRowKeys = [];
  int? _highlightedRow;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _buildHazardKeys(int count) {
    _hazardRowKeys.clear();
    for (int i = 0; i < count; i++) {
      _hazardRowKeys.add(GlobalKey());
    }
  }

  void _onBboxTap(int index) {
    setState(() => _highlightedRow = index == _highlightedRow ? null : index);
    if (index >= _hazardRowKeys.length) return;
    final ctx = _hazardRowKeys[index].currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(ctx,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeInOut,
        alignment: 0.1);
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: source, imageQuality: 20, maxWidth: 500, maxHeight: 500);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    setState(() {
      _pickedFile = picked;
      _imageBytes = bytes;
      _analyzing = true;
      _result = null;
      _hazardRowKeys.clear();
      _highlightedRow = null;
    });
    await _analyze();
  }

  Future<void> _analyze() async {
    final steps = ['Image uploaded', 'Sending to AI...', 'Analyzing hazards...',
                   'Mapping IS 14489...', 'Building report...'];
    for (var i = 0; i < steps.length - 1; i++) {
      setState(() => _step = steps[i]);
      await Future.delayed(const Duration(milliseconds: 700));
    }
    try {
      setState(() => _step = steps.last);
      Map<String, dynamic>? result;
      try {
        result = kIsWeb
            ? await GeminiVision.analyseImageBytes(_imageBytes!)
            : await GeminiVision.analyseImage(File(_pickedFile!.path));
      } catch (e) {
        result = kIsWeb
            ? LocalAI.demoAnalysis()
            : await LocalAI.analyseImage(File(_pickedFile!.path));
      }
      if (mounted) {
        final hazards = (result?['hazards'] as List?) ?? [];
        _buildHazardKeys(hazards.length);
        setState(() { _result = result; _analyzing = false; });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _analyzing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Analysis failed: $e'),
            backgroundColor: AppColors.red));
      }
    }
  }

  Map<String, dynamic> _buildIncident(Map<String, dynamic> user) {
    final hazards = (_result!['hazards'] as List?) ?? [];
    final firstHazard = hazards.isNotEmpty ? hazards.first['name'] : 'AI Hazard Scan';
    final firstHazardMap = hazards.isNotEmpty
        ? Map<String, dynamic>.from(hazards.first as Map)
        : <String, dynamic>{};
    return {
      'id': DateTime.now().millisecondsSinceEpoch.toString(),
      'title': 'AI Hazard Scan: ${firstHazard.toString()}',
      'plant': user['plant']?.toString() ?? 'SAIL Safety Organisation',
      'dept': user['department']?.toString() ?? '',
      'location': 'AI scan result',
      'severity': _result!['overallRisk'] ?? 'MEDIUM',
      'wsaCategory': firstHazardMap['wsaCause']?.toString() ?? 'Multiple causes',
      'obsType': 'N/A',
      'summary': _result!['summary']?.toString() ?? '',
      'desc': _result!['summary']?.toString() ?? '',
      'immediateAction': firstHazardMap['correctiveAction']?.toString()
          ?? 'Investigate per IS 14489:1998',
      'type': 'AI_SCAN',
      'status': 'OPEN',
      'date': DateTime.now().toIso8601String(),
      'reportedBy': user['name']?.toString() ?? 'SAIL Safety Officer',
      'reportedByPno': user['pno']?.toString() ?? '',
      'people': '0',
      'hazards': hazards,
      'riskScore': _result!['riskScore'] ?? 0,
      'confidence': _result!['confidence'] ?? 0,
      'imageBase64': _imageBytes != null ? base64Encode(_imageBytes!) : null,
    };
  }

  Future<void> _save() async {
    if (_result == null) return;
    final user = await LocalDB.getCurrentUser() ?? {};
    final incident = _buildIncident(user);
    final dbIncident = Map<String, dynamic>.from(incident);
    dbIncident['hazards'] = jsonEncode(incident['hazards']);
    await LocalDB.saveIncident(dbIncident);
    SyncService.pushIncident(dbIncident).catchError((_) => false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Saved to Reports'),
          backgroundColor: AppColors.green));
    }
  }

  Future<void> _exportPdf() async {
    if (_result == null) return;
    final user = await LocalDB.getCurrentUser() ?? {};
    final incident = _buildIncident(user);
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Generating PDF...'),
          duration: Duration(seconds: 1)));
      await PdfExport.downloadOrShareIncident(
        incident: incident,
        reporterName: user['name']?.toString() ?? 'SAIL Safety Officer',
        reporterPno: user['pno']?.toString() ?? '',
        imageBytes: _imageBytes,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(kIsWeb ? 'PDF downloaded' : 'PDF ready to share'),
            backgroundColor: AppColors.green));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF failed: $e'),
            backgroundColor: AppColors.red));
      }
    }
  }

  void _reset() => setState(() {
    _pickedFile = null; _imageBytes = null;
    _result = null; _analyzing = false;
    _hazardRowKeys.clear(); _highlightedRow = null;
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(children: [
        _topBar(),
        Expanded(child: SingleChildScrollView(
          controller: _scrollController,
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 80),
          child: _analyzing ? _analyzingView()
              : _result != null ? _resultView()
              : _emptyView(),
        )),
      ]),
    );
  }

  Widget _topBar() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: AppColors.bg2,
      border: Border(bottom: BorderSide(
        color: AppColors.border, width: 0.5))),
    child: Row(children: [
      Expanded(child: Text('AI Hazard Scan',
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurface,
          fontSize: 16, fontWeight: FontWeight.w700))),
    ]));

  Widget _emptyView() => Column(children: [
    GestureDetector(
      onTap: () => _pickImage(ImageSource.camera),
      child: Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border.all(color: Theme.of(context).dividerColor, width: 2),
          borderRadius: BorderRadius.circular(12)),
        child: Column(children: [
          const Icon(Icons.add_a_photo_outlined, size: 44, color: AppColors.accent),
          const SizedBox(height: 10),
          const Text('Capture workplace photo',
            style: TextStyle(color: AppColors.text1, fontSize: 13,
              fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          const Text('AI identifies hazards + marks them on photo',
            style: TextStyle(color: AppColors.text3, fontSize: 10)),
        ]),
      ),
    ),
    const SizedBox(height: 12),
    Row(children: [
      Expanded(child: _bigBtn(Icons.camera_alt, 'Camera',
        () => _pickImage(ImageSource.camera))),
      const SizedBox(width: 8),
      Expanded(child: _outlineBtn(Icons.photo_library, 'Gallery',
        () => _pickImage(ImageSource.gallery))),
    ]),
    const SizedBox(height: 14),
    _infoBox(),
  ]);

  Widget _analyzingView() {
    DecorationImage? bgImage;
    if (_imageBytes != null) {
      bgImage = DecorationImage(
        image: MemoryImage(_imageBytes!), fit: BoxFit.cover);
    }
    return Container(
      height: 160,
      decoration: BoxDecoration(
        color: AppColors.card2,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(10),
        image: bgImage),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.5),
          borderRadius: BorderRadius.circular(10)),
        child: Center(child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(strokeWidth: 3,
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.accent)),
            const SizedBox(height: 10),
            Text(_step, style: const TextStyle(
              color: Colors.white, fontSize: 12,
              fontWeight: FontWeight.w600)),
          ],
        )),
      ),
    );
  }

  Widget _resultView() {
    final overallRisk = _result!['overallRisk']?.toString() ?? 'MEDIUM';
    final score      = _result!['riskScore'] ?? 50;
    final confidence = _result!['confidence'] ?? 75;
    final summary    = _result!['summary']?.toString() ?? '';
    final hazards    = (_result!['hazards'] as List?) ?? [];
    final riskColor  = _severityColor(overallRisk);

    // Check if any hazard has bbox data
    final hasBbox = hazards.any((h) =>
      (h as Map)['bbox'] != null);

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [

      // ── Annotated image (with bounding boxes) ─────────────────────────
      if (_imageBytes != null) ...[
        if (hasBbox)
          HazardAnnotatedImage(
            imageBytes: _imageBytes!,
            hazards: hazards,
            onHazardTap: _onBboxTap,
          )
        else
          // Fallback: plain image if Gemini didn't return bbox
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.memory(_imageBytes!,
              height: 200, width: double.infinity, fit: BoxFit.cover)),
        const SizedBox(height: 12),
      ],

      // ── Risk summary card ──────────────────────────────────────────────
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: riskColor.withOpacity(0.08),
          border: Border.all(color: riskColor, width: 2),
          borderRadius: BorderRadius.circular(14)),
        child: Row(children: [
          Container(
            width: 70, height: 70,
            decoration: BoxDecoration(
              color: riskColor.withOpacity(0.25),
              shape: BoxShape.circle,
              border: Border.all(color: riskColor, width: 3)),
            child: Center(child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('$score', style: TextStyle(
                  color: riskColor, fontSize: 22,
                  fontWeight: FontWeight.w700)),
                Text('/100', style: TextStyle(
                  color: riskColor, fontSize: 8)),
              ],
            )),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('OVERALL RISK', style: TextStyle(
                color: AppColors.text4, fontSize: 9,
                fontWeight: FontWeight.w600)),
              Text(overallRisk, style: TextStyle(
                color: riskColor, fontSize: 18,
                fontWeight: FontWeight.w700)),
              Text('${hazards.length} hazards · $confidence% confidence',
                style: const TextStyle(
                  color: AppColors.text3, fontSize: 10)),
              if (hasBbox)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Row(children: [
                    Icon(Icons.touch_app_outlined,
                      size: 10, color: AppColors.accent),
                    SizedBox(width: 4),
                    Text('Tap boxes on image to jump to hazard',
                      style: TextStyle(
                        color: AppColors.accent,
                        fontSize: 9,
                        fontStyle: FontStyle.italic)),
                  ]),
                ),
            ],
          )),
        ]),
      ),
      const SizedBox(height: 12),

      // ── Summary ────────────────────────────────────────────────────────
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.card,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('SUMMARY', style: TextStyle(
            color: AppColors.text4, fontSize: 9,
            fontWeight: FontWeight.w600, letterSpacing: 0.9)),
          const SizedBox(height: 6),
          Text(summary, style: const TextStyle(
            color: AppColors.text2, fontSize: 11, height: 1.5)),
        ]),
      ),
      const SizedBox(height: 12),

      // ── Hazard table ───────────────────────────────────────────────────
      _hazardTable(hazards),
      const SizedBox(height: 12),

      // ── Action buttons ─────────────────────────────────────────────────
      Row(children: [
        Expanded(child: ElevatedButton.icon(
          onPressed: _save,
          icon: const Icon(Icons.save_outlined, size: 14, color: Colors.white),
          label: const Text('Save',
            style: TextStyle(color: Colors.white, fontSize: 12)),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.green,
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10))),
        )),
        const SizedBox(width: 8),
        Expanded(child: ElevatedButton.icon(
          onPressed: _exportPdf,
          icon: const Icon(Icons.picture_as_pdf, size: 14, color: Colors.white),
          label: const Text('PDF',
            style: TextStyle(color: Colors.white, fontSize: 12)),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.accent,
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10))),
        )),
        const SizedBox(width: 8),
        Expanded(child: OutlinedButton.icon(
          onPressed: _reset,
          icon: const Icon(Icons.refresh, size: 14, color: AppColors.accent),
          label: const Text('New',
            style: TextStyle(color: AppColors.accent, fontSize: 12)),
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: AppColors.accent, width: 2),
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10))),
        )),
      ]),
    ]);
  }

  Widget _hazardTable(List hazards) => Container(
    decoration: BoxDecoration(
      color: AppColors.card,
      border: Border.all(color: AppColors.border),
      borderRadius: BorderRadius.circular(12)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Padding(
        padding: EdgeInsets.fromLTRB(12, 12, 12, 6),
        child: Row(children: [
          Icon(Icons.table_view_outlined, size: 14, color: AppColors.red),
          SizedBox(width: 6),
          Text('HAZARD ANALYSIS', style: TextStyle(
            color: AppColors.text4, fontSize: 10,
            fontWeight: FontWeight.w600, letterSpacing: 0.9)),
        ])),
      Table(
        border: const TableBorder(
          horizontalInside: BorderSide(
            color: AppColors.border, width: 0.5)),
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
              _hth('HAZARD'), _hth('REGULATION'),
              _hth('SEVERITY', center: true), _hth('ACTION'),
            ]),
          ...hazards.asMap().entries.map((entry) {
            final i  = entry.key;
            final h  = entry.value;
            final hm = Map<String, dynamic>.from(h as Map);
            final sev = (hm['severity'] ?? 'MEDIUM').toString();
            final isHighlighted = _highlightedRow == i;
            final color = _severityColor(sev);

            return TableRow(
              // Row highlight when bbox tapped
              decoration: BoxDecoration(
                color: isHighlighted
                    ? color.withOpacity(0.12)
                    : Colors.transparent),
              children: [
                // Hazard name with number badge + GlobalKey for scroll
                Padding(
                  key: i < _hazardRowKeys.length
                      ? _hazardRowKeys[i] : null,
                  padding: const EdgeInsets.all(7),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Numbered badge matching image overlay
                      Container(
                        width: 16, height: 16,
                        margin: const EdgeInsets.only(right: 5, top: 1),
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle),
                        child: Center(child: Text(
                          '${i + 1}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 8,
                            fontWeight: FontWeight.w900)))),
                      Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(hm['name']?.toString() ?? '',
                            style: const TextStyle(
                              color: AppColors.text1, fontSize: 9.5,
                              fontWeight: FontWeight.w600, height: 1.4)),
                          if (hm['type'] != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(hm['type'].toString(),
                                style: const TextStyle(
                                  color: AppColors.text4, fontSize: 8))),
                        ])),
                    ],
                  ),
                ),
                _htd(hm['regulation']?.toString() ?? ''),
                Padding(
                  padding: const EdgeInsets.all(7),
                  child: Center(child: _sevPill(sev, color))),
                _htd(hm['correctiveAction']?.toString() ?? ''),
              ]);
          }).toList(),
        ],
      ),
    ]));

  Widget _hth(String t, {bool center = false}) => Padding(
    padding: const EdgeInsets.all(7),
    child: Text(t,
      textAlign: center ? TextAlign.center : TextAlign.left,
      style: const TextStyle(color: AppColors.text3, fontSize: 8,
        fontWeight: FontWeight.w700, letterSpacing: 0.4)));

  Widget _htd(String t, {String? sub}) => Padding(
    padding: const EdgeInsets.all(7),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(t, style: const TextStyle(color: AppColors.text1,
        fontSize: 9.5, fontWeight: FontWeight.w600, height: 1.4)),
      if (sub != null) Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text(sub, style: const TextStyle(
          color: AppColors.text4, fontSize: 8))),
    ]));

  Widget _sevPill(String sev, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: color.withOpacity(0.2),
      border: Border.all(color: color),
      borderRadius: BorderRadius.circular(8)),
    child: Text(
      sev.substring(0, sev.length > 4 ? 4 : sev.length),
      style: TextStyle(
        color: color, fontSize: 8, fontWeight: FontWeight.w700)));

  Color _severityColor(String sev) {
    switch (sev.toUpperCase()) {
      case 'CRITICAL': return AppColors.crit;
      case 'HIGH':     return AppColors.red;
      case 'MEDIUM':   return AppColors.cyan;
      case 'LOW':      return AppColors.green;
      default:         return AppColors.amber;
    }
  }

  Widget _bigBtn(IconData icon, String label, VoidCallback fn) =>
    ElevatedButton.icon(
      onPressed: fn,
      icon: Icon(icon, size: 14, color: Colors.white),
      label: Text(label, style: const TextStyle(
        color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.accent,
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(
            color: AppColors.accentDark, width: 2))));

  Widget _outlineBtn(IconData icon, String label, VoidCallback fn) =>
    OutlinedButton.icon(
      onPressed: fn,
      icon: Icon(icon, size: 14, color: AppColors.accent),
      label: Text(label, style: const TextStyle(
        color: AppColors.accent, fontSize: 12,
        fontWeight: FontWeight.w600)),
      style: OutlinedButton.styleFrom(
        side: const BorderSide(color: AppColors.accent, width: 2),
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10))));

  Widget _infoBox() => Container(
    padding: const EdgeInsets.all(11),
    decoration: BoxDecoration(
      color: AppColors.accent.withOpacity(0.08),
      border: Border.all(color: AppColors.accent),
      borderRadius: BorderRadius.circular(11)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Row(children: [
        Icon(Icons.table_chart_outlined, size: 13, color: AppColors.accent),
        SizedBox(width: 6),
        Text('AI Hazard Analysis',
          style: TextStyle(color: AppColors.accent,
            fontSize: 12, fontWeight: FontWeight.w700)),
      ]),
      const SizedBox(height: 4),
      Text(
        'Hazards are marked directly on the photo with colored boxes. '
        'Tap any box to highlight its row in the table below.',
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
          fontSize: 11, height: 1.5)),
    ]));
}
