// lib/screens/ai_scan_tab.dart
// ✅ Infographic header with AI badge
// ✅ Duplicate image detection — warns before saving same image twice
// ✅ imageHash stored in incident record for cross-session detection
// ✅ All original functionality preserved

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
  XFile?     _pickedFile;
  Uint8List? _imageBytes;
  bool       _analyzing = false;
  Map<String, dynamic>? _result;
  String     _step = '';
  String?    _savedImageHash; // ← duplicate detection: tracks last saved image

  // Scroll + row highlight for bbox tap → table sync
  final ScrollController _scrollController = ScrollController();
  final List<GlobalKey>  _hazardRowKeys    = [];
  int? _highlightedRow;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  // ─── HASH HELPER ─────────────────────────────────────────────
  // Fast XOR hash of sampled bytes — not cryptographic, good enough
  // for duplicate detection across large image files
  String _computeHash(Uint8List bytes) {
    int h    = 0;
    final step = bytes.length > 1000 ? bytes.length ~/ 500 : 1;
    for (int i = 0; i < bytes.length; i += step) {
      h ^= (bytes[i] << (i % 24));
      h  = h & 0xFFFFFFFF;
    }
    return h.toRadixString(16).padLeft(8, '0');
  }

  // ─── BBOX HELPERS ─────────────────────────────────────────────
  void _buildHazardKeys(int count) {
    _hazardRowKeys.clear();
    for (int i = 0; i < count; i++) {
      _hazardRowKeys.add(GlobalKey());
    }
  }

  void _onBboxTap(int index) {
    setState(() =>
        _highlightedRow = index == _highlightedRow ? null : index);
    if (index >= _hazardRowKeys.length) return;
    final ctx = _hazardRowKeys[index].currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(ctx,
          duration: const Duration(milliseconds: 450),
          curve: Curves.easeInOut,
          alignment: 0.1);
    }
  }

  // ─── PICK IMAGE ───────────────────────────────────────────────
  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
        source: source, imageQuality: 20,
        maxWidth: 500, maxHeight: 500);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    setState(() {
      _pickedFile      = picked;
      _imageBytes      = bytes;
      _analyzing       = true;
      _result          = null;
      _hazardRowKeys.clear();
      _highlightedRow  = null;
    });
    await _analyze();
  }

  // ─── ANALYZE ─────────────────────────────────────────────────
  Future<void> _analyze() async {
    final steps = [
      'Image uploaded', 'Sending to AI…',
      'Analyzing hazards…', 'Mapping IS 14489…', 'Building report…'
    ];
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Analysis failed: $e'),
            backgroundColor: AppColors.red));
      }
    }
  }

  // ─── BUILD INCIDENT ───────────────────────────────────────────
  Map<String, dynamic> _buildIncident(Map<String, dynamic> user) {
    final hazards       = (_result!['hazards'] as List?) ?? [];
    final firstHazard   = hazards.isNotEmpty
        ? hazards.first['name'] : 'AI Hazard Scan';
    final firstHazardMap = hazards.isNotEmpty
        ? Map<String, dynamic>.from(hazards.first as Map)
        : <String, dynamic>{};
    return {
      'id':             DateTime.now().millisecondsSinceEpoch.toString(),
      'title':          'AI Hazard Scan: ${firstHazard.toString()}',
      'plant':          user['plant']?.toString() ?? 'SAIL Safety Organisation',
      'dept':           user['department']?.toString() ?? '',
      'location':       'AI scan result',
      'severity':       _result!['overallRisk'] ?? 'MEDIUM',
      'wsaCategory':    firstHazardMap['wsaCause']?.toString() ?? 'Multiple causes',
      'obsType':        'N/A',
      'summary':        _result!['summary']?.toString() ?? '',
      'desc':           _result!['summary']?.toString() ?? '',
      'immediateAction':firstHazardMap['correctiveAction']?.toString()
          ?? 'Investigate per IS 14489:1998',
      'type':           'AI_SCAN',
      'status':         'OPEN',
      'date':           DateTime.now().toIso8601String(),
      'reportedBy':     user['name']?.toString() ?? 'SAIL Safety Officer',
      'reportedByPno':  user['pno']?.toString()  ?? '',
      'people':         '0',
      'hazards':        hazards,
      'riskScore':      _result!['riskScore']    ?? 0,
      'confidence':     _result!['confidence']   ?? 0,
      'imageBase64':    _imageBytes != null
          ? base64Encode(_imageBytes!) : null,
    };
  }

  // ─── SAVE (with duplicate detection) ─────────────────────────
  Future<void> _save() async {
    if (_result == null) return;

    // ── Step 1: compute hash of current image ──
    if (_imageBytes != null) {
      final hash = _computeHash(_imageBytes!);

      // ── Step 2: same image saved in THIS session ──
      if (_savedImageHash == hash) {
        _showDuplicateSnack(
            'This image was already saved. Scan a new photo to add another report.');
        return;
      }

      // ── Step 3: check LocalDB for same hash (cross-session) ──
      final existing  = await LocalDB.getIncidents();
      final duplicate = existing.any(
          (inc) => inc['imageHash']?.toString() == hash);

      if (duplicate) {
        // Ask user — show dialog
        if (!mounted) return;
        final confirm = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            backgroundColor:
                Theme.of(context).colorScheme.surface,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
            title: const Row(children: [
              Icon(Icons.warning_amber_rounded,
                  color: Color(0xFFD97706), size: 22),
              SizedBox(width: 8),
              Text('Duplicate Image',
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700)),
            ]),
            content: const Text(
              'This image has already been saved as a report.\n\n'
              'Do you want to save it again as a new entry?',
              style: TextStyle(fontSize: 13, height: 1.5)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel',
                    style: TextStyle(color: Colors.grey))),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFD97706)),
                child: const Text('Save Anyway',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700))),
            ]));
        if (confirm != true) return;
      }
    }

    // ── Step 4: proceed with save ──
    final user     = await LocalDB.getCurrentUser() ?? {};
    final incident = _buildIncident(user);
    final dbInc    = Map<String, dynamic>.from(incident);
    dbInc['hazards'] = jsonEncode(incident['hazards']);

    // Store hash so we can detect duplicates next time
    if (_imageBytes != null) {
      final hash        = _computeHash(_imageBytes!);
      dbInc['imageHash'] = hash;
      _savedImageHash   = hash; // remember in session
    }

    await LocalDB.saveIncident(dbInc);
    SyncService.pushIncident(dbInc).catchError((_) => false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Row(children: [
          Icon(Icons.check_circle_outline,
              color: Colors.white, size: 16),
          SizedBox(width: 8),
          Expanded(child: Text(
              '✅ Saved to Reports · syncing to Google Sheets',
              style: TextStyle(fontSize: 12))),
        ]),
        backgroundColor: AppColors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(12),
      ));
    }
  }

  void _showDuplicateSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        const Icon(Icons.warning_amber_rounded,
            color: Colors.white, size: 16),
        const SizedBox(width: 8),
        Expanded(child: Text(msg,
            style: const TextStyle(fontSize: 12))),
      ]),
      backgroundColor: const Color(0xFFD97706),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10)),
      margin: const EdgeInsets.all(12),
      duration: const Duration(seconds: 3),
    ));
  }

  // ─── EXPORT PDF ───────────────────────────────────────────────
  Future<void> _exportPdf() async {
    if (_result == null) return;
    final user     = await LocalDB.getCurrentUser() ?? {};
    final incident = _buildIncident(user);
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Generating PDF…'),
            duration: Duration(seconds: 1)));
      await PdfExport.downloadOrShareIncident(
        incident:    incident,
        reporterName: user['name']?.toString() ?? 'SAIL Safety Officer',
        reporterPno:  user['pno']?.toString()  ?? '',
        imageBytes:  _imageBytes,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                kIsWeb ? 'PDF downloaded' : 'PDF ready to share'),
            backgroundColor: AppColors.green));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('PDF failed: $e'),
            backgroundColor: AppColors.red));
      }
    }
  }

  void _reset() => setState(() {
    _pickedFile     = null;
    _imageBytes     = null;
    _result         = null;
    _analyzing      = false;
    _hazardRowKeys.clear();
    _highlightedRow = null;
    // Note: _savedImageHash is intentionally NOT reset
    // so duplicate detection persists within the session
  });

  // ─────────────────────────────────────────────────────────────
  //  BUILD
  // ─────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final sl = SL.of(context);
    return Container(
      color: sl.isDark
          ? const Color(0xFF1C1F2E)
          : const Color(0xFFF5F6FA),
      child: SafeArea(
        child: Column(children: [
          _topBar(sl),
          Expanded(child: SingleChildScrollView(
            controller: _scrollController,
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 80),
            child: _analyzing
                ? _analyzingView()
                : _result != null
                    ? _resultView(sl)
                    : _emptyView(sl),
          )),
        ]),
      ),
    );
  }

  // ─── INFOGRAPHIC TOP BAR ──────────────────────────────────────
  Widget _topBar(SL sl) => Container(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
    decoration: BoxDecoration(
      color: sl.isDark ? const Color(0xFF252840) : Colors.white,
      border: Border(bottom: BorderSide(
          color: sl.border.withOpacity(0.35)))),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: AppColors.accent.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.document_scanner_rounded,
                color: AppColors.accent, size: 20)),
          const SizedBox(width: 10),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('AI Hazard Scan', style: TextStyle(
                  color: sl.text1, fontSize: 16,
                  fontWeight: FontWeight.w800)),
              Text('Gemini Vision · IS 14489 · WSA 13 · Factories Act',
                style: TextStyle(color: sl.text4, fontSize: 9)),
            ])),
          // Feature chips row
          _topChip('📸 Photo', AppColors.accent, sl),
          const SizedBox(width: 6),
          _topChip('🤖 AI', AppColors.cyan, sl),
        ]),
        const SizedBox(height: 10),
        // Workflow steps
        Row(children: [
          _stepChip('1', 'Capture', AppColors.accent, sl),
          _arrow(sl),
          _stepChip('2', 'AI Scan', AppColors.cyan, sl),
          _arrow(sl),
          _stepChip('3', 'Review', AppColors.amber, sl),
          _arrow(sl),
          _stepChip('4', 'Save', AppColors.green, sl),
          _arrow(sl),
          _stepChip('5', 'Mitigate', AppColors.purple, sl),
        ]),
      ]));

  Widget _topChip(String label, Color color, SL sl) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: color.withOpacity(0.08),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: color.withOpacity(0.3))),
    child: Text(label, style: TextStyle(color: color,
        fontSize: 9, fontWeight: FontWeight.w700)));

  Widget _stepChip(String num, String label, Color color, SL sl) =>
    Column(children: [
      Container(
        width: 20, height: 20,
        decoration: BoxDecoration(
          shape: BoxShape.circle, color: color.withOpacity(0.15),
          border: Border.all(color: color, width: 1.5)),
        child: Center(child: Text(num, style: TextStyle(
            color: color, fontSize: 9,
            fontWeight: FontWeight.w800)))),
      const SizedBox(height: 2),
      Text(label, style: TextStyle(
          color: sl.text4, fontSize: 7,
          fontWeight: FontWeight.w600)),
    ]);

  Widget _arrow(SL sl) => Expanded(child: Container(
    height: 1.5,
    margin: const EdgeInsets.only(bottom: 14),
    color: sl.border.withOpacity(0.4)));

  // ─── EMPTY VIEW ───────────────────────────────────────────────
  Widget _emptyView(SL sl) {
    final cardBg  = sl.isDark ? const Color(0xFF252840) : Colors.white;
    final fieldBg = sl.isDark
        ? const Color(0xFF2A2D42) : const Color(0xFFF0F1F5);
    return Column(children: [
      GestureDetector(
        onTap: () => _pickImage(ImageSource.camera),
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: cardBg,
            border: Border.all(
                color: AppColors.accent.withOpacity(0.3), width: 2),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [BoxShadow(
              color: Colors.black.withOpacity(
                  sl.isDark ? 0.2 : 0.04),
              blurRadius: 8, offset: const Offset(0, 2))]),
          child: Column(children: [
            Container(
              width: 64, height: 64,
              decoration: BoxDecoration(
                color: AppColors.accent.withOpacity(0.1),
                shape: BoxShape.circle),
              child: const Icon(Icons.add_a_photo_outlined,
                  size: 32, color: AppColors.accent)),
            const SizedBox(height: 12),
            Text('Capture workplace photo',
              style: TextStyle(color: sl.text1,
                  fontSize: 14, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('AI identifies hazards & marks them on photo',
              style: TextStyle(color: sl.text4, fontSize: 11)),
            const SizedBox(height: 12),
            // Mini feature tags
            Wrap(spacing: 6, runSpacing: 4, children: [
              _featureTag('🎯 Bbox mapping', sl),
              _featureTag('⚖️ IS 14489', sl),
              _featureTag('🏭 WSA 13', sl),
              _featureTag('📋 PDF export', sl),
            ]),
          ])),
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
      _infoBox(sl),
    ]);
  }

  Widget _featureTag(String label, SL sl) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: AppColors.accent.withOpacity(0.07),
      borderRadius: BorderRadius.circular(99),
      border: Border.all(
          color: AppColors.accent.withOpacity(0.2))),
    child: Text(label, style: const TextStyle(
        color: AppColors.accent, fontSize: 9,
        fontWeight: FontWeight.w600)));

  // ─── ANALYZING VIEW ───────────────────────────────────────────
  Widget _analyzingView() {
    DecorationImage? bgImage;
    if (_imageBytes != null) {
      bgImage = DecorationImage(
          image: MemoryImage(_imageBytes!), fit: BoxFit.cover);
    }
    return Container(
      height: 160,
      decoration: BoxDecoration(
        color: const Color(0xFF252840),
        borderRadius: BorderRadius.circular(12),
        image: bgImage),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.55),
          borderRadius: BorderRadius.circular(12)),
        child: Center(child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(strokeWidth: 3,
              valueColor: AlwaysStoppedAnimation<Color>(
                  AppColors.accent)),
            const SizedBox(height: 10),
            Text(_step, style: const TextStyle(
              color: Colors.white, fontSize: 12,
              fontWeight: FontWeight.w600)),
          ]))));
  }

  // ─── RESULT VIEW ──────────────────────────────────────────────
  Widget _resultView(SL sl) {
    final overallRisk = _result!['overallRisk']?.toString() ?? 'MEDIUM';
    final score       = _result!['riskScore']    ?? 50;
    final confidence  = _result!['confidence']   ?? 75;
    final summary     = _result!['summary']?.toString() ?? '';
    final hazards     = (_result!['hazards'] as List?) ?? [];
    final riskColor   = _severityColor(overallRisk);
    final hasBbox     = hazards.any((h) => (h as Map)['bbox'] != null);

    final cardBg = sl.isDark
        ? const Color(0xFF252840) : Colors.white;

    return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [

      // ── Annotated image ──────────────────────────────────────
      if (_imageBytes != null) ...[
        if (hasBbox)
          HazardAnnotatedImage(
            imageBytes: _imageBytes!,
            hazards: hazards,
            onHazardTap: _onBboxTap,
          )
        else
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.memory(_imageBytes!,
                height: 200, width: double.infinity,
                fit: BoxFit.cover)),
        const SizedBox(height: 12),
      ],

      // ── Risk summary card ─────────────────────────────────────
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: riskColor.withOpacity(0.06),
          border: Border.all(color: riskColor, width: 2),
          borderRadius: BorderRadius.circular(14)),
        child: Row(children: [
          Container(
            width: 64, height: 64,
            decoration: BoxDecoration(
              color: riskColor.withOpacity(0.15),
              shape: BoxShape.circle,
              border: Border.all(color: riskColor, width: 2.5)),
            child: Center(child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('$score', style: TextStyle(
                  color: riskColor, fontSize: 20,
                  fontWeight: FontWeight.w800)),
                Text('/100', style: TextStyle(
                  color: riskColor, fontSize: 8)),
              ]))),
          const SizedBox(width: 12),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('OVERALL RISK', style: TextStyle(
                color: sl.text4, fontSize: 9,
                fontWeight: FontWeight.w600)),
              Text(overallRisk, style: TextStyle(
                color: riskColor, fontSize: 18,
                fontWeight: FontWeight.w800)),
              Text('${hazards.length} hazards · $confidence% confidence',
                style: TextStyle(color: sl.text3, fontSize: 10)),
              if (hasBbox)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(children: [
                    const Icon(Icons.touch_app_outlined,
                        size: 10, color: AppColors.accent),
                    const SizedBox(width: 4),
                    Text('Tap boxes on image → jumps to hazard row',
                      style: const TextStyle(
                        color: AppColors.accent, fontSize: 9,
                        fontStyle: FontStyle.italic)),
                  ])),
            ])),
        ])),
      const SizedBox(height: 10),

      // ── Summary ───────────────────────────────────────────────
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cardBg,
          border: Border.all(
              color: sl.border.withOpacity(0.4)),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(
            color: Colors.black.withOpacity(
                sl.isDark ? 0.15 : 0.04),
            blurRadius: 6, offset: const Offset(0, 2))]),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
          Text('SUMMARY', style: TextStyle(
            color: sl.text4, fontSize: 9,
            fontWeight: FontWeight.w700, letterSpacing: 0.9)),
          const SizedBox(height: 6),
          Text(summary, style: TextStyle(
            color: sl.text2, fontSize: 11, height: 1.5)),
        ])),
      const SizedBox(height: 10),

      // ── Hazard table ──────────────────────────────────────────
      _hazardTable(hazards, sl),
      const SizedBox(height: 12),

      // ── Action buttons ────────────────────────────────────────
      Row(children: [
        Expanded(child: ElevatedButton.icon(
          onPressed: _save,
          icon: const Icon(Icons.save_outlined,
              size: 14, color: Colors.white),
          label: const Text('Save',
              style: TextStyle(color: Colors.white,
                  fontSize: 12, fontWeight: FontWeight.w700)),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.green,
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10))),
        )),
        const SizedBox(width: 8),
        Expanded(child: ElevatedButton.icon(
          onPressed: _exportPdf,
          icon: const Icon(Icons.picture_as_pdf,
              size: 14, color: Colors.white),
          label: const Text('PDF',
              style: TextStyle(color: Colors.white,
                  fontSize: 12, fontWeight: FontWeight.w700)),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.accent,
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10))),
        )),
        const SizedBox(width: 8),
        Expanded(child: OutlinedButton.icon(
          onPressed: _reset,
          icon: const Icon(Icons.refresh,
              size: 14, color: AppColors.accent),
          label: const Text('New',
              style: TextStyle(color: AppColors.accent,
                  fontSize: 12, fontWeight: FontWeight.w700)),
          style: OutlinedButton.styleFrom(
            side: const BorderSide(
                color: AppColors.accent, width: 2),
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10))),
        )),
      ]),
    ]);
  }

  // ─── HAZARD TABLE ─────────────────────────────────────────────
  Widget _hazardTable(List hazards, SL sl) {
    final cardBg = sl.isDark
        ? const Color(0xFF252840) : Colors.white;
    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        border: Border.all(color: sl.border.withOpacity(0.4)),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(
          color: Colors.black.withOpacity(
              sl.isDark ? 0.15 : 0.04),
          blurRadius: 6, offset: const Offset(0, 2))]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
          child: Row(children: [
            const Icon(Icons.table_view_outlined,
                size: 14, color: AppColors.red),
            const SizedBox(width: 6),
            Text('HAZARD ANALYSIS',
              style: TextStyle(color: sl.text4, fontSize: 10,
                fontWeight: FontWeight.w700, letterSpacing: 0.9)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(99),
                border: Border.all(
                    color: AppColors.red.withOpacity(0.3))),
              child: Text('${hazards.length} hazards',
                style: const TextStyle(color: AppColors.red,
                    fontSize: 9, fontWeight: FontWeight.w700))),
          ])),
        Table(
          border: TableBorder(
            horizontalInside: BorderSide(
                color: sl.border.withOpacity(0.4), width: 0.5)),
          columnWidths: const {
            0: FlexColumnWidth(2.0),   // Hazard
            1: FlexColumnWidth(2.8),   // Description
            2: FlexColumnWidth(2.0),   // Regulation
            3: FlexColumnWidth(1.2),   // Severity
            4: FlexColumnWidth(2.8),   // Action
          },
          children: [
            TableRow(
              decoration: BoxDecoration(
                color: sl.isDark
                    ? const Color(0xFF2A2D42)
                    : const Color(0xFFF0F1F5)),
              children: [
                _hth('HAZARD', sl),
                _hth('DESCRIPTION', sl),
                _hth('REGULATION', sl),
                _hth('SEVERITY', sl, center: true),
                _hth('ACTION', sl),
              ]),
            ...hazards.asMap().entries.map((entry) {
              final i   = entry.key;
              final h   = entry.value;
              final hm  = Map<String, dynamic>.from(h as Map);
              final sev = (hm['severity'] ?? 'MEDIUM').toString();
              final isHighlighted = _highlightedRow == i;
              final color = _severityColor(sev);
              return TableRow(
                decoration: BoxDecoration(
                  color: isHighlighted
                      ? color.withOpacity(0.1)
                      : Colors.transparent),
                children: [
                  Padding(
                    key: i < _hazardRowKeys.length
                        ? _hazardRowKeys[i] : null,
                    padding: const EdgeInsets.all(7),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 16, height: 16,
                          margin: const EdgeInsets.only(
                              right: 5, top: 1),
                          decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle),
                          child: Center(child: Text('${i+1}',
                            style: const TextStyle(
                              color: Colors.white, fontSize: 8,
                              fontWeight: FontWeight.w900)))),
                        Expanded(child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                          Text(hm['name']?.toString() ?? '',
                            style: TextStyle(
                              color: sl.text1, fontSize: 9.5,
                              fontWeight: FontWeight.w600,
                              height: 1.4)),
                          if (hm['type'] != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(hm['type'].toString(),
                                style: TextStyle(
                                    color: sl.text4, fontSize: 8))),
                        ])),
                      ])),
                  _htd(hm['description']?.toString() ?? '', sl),
                  _htd(hm['regulation']?.toString()  ?? '', sl),
                  Padding(
                    padding: const EdgeInsets.all(7),
                    child: Center(
                        child: _sevPill(sev, color))),
                  _htd(hm['correctiveAction']?.toString() ?? '', sl),
                ]);
            }).toList(),
          ]),
      ]));
  }

  Widget _hth(String t, SL sl, {bool center = false}) => Padding(
    padding: const EdgeInsets.all(7),
    child: Text(t,
      textAlign: center ? TextAlign.center : TextAlign.left,
      style: TextStyle(color: sl.text3, fontSize: 8,
          fontWeight: FontWeight.w700, letterSpacing: 0.4)));

  Widget _htd(String t, SL sl) => Padding(
    padding: const EdgeInsets.all(7),
    child: Text(t, style: TextStyle(
        color: sl.text1, fontSize: 9.5,
        fontWeight: FontWeight.w600, height: 1.4)));

  Widget _sevPill(String sev, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: color.withOpacity(0.15),
      border: Border.all(color: color),
      borderRadius: BorderRadius.circular(8)),
    child: Text(
      sev.substring(0, sev.length > 4 ? 4 : sev.length),
      style: TextStyle(color: color, fontSize: 8,
          fontWeight: FontWeight.w800)));

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
          color: Colors.white, fontSize: 12,
          fontWeight: FontWeight.w600)),
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
        side: const BorderSide(
            color: AppColors.accent, width: 2),
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10))));

  Widget _infoBox(SL sl) {
    final cardBg = sl.isDark
        ? const Color(0xFF252840) : Colors.white;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cardBg,
        border: Border.all(
            color: AppColors.accent.withOpacity(0.35)),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(
          color: Colors.black.withOpacity(
              sl.isDark ? 0.15 : 0.04),
          blurRadius: 6, offset: const Offset(0, 2))]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
        Row(children: [
          const Icon(Icons.info_outline_rounded,
              size: 14, color: AppColors.accent),
          const SizedBox(width: 6),
          Text('How AI Hazard Scan works',
            style: TextStyle(color: sl.text1,
                fontSize: 12, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 8),
        _infoRow('📸', 'Take a workplace photo', sl),
        _infoRow('🤖', 'AI detects hazards with coloured bounding boxes', sl),
        _infoRow('⚖️', 'Each hazard mapped to IS/FA regulation', sl),
        _infoRow('💾', 'Save → auto-syncs to Google Sheets', sl),
        _infoRow('🔒', 'Duplicate images are blocked from double-saving', sl),
      ]));
  }

  Widget _infoRow(String icon, String text, SL sl) => Padding(
    padding: const EdgeInsets.only(bottom: 5),
    child: Row(children: [
      Text(icon, style: const TextStyle(fontSize: 12)),
      const SizedBox(width: 8),
      Expanded(child: Text(text,
        style: TextStyle(color: sl.text2,
            fontSize: 11, height: 1.4))),
    ]));
}
