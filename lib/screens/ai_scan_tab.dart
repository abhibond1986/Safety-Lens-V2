// lib/screens/ai_scan_tab.dart
// ✅ Step chips 1-5 are fully interactive
// ✅ Duplicate image detection
// ✅ Google Sheets link shown after save
// ✅ Save success dialog
// ✅ NEW: "Review & Edit AI Findings" hint banner at top of review sheet
// ✅ Inline edit per hazard preserved

import 'dart:io' show File;
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb, Uint8List;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../main.dart';
import '../services/gemini_vision.dart';
import '../services/local_ai.dart';
import '../services/local_db.dart';
import '../services/sync_service.dart';
import '../services/pdf_export.dart';
import '../widgets/hazard_annotated_image.dart';
import '../widgets/universal_app_bar.dart';
import '../services/i18n.dart';

class AIScanTab extends StatefulWidget {
  final Map<String, dynamic>? user;
  final VoidCallback? toggleTheme;
  final VoidCallback? onSignOut;
  final bool isDark;
  const AIScanTab({
    super.key,
    this.user,
    this.toggleTheme,
    this.onSignOut,
    this.isDark = true,
  });
  @override
  State<AIScanTab> createState() => _AIScanTabState();
}

class _AIScanTabState extends State<AIScanTab> {
  XFile?     _pickedFile;
  Uint8List? _imageBytes;
  bool       _analyzing = false;
  Map<String, dynamic>? _result;
  String     _step = '';
  String?    _savedImageHash;
  int _currentStep = 0;
  String? _savedIncidentId;
  bool    _isSaved = false;
  final Map<int, TextEditingController> _mitigationControllers = {};
  final Map<int, bool> _hazardClosed = {};
  final ScrollController _scrollController = ScrollController();
  final List<GlobalKey>  _hazardRowKeys    = [];
  int? _highlightedRow;

  static const String _sheetUrl =
      'https://docs.google.com/spreadsheets/d/1gkN0Kxy5tulHN9oCbvliI5bota7S1UpK6gusftWUZgI/edit';

  @override
  void dispose() {
    _scrollController.dispose();
    for (final c in _mitigationControllers.values) { c.dispose(); }
    super.dispose();
  }

  String _computeHash(Uint8List bytes) {
    int h = 0;
    final step = bytes.length > 1000 ? bytes.length ~/ 500 : 1;
    for (int i = 0; i < bytes.length; i += step) {
      h ^= (bytes[i] << (i % 24));
      h  =  h & 0xFFFFFFFF;
    }
    return h.toRadixString(16).padLeft(8, '0');
  }

  void _buildHazardKeys(int count) {
    _hazardRowKeys.clear();
    _mitigationControllers.forEach((_, c) => c.dispose());
    _mitigationControllers.clear();
    _hazardClosed.clear();
    for (int i = 0; i < count; i++) {
      _hazardRowKeys.add(GlobalKey());
      _mitigationControllers[i] = TextEditingController();
      _hazardClosed[i] = false;
    }
  }

  void _onBboxTap(int index) {
    setState(() => _highlightedRow =
        index == _highlightedRow ? null : index);
    if (index >= _hazardRowKeys.length) return;
    final ctx = _hazardRowKeys[index].currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(ctx,
          duration: const Duration(milliseconds: 450),
          curve: Curves.easeInOut, alignment: 0.1);
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    // ✅ FIX: 1600×1600 @ q=85 gives the AI enough visual detail to actually
    // read equipment tags, spot corrosion, identify hazards reliably.
    // Previously 500×500 @ q=20 produced WhatsApp-thumbnail-quality images
    // that no AI model could analyse meaningfully (~30 KB upload size).
    // New settings → ~300–500 KB per image (still fast over mobile data).
    final picked = await picker.pickImage(
        source: source, imageQuality: 85,
        maxWidth: 1600, maxHeight: 1600);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    setState(() {
      _pickedFile     = picked;
      _imageBytes     = bytes;
      _analyzing      = true;
      _result         = null;
      _isSaved        = false;
      _savedIncidentId = null;
      _hazardRowKeys.clear();
      _highlightedRow = null;
      _currentStep    = 2;
    });
    await _analyze();
  }

  Future<void> _analyze() async {
    final steps = ['Image uploaded', 'Sending to AI…',
                   'Analyzing hazards…', 'Mapping IS 14489…',
                   'Building report…'];
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
        setState(() {
          _result      = result;
          _analyzing   = false;
          _currentStep = 3;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() { _analyzing = false; _currentStep = 1; });
        _snack('Analysis failed: $e', AppColors.red);
      }
    }
  }

  // ─── STEP 3: REVIEW (with inline edit per hazard) ───────────
  void _openReviewSheet() {
    if (_result == null) return;
    setState(() => _currentStep = 3);

    final sl        = SL.of(context);
    final riskColor = _sevColor(
        _result!['overallRisk']?.toString() ?? 'MEDIUM');

    final List<Map<String, dynamic>> editableHazards =
        ((_result!['hazards'] as List?) ?? [])
            .map((h) => Map<String, dynamic>.from(h as Map))
            .toList();

    final Map<int, Map<String, TextEditingController>> editControllers = {};
    final Map<int, bool> editingIndex = {};

    final summaryCtrl = TextEditingController(
        text: _result!['summary']?.toString() ?? '');
    bool editingSummary = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setLocal) {
          Map<String, TextEditingController> ctrlsFor(int i) {
            if (!editControllers.containsKey(i)) {
              final h = editableHazards[i];
              editControllers[i] = {
                'name':             TextEditingController(text: h['name']?.toString() ?? ''),
                'description':      TextEditingController(text: h['description']?.toString() ?? ''),
                'regulation':       TextEditingController(text: h['regulation']?.toString() ?? ''),
                'correctiveAction': TextEditingController(text: h['correctiveAction']?.toString() ?? ''),
                'wsaCause':         TextEditingController(text: h['wsaCause']?.toString() ?? ''),
                'type':             TextEditingController(text: h['type']?.toString() ?? ''),
              };
            }
            return editControllers[i]!;
          }

          void applyEdits(int i) {
            final ctrls = ctrlsFor(i);
            editableHazards[i]['name']             = ctrls['name']!.text.trim();
            editableHazards[i]['description']      = ctrls['description']!.text.trim();
            editableHazards[i]['regulation']       = ctrls['regulation']!.text.trim();
            editableHazards[i]['correctiveAction'] = ctrls['correctiveAction']!.text.trim();
            editableHazards[i]['wsaCause']         = ctrls['wsaCause']!.text.trim();
            editableHazards[i]['type']             = ctrls['type']!.text.trim();
          }

          final fieldBg = sl.isDark
              ? const Color(0xFF1C1F2E)
              : const Color(0xFFF0F1F5);

          // ✅ NEW: Prominent hint banner — first thing user sees in review
          final hintBanner = Container(
            margin: const EdgeInsets.fromLTRB(0, 0, 0, 12),
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.accent.withOpacity(0.12),
                  AppColors.cyan.withOpacity(0.08),
                ]),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: AppColors.accent.withOpacity(0.4), width: 1)),
            child: Row(children: [
              Container(
                width: 32, height: 32,
                decoration: BoxDecoration(
                  color: AppColors.accent.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.edit_note_rounded,
                    color: AppColors.accent, size: 20)),
              const SizedBox(width: 10),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Review & Edit AI Findings',
                      style: TextStyle(color: sl.text1, fontSize: 12.5,
                          fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text(
                      'Tap ✏️ Edit on any hazard to modify name, '
                      'severity, description, regulation, or '
                      'corrective action. Then tap Save with edits.',
                      style: TextStyle(color: sl.text3, fontSize: 10,
                          height: 1.35)),
                ])),
            ]));

          Widget editField(TextEditingController c,
              {String hint = '', int lines = 1}) =>
            TextField(
              controller: c,
              maxLines: lines,
              style: TextStyle(color: sl.text1,
                  fontSize: 11, height: 1.4),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: TextStyle(color: sl.text4, fontSize: 10),
                filled: true, fillColor: fieldBg,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 6),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(7),
                  borderSide: BorderSide(
                      color: sl.border.withOpacity(0.5))),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(7),
                  borderSide: const BorderSide(
                      color: AppColors.accent, width: 2))));

          Widget editableRow(String label, TextEditingController c,
              {int lines = 1}) =>
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                SizedBox(width: 84, child: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(label, style: TextStyle(
                      color: sl.text4, fontSize: 9,
                      fontWeight: FontWeight.w600)))),
                Expanded(child: editField(c,
                    hint: label, lines: lines)),
              ]));

          return DraggableScrollableSheet(
            initialChildSize: 0.88,
            maxChildSize: 0.97,
            minChildSize: 0.5,
            builder: (_, ctrl) => Container(
              decoration: BoxDecoration(
                color: sl.isDark
                    ? const Color(0xFF1C1F2E) : Colors.white,
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(20))),
              child: Column(children: [
                Center(child: Container(
                  margin: const EdgeInsets.only(top: 10, bottom: 4),
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: sl.border,
                    borderRadius: BorderRadius.circular(99)))),

                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
                  child: Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: riskColor.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: riskColor)),
                      child: Text(
                        '${_result!['overallRisk']} · ${_result!['riskScore']}/100',
                        style: TextStyle(color: riskColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w800))),
                    const SizedBox(width: 10),
                    Expanded(child: Text(
                      '${editableHazards.length} Hazards Identified',
                      style: TextStyle(color: sl.text1,
                          fontSize: 14,
                          fontWeight: FontWeight.w700))),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.accent.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(7),
                        border: Border.all(
                            color: AppColors.accent.withOpacity(0.3))),
                      child: const Text('✏️ Tap Edit',
                        style: TextStyle(
                            color: AppColors.accent,
                            fontSize: 9,
                            fontWeight: FontWeight.w700))),
                    const SizedBox(width: 8),
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      icon: Icon(Icons.close, color: sl.text4, size: 20),
                      onPressed: () {
                        for (final m in editControllers.values) {
                          for (final c in m.values) { c.dispose(); }
                        }
                        summaryCtrl.dispose();
                        Navigator.pop(ctx);
                      }),
                  ])),
                Divider(height: 1, color: sl.border),

                Expanded(child: ListView(
                  controller: ctrl,
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 120),
                  children: [
                    // ✅ NEW: hint banner is the first item
                    hintBanner,

                    // ── Editable summary ──────────────────
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: sl.isDark
                            ? const Color(0xFF252840)
                            : const Color(0xFFF5F6FA),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: sl.border.withOpacity(0.5))),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                        Row(children: [
                          Text('SUMMARY', style: TextStyle(
                              color: sl.text4, fontSize: 9,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.6)),
                          const Spacer(),
                          GestureDetector(
                            onTap: () => setLocal(() =>
                                editingSummary = !editingSummary),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 3),
                              decoration: BoxDecoration(
                                color: editingSummary
                                    ? AppColors.accent
                                    : AppColors.accent.withOpacity(0.1),
                                borderRadius:
                                    BorderRadius.circular(6)),
                              child: Text(
                                editingSummary ? 'Done' : 'Edit',
                                style: TextStyle(
                                  color: editingSummary
                                      ? Colors.white
                                      : AppColors.accent,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700)))),
                        ]),
                        const SizedBox(height: 6),
                        editingSummary
                          ? editField(summaryCtrl,
                              hint: 'Overall summary…', lines: 3)
                          : Text(summaryCtrl.text.isNotEmpty
                                ? summaryCtrl.text
                                : _result!['summary']?.toString() ?? '',
                              style: TextStyle(
                                  color: sl.text2,
                                  fontSize: 11, height: 1.5)),
                      ])),
                    const SizedBox(height: 10),

                    // ── Hazard cards ──────────────────────
                    ...editableHazards.asMap().entries.map((e) {
                      final i  = e.key;
                      final h  = e.value;
                      final sc = _sevColor(
                          h['severity']?.toString() ?? 'MEDIUM');
                      final isEditing = editingIndex[i] ?? false;
                      final ctrls = isEditing ? ctrlsFor(i) : null;

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: sl.isDark
                                ? const Color(0xFF252840)
                                : Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isEditing
                                  ? AppColors.accent.withOpacity(0.5)
                                  : sc.withOpacity(0.35),
                              width: isEditing ? 1.5 : 1)),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                            Row(children: [
                              Container(
                                width: 22, height: 22,
                                decoration: BoxDecoration(
                                    color: sc, shape: BoxShape.circle),
                                child: Center(child: Text('${i+1}',
                                  style: const TextStyle(
                                    color: Colors.white, fontSize: 9,
                                    fontWeight: FontWeight.w800)))),
                              const SizedBox(width: 8),
                              Expanded(child: isEditing
                                ? editField(ctrls!['name']!,
                                    hint: 'Hazard name')
                                : Text(h['name']?.toString() ?? '—',
                                    style: TextStyle(
                                        color: sl.text1, fontSize: 13,
                                        fontWeight: FontWeight.w700))),
                              const SizedBox(width: 8),
                              isEditing
                                ? _severityDropdown(
                                    h['severity']?.toString() ?? 'MEDIUM',
                                    sl,
                                    (val) => setLocal(() =>
                                        editableHazards[i]['severity'] = val))
                                : Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: sc.withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: sc)),
                                    child: Text(
                                      h['severity']?.toString() ?? '—',
                                      style: TextStyle(
                                          color: sc, fontSize: 8,
                                          fontWeight: FontWeight.w800))),
                              const SizedBox(width: 8),
                              GestureDetector(
                                onTap: () => setLocal(() {
                                  if (isEditing) {
                                    applyEdits(i);
                                    editingIndex[i] = false;
                                  } else {
                                    ctrlsFor(i);
                                    editingIndex[i] = true;
                                  }
                                }),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: isEditing
                                        ? AppColors.green
                                        : AppColors.accent.withOpacity(0.1),
                                    borderRadius:
                                        BorderRadius.circular(7)),
                                  child: Text(
                                    isEditing ? '✓ Done' : '✏️ Edit',
                                    style: TextStyle(
                                      color: isEditing
                                          ? Colors.white
                                          : AppColors.accent,
                                      fontSize: 9,
                                      fontWeight: FontWeight.w700)))),
                            ]),
                            const SizedBox(height: 8),

                            if (!isEditing) ...[
                              Text(
                                h['description']?.toString() ?? '',
                                style: TextStyle(
                                    color: sl.text2,
                                    fontSize: 11, height: 1.4)),
                              const SizedBox(height: 5),
                              _reviewRow('⚖️ Regulation',
                                  h['regulation']?.toString() ?? '', sl),
                              _reviewRow('🔧 Action',
                                  h['correctiveAction']?.toString() ?? '', sl),
                              if ((h['wsaCause']?.toString() ?? '').isNotEmpty)
                                _reviewRow('📋 WSA Cause',
                                    h['wsaCause']?.toString() ?? '', sl),
                              if ((h['type']?.toString() ?? '').isNotEmpty)
                                _reviewRow('🔍 Type',
                                    h['type']?.toString() ?? '', sl),
                            ] else ...[
                              editableRow('Description',
                                  ctrls!['description']!, lines: 3),
                              editableRow('⚖️ Regulation',
                                  ctrls['regulation']!, lines: 2),
                              editableRow('🔧 Action',
                                  ctrls['correctiveAction']!, lines: 2),
                              editableRow('📋 WSA Cause',
                                  ctrls['wsaCause']!),
                              editableRow('🔍 Type', ctrls['type']!),
                              const SizedBox(height: 4),
                              GestureDetector(
                                onTap: () => setLocal(() {
                                  editControllers.remove(i);
                                  editingIndex[i] = false;
                                }),
                                child: Row(children: [
                                  Icon(Icons.undo_rounded,
                                      size: 12, color: sl.text4),
                                  const SizedBox(width: 4),
                                  Text('Discard changes',
                                    style: TextStyle(
                                        color: sl.text4, fontSize: 10)),
                                ])),
                            ],
                          ])));
                    }).toList(),
                  ])),

                Container(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
                  decoration: BoxDecoration(
                    color: sl.isDark
                        ? const Color(0xFF252840) : Colors.white,
                    border: Border(top: BorderSide(
                        color: sl.border.withOpacity(0.4)))),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                    if (editingIndex.values.any((v) => v))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppColors.amber.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: AppColors.amber.withOpacity(0.35))),
                          child: const Row(children: [
                            Icon(Icons.edit_note_rounded,
                                color: AppColors.amber, size: 14),
                            SizedBox(width: 6),
                            Expanded(child: Text(
                              'Tap ✓ Done on each hazard to apply edits before saving.',
                              style: TextStyle(
                                  color: AppColors.amber,
                                  fontSize: 10, height: 1.4))),
                          ]))),
                    Row(children: [
                      Expanded(
                        flex: 2,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            for (final i in editingIndex.keys) {
                              if (editingIndex[i] == true) {
                                applyEdits(i);
                              }
                            }
                            if (editingSummary) {
                              _result!['summary'] = summaryCtrl.text.trim();
                            }
                            _result!['hazards'] = editableHazards;
                            for (final m in editControllers.values) {
                              for (final c in m.values) { c.dispose(); }
                            }
                            summaryCtrl.dispose();
                            Navigator.pop(ctx);
                            setState(() => _currentStep = 4);
                            _save();
                          },
                          icon: const Icon(Icons.save_outlined,
                              size: 14, color: Colors.white),
                          label: const Text(
                            'Save with edits',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 13)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.green,
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10))),
                        )),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            for (final m in editControllers.values) {
                              for (final c in m.values) { c.dispose(); }
                            }
                            summaryCtrl.dispose();
                            Navigator.pop(ctx);
                            setState(() => _currentStep = 4);
                            _save();
                          },
                          icon: const Icon(Icons.check_circle_outline,
                              size: 13, color: AppColors.accent),
                          label: const Text('Save as-is',
                            style: TextStyle(
                                color: AppColors.accent,
                                fontWeight: FontWeight.w700,
                                fontSize: 12)),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(
                                color: AppColors.accent, width: 1.5),
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10))),
                        )),
                    ]),
                  ])),
              ])));
        }));
  }

  Widget _severityDropdown(
      String current, SL sl, ValueChanged<String> onChanged) {
    const sevs = ['CRITICAL', 'HIGH', 'MEDIUM', 'LOW'];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: _sevColor(current).withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _sevColor(current))),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: sevs.contains(current) ? current : 'MEDIUM',
          isDense: true,
          dropdownColor: sl.isDark ? const Color(0xFF252840) : Colors.white,
          style: TextStyle(
              color: _sevColor(current), fontSize: 9,
              fontWeight: FontWeight.w800),
          icon: Icon(Icons.arrow_drop_down,
              color: _sevColor(current), size: 14),
          items: sevs.map((s) => DropdownMenuItem(
              value: s,
              child: Text(s, style: TextStyle(
                  color: _sevColor(s), fontSize: 9,
                  fontWeight: FontWeight.w800)))).toList(),
          onChanged: (v) { if (v != null) onChanged(v); })));
  }

  Widget _reviewRow(String label, String value, SL sl) =>
    Padding(padding: const EdgeInsets.only(top: 3),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 90, child: Text(label, style: TextStyle(
            color: sl.text4, fontSize: 9, fontWeight: FontWeight.w600))),
        Expanded(child: Text(value, style: TextStyle(
            color: sl.text1, fontSize: 10, height: 1.4))),
      ]));

  // ─── STEP 4: SAVE ────────────────────────────────────────────
  Future<void> _save() async {
    if (_result == null) return;

    if (_imageBytes != null) {
      final hash = _computeHash(_imageBytes!);
      if (_savedImageHash == hash) {
        _snack('This image was already saved. Scan a new photo.',
            const Color(0xFFD97706));
        return;
      }
      final existing   = await LocalDB.getIncidents();
      final alreadySaved = existing.any(
          (inc) => inc['imageHash']?.toString() == hash);
      if (alreadySaved) {
        if (!mounted) return;
        final confirm = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            backgroundColor: Theme.of(context).colorScheme.surface,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
            title: const Row(children: [
              Icon(Icons.warning_amber_rounded,
                  color: Color(0xFFD97706), size: 22),
              SizedBox(width: 8),
              Text('Duplicate Image',
                style: TextStyle(fontSize: 16,
                    fontWeight: FontWeight.w700)),
            ]),
            content: const Text(
              'This image was already saved as a report.\n'
              'Save again as a new entry?',
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
                    style: TextStyle(color: Colors.white,
                        fontWeight: FontWeight.w700))),
            ]));
        if (confirm != true) return;
      }
    }

    final user  = await LocalDB.getCurrentUser() ?? {};
    final incident = _buildIncident(user);
    final dbInc    = Map<String, dynamic>.from(incident);
    dbInc['hazards'] = jsonEncode(incident['hazards']);

    if (_imageBytes != null) {
      final hash         = _computeHash(_imageBytes!);
      dbInc['imageHash'] = hash;
      _savedImageHash    = hash;
    }

    await LocalDB.saveIncident(dbInc);
    SyncService.pushIncident(dbInc).catchError((_) => false);
    _uploadPdfBackground(dbInc, user);

    setState(() {
      _isSaved         = true;
      _savedIncidentId = dbInc['id']?.toString();
      _currentStep     = 5;
    });

    if (mounted) {
      _showSaveSuccessDialog(dbInc);
    }
  }

  void _showSaveSuccessDialog(Map<String, dynamic> incident) {
    final sl = SL.of(context);
    final id = incident['id']?.toString() ?? '';
    final shortId = id.length > 8 ? id.substring(id.length - 8) : id;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        backgroundColor: sl.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 70, height: 70,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                  colors: [Color(0xFF10B981), Color(0xFF059669)]),
                boxShadow: [BoxShadow(
                  color: AppColors.green.withOpacity(0.3),
                  blurRadius: 16, spreadRadius: 2)]),
              child: const Icon(Icons.check_rounded,
                  color: Colors.white, size: 40)),
            const SizedBox(height: 14),
            Text('Report Saved Successfully',
                style: TextStyle(color: sl.text1, fontSize: 17,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text('Report ID: #$shortId',
                style: TextStyle(color: sl.text3, fontSize: 11,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: sl.card2,
                borderRadius: BorderRadius.circular(12)),
              child: Column(children: [
                _saveRow(Icons.save_outlined, 'Saved locally',
                    'Available offline', AppColors.green, sl),
                const SizedBox(height: 8),
                _saveRow(Icons.cloud_upload_outlined, 'Synced to Google Sheets',
                    'Visible to admin', AppColors.cyan, sl),
                const SizedBox(height: 8),
                _saveRow(Icons.picture_as_pdf_outlined, 'PDF report',
                    'Uploading in background', AppColors.amber, sl),
              ])),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: OutlinedButton.icon(
                onPressed: () { Navigator.pop(ctx); _openSheetsLink(); },
                icon: const Icon(Icons.open_in_new_rounded,
                    size: 14, color: AppColors.accent),
                label: const Text('View Sheet',
                    style: TextStyle(color: AppColors.accent,
                        fontSize: 12, fontWeight: FontWeight.w700)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.accent, width: 1.5),
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10))),
              )),
              const SizedBox(width: 10),
              Expanded(child: ElevatedButton.icon(
                onPressed: () => Navigator.pop(ctx),
                icon: const Icon(Icons.check_rounded,
                    size: 14, color: Colors.white),
                label: const Text('Done',
                    style: TextStyle(color: Colors.white,
                        fontSize: 12, fontWeight: FontWeight.w700)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.green,
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10))),
              )),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _saveRow(IconData icon, String title, String sub, Color color, SL sl) {
    return Row(children: [
      Container(
        width: 28, height: 28,
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(8)),
        child: Icon(icon, color: color, size: 15)),
      const SizedBox(width: 10),
      Expanded(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: TextStyle(
            color: sl.text1, fontSize: 12,
            fontWeight: FontWeight.w700)),
        Text(sub, style: TextStyle(color: sl.text4, fontSize: 10)),
      ])),
      Icon(Icons.check_circle, color: color, size: 16),
    ]);
  }

  // ─── STEP 5: MITIGATE ────────────────────────────────────────
  void _openMitigateSheet() {
    if (_result == null) return;
    if (!_isSaved) {
      _snack('Save the scan first (Step 4) before mitigating',
          AppColors.amber);
      return;
    }
    setState(() => _currentStep = 5);
    final hazards = (_result!['hazards'] as List?) ?? [];
    final sl      = SL.of(context);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setLocal) => DraggableScrollableSheet(
          initialChildSize: 0.88,
          maxChildSize: 0.97,
          minChildSize: 0.5,
          builder: (_, ctrl) => Container(
            decoration: BoxDecoration(
              color: sl.isDark ? const Color(0xFF1C1F2E) : Colors.white,
              borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20))),
            child: Column(children: [
              Center(child: Container(
                margin: const EdgeInsets.only(top: 10, bottom: 4),
                width: 40, height: 4,
                decoration: BoxDecoration(
                    color: sl.border,
                    borderRadius: BorderRadius.circular(99)))),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                child: Row(children: [
                  Container(
                    width: 28, height: 28,
                    decoration: BoxDecoration(
                      color: AppColors.purple.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8)),
                    child: const Icon(Icons.engineering_rounded,
                        color: AppColors.purple, size: 16)),
                  const SizedBox(width: 10),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                    Text('Mitigate Hazards',
                      style: TextStyle(color: sl.text1,
                          fontSize: 15,
                          fontWeight: FontWeight.w700)),
                    Text('Add corrective action per hazard & close',
                      style: TextStyle(color: sl.text4, fontSize: 10)),
                  ])),
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    icon: Icon(Icons.close, color: sl.text4, size: 20),
                    onPressed: () => Navigator.pop(ctx)),
                ])),
              Divider(height: 1, color: sl.border),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(children: [
                  Text(
                    '${_hazardClosed.values.where((v) => v).length}'
                    ' / ${hazards.length} closed',
                    style: TextStyle(color: sl.text4, fontSize: 11)),
                  const SizedBox(width: 10),
                  Expanded(child: ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      value: hazards.isEmpty ? 0
                          : _hazardClosed.values.where((v) => v).length
                              / hazards.length,
                      minHeight: 6,
                      backgroundColor: sl.border.withOpacity(0.3),
                      valueColor: const AlwaysStoppedAnimation<Color>(
                              AppColors.green)))),
                ])),
              Expanded(child: ListView.separated(
                controller: ctrl,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                itemCount: hazards.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, i) {
                  final h      = Map<String, dynamic>.from(hazards[i] as Map);
                  final sc     = _sevColor(
                      h['severity']?.toString() ?? 'MEDIUM');
                  final closed = _hazardClosed[i] ?? false;
                  final ctrl2  = _mitigationControllers[i]!;

                  return Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: closed
                          ? AppColors.green.withOpacity(0.05)
                          : (sl.isDark
                              ? const Color(0xFF252840) : Colors.white),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: closed
                            ? AppColors.green.withOpacity(0.5)
                            : sc.withOpacity(0.35),
                        width: closed ? 1.5 : 1)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                      Row(children: [
                        Container(
                          width: 20, height: 20,
                          decoration: BoxDecoration(
                            color: closed ? AppColors.green : sc,
                            shape: BoxShape.circle),
                          child: Center(child: closed
                            ? const Icon(Icons.check,
                                color: Colors.white, size: 11)
                            : Text('${i+1}',
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 9,
                                    fontWeight: FontWeight.w800)))),
                        const SizedBox(width: 8),
                        Expanded(child: Text(
                          h['name']?.toString() ?? '—',
                          style: TextStyle(
                            color: closed ? sl.text3 : sl.text1,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            decoration: closed
                                ? TextDecoration.lineThrough : null))),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: sc.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(5),
                            border: Border.all(color: sc)),
                          child: Text(
                            (h['severity']?.toString() ?? '—').substring(0,
                                  (h['severity']?.toString().length ?? 4)
                                  .clamp(0, 4)),
                            style: TextStyle(color: sc,
                                fontSize: 7, fontWeight: FontWeight.w800))),
                      ]),
                      if (!closed) ...[
                        const SizedBox(height: 6),
                        if ((h['correctiveAction']?.toString() ?? '').isNotEmpty)
                          Container(
                            padding: const EdgeInsets.all(7),
                            margin: const EdgeInsets.only(bottom: 6),
                            decoration: BoxDecoration(
                              color: AppColors.accent.withOpacity(0.06),
                              borderRadius: BorderRadius.circular(7),
                              border: Border.all(
                                  color: AppColors.accent.withOpacity(0.25))),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                              const Text('🔧 ', style: TextStyle(fontSize: 10)),
                              Expanded(child: Text(
                                'AI suggests: ${h['correctiveAction']}',
                                style: const TextStyle(
                                    color: AppColors.accent,
                                    fontSize: 9, height: 1.4))),
                            ])),
                        Text('Your corrective action / comment:',
                          style: TextStyle(color: sl.text3, fontSize: 10,
                              fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        TextField(
                          controller: ctrl2,
                          maxLines: 2,
                          style: TextStyle(color: sl.text1, fontSize: 12),
                          decoration: InputDecoration(
                            hintText: 'Describe what was done…',
                            hintStyle: TextStyle(color: sl.text4, fontSize: 11),
                            filled: true,
                            fillColor: sl.isDark
                                ? const Color(0xFF1C1F2E)
                                : const Color(0xFFF5F6FA),
                            contentPadding: const EdgeInsets.all(10),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(9),
                              borderSide: BorderSide(
                                  color: sl.border.withOpacity(0.4))),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(9),
                              borderSide: const BorderSide(
                                  color: AppColors.green, width: 2)))),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () {
                              if (ctrl2.text.trim().isEmpty) {
                                ScaffoldMessenger.of(ctx).showSnackBar(
                                  const SnackBar(
                                  content: Text('Add a comment first'),
                                  backgroundColor: Color(0xFFD97706)));
                                return;
                              }
                              setLocal(() {
                                _hazardClosed[i] = true;
                              });
                              setState(() {
                                _hazardClosed[i] = true;
                              });
                              _saveHazardMitigation(i, h, ctrl2.text.trim());
                            },
                            icon: const Icon(Icons.lock_rounded,
                                size: 14, color: Colors.white),
                            label: const Text('Close this hazard',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.green,
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(9))))),
                      ] else ...[
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppColors.green.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: AppColors.green.withOpacity(0.3))),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                            const Icon(Icons.check_circle_outline,
                                color: AppColors.green, size: 14),
                            const SizedBox(width: 6),
                            Expanded(child: Text(
                              ctrl2.text.isNotEmpty
                                  ? ctrl2.text : 'Hazard closed',
                              style: const TextStyle(
                                  color: AppColors.green,
                                  fontSize: 11, height: 1.4))),
                          ])),
                      ],
                    ]));
                })),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                child: Column(children: [
                  if (_hazardClosed.values.every((v) => v) && hazards.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.green.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: AppColors.green.withOpacity(0.4))),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                          Icon(Icons.celebration_rounded,
                              color: AppColors.green, size: 18),
                          SizedBox(width: 8),
                          Text('All hazards mitigated!',
                            style: TextStyle(
                                color: AppColors.green,
                                fontSize: 13,
                                fontWeight: FontWeight.w700)),
                        ]))),
                  Row(children: [
                    Expanded(child: OutlinedButton.icon(
                      onPressed: _openSheetsLink,
                      icon: const Icon(Icons.table_chart_rounded,
                          size: 14, color: AppColors.accent),
                      label: const Text('View in Sheets',
                        style: TextStyle(
                            color: AppColors.accent,
                            fontSize: 12, fontWeight: FontWeight.w700)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(
                            color: AppColors.accent, width: 1.5),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10))),
                    )),
                    const SizedBox(width: 10),
                    Expanded(child: ElevatedButton.icon(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.done_all_rounded,
                          size: 14, color: Colors.white),
                      label: const Text('Done',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 12, fontWeight: FontWeight.w700)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.purple,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10))),
                    )),
                  ]),
                ])),
            ])))));
  }

  Future<void> _saveHazardMitigation(
      int idx, Map<String, dynamic> hazard, String comment) async {
    if (_savedIncidentId == null) return;
    final all = await LocalDB.getIncidents();
    final incIdx = all.indexWhere(
        (i) => i['id']?.toString() == _savedIncidentId);
    if (incIdx < 0) return;

    dynamic rawHazards = all[incIdx]['hazards'];
    List hazards = [];
    if (rawHazards is String) {
      try { hazards = jsonDecode(rawHazards); } catch (_) {}
    } else if (rawHazards is List) {
      hazards = rawHazards;
    }

    if (idx < hazards.length) {
      final updated = Map<String, dynamic>.from(hazards[idx] as Map);
      updated['mitigationComment'] = comment;
      updated['mitigatedAt']       = DateTime.now().toIso8601String();
      updated['mitigated']         = true;
      hazards[idx] = updated;
    }

    all[incIdx]['hazards'] = jsonEncode(hazards);
    final allClosed = _hazardClosed.values.every((v) => v);
    if (allClosed) {
      all[incIdx]['status']   = 'CLOSED';
      all[incIdx]['closedAt'] = DateTime.now().toIso8601String();
    }

    await LocalDB.saveIncident(all[incIdx]);
    SyncService.pushIncident(all[incIdx]).catchError((_) => false);
  }

  Future<void> _openSheetsLink() async {
    final uri = Uri.parse(_sheetUrl);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        _snack('Could not open browser', AppColors.red);
      }
    } catch (e) {
      _snack('Error: $e', AppColors.red);
    }
  }

  Map<String, dynamic> _buildIncident(Map<String, dynamic> user) {
    final hazards        = (_result!['hazards'] as List?) ?? [];
    final firstHazard    = hazards.isNotEmpty
        ? hazards.first['name'] : 'AI Hazard Scan';
    final firstHazardMap = hazards.isNotEmpty
        ? Map<String, dynamic>.from(hazards.first as Map)
        : <String, dynamic>{};
    return {
      'id':              DateTime.now().millisecondsSinceEpoch.toString(),
      'title':           'AI Hazard Scan: ${firstHazard.toString()}',
      'plant':           user['plant']?.toString() ?? 'SAIL Safety Organisation',
      'dept':            user['department']?.toString() ?? '',
      'location':        'AI scan result',
      'severity':        _result!['overallRisk'] ?? 'MEDIUM',
      'wsaCategory':     firstHazardMap['wsaCause']?.toString() ?? 'Multiple causes',
      'obsType':         'N/A',
      'summary':         _result!['summary']?.toString() ?? '',
      'desc':            _result!['summary']?.toString() ?? '',
      'immediateAction': firstHazardMap['correctiveAction']?.toString()
                         ?? 'Investigate per IS 14489:1998',
      'type':            'AI_SCAN',
      'status':          'OPEN',
      'date':            DateTime.now().toIso8601String(),
      'reportedBy':      user['name']?.toString() ?? 'SAIL Safety Officer',
      'reportedByPno':   user['pno']?.toString()  ?? '',
      'people':          '0',
      'hazards':         hazards,
      'riskScore':       _result!['riskScore']    ?? 0,
      'confidence':      _result!['confidence']   ?? 0,
      'imageBase64':     _imageBytes != null
                         ? base64Encode(_imageBytes!) : null,
    };
  }

  Future<void> _uploadPdfBackground(
      Map<String, dynamic> incident, Map<String, dynamic> user) async {
    try {
      final pdfBytes = await PdfExport.generateIncidentReportBytes(
        incident:     incident,
        reporterName: user['name']?.toString() ?? 'SAIL Safety Officer',
        reporterPno:  user['pno']?.toString()  ?? '',
        imageBytes:   _imageBytes,
      );
      if (pdfBytes.isEmpty) return;
      final url = await SyncService.uploadPdfToDrive(
        incidentId: incident['id']?.toString() ?? '',
        pdfBytes:   pdfBytes,
        fileName:   'SafetyLens_${incident['id']}.pdf',
      );
      if (url != null && url.isNotEmpty) {
        await SyncService.pushIncident({
          ...incident, 'pdfUrl': url,
        }).catchError((_) => false);
      }
    } catch (_) {}
  }

  Future<void> _exportPdf() async {
    if (_result == null) return;
    final user     = await LocalDB.getCurrentUser() ?? {};
    final incident = _buildIncident(user);
    try {
      _snack('Generating PDF…', AppColors.accent);
      await PdfExport.downloadOrShareIncident(
        incident:     incident,
        reporterName: user['name']?.toString() ?? 'SAIL Safety Officer',
        reporterPno:  user['pno']?.toString()  ?? '',
        imageBytes:   _imageBytes,
      );
      if (mounted) _snack(
          kIsWeb ? 'PDF downloaded' : 'PDF ready to share',
          AppColors.green);
    } catch (e) {
      if (mounted) _snack('PDF failed: $e', AppColors.red);
    }
  }

  void _reset() {
    for (final c in _mitigationControllers.values) { c.dispose(); }
    _mitigationControllers.clear();
    _hazardClosed.clear();
    setState(() {
      _pickedFile      = null; _imageBytes = null;
      _result          = null; _analyzing  = false;
      _hazardRowKeys.clear(); _highlightedRow = null;
      _isSaved         = false; _savedIncidentId = null;
      _currentStep     = 0;
    });
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontSize: 12)),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      margin: const EdgeInsets.all(12),
    ));
  }

  // ─────────────────────────────────────────────────────────────
  //  BUILD
  // ─────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final sl = SL.of(context);
    return Container(
      color: sl.isDark ? const Color(0xFF1C1F2E) : const Color(0xFFF5F6FA),
      child: SafeArea(child: Column(children: [
        UniversalAppBar(
          title: I18n.t('aiScan.title'),
          subtitle: I18n.t('aiScan.subtitle'),
          user: widget.user,
          toggleTheme: widget.toggleTheme,
          onSignOut: widget.onSignOut,
          isDark: widget.isDark,
        ),
        Expanded(child: SingleChildScrollView(
          controller: _scrollController,
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 80),
          child: _analyzing
              ? _analyzingView()
              : _result != null
                  ? _resultView(sl)
                  : _emptyView(sl),
        )),
      ])));
  }

  Widget _emptyView(SL sl) {
    final cardBg = sl.isDark ? const Color(0xFF252840) : Colors.white;
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
              color: Colors.black.withOpacity(sl.isDark ? 0.2 : 0.04),
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
              style: TextStyle(color: sl.text1, fontSize: 14,
                  fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('AI detects hazards & marks them on photo',
              style: TextStyle(color: sl.text4, fontSize: 11)),
            const SizedBox(height: 12),
            Wrap(spacing: 6, runSpacing: 4, children: [
              _featureTag('🎯 Bbox mapping', sl),
              _featureTag('⚖️ IS 14489', sl),
              _featureTag('🏭 WSA 13', sl),
              _featureTag('📋 PDF export', sl),
              _featureTag('📊 Sheets sync', sl),
            ]),
          ])),
      ),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: ElevatedButton.icon(
          onPressed: () => _pickImage(ImageSource.camera),
          icon: const Icon(Icons.camera_alt, size: 14, color: Colors.white),
          label: const Text('Camera', style: TextStyle(
              color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.accent,
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: const BorderSide(color: AppColors.accentDark, width: 2))),
        )),
        const SizedBox(width: 8),
        Expanded(child: OutlinedButton.icon(
          onPressed: () => _pickImage(ImageSource.gallery),
          icon: const Icon(Icons.photo_library,
              size: 14, color: AppColors.accent),
          label: const Text('Gallery', style: TextStyle(
              color: AppColors.accent, fontSize: 12,
              fontWeight: FontWeight.w600)),
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: AppColors.accent, width: 2),
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10))),
        )),
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
      border: Border.all(color: AppColors.accent.withOpacity(0.2))),
    child: Text(label, style: const TextStyle(
        color: AppColors.accent, fontSize: 9,
        fontWeight: FontWeight.w600)));

  Widget _analyzingView() => Container(
    height: 160,
    decoration: BoxDecoration(
      color: const Color(0xFF252840),
      borderRadius: BorderRadius.circular(12),
      image: _imageBytes != null ? DecorationImage(
          image: MemoryImage(_imageBytes!),
          fit: BoxFit.cover) : null),
    child: Container(
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.55),
        borderRadius: BorderRadius.circular(12)),
      child: Center(child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
        const CircularProgressIndicator(strokeWidth: 3,
          valueColor: AlwaysStoppedAnimation<Color>(AppColors.accent)),
        const SizedBox(height: 10),
        Text(_step, style: const TextStyle(
          color: Colors.white, fontSize: 12,
          fontWeight: FontWeight.w600)),
      ]))));

  Widget _resultView(SL sl) {
    final overallRisk = _result!['overallRisk']?.toString() ?? 'MEDIUM';
    final score       = _result!['riskScore']    ?? 50;
    final confidence  = _result!['confidence']   ?? 75;
    final summary     = _result!['summary']?.toString() ?? '';
    final hazards     = (_result!['hazards'] as List?) ?? [];
    final riskColor   = _sevColor(overallRisk);
    final hasBbox     = hazards.any((h) => (h as Map)['bbox'] != null);
    final cardBg      = sl.isDark ? const Color(0xFF252840) : Colors.white;

    return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [

      if (_isSaved) Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.green.withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.green.withOpacity(0.4))),
        child: Row(children: [
          const Icon(Icons.check_circle_outline,
              color: AppColors.green, size: 16),
          const SizedBox(width: 8),
          const Expanded(child: Text('Saved & synced to Sheets',
            style: TextStyle(color: AppColors.green,
                fontSize: 11, fontWeight: FontWeight.w600))),
          GestureDetector(
            onTap: _openSheetsLink,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.green,
                borderRadius: BorderRadius.circular(6)),
              child: const Text('View Sheet →',
                style: TextStyle(color: Colors.white,
                    fontSize: 10, fontWeight: FontWeight.w700)))),
        ])),

      if (_imageBytes != null) ...[
        // ✅ FIX: cap display height + add pinch-to-zoom.
        // Previously the image filled entire desktop viewport with no max
        // height, and BoxFit.cover cropped off bounding boxes near edges.
        // Now: capped at 45% of screen height, fits without cropping,
        // pinch/scroll to zoom (max 4×) to inspect bounding-box details.
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.45,
            ),
            child: hasBbox
              ? InteractiveViewer(
                  maxScale: 4.0,
                  minScale: 0.8,
                  boundaryMargin: const EdgeInsets.all(20),
                  child: HazardAnnotatedImage(
                    imageBytes: _imageBytes!,
                    hazards: hazards,
                    onHazardTap: _onBboxTap),
                )
              : InteractiveViewer(
                  maxScale: 4.0,
                  child: Image.memory(_imageBytes!,
                      width: double.infinity,
                      fit: BoxFit.contain),
                ),
          ),
        ),
        const SizedBox(height: 10),
      ],

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
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text('Tap boxes on image → jumps to row',
                  style: TextStyle(color: AppColors.accent,
                      fontSize: 9, fontStyle: FontStyle.italic))),
          ])),
        ])),
      const SizedBox(height: 10),

      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cardBg,
          border: Border.all(color: sl.border.withOpacity(0.4)),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(
            color: Colors.black.withOpacity(sl.isDark ? 0.15 : 0.04),
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

      _hazardTable(hazards, sl),
      const SizedBox(height: 12),

      Row(children: [
        Expanded(child: ElevatedButton.icon(
          onPressed: _result != null
              ? (_isSaved ? null : _openReviewSheet) : null,
          icon: const Icon(Icons.fact_check_outlined,
              size: 14, color: Colors.white),
          label: const Text('Review',
              style: TextStyle(color: Colors.white,
                  fontSize: 12, fontWeight: FontWeight.w700)),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.amber,
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10))),
        )),
        const SizedBox(width: 8),
        Expanded(child: ElevatedButton.icon(
          onPressed: _isSaved ? null : _save,
          icon: Icon(_isSaved ? Icons.check_rounded : Icons.save_outlined,
              size: 14, color: Colors.white),
          label: Text(_isSaved ? 'Saved ✓' : 'Save',
              style: const TextStyle(color: Colors.white,
                  fontSize: 12, fontWeight: FontWeight.w700)),
          style: ElevatedButton.styleFrom(
            backgroundColor: _isSaved ? Colors.grey : AppColors.green,
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
          icon: const Icon(Icons.refresh, size: 14, color: AppColors.accent),
          label: const Text('New',
              style: TextStyle(color: AppColors.accent,
                  fontSize: 12, fontWeight: FontWeight.w700)),
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: AppColors.accent, width: 2),
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10))),
        )),
      ]),

      if (_isSaved) ...[
        const SizedBox(height: 8),
        SizedBox(width: double.infinity, child: ElevatedButton.icon(
          onPressed: _openMitigateSheet,
          icon: const Icon(Icons.engineering_rounded,
              size: 14, color: Colors.white),
          label: const Text('Mitigate Hazards',
              style: TextStyle(color: Colors.white,
                  fontSize: 12, fontWeight: FontWeight.w700)),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.purple,
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10))),
        )),
      ],
    ]);
  }

  Widget _hazardTable(List hazards, SL sl) {
    final cardBg = sl.isDark ? const Color(0xFF252840) : Colors.white;
    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        border: Border.all(color: sl.border.withOpacity(0.4)),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(
          color: Colors.black.withOpacity(sl.isDark ? 0.15 : 0.04),
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
            Text('HAZARD ANALYSIS', style: TextStyle(
              color: sl.text4, fontSize: 10,
              fontWeight: FontWeight.w700, letterSpacing: 0.9)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(99),
                border: Border.all(color: AppColors.red.withOpacity(0.3))),
              child: Text('${hazards.length} hazards',
                style: const TextStyle(color: AppColors.red,
                    fontSize: 9, fontWeight: FontWeight.w700))),
          ])),
        Table(
          border: TableBorder(
            horizontalInside: BorderSide(
                color: sl.border.withOpacity(0.4), width: 0.5)),
          columnWidths: const {
            0: FlexColumnWidth(2.0),
            1: FlexColumnWidth(2.8),
            2: FlexColumnWidth(2.0),
            3: FlexColumnWidth(1.2),
            4: FlexColumnWidth(2.8),
          },
          children: [
          TableRow(
            decoration: BoxDecoration(
              color: sl.isDark
                  ? const Color(0xFF2A2D42)
                  : const Color(0xFFF0F1F5)),
            children: [
              _hth('HAZARD', sl), _hth('DESCRIPTION', sl),
              _hth('REGULATION', sl),
              _hth('SEVERITY', sl, center: true),
              _hth('ACTION', sl),
            ]),
          ...hazards.asMap().entries.map((entry) {
            final i   = entry.key;
            final h   = entry.value;
            final hm  = Map<String, dynamic>.from(h as Map);
            final sev = (hm['severity'] ?? 'MEDIUM').toString();
            final isH = _highlightedRow == i;
            final color = _sevColor(sev);
            return TableRow(
              decoration: BoxDecoration(
                color: isH ? color.withOpacity(0.1) : Colors.transparent),
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
                      margin: const EdgeInsets.only(right: 5, top: 1),
                      decoration: BoxDecoration(
                          color: color, shape: BoxShape.circle),
                      child: Center(child: Text('${i+1}',
                        style: const TextStyle(
                          color: Colors.white, fontSize: 8,
                          fontWeight: FontWeight.w900)))),
                    Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                      Text(hm['name']?.toString() ?? '',
                        style: TextStyle(color: sl.text1,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w600,
                          height: 1.4)),
                      if (hm['type'] != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            hm['type'].toString(),
                            style: TextStyle(
                                color: sl.text4, fontSize: 8))),
                    ])),
                  ])),
                _htd(hm['description']?.toString() ?? '', sl),
                _htd(hm['regulation']?.toString()  ?? '', sl),
                Padding(
                  padding: const EdgeInsets.all(7),
                  child: Center(child: _sevPill(sev, color))),
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

  Color _sevColor(String sev) {
    switch (sev.toUpperCase()) {
      case 'CRITICAL': return AppColors.crit;
      case 'HIGH':     return AppColors.red;
      case 'MEDIUM':   return AppColors.cyan;
      case 'LOW':      return AppColors.green;
      default:         return AppColors.amber;
    }
  }

  Widget _infoBox(SL sl) {
    final cardBg = sl.isDark ? const Color(0xFF252840) : Colors.white;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cardBg,
        border: Border.all(color: AppColors.accent.withOpacity(0.35)),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(
          color: Colors.black.withOpacity(sl.isDark ? 0.15 : 0.04),
          blurRadius: 6, offset: const Offset(0, 2))]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
        Row(children: [
          const Icon(Icons.info_outline_rounded,
              size: 14, color: AppColors.accent),
          const SizedBox(width: 6),
          Text('How AI Hazard Scan works',
            style: TextStyle(color: sl.text1, fontSize: 12,
                fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 8),
        _infoRow('1.', 'Capture: take a workplace photo', sl),
        _infoRow('2.', 'AI Scan: Gemini detects all hazards', sl),
        _infoRow('3.', 'Review: see all hazards & regulations', sl),
        _infoRow('4.', 'Save: stores to device + Google Sheets', sl),
        _infoRow('5.', 'Mitigate: add action per hazard & close', sl),
      ]));
  }

  Widget _infoRow(String icon, String text, SL sl) => Padding(
    padding: const EdgeInsets.only(bottom: 5),
    child: Row(children: [
      Text(icon, style: const TextStyle(fontSize: 12)),
      const SizedBox(width: 8),
      Expanded(child: Text(text, style: TextStyle(
          color: sl.text2, fontSize: 11, height: 1.4))),
    ]));
}
