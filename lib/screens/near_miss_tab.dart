// lib/screens/near_miss_tab.dart
//
// ✅ Infographic header (matches AI Scan tab style)
// ✅ Duplicate submission detection (same location + title within 5 min)
// ✅ Neutral background — #1C1F2E dark / #F5F6FA light (no pure black)
// ✅ Sheets sync confirmed on submit with snackbar
// ✅ All 6 original voice input bug fixes preserved
// ✅ All original form fields, validation, AI pre-fill preserved

import 'dart:convert';
import 'dart:io' show File;
import 'package:flutter/foundation.dart' show kIsWeb, Uint8List;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../main.dart';
import '../services/gemini_vision.dart';
import '../services/local_db.dart';
import '../services/pdf_export.dart';
import '../services/sync_service.dart';

class NearMissTab extends StatefulWidget {
  const NearMissTab({super.key});
  @override
  State<NearMissTab> createState() => _NearMissTabState();
}

class _NearMissTabState extends State<NearMissTab> {
  XFile?     _pickedFile;
  Uint8List? _imageBytes;
  bool       _analyzing = false;
  String     _step      = '';
  Map<String, dynamic>? _aiBrief;

  final _brief           = TextEditingController();
  final _dept            = TextEditingController();
  final _location        = TextEditingController();
  final _people          = TextEditingController();
  final _description     = TextEditingController();
  final _immediateAction = TextEditingController();

  String _plant   = 'SAIL Safety Organisation';
  String _wsaCause = 'Slip / Fall';
  String _severity = 'MEDIUM';
  String _obsType  = 'Unsafe Condition';

  // ── Duplicate detection ───────────────────────────────────────
  // Stores key of last submission: "location|title|timestamp(minute)"
  String? _lastSubmissionKey;

  // ─── VOICE INPUT (all 6 original bug fixes preserved) ─────────
  final stt.SpeechToText _speech         = stt.SpeechToText();
  bool                   _speechAvailable = false;
  bool                   _isListening     = false;
  TextEditingController? _activeMicField;

  static const Map<String, String> _voiceLocaleMap = {
    'en': 'en-IN', 'hi': 'hi-IN', 'bn': 'bn-IN', 'or': 'or-IN',
  };

  String get _voiceLocaleId {
    final lang = LocaleService().locale.languageCode;
    return _voiceLocaleMap[lang] ?? 'en-IN';
  }

  String get _voiceLanguageName {
    final lang = LocaleService().locale.languageCode;
    return {'en': 'English', 'hi': 'हिंदी',
            'bn': 'বাংলা',   'or': 'ଓଡ଼ିଆ'}[lang] ?? 'English';
  }

  @override
  void initState() {
    super.initState();
    _initSpeech();
  }

  Future<void> _initSpeech() async {
    try {
      _speechAvailable = await _speech.initialize(
        onError: (e) {
          debugPrint('Speech error: ${e.errorMsg}');
          if (mounted) setState(() => _isListening = false);
        },
        onStatus: (s) {
          debugPrint('Speech status: $s');
          if (s == 'done' && _isListening && _activeMicField != null) {
            _restartListening();
          } else if (s == 'notListening') {
            if (mounted) setState(() => _isListening = false);
          }
        },
      );
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Speech init error: $e');
    }
  }

  Future<void> _restartListening() async {
    if (!_isListening || _activeMicField == null) return;
    final field    = _activeMicField!;
    final baseText = field.text;
    try {
      await _speech.listen(
        onResult: (result) {
          if (!mounted || _activeMicField != field) return;
          final appended = result.recognizedWords.isEmpty
              ? baseText
              : '$baseText ${result.recognizedWords}'.trim();
          setState(() {
            field.text      = appended;
            field.selection = TextSelection.fromPosition(
                TextPosition(offset: field.text.length));
          });
        },
        localeId:     _voiceLocaleId,
        listenFor:    const Duration(seconds: 30),
        pauseFor:     const Duration(seconds: 5),
        partialResults: true,
        cancelOnError:  false,
        listenMode:   stt.ListenMode.dictation,
      );
    } catch (e) {
      debugPrint('Restart listen error: $e');
      if (mounted) setState(() => _isListening = false);
    }
  }

  Future<void> _toggleVoice([TextEditingController? field]) async {
    final targetField = field ?? _location;

    if (_isListening && _activeMicField == targetField) {
      await _speech.stop();
      setState(() { _isListening = false; _activeMicField = null; });
      return;
    }

    if (_isListening) {
      await _speech.stop();
      setState(() { _isListening = false; _activeMicField = null; });
      await Future.delayed(const Duration(milliseconds: 200));
    }

    if (!_speechAvailable) {
      await _initSpeech();
      if (!_speechAvailable) {
        if (mounted) {
          _snack(
            kIsWeb
                ? 'Voice input requires Chrome. Allow microphone access.'
                : 'Microphone unavailable. Check app permissions in Settings.',
            AppColors.amber);
        }
        return;
      }
    }

    final baseText    = targetField.text;
    _activeMicField   = targetField;

    try {
      setState(() => _isListening = true);
      await _speech.listen(
        onResult: (result) {
          if (!mounted || _activeMicField != targetField) return;
          final words = result.recognizedWords;
          if (words.isEmpty) return;
          final appended = baseText.isEmpty ? words : '$baseText $words';
          setState(() {
            targetField.text      = appended.trim();
            targetField.selection = TextSelection.fromPosition(
                TextPosition(offset: targetField.text.length));
          });
        },
        localeId:      _voiceLocaleId,
        listenFor:     const Duration(seconds: 30),
        pauseFor:      const Duration(seconds: 5),
        partialResults: true,
        cancelOnError:  false,
        listenMode:    stt.ListenMode.dictation,
      );
    } catch (e) {
      debugPrint('Listen error: $e');
      if (mounted) setState(() { _isListening = false; _activeMicField = null; });
    }
  }

  @override
  void dispose() {
    _speech.cancel();
    _brief.dispose(); _dept.dispose(); _location.dispose();
    _people.dispose(); _description.dispose(); _immediateAction.dispose();
    super.dispose();
  }

  // ─── DATA ─────────────────────────────────────────────────────
  final _plants = const [
    'BSP Bhilai', 'DSP Durgapur', 'RSP Rourkela',
    'BSL Bokaro', 'ISP Burnpur', 'SAIL Safety Organisation',
  ];
  final _wsaCauses = const [
    'Burn / Fire', 'Chemical', 'Electrical', 'Fall from Height',
    'Fall of Material', 'Gas Related', 'Hit / Caught / Pressed',
    'Hot Metal / Slag / Sub', 'Machine / Equipment',
    'Material Handling', 'Road / Rail', 'Slip / Fall', 'Other',
  ];

  // ─── IMAGE + AI ───────────────────────────────────────────────
  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
        source: source, imageQuality: 85);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    setState(() {
      _pickedFile = picked; _imageBytes = bytes;
      _analyzing = true; _aiBrief = null;
    });
    await _analyzeImage();
  }

  Future<void> _analyzeImage() async {
    final steps = ['Uploaded', 'Analyzing image…',
                   'Classifying hazard…', 'Pre-filling form…'];
    for (var i = 0; i < steps.length - 1; i++) {
      setState(() => _step = steps[i]);
      await Future.delayed(const Duration(milliseconds: 700));
    }
    try {
      setState(() => _step = steps.last);
      Map<String, dynamic>? result;
      result = kIsWeb
          ? await GeminiVision.analyseImageBytes(_imageBytes!)
          : await GeminiVision.analyseImage(File(_pickedFile!.path));

      final hazards = (result?['hazards'] as List?) ?? [];
      final first   = hazards.isNotEmpty
          ? Map<String, dynamic>.from(hazards.first) : null;

      final name      = first?['name']?.toString()            ?? 'Near miss observed';
      final desc      = first?['description']?.toString()     ?? result?['summary']?.toString() ?? '';
      final action    = first?['correctiveAction']?.toString() ?? '';
      final regulation= first?['regulation']?.toString()      ?? '';
      final sev       = (first?['severity']?.toString()       ?? 'MEDIUM').toUpperCase();
      final hazardType= first?['type']?.toString()            ?? 'Unsafe Condition';
      final wsaCause  = _mapToWsaCause(
          first?['category']?.toString() ?? '', name);

      final user            = await LocalDB.getCurrentUser();
      String plantFromProfile = user?['plant']?.toString() ?? _plant;
      if (!_plants.contains(plantFromProfile)) plantFromProfile = _plant;

      setState(() {
        _aiBrief = {
          'identified': name,
          'statutory':  regulation.isEmpty
              ? 'Refer Factories Act §35-41' : regulation,
          'type':       hazardType,
          'severity':   sev,
          'confidence': result?['confidence'] ?? 75,
        };
        _brief.text           = '$name. $desc'.trim();
        _description.text     = desc;
        _immediateAction.text = action;
        _dept.text            = user?['department']?.toString() ?? 'Operations';
        _location.text        = 'To be confirmed (edit if needed)';
        _people.text          = '1';
        _plant                = plantFromProfile;
        _wsaCause             = wsaCause;
        _severity             = sev;
        _obsType              = hazardType.toLowerCase().contains('act')
            ? 'Unsafe Act' : 'Unsafe Condition';
        _analyzing            = false;
      });
    } catch (e) {
      setState(() {
        _aiBrief = {
          'identified': 'Manual entry — AI offline',
          'statutory':  'Manual entry needed',
          'type':       'Unsafe condition',
          'severity':   'MEDIUM',
          'confidence': 0,
        };
        _brief.text = 'Describe the near miss observed.';
        _analyzing  = false;
      });
    }
  }

  String _mapToWsaCause(String category, String name) {
    final c = category.toUpperCase();
    final n = name.toLowerCase();
    if (c == 'HEIGHT'    || n.contains('fall') || n.contains('height'))  return 'Fall from Height';
    if (c == 'ELECTRICAL'|| n.contains('electric'))                      return 'Electrical';
    if (c == 'HOT_WORK'  || n.contains('hot')  || n.contains('weld'))   return 'Burn / Fire';
    if (c == 'GAS'       || n.contains('gas'))                           return 'Gas Related';
    if (c == 'MACHINERY' || n.contains('machine') || n.contains('crane'))return 'Machine / Equipment';
    if (c == 'HOUSEKEEPING'|| n.contains('spill') || n.contains('slip')) return 'Slip / Fall';
    return 'Other';
  }

  // ─── DUPLICATE DETECTION ─────────────────────────────────────
  // Key = "plant|location|title_prefix" — if same within session → warn
  String _buildSubmissionKey() {
    final title = (_aiBrief?['identified']?.toString()
        ?? _brief.text.split('.').first).trim().toLowerCase();
    final loc   = _location.text.trim().toLowerCase();
    final now   = DateTime.now();
    // Minute-level bucket — same submission within ~5 min = duplicate
    final bucket = '${now.year}${now.month}${now.day}${now.hour}${now.minute ~/ 5}';
    return '${_plant}|$loc|$title|$bucket';
  }

  Future<bool> _checkDuplicate() async {
    final key = _buildSubmissionKey();

    // Session-level: exact same key
    if (_lastSubmissionKey == key) {
      _snack('This report appears to be a duplicate. '
          'Wait a moment or change the location/description.',
          const Color(0xFFD97706));
      return true; // is duplicate
    }

    // DB-level: check for very similar entries in last 10 minutes
    final existing = await LocalDB.getIncidents();
    final tenMinAgo = DateTime.now().subtract(const Duration(minutes: 10));
    final loc   = _location.text.trim().toLowerCase();
    final plant = _plant.toLowerCase();

    final found = existing.where((inc) {
      try {
        final incDate = DateTime.parse(inc['date']?.toString() ?? '');
        if (incDate.isBefore(tenMinAgo)) return false;
      } catch (_) { return false; }
      final incLoc   = inc['location']?.toString().toLowerCase() ?? '';
      final incPlant = inc['plant']?.toString().toLowerCase()    ?? '';
      final incType  = inc['type']?.toString() ?? '';
      return incType == 'NEAR_MISS'
          && incPlant == plant
          && incLoc == loc;
    }).toList();

    if (found.isNotEmpty) {
      if (!mounted) return true;
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
            Text('Possible Duplicate',
              style: TextStyle(fontSize: 16,
                  fontWeight: FontWeight.w700)),
          ]),
          content: Text(
            'A near miss from the same location '
            '(${_location.text.trim()}) was already reported '
            'in the last 10 minutes.\n\n'
            'Are you sure you want to submit another report?',
            style: const TextStyle(fontSize: 13, height: 1.5)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel',
                  style: TextStyle(color: Colors.grey))),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFD97706)),
              child: const Text('Submit Anyway',
                  style: TextStyle(color: Colors.white,
                      fontWeight: FontWeight.w700))),
          ]));
      return confirm != true; // true = is duplicate (user cancelled)
    }
    return false; // not a duplicate
  }

  // ─── SUBMIT ───────────────────────────────────────────────────
  Future<bool> _submit({bool exportAfter = false}) async {
    // Validate location
    final loc = _location.text.trim();
    if (loc.isEmpty || loc == 'To be confirmed (edit if needed)') {
      _snack('Please enter the actual location', AppColors.red);
      return false;
    }

    // Duplicate check
    final isDuplicate = await _checkDuplicate();
    if (isDuplicate) return false;

    final user = await LocalDB.getCurrentUser();
    final incident = {
      'id':              DateTime.now().millisecondsSinceEpoch.toString(),
      'title':           _aiBrief?['identified']?.toString()
                         ?? _brief.text.split('.').first.trim(),
      'plant':           _plant,
      'dept':            _dept.text.trim(),
      'location':        loc,
      'severity':        _severity,
      'wsaCategory':     _wsaCause,
      'obsType':         _obsType,
      'desc':            '${_brief.text}\n\n${_description.text}'.trim(),
      'people':          _people.text.trim(),
      'immediateAction': _immediateAction.text.trim(),
      'type':            'NEAR_MISS',
      'status':          'OPEN',
      'reportedBy':      user?['name']   ?? 'Unknown',
      'reportedByPno':   user?['pno']    ?? '',
      'date':            DateTime.now().toIso8601String(),
      'imageBase64':     _imageBytes != null
                         ? base64Encode(_imageBytes!) : null,
    };

    // Save to LocalDB
    await LocalDB.saveIncident(incident);

    // Push to Google Sheets — fire and forget with error catch
    final synced = await SyncService.pushIncident(incident)
        .catchError((_) => false);

    // Remember submission key to detect session-level duplicates
    _lastSubmissionKey = _buildSubmissionKey();

    // Export PDF if requested
    if (exportAfter) {
      try {
        await PdfExport.downloadOrShareIncident(
          incident:    incident,
          reporterName: user?['name']?.toString() ?? 'SAIL Safety Officer',
          reporterPno:  user?['pno']?.toString()  ?? '',
          imageBytes:  _imageBytes,
        );
      } catch (e) {
        if (mounted) _snack('PDF export failed: $e', AppColors.red);
      }
    }

    if (mounted) {
      final syncMsg = synced == true
          ? ' · synced to Google Sheets ✓'
          : ' · will sync when online';
      _snack(
        exportAfter
            ? 'Near Miss saved + PDF exported$syncMsg'
            : 'Near Miss submitted$syncMsg',
        AppColors.green);

      // Clear form
      setState(() {
        _pickedFile = null; _imageBytes = null; _aiBrief = null;
        _brief.clear(); _dept.clear(); _location.clear();
        _people.clear(); _description.clear(); _immediateAction.clear();
      });
    }
    return true;
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontSize: 12)),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10)),
      margin: const EdgeInsets.all(12),
      duration: const Duration(seconds: 3),
    ));
  }

  // ─────────────────────────────────────────────────────────────
  //  BUILD
  // ─────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final sl = SL.of(context);
    return Container(
      // Neutral background — not pure black
      color: sl.isDark
          ? const Color(0xFF1C1F2E)
          : const Color(0xFFF5F6FA),
      child: SafeArea(
        child: Column(children: [
          _buildTopBar(sl),
          Expanded(child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 80),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _guidanceBox(sl),
                _imageSection(sl),
                _detailsSection(sl),
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(child: _submitBtn(
                    label: 'Save Report',
                    icon:  Icons.save_outlined,
                    colors: const [Color(0xFF16A34A), Color(0xFF059669)],
                    onTap: () => _submit(exportAfter: false),
                  )),
                  const SizedBox(width: 10),
                  Expanded(child: _submitBtn(
                    label: 'Save + PDF',
                    icon:  Icons.picture_as_pdf,
                    colors: const [AppColors.accent, AppColors.cyan],
                    onTap: () => _submit(exportAfter: true),
                  )),
                ]),
              ],
            ),
          )),
        ]),
      ),
    );
  }

  // ─── INFOGRAPHIC TOP BAR ──────────────────────────────────────
  Widget _buildTopBar(SL sl) {
    final cardBg = sl.isDark ? const Color(0xFF252840) : Colors.white;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: BoxDecoration(
        color: cardBg,
        border: Border(bottom: BorderSide(
            color: sl.border.withOpacity(0.35)))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: AppColors.amber.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.warning_amber_rounded,
                color: AppColors.amber, size: 20)),
          const SizedBox(width: 10),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Near Miss Report', style: TextStyle(
                  color: sl.text1, fontSize: 16,
                  fontWeight: FontWeight.w800)),
              Text('No-blame · Safety first · WSA 13 causes',
                style: TextStyle(color: sl.text4, fontSize: 9)),
            ])),
          // Voice language indicator
          if (_speechAvailable)
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.accent.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: AppColors.accent.withOpacity(0.3))),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.mic_none_rounded,
                    size: 11, color: AppColors.accent),
                const SizedBox(width: 4),
                Text(_voiceLanguageName, style: const TextStyle(
                    color: AppColors.accent, fontSize: 10,
                    fontWeight: FontWeight.w600)),
              ])),
        ]),
        const SizedBox(height: 10),
        // Workflow steps
        Row(children: [
          _stepChip('1', 'Photo',    AppColors.accent, sl),
          _arrow(sl),
          _stepChip('2', 'Details',  AppColors.amber,  sl),
          _arrow(sl),
          _stepChip('3', 'Submit',   AppColors.green,  sl),
          _arrow(sl),
          _stepChip('4', 'Sheets',   AppColors.cyan,   sl),
          _arrow(sl),
          _stepChip('5', 'Close',    AppColors.purple, sl),
        ]),
      ]));
  }

  Widget _stepChip(String num, String label, Color color, SL sl) =>
    Column(children: [
      Container(
        width: 20, height: 20,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withOpacity(0.12),
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

  // ─── GUIDANCE BOX ─────────────────────────────────────────────
  Widget _guidanceBox(SL sl) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(11),
    decoration: BoxDecoration(
      color: AppColors.amber.withOpacity(0.07),
      border: Border.all(color: AppColors.amber.withOpacity(0.5)),
      borderRadius: BorderRadius.circular(11)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Row(children: [
        Icon(Icons.info_outline, size: 12, color: AppColors.amber),
        SizedBox(width: 5),
        Text('Reporting guidance', style: TextStyle(
            color: AppColors.amber, fontSize: 11,
            fontWeight: FontWeight.w700)),
      ]),
      const SizedBox(height: 5),
      Text(
        'A near miss is an unplanned event that did NOT result in '
        'injury but had the potential to do so. '
        'Report freely — no blame, only learning.',
        style: TextStyle(color: sl.text2, fontSize: 10, height: 1.5)),
    ]));

  // ─── IMAGE SECTION ────────────────────────────────────────────
  Widget _imageSection(SL sl) {
    final cardBg = sl.isDark ? const Color(0xFF252840) : Colors.white;
    return Container(
      padding: const EdgeInsets.all(14),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: cardBg,
        border: Border.all(color: sl.border.withOpacity(0.4)),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(
          color: Colors.black.withOpacity(sl.isDark ? 0.15 : 0.04),
          blurRadius: 8, offset: const Offset(0, 2))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _stepLabel('1', 'Image evidence (optional)', sl),
        const SizedBox(height: 10),
        if (_imageBytes == null && !_analyzing) _emptyImage(sl),
        if (_analyzing) _analyzingImage(),
        if (_imageBytes != null && !_analyzing && _aiBrief != null)
          _imageWithBrief(sl),
      ]));
  }

  Widget _emptyImage(SL sl) => Column(children: [
    GestureDetector(
      onTap: () => _pickImage(ImageSource.camera),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(
              color: AppColors.accent.withOpacity(0.3), width: 2),
          borderRadius: BorderRadius.circular(12)),
        child: Column(children: [
          Container(
            width: 48, height: 48,
            decoration: BoxDecoration(
              color: AppColors.accent.withOpacity(0.1),
              shape: BoxShape.circle),
            child: const Icon(Icons.camera_alt_outlined,
                size: 26, color: AppColors.accent)),
          const SizedBox(height: 8),
          Text('Add photo of hazard', style: TextStyle(
              color: sl.text1, fontSize: 12,
              fontWeight: FontWeight.w600)),
          const SizedBox(height: 3),
          Text('AI identifies hazard & pre-fills form',
            style: TextStyle(color: sl.text4, fontSize: 9)),
        ])),
    ),
    const SizedBox(height: 10),
    Row(children: [
      Expanded(child: ElevatedButton.icon(
        onPressed: () => _pickImage(ImageSource.camera),
        icon: const Icon(Icons.camera_alt,
            size: 14, color: Colors.white),
        label: const Text('Capture', style: TextStyle(
            color: Colors.white, fontSize: 12,
            fontWeight: FontWeight.w600)),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.accent,
          padding: const EdgeInsets.symmetric(vertical: 11),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10))),
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
          side: const BorderSide(
              color: AppColors.accent, width: 2),
          padding: const EdgeInsets.symmetric(vertical: 11),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10))),
      )),
    ]),
  ]);

  Widget _analyzingImage() => Container(
    height: 130,
    decoration: BoxDecoration(
      color: const Color(0xFF252840),
      borderRadius: BorderRadius.circular(10),
      image: _imageBytes != null
          ? DecorationImage(
              image: MemoryImage(_imageBytes!),
              fit: BoxFit.cover) : null),
    child: Container(
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.5),
        borderRadius: BorderRadius.circular(10)),
      child: Center(child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(width: 28, height: 28,
            child: CircularProgressIndicator(
                strokeWidth: 3,
                color: AppColors.accent)),
          const SizedBox(height: 8),
          Text(_step, style: const TextStyle(
              color: Colors.white, fontSize: 11,
              fontWeight: FontWeight.w600)),
        ]))));

  Widget _imageWithBrief(SL sl) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.memory(_imageBytes!,
            height: 130, fit: BoxFit.cover)),
      const SizedBox(height: 10),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.purple.withOpacity(0.08),
          border: Border.all(
              color: AppColors.purple.withOpacity(0.4), width: 1.5),
          borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.auto_awesome, size: 12,
                color: Color(0xFFC4B5FD)),
            const SizedBox(width: 4),
            const Text('AI assessment', style: TextStyle(
                color: Color(0xFFC4B5FD), fontSize: 11,
                fontWeight: FontWeight.w700)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.amber.withOpacity(0.15),
                border: Border.all(color: AppColors.amber),
                borderRadius: BorderRadius.circular(8)),
              child: Text(
                '${_aiBrief!['severity']} · ${_aiBrief!['confidence']}%',
                style: const TextStyle(color: AppColors.amber,
                    fontSize: 8, fontWeight: FontWeight.w800))),
          ]),
          const SizedBox(height: 8),
          _briefRow('Identified', _aiBrief!['identified'].toString(), sl),
          _briefRow('Statutory',  _aiBrief!['statutory'].toString(),  sl),
          _briefRow('Type',       _aiBrief!['type'].toString(),       sl),
          const SizedBox(height: 8),
          Text('AI brief (editable):', style: TextStyle(
              color: sl.text3, fontSize: 10,
              fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          TextField(
            controller: _brief,
            maxLines: 4,
            style: TextStyle(color: sl.text1,
                fontSize: 11, height: 1.5),
            decoration: InputDecoration(
              filled: true,
              fillColor: sl.isDark
                  ? const Color(0xFF1C1F2E)
                  : const Color(0xFFF5F6FA),
              contentPadding: const EdgeInsets.all(10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                    color: sl.border, width: 1.5)),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(
                    color: AppColors.accent, width: 2)),
            )),
          const SizedBox(height: 6),
          Text('Edit any field directly above',
            textAlign: TextAlign.center,
            style: TextStyle(color: sl.text4, fontSize: 9)),
        ])),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: () => setState(() {
          _pickedFile = null; _imageBytes = null;
          _aiBrief = null; _brief.clear();
        }),
        icon: const Icon(Icons.delete_outline,
            size: 14, color: AppColors.accent),
        label: const Text('Remove image',
            style: TextStyle(color: AppColors.accent,
                fontWeight: FontWeight.w600)),
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: AppColors.accent, width: 1.5),
          padding: const EdgeInsets.symmetric(vertical: 10),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10)))),
    ]);

  Widget _briefRow(String k, String v, SL sl) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(width: 76, child: Text(k, style: TextStyle(
          color: sl.text4, fontSize: 9, fontWeight: FontWeight.w700))),
      Expanded(child: Text(v, style: TextStyle(
          color: sl.text1, fontSize: 10, height: 1.4))),
    ]));

  // ─── DETAILS SECTION ──────────────────────────────────────────
  Widget _detailsSection(SL sl) {
    final cardBg  = sl.isDark ? const Color(0xFF252840) : Colors.white;
    final hasImage = _imageBytes != null && _aiBrief != null;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardBg,
        border: Border.all(color: sl.border.withOpacity(0.4)),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(
          color: Colors.black.withOpacity(sl.isDark ? 0.15 : 0.04),
          blurRadius: 8, offset: const Offset(0, 2))]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
        _stepLabel('2', 'Incident details', sl),
        if (hasImage) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.green.withOpacity(0.08),
              border: Border.all(
                  color: AppColors.green.withOpacity(0.35)),
              borderRadius: BorderRadius.circular(8)),
            child: const Row(children: [
              Icon(Icons.auto_awesome,
                  color: AppColors.green, size: 13),
              SizedBox(width: 6),
              Expanded(child: Text(
                'Fields auto-filled from AI. Review and edit as needed.',
                style: TextStyle(color: AppColors.green,
                    fontSize: 10, fontWeight: FontWeight.w600,
                    height: 1.4))),
            ])),
        ],
        const SizedBox(height: 12),

        _lbl('Plant', sl),
        _dropdown(_plant, _plants,
            (v) => setState(() => _plant = v ?? _plant), sl),
        const SizedBox(height: 10),

        _lbl('Department', sl),
        _txt(_dept, hint: 'e.g. Rolling Mill, BF, Coke Oven', sl: sl),
        const SizedBox(height: 10),

        _lbl('Exact location *', sl),
        Row(children: [
          Expanded(child: _txt(_location,
              hint: 'e.g. BF-2 Cast House, Bay 4', sl: sl)),
          const SizedBox(width: 6),
          _micButton(_location, sl),
        ]),
        const SizedBox(height: 10),

        _lbl('Cause category (WSA 13)', sl),
        _dropdown(_wsaCause, _wsaCauses,
            (v) => setState(() => _wsaCause = v ?? _wsaCause), sl),
        const SizedBox(height: 10),

        _lbl('Type of observation', sl),
        Row(children: [
          _typeChip('Unsafe Condition',
              Icons.visibility_outlined, AppColors.amber, sl),
          const SizedBox(width: 6),
          _typeChip('Unsafe Act',
              Icons.person_off_outlined, AppColors.red, sl),
        ]),
        const SizedBox(height: 10),

        _lbl('Severity (potential)', sl),
        Row(children: [
          for (final s in ['LOW', 'MED', 'HIGH', 'CRIT']) ...[
            _sevBtn(s, sl),
            if (s != 'CRIT') const SizedBox(width: 6),
          ],
        ]),
        const SizedBox(height: 10),

        _lbl('People involved / present', sl),
        _txt(_people,
            hint: 'e.g. Operator, contract workers', sl: sl),
        const SizedBox(height: 10),

        _lbl('Description (additional context)', sl),
        _txtWithMic(_description,
            hint: 'Describe what happened… (or use mic)',
            lines: 3, sl: sl),
        const SizedBox(height: 10),

        _lbl('Immediate action taken at site', sl),
        _txtWithMic(_immediateAction,
            hint: 'e.g. Barricaded the area… (or use mic)',
            lines: 2, sl: sl),
      ]));
  }

  // ─── FORM WIDGETS ─────────────────────────────────────────────
  Widget _stepLabel(String num, String label, SL sl) => Row(children: [
    Container(
      width: 22, height: 22,
      decoration: const BoxDecoration(
          color: AppColors.accent, shape: BoxShape.circle),
      child: Center(child: Text(num, style: const TextStyle(
          color: Colors.white, fontSize: 11,
          fontWeight: FontWeight.w700)))),
    const SizedBox(width: 8),
    Text(label.toUpperCase(), style: TextStyle(
        color: sl.text4, fontSize: 10,
        fontWeight: FontWeight.w700, letterSpacing: 0.8)),
  ]);

  Widget _lbl(String t, SL sl) => Padding(
    padding: const EdgeInsets.only(bottom: 5),
    child: Text(t, style: TextStyle(
        color: sl.text3, fontSize: 11,
        fontWeight: FontWeight.w700)));

  Widget _txt(TextEditingController c,
      {String? hint, int lines = 1, required SL sl}) {
    final fieldBg = sl.isDark
        ? const Color(0xFF1C1F2E)
        : const Color(0xFFF0F1F5);
    return TextField(
      controller: c, maxLines: lines,
      style: TextStyle(color: sl.text1, fontSize: 13),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: sl.text4, fontSize: 12),
        filled: true, fillColor: fieldBg,
        contentPadding: const EdgeInsets.symmetric(
            horizontal: 12, vertical: 11),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
              color: sl.border.withOpacity(0.5), width: 1.5)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
              color: sl.border.withOpacity(0.5), width: 1.5)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(
              color: AppColors.accent, width: 2))));
  }

  Widget _txtWithMic(TextEditingController c,
      {String? hint, int lines = 1, required SL sl}) {
    final fieldBg = sl.isDark
        ? const Color(0xFF1C1F2E)
        : const Color(0xFFF0F1F5);
    final isMicActive = _isListening && _activeMicField == c;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isMicActive
              ? AppColors.red.withOpacity(0.6)
              : sl.border.withOpacity(0.5),
          width: isMicActive ? 2 : 1.5)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: TextField(
          controller: c, maxLines: lines,
          style: TextStyle(color: sl.text1, fontSize: 13),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: sl.text4, fontSize: 12),
            filled: true, fillColor: fieldBg,
            contentPadding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 11),
            border: OutlineInputBorder(
              borderRadius: const BorderRadius.only(
                topLeft:    Radius.circular(10),
                bottomLeft: Radius.circular(10)),
              borderSide: BorderSide.none),
            enabledBorder: OutlineInputBorder(
              borderRadius: const BorderRadius.only(
                topLeft:    Radius.circular(10),
                bottomLeft: Radius.circular(10)),
              borderSide: BorderSide.none),
            focusedBorder: OutlineInputBorder(
              borderRadius: const BorderRadius.only(
                topLeft:    Radius.circular(10),
                bottomLeft: Radius.circular(10)),
              borderSide: BorderSide.none)))),
        GestureDetector(
          onTap: () => _toggleVoice(c),
          child: Tooltip(
            message: isMicActive
                ? 'Listening in $_voiceLanguageName… tap to stop'
                : 'Tap to speak in $_voiceLanguageName',
            child: Container(
              width: 46,
              height: lines > 1 ? (lines * 24.0 + 22) : 46,
              decoration: BoxDecoration(
                color: isMicActive
                    ? AppColors.red.withOpacity(0.12)
                    : AppColors.accent.withOpacity(0.08),
                borderRadius: const BorderRadius.only(
                  topRight:    Radius.circular(10),
                  bottomRight: Radius.circular(10))),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(isMicActive
                      ? Icons.mic_rounded
                      : Icons.mic_none_rounded,
                    color: isMicActive
                        ? AppColors.red : AppColors.accent,
                    size: 20),
                  if (isMicActive) ...[
                    const SizedBox(height: 2),
                    const Text('Live', style: TextStyle(
                        color: AppColors.red, fontSize: 8,
                        fontWeight: FontWeight.w700)),
                  ],
                ]))))]),
    );
  }

  Widget _micButton(TextEditingController c, SL sl) {
    final isActive = _isListening && _activeMicField == c;
    return GestureDetector(
      onTap: () => _toggleVoice(c),
      child: Tooltip(
        message: isActive
            ? 'Listening in $_voiceLanguageName… tap to stop'
            : 'Tap to speak in $_voiceLanguageName',
        child: Container(
          width: 44, height: 44,
          decoration: BoxDecoration(
            color: (isActive ? AppColors.red : AppColors.amber)
                .withOpacity(0.12),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isActive ? AppColors.red : AppColors.amber,
              width: 1.5)),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(isActive
                  ? Icons.mic_rounded : Icons.mic_none_rounded,
                color: isActive ? AppColors.red : AppColors.amber,
                size: 18),
              if (isActive)
                const Text('Live', style: TextStyle(
                    color: AppColors.red, fontSize: 7,
                    fontWeight: FontWeight.w700)),
            ]))));
  }

  Widget _dropdown(String value, List<String> options,
      ValueChanged<String?> onChange, SL sl) {
    final fieldBg = sl.isDark
        ? const Color(0xFF1C1F2E)
        : const Color(0xFFF0F1F5);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: fieldBg,
        border: Border.all(
            color: sl.border.withOpacity(0.5), width: 1.5),
        borderRadius: BorderRadius.circular(10)),
      child: DropdownButton<String>(
        value: value, isExpanded: true,
        underline: const SizedBox(),
        dropdownColor: sl.isDark
            ? const Color(0xFF252840) : Colors.white,
        style: TextStyle(color: sl.text1, fontSize: 12),
        items: options.map((s) => DropdownMenuItem(
            value: s, child: Text(s))).toList(),
        onChanged: onChange));
  }

  Widget _typeChip(String label, IconData icon,
      Color color, SL sl) => GestureDetector(
    onTap: () => setState(() => _obsType = label),
    child: Container(
      padding: const EdgeInsets.symmetric(
          horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: _obsType == label
            ? AppColors.accent.withOpacity(0.12)
            : (sl.isDark
                ? const Color(0xFF1C1F2E)
                : const Color(0xFFF0F1F5)),
        border: Border.all(
          color: _obsType == label
              ? AppColors.accent
              : sl.border.withOpacity(0.5),
          width: 1.5),
        borderRadius: BorderRadius.circular(18)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(
            color: sl.text1, fontSize: 11,
            fontWeight: FontWeight.w500)),
      ])));

  Widget _sevBtn(String label, SL sl) {
    final isSel =
        (_severity == 'MEDIUM'   && label == 'MED')  ||
        (_severity == 'CRITICAL' && label == 'CRIT') ||
        _severity == label;
    final color =
        label == 'LOW'  ? AppColors.green :
        label == 'MED'  ? AppColors.amber :
        label == 'HIGH' ? AppColors.red   :
        AppColors.crit;
    final fullSev =
        label == 'MED'  ? 'MEDIUM'   :
        label == 'CRIT' ? 'CRITICAL' : label;
    return Expanded(child: GestureDetector(
      onTap: () => setState(() => _severity = fullSev),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: isSel ? color.withOpacity(0.15) : Colors.transparent,
          border: Border.all(color: color, width: isSel ? 2 : 1.5),
          borderRadius: BorderRadius.circular(8)),
        alignment: Alignment.center,
        child: Text(label, style: TextStyle(
            color: color, fontSize: 10,
            fontWeight: FontWeight.w700)))));
  }

  Widget _submitBtn({
    required String label,
    required IconData icon,
    required List<Color> colors,
    required Future<bool> Function() onTap,
  }) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: colors),
        borderRadius: BorderRadius.circular(12)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 16, color: Colors.white),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(
              color: Colors.white, fontSize: 13,
              fontWeight: FontWeight.w700)),
        ])));
}
