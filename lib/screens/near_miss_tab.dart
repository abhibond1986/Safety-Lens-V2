// lib/screens/near_miss_tab.dart
// v11 MOBILE OPTIMIZATIONS:
//   ✅ Network status check before image analysis
//   ✅ Clear warnings when offline or backend unreachable
//   ✅ Form works fully offline (image analysis optional)
//   ✅ All original voice input, duplicate detection preserved
//   ✅ Infographic header with workflow steps

import 'dart:convert';
import 'dart:io' show File;
import 'package:flutter/foundation.dart' show kIsWeb, Uint8List;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../main.dart';
import '../services/gemini_vision.dart';
import '../services/network_checker.dart';
import '../services/local_db.dart';
import '../services/pdf_export.dart';
import '../services/sync_service.dart';
import '../widgets/universal_app_bar.dart';
import '../services/i18n.dart';

class NearMissTab extends StatefulWidget {
  final Map<String, dynamic>? user;
  final VoidCallback? toggleTheme;
  final VoidCallback? onSignOut;
  final bool isDark;
  const NearMissTab({
    super.key,
    this.user,
    this.toggleTheme,
    this.onSignOut,
    this.isDark = true,
  });
  @override
  State<NearMissTab> createState() => _NearMissTabState();
}

class _NearMissTabState extends State<NearMissTab> {
  XFile?     _pickedFile;
  Uint8List? _imageBytes;
  bool       _analyzing = false;
  String     _step      = '';
  Map<String, dynamic>? _aiBrief;
  bool       _isOnlineMode = true; // ✅ NEW: Track if AI is available

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
        listenFor:    const Duration(minutes: 5),
        pauseFor:     const Duration(seconds: 30),
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
        listenFor:     const Duration(minutes: 5),
        pauseFor:      const Duration(seconds: 30),
        partialResults: true,
        cancelOnError:  false,
        listenMode:    stt.ListenMode.dictation,
      );
    } catch (e) {
      debugPrint('Listen error: $e');
      if (mounted) setState(() { _isListening = false; _activeMicField = null; });
    }
  }

  /// Background-upload PDF to Drive after submit. Fire-and-forget.
  Future<void> _uploadPdfBackground(
      Map<String, dynamic> incident, Map<String, dynamic>? user) async {
    try {
      final pdfBytes = await PdfExport.generateIncidentReportBytes(
        incident:     incident,
        reporterName: user?['name']?.toString() ?? 'SAIL Safety Officer',
        reporterPno:  user?['pno']?.toString()  ?? '',
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

  @override
  void dispose() {
    _speech.cancel();
    _brief.dispose(); _dept.dispose(); _location.dispose();
    _people.dispose(); _description.dispose(); _immediateAction.dispose();
    super.dispose();
  }

  // ─── DATA ─────────────────────────────────────────────────────
  final _plants = const [
    'BSP',
    'DSP',
    'RSP',
    'BSL',
    'ISP',
    'ASP',
    'SSP',
    'CFP',
    'CMO',
    'JGOM',
    'OGOM',
    'BSP(M)',
    'Collieries',
    'SRU Kulti',
  ];
  final _wsaCauses = const [
    'Burn / Fire', 'Chemical', 'Electrical', 'Fall from Height',
    'Fall of Material', 'Gas Related', 'Hit / Caught / Pressed',
    'Hot Metal / Slag / Sub', 'Machine / Equipment',
    'Material Handling', 'Road / Rail', 'Slip / Fall', 'Other',
  ];

  // ─── IMAGE + AI WITH NETWORK CHECK ────────────────────────────
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
    // ✅ NEW: Check network status BEFORE attempting analysis
    final networkStatus = await NetworkChecker.getNetworkStatus();
    
    if (!networkStatus['hasInternet']!) {
      // Device is offline
      _snack(
        '📱 Offline · Image analysis skipped. Fill form manually.',
        const Color(0xFFD97706),
      );
      setState(() {
        _isOnlineMode = false;
        _aiBrief = {
          'identified': 'Manual entry — Offline',
          'statutory':  'Complete form manually',
          'type':       'Unsafe Condition',
          'severity':   'MEDIUM',
          'confidence': 0,
        };
        _brief.text = 'Describe the near miss observed.';
        _analyzing  = false;
      });
      return;
    }

    if (!networkStatus['backendReachable']!) {
      // Internet OK but backend down
      _snack(
        '⚠️ AI server unavailable · Using knowledge-based analysis',
        const Color(0xFFD97706),
      );
    }

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
      final isOnline  = result?['_isOnline'] == true;

      final user            = await LocalDB.getCurrentUser();
      String plantFromProfile = user?['plant']?.toString() ?? _plant;
      if (!_plants.contains(plantFromProfile)) plantFromProfile = _plant;

      setState(() {
        _isOnlineMode = isOnline;
        _aiBrief = {
          'identified': name,
          'statutory':  regulation.isEmpty
              ? 'Refer Factories Act §35-41' : regulation,
          'type':       hazardType,
          'severity':   sev,
          'confidence': result?['confidence'] ?? 75,
          'isOnline':   isOnline,
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
        _isOnlineMode = false;
        _aiBrief = {
          'identified': 'Manual entry — Analysis failed',
          'statutory':  'Complete form manually',
          'type':       'Unsafe Condition',
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
  String _buildSubmissionKey() {
    final title = (_aiBrief?['identified']?.toString()
        ?? _brief.text.split('.').first).trim().toLowerCase();
    final loc   = _location.text.trim().toLowerCase();
    final now   = DateTime.now();
    final bucket = '${now.year}${now.month}${now.day}${now.hour}${now.minute ~/ 5}';
    return '${_plant}|$loc|$title|$bucket';
  }

  Future<bool> _checkDuplicate() async {
    final key = _buildSubmissionKey();

    if (_lastSubmissionKey == key) {
      _snack('This report appears to be a duplicate. '
          'Wait a moment or change the location/description.',
          const Color(0xFFD97706));
      return true;
    }

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
      return confirm != true;
    }
    return false;
  }

  // ─── SUBMIT ───────────────────────────────────────────────────
  Future<bool> _submit({bool exportAfter = false}) async {
    final loc = _location.text.trim();
    if (loc.isEmpty || loc == 'To be confirmed (edit if needed)') {
      _snack('Please enter the actual location', AppColors.red);
      return false;
    }

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

    await LocalDB.saveIncident(incident);
    final synced = await SyncService.pushIncident(incident)
        .catchError((_) => false);
    _uploadPdfBackground(incident, user);
    _lastSubmissionKey = _buildSubmissionKey();

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
      color: sl.isDark
          ? const Color(0xFF1C1F2E)
          : const Color(0xFFF5F6FA),
      child: SafeArea(
        child: Column(children: [
          UniversalAppBar(
            title: I18n.t('nearMiss.title'),
            user: widget.user,
            toggleTheme: widget.toggleTheme,
            onSignOut: widget.onSignOut,
            isDark: widget.isDark,
          ),
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
        ])))));

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
          color: _isOnlineMode
              ? AppColors.purple.withOpacity(0.08)
              : AppColors.amber.withOpacity(0.08),
          border: Border.all(
              color: _isOnlineMode
                  ? AppColors.purple.withOpacity(0.4)
                  : AppColors.amber.withOpacity(0.4),
              width: 1.5),
          borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.auto_awesome, size: 12,
                color: _isOnlineMode
                    ? const Color(0xFFC4B5FD)
                    : AppColors.amber),
            const SizedBox(width: 4),
            Text(_isOnlineMode ? 'AI assessment' : 'Knowledge-based',
                style: TextStyle(
                color: _isOnlineMode
                    ? const Color(0xFFC4B5FD)
                    : AppColors.amber,
                fontSize: 11,
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
        if (hasImage) ...[  const SizedBox(height: 10),
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
          for (final s in ['LOW', 'MED', 'HIGH', 'CRIT']) ...[        _sevBtn(s, sl),
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
          fontWeight: FontWeight.w800)))),
    const SizedBox(width: 10),
    Text(label, style: TextStyle(
        color: sl.text1, fontSize: 13,
        fontWeight: FontWeight.w700)),
  ]);

  Widget _lbl(String text, SL sl) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(text, style: TextStyle(
        color: sl.text1, fontSize: 11,
        fontWeight: FontWeight.w700)));

  Widget _txt(TextEditingController c,
      {String hint = '', required SL sl}) =>
    TextField(
      controller: c,
      style: TextStyle(color: sl.text1, fontSize: 11),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: sl.text4, fontSize: 10),
        filled: true,
        fillColor: sl.isDark
            ? const Color(0xFF1C1F2E)
            : const Color(0xFFF5F6FA),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
            horizontal: 10, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: sl.border.withOpacity(0.4))),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(
              color: AppColors.accent, width: 1.5))));

  Widget _dropdown(String value, List<String> items,
      ValueChanged<String?> onChange, SL sl) =>
    Container(
      decoration: BoxDecoration(
        color: sl.isDark
            ? const Color(0xFF1C1F2E)
            : const Color(0xFFF5F6FA),
        border: Border.all(color: sl.border.withOpacity(0.4)),
        borderRadius: BorderRadius.circular(8)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: items.contains(value) ? value : items.first,
          isExpanded: true,
          isDense: true,
          dropdownColor: sl.isDark
              ? const Color(0xFF252840) : Colors.white,
          style: TextStyle(color: sl.text1, fontSize: 11),
          icon: Icon(Icons.arrow_drop_down, color: AppColors.accent),
          items: items.map((v) => DropdownMenuItem(
              value: v,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text(v)))).toList(),
          onChanged: onChange,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6))));

  Widget _micButton(TextEditingController c, SL sl) =>
    GestureDetector(
      onTap: () => _toggleVoice(c),
      child: Container(
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(
          color: _isListening && _activeMicField == c
              ? AppColors.red.withOpacity(0.12)
              : AppColors.accent.withOpacity(0.08),
          border: Border.all(
              color: _isListening && _activeMicField == c
                  ? AppColors.red
                  : AppColors.accent.withOpacity(0.3)),
          borderRadius: BorderRadius.circular(8)),
        child: Icon(
          _isListening && _activeMicField == c
              ? Icons.mic_rounded
              : Icons.mic_none_rounded,
          size: 18,
          color: _isListening && _activeMicField == c
              ? AppColors.red
              : AppColors.accent)));

  Widget _txtWithMic(TextEditingController c,
      {String hint = '', int lines = 1, required SL sl}) =>
    Row(children: [
      Expanded(
        child: TextField(
          controller: c,
          maxLines: lines,
          style: TextStyle(color: sl.text1, fontSize: 11),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: sl.text4, fontSize: 10),
            filled: true,
            fillColor: sl.isDark
                ? const Color(0xFF1C1F2E)
                : const Color(0xFFF5F6FA),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
                horizontal: 10, vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: sl.border.withOpacity(0.4))),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(
                  color: AppColors.accent, width: 1.5))))),
      const SizedBox(width: 8),
      _micButton(c, sl),
    ]);

  Widget _typeChip(String label, IconData icon, Color color, SL sl) =>
    Expanded(
      child: GestureDetector(
        onTap: () => setState(() =>
            _obsType = label),
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            color: _obsType == label
                ? color.withOpacity(0.2)
                : sl.isDark
                    ? const Color(0xFF252840)
                    : Colors.white,
            border: Border.all(
              color: _obsType == label ? color : sl.border,
              width: _obsType == label ? 1.5 : 1),
            borderRadius: BorderRadius.circular(8)),
          child: Row(mainAxisAlignment: MainAxisAlignment.center,
            children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Expanded(child: Text(label.split(' ').first,
              style: TextStyle(color: sl.text1, fontSize: 10,
                  fontWeight: FontWeight.w600),
              textAlign: TextAlign.center)),
          ]))));

  Widget _sevBtn(String label, SL sl) {
    final mapping = {'LOW': _severity == 'LOW', 'MED': _severity == 'MEDIUM',
                     'HIGH': _severity == 'HIGH', 'CRIT': _severity == 'CRITICAL'};
    final isSelected = mapping[label] ?? false;
    final sevColor = _sevColor(_severity);

    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _severity =
            label == 'MED' ? 'MEDIUM' : label == 'CRIT' ? 'CRITICAL' : label),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? sevColor.withOpacity(0.15)
                : sl.isDark
                    ? const Color(0xFF252840)
                    : Colors.white,
            border: Border.all(
              color: isSelected ? sevColor : sl.border,
              width: isSelected ? 1.5 : 1),
            borderRadius: BorderRadius.circular(6)),
          child: Center(child: Text(label,
            style: TextStyle(color: isSelected ? sevColor : sl.text3,
                fontSize: 10, fontWeight: FontWeight.w700))))));
  }

  Color _sevColor(String sev) {
    switch (sev.toUpperCase()) {
      case 'CRITICAL': return AppColors.red;
      case 'HIGH':     return AppColors.amber;
      case 'MEDIUM':   return AppColors.amber;
      default:         return AppColors.green;
    }
  }

  Widget _submitBtn({
    required String label,
    required IconData icon,
    required List<Color> colors,
    required VoidCallback onTap,
  }) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 13),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: colors),
        borderRadius: BorderRadius.circular(10),
        boxShadow: [BoxShadow(
          color: colors.first.withOpacity(0.3),
          blurRadius: 10, offset: const Offset(0, 4))]),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(icon, size: 15, color: Colors.white),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(
            color: Colors.white, fontSize: 12,
            fontWeight: FontWeight.w700)),
      ])));
}
