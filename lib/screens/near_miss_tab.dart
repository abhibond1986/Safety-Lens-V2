// lib/screens/near_miss_tab.dart
// v15 MOBILE OPTIMIZATIONS:
//   ✅ Network status check before image analysis
//   ✅ Clear warnings when offline or backend unreachable
//   ✅ Form works fully offline (image analysis optional)
//   ✅ All original voice input, duplicate detection preserved
//   ✅ Infographic header with workflow steps
//   ✅ v15 Hardened suppression protocol for industrial tubes/wires

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
  XFile?      _pickedFile;
  Uint8List? _imageBytes;
  bool        _analyzing = false;
  String      _step      = '';
  Map<String, dynamic>? _aiBrief;
  bool        _isOnlineMode = true;

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

  String? _lastSubmissionKey;

  final stt.SpeechToText _speech         = stt.SpeechToText();
  bool                    _speechAvailable = false;
  bool                    _isListening     = false;
  TextEditingController? _activeMicField;

  static const Map<String, String> _voiceLocaleMap = {
    'en': 'en-IN', 'hi': 'hi-IN', 'bn': 'bn-IN', 'or': 'or-IN',
  };

  String get _voiceLocaleId {
    final lang = LocaleService().locale.languageCode;
    return _voiceLocaleMap[lang] ?? 'en-IN';
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
          _snack(kIsWeb ? 'Voice input requires Chrome.' : 'Microphone unavailable.', AppColors.amber);
        }
        return;
      }
    }
    final baseText = targetField.text;
    _activeMicField = targetField;
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
        localeId:       _voiceLocaleId,
        listenFor:      const Duration(minutes: 5),
        pauseFor:       const Duration(seconds: 30),
        partialResults: true,
        cancelOnError:  false,
        listenMode:     stt.ListenMode.dictation,
      );
    } catch (e) {
      if (mounted) setState(() { _isListening = false; _activeMicField = null; });
    }
  }

  Future<void> _uploadPdfBackground(Map<String, dynamic> incident, Map<String, dynamic>? user) async {
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
        await SyncService.pushIncident({...incident, 'pdfUrl': url}).catchError((_) => false);
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

  final _plants = const ['BSP', 'DSP', 'RSP', 'BSL', 'ISP', 'ASP', 'SSP', 'CFP', 'CMO', 'JGOM', 'OGOM', 'BSP(M)', 'Collieries', 'SRU Kulti'];
  final _wsaCauses = const ['Burn / Fire', 'Chemical', 'Electrical', 'Fall from Height', 'Fall of Material', 'Gas Related', 'Hit / Caught / Pressed', 'Hot Metal / Slag / Sub', 'Machine / Equipment', 'Material Handling', 'Road / Rail', 'Slip / Fall', 'Other'];

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: source, imageQuality: 85);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    setState(() {
      _pickedFile = picked; _imageBytes = bytes;
      _analyzing = true; _aiBrief = null;
    });
    await _analyzeImage();
  }

  // ─── OPTIMIZED V15 SUPPRESSION FILTER ───────────────────────
  Map<String, dynamic> _applyHardenedV15Filters(String name, String desc, String action, String reg, String cause) {
    final n = name.toLowerCase();
    final d = desc.toLowerCase();
    
    // Check for explicit structural proximity, manifold pipes, loops, brackets, or oxygen references
    bool isLikelyTubeOrConduit = n.contains('wire') || n.contains('cable') || n.contains('electrical');
    bool hasPipingContext = d.contains('pipe') || d.contains('bracket') || d.contains('oxygen') || d.contains('manifold') || d.contains('support') || d.contains('tube');
    
    if (isLikelyTubeOrConduit && hasPipingContext) {
      return {
        'name': 'Small-bore process tubing / conduit',
        'desc': 'Small diameter instrumentation line, impulse line, or process tubing tracking along the primary structural bracket alignment. Safe fixed configuration.',
        'action': 'Maintain standard periodic mechanical integrity checks on pipes and structural bracket elements.',
        'reg': 'FA 1948 S39 (Equipment Integrity & Inspection)',
        'cause': 'Equipment failure', // Remapped from Electrical
        'obsType': 'Unsafe Condition'
      };
    }
    return {'name': name, 'desc': desc, 'action': action, 'reg': reg, 'cause': cause, 'obsType': _obsType};
  }

  Future<void> _analyzeImage() async {
    final networkStatus = await NetworkChecker.getNetworkStatus();
    
    if (!networkStatus['hasInternet']!) {
      _snack('📱 Offline · Image analysis skipped. Fill form manually.', const Color(0xFFD97706));
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
      _snack('⚠️ AI server unavailable · Using knowledge-based analysis', const Color(0xFFD97706));
    }

    final steps = ['Uploaded', 'Analyzing image…', 'Classifying hazard…', 'Pre-filling form…'];
    for (var i = 0; i < steps.length - 1; i++) {
      setState(() => _step = steps[i]);
      await Future.delayed(const Duration(milliseconds: 700));
    }
    try {
      setState(() => _step = steps.last);
      Map<String, dynamic>? result = kIsWeb
          ? await GeminiVision.analyseImageBytes(_imageBytes!)
          : await GeminiVision.analyseImage(File(_pickedFile!.path));

      final hazards = (result?['hazards'] as List?) ?? [];
      final first   = hazards.isNotEmpty ? Map<String, dynamic>.from(hazards.first) : null;

      String rawName   = first?['name']?.toString() ?? 'Near miss observed';
      String rawDesc   = first?['description']?.toString() ?? result?['summary']?.toString() ?? '';
      String rawAction = first?['correctiveAction']?.toString() ?? '';
      String rawReg    = first?['regulation']?.toString() ?? '';
      String rawCause  = _mapToWsaCause(first?['category']?.toString() ?? '', rawName);
      
      // ✅ V15 Elimination Layer Enforced Programmatically
      final refinedData = _applyHardenedV15Filters(rawName, rawDesc, rawAction, rawReg, rawCause);

      final sev        = (first?['severity']?.toString() ?? 'MEDIUM').toUpperCase();
      final isOnline   = result?['_isOnline'] == true;

      final user              = await LocalDB.getCurrentUser();
      String plantFromProfile = user?['plant']?.toString() ?? _plant;
      if (!_plants.contains(plantFromProfile)) plantFromProfile = _plant;

      setState(() {
        _isOnlineMode = isOnline;
        _aiBrief = {
          'identified': refinedData['name'],
          'statutory':  refinedData['reg'].isEmpty ? 'Refer Factories Act §35-41' : refinedData['reg'],
          'type':       refinedData['obsType'],
          'severity':   sev,
          'confidence': result?['confidence'] ?? 75,
          'isOnline':   isOnline,
        };
        _brief.text           = '${refinedData['name']}. ${refinedData['desc']}'.trim();
        _description.text     = refinedData['desc']!;
        _immediateAction.text = refinedData['action']!;
        _dept.text            = user?['department']?.toString() ?? 'Operations';
        _location.text        = 'To be confirmed (edit if needed)';
        _people.text          = '0';
        _plant                = plantFromProfile;
        _wsaCause             = refinedData['cause']!;
        _severity             = sev;
        _obsType              = refinedData['obsType']!;
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

  String _buildSubmissionKey() {
    final title = (_aiBrief?['identified']?.toString() ?? _brief.text.split('.').first).trim().toLowerCase();
    final loc   = _location.text.trim().toLowerCase();
    final now   = DateTime.now();
    final bucket = '${now.year}${now.month}${now.day}${now.hour}${now.minute ~/ 5}';
    return '${_plant}|$loc|$title|$bucket';
  }

  Future<bool> _checkDuplicate() async {
    final key = _buildSubmissionKey();
    if (_lastSubmissionKey == key) {
      _snack('This report appears to be a duplicate.', const Color(0xFFD97706));
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
      return inc['type'] == 'NEAR_MISS' && incPlant == plant && incLoc == loc;
    }).toList();

    if (found.isNotEmpty) {
      if (!mounted) return true;
      final confirm = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: Theme.of(context).colorScheme.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: const Row(children: [
            Icon(Icons.warning_amber_rounded, color: Color(0xFFD97706), size: 22),
            SizedBox(width: 8),
            Text('Possible Duplicate', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ]),
          content: Text('A near miss from this exact location was already reported within the last 10 minutes.\n\nSubmit anyway?', style: const TextStyle(fontSize: 13, height: 1.5)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel', style: TextStyle(color: Colors.grey))),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD97706)),
              child: const Text('Submit Anyway', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700))),
          ]));
      return confirm != true;
    }
    return false;
  }

  Future<bool> _submit({bool exportAfter = false}) async {
    final loc = _location.text.trim();
    if (loc.isEmpty || loc == 'To be confirmed (edit if needed)') {
      _snack('Please enter the actual location', AppColors.red);
      return false;
    }
    if (await _checkDuplicate()) return false;

    final user = await LocalDB.getCurrentUser();
    final incident = {
      'id':              DateTime.now().millisecondsSinceEpoch.toString(),
      'title':           _aiBrief?['identified']?.toString() ?? _brief.text.split('.').first.trim(),
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
      'reportedBy':      user?['name'] ?? 'Unknown',
      'reportedByPno':   user?['pno']  ?? '',
      'date':            DateTime.now().toIso8601String(),
      'imageBase64':     _imageBytes != null ? base64Encode(_imageBytes!) : null,
    };

    await LocalDB.saveIncident(incident);
    final synced = await SyncService.pushIncident(incident).catchError((_) => false);
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
      _snack(exportAfter ? 'Saved + PDF exported' : 'Report submitted successfully', AppColors.green);
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      margin: const EdgeInsets.all(12),
      duration: const Duration(seconds: 3),
    ));
  }

  Widget _stepLabel(String num, String txt, SL sl) => Row(children: [
    CircleAvatar(radius: 9, backgroundColor: AppColors.accent, child: Text(num, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold))),
    const SizedBox(width: 6),
    Text(txt, style: TextStyle(color: sl.text1, fontSize: 12, fontWeight: FontWeight.w700))
  ]);

  Widget _submitBtn({required String label, required IconData icon, required List<Color> colors, required VoidCallback onTap}) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: colors),
        borderRadius: BorderRadius.circular(12)),
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 16, color: Colors.white),
        label: Text(label, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)))),
    );
  }

  // [Remainder of layout blocks continue downward below seamlessly...]
