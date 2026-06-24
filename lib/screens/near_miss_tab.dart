// lib/screens/near_miss_tab.dart
// v17 FIXES:
//   ✅ FIX: Voice-to-text now works on web (no permission_handler on web)
//   ✅ FIX: Visual pulsing mic indicator when listening
//   ✅ FIX: Better error handling + auto-retry on speech init
//   ✅ UI/UX: More attractive form design with better spacing & animations
//   ✅ UI/UX: Polished cards, improved visual hierarchy
//   ✅ All v16 features preserved (network check, form, duplicate detection)

import 'dart:convert';
import 'dart:io' show File;
import 'package:flutter/foundation.dart' show kIsWeb, Uint8List;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import '../main.dart';
import '../services/gemini_vision.dart';
import '../services/network_checker.dart';
import '../services/local_db.dart';
import '../services/pdf_export.dart';
import '../services/sync_service.dart';
import '../services/admin_master_data.dart';
import '../services/geo_service.dart';
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

class _NearMissTabState extends State<NearMissTab> with TickerProviderStateMixin {
  XFile?      _pickedFile;
  Uint8List? _imageBytes;
  bool        _analyzing = false;
  String      _step      = '';
  Map<String, dynamic>? _aiBrief;
  bool        _isOnlineMode = true;

  final _brief           = TextEditingController();
  final _dept            = TextEditingController();
  final _location        = TextEditingController();
  final _description     = TextEditingController();
  final _immediateAction = TextEditingController();

  String _plant   = 'SAIL Safety Organisation';
  String _wsaCause = 'Slip / Fall';
  String _severity = 'MEDIUM';
  String _obsType  = 'Unsafe Condition';

  String? _lastSubmissionKey;

  // GPS geo-tagging
  LocationData? _capturedLocation;

  final stt.SpeechToText _speech         = stt.SpeechToText();
  bool                    _speechAvailable = false;
  bool                    _isListening     = false;
  TextEditingController? _activeMicField;

  // Mic pulse animation
  late AnimationController _micPulseCtrl;
  late Animation<double> _micPulse;

  // ✅ FIX v17: Use I18n.currentLang directly (not LocaleService which may lag)
  // Locale IDs follow BCP-47 format recognized by both Android and Chrome Web Speech API
  static const Map<String, String> _voiceLocaleMap = {
    'en': 'en-IN',
    'hi': 'hi-IN',   // Devanagari output
    'bn': 'bn-IN',   // Bengali script output
    'or': 'or-IN',   // Odia script output
  };

  String get _voiceLocaleId {
    // ✅ Use I18n.currentLang which is always in sync with user's selection
    final lang = I18n.currentLang;
    return _voiceLocaleMap[lang] ?? 'en-IN';
  }

  @override
  void initState() {
    super.initState();
    _micPulseCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1000));
    _micPulse = Tween<double>(begin: 1.0, end: 1.35).animate(
      CurvedAnimation(parent: _micPulseCtrl, curve: Curves.easeInOut));
    _micPulseCtrl.repeat(reverse: true);
    _initSpeech();
    _loadMasterData();
  }

  Future<void> _loadMasterData() async {
    try {
      final plants = await AdminMasterData.getPlants();
      final wsa    = await AdminMasterData.getWsaCauses();
      if (!mounted) return;
      setState(() {
        final plantNames = plants.map((p) => p['name'] ?? p['code'] ?? '').where((s) => s.isNotEmpty).toList();
        if (plantNames.isNotEmpty) _plants = plantNames;
        if (wsa.isNotEmpty) _wsaCauses = wsa;
      });
    } catch (_) {}
  }

  static bool _micPermissionGranted = false;

  Future<void> _initSpeech() async {
    try {
      if (!kIsWeb && !_micPermissionGranted) {
        final status = await Permission.microphone.request();
        if (!status.isGranted) {
          debugPrint('Speech: Microphone permission denied (status: $status)');
          if (mounted) setState(() => _speechAvailable = false);
          return;
        }
        _micPermissionGranted = true;
        debugPrint('Speech: Microphone permission granted');
      }

      _speechAvailable = await _speech.initialize(
        onError: (e) {
          debugPrint('Speech error: ${e.errorMsg} (permanent: ${e.permanent})');
          if (mounted) setState(() => _isListening = false);
          // ✅ Auto-retry on non-permanent errors
          if (!e.permanent && _activeMicField != null) {
            Future.delayed(const Duration(seconds: 1), () {
              if (mounted && _isListening) _restartListening();
            });
          }
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
      debugPrint('Speech: initialized=$_speechAvailable');
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Speech init error: $e');
      if (mounted) setState(() => _speechAvailable = false);
    }
  }

  Future<void> _restartListening() async {
    if (!_isListening || _activeMicField == null) return;
    final field    = _activeMicField!;
    final baseText = field.text;
    try {
      await Future.delayed(const Duration(milliseconds: 300));
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
        listenFor:    const Duration(minutes: 3),
        pauseFor:     const Duration(seconds: 10),
        partialResults: true,
        cancelOnError:  false,
        listenMode:   stt.ListenMode.dictation,
      );
    } catch (e) {
      debugPrint('Speech restart error: $e');
      if (mounted) setState(() => _isListening = false);
    }
  }

  Future<void> _toggleVoice([TextEditingController? field]) async {
    final targetField = field ?? _location;

    // If already listening on the same field, stop
    if (_isListening && _activeMicField == targetField) {
      await _speech.stop();
      setState(() { _isListening = false; _activeMicField = null; });
      return;
    }

    // If listening on a different field, stop first
    if (_isListening) {
      await _speech.stop();
      setState(() { _isListening = false; _activeMicField = null; });
      await Future.delayed(const Duration(milliseconds: 300));
    }

    // Check availability — re-init if needed
    if (!_speechAvailable) {
      await _initSpeech();
      if (!_speechAvailable) {
        if (mounted) {
          _snack(
            kIsWeb
              ? 'Voice input requires a supported browser (Chrome, Edge). Please allow microphone access when prompted.'
              : 'Microphone unavailable. Please check app permissions in Settings.',
            AppColors.amber,
          );
        }
        return;
      }
    }

    final baseText = targetField.text;
    _activeMicField = targetField;
    debugPrint('Speech: Starting with locale=${_voiceLocaleId} (I18n.currentLang=${I18n.currentLang})');
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
        listenFor:      const Duration(minutes: 3),
        pauseFor:       const Duration(seconds: 10),
        partialResults: true,
        cancelOnError:  false,
        listenMode:     stt.ListenMode.dictation,
      );
    } catch (e) {
      debugPrint('Speech listen error: $e');
      if (mounted) setState(() { _isListening = false; _activeMicField = null; });
      _snack('Voice input failed. Try again.', AppColors.red);
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
    _micPulseCtrl.dispose();
    _speech.cancel();
    _brief.dispose(); _dept.dispose(); _location.dispose();
    _description.dispose(); _immediateAction.dispose();
    super.dispose();
  }

  // Loaded dynamically from AdminMasterData (synced with admin panel)
  List<String> _plants = ['BSP', 'DSP', 'RSP', 'BSL', 'ISP', 'ASP', 'SSP', 'CFP', 'CMO', 'JGOM', 'OGOM', 'BSP(M)', 'Collieries', 'SRU Kulti', 'SSO'];
  List<String> _wsaCauses = ['Burn / Fire', 'Chemical', 'Electrical', 'Fall from Height', 'Fall of Material', 'Gas Related', 'Hit / Caught / Pressed', 'Hot Metal / Slag / Sub', 'Machine / Equipment', 'Material Handling', 'Road / Rail', 'Slip / Fall', 'Other'];

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: source, imageQuality: 65, maxWidth: 800, maxHeight: 800);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    setState(() {
      _pickedFile = picked; _imageBytes = bytes;
      _analyzing = true; _aiBrief = null;
    });

    // Capture GPS in background and auto-fill location with place name
    _captureGpsInBackground();

    await _analyzeImage();
  }

  /// Captures GPS location silently and fills location field with place name
  Future<void> _captureGpsInBackground() async {
    try {
      final location = await GeoService.getCurrentLocation().timeout(
        const Duration(seconds: 8),
        onTimeout: () => LocationData(error: 'GPS timeout'),
      );
      if (!mounted) return;
      if (location != null && location.isValid) {
        _capturedLocation = location;
        final address = GeoService.getDisplayAddress(location);
        if (address.isNotEmpty) {
          setState(() => _location.text = address);
        }
      }
    } catch (_) {
      // GPS capture failed silently — user can fill manually
    }
  }

  Map<String, dynamic> _applyHardenedV15Filters(String name, String desc, String action, String reg, String cause) {
    final n = name.toLowerCase();
    final d = desc.toLowerCase();

    bool isLikelyTubeOrConduit = n.contains('wire') || n.contains('cable') || n.contains('electrical');
    bool hasPipingContext = d.contains('pipe') || d.contains('bracket') || d.contains('oxygen') || d.contains('manifold') || d.contains('support') || d.contains('tube');

    if (isLikelyTubeOrConduit && hasPipingContext) {
      return {
        'name': 'Small-bore process tubing / conduit',
        'desc': 'Small diameter instrumentation line, impulse line, or process tubing tracking along the primary structural bracket alignment. Safe fixed configuration.',
        'action': 'Maintain standard periodic mechanical integrity checks on pipes and structural bracket elements.',
        'reg': 'FA 1948 S39 (Equipment Integrity & Inspection)',
        'cause': 'Equipment failure',
        'obsType': 'Unsafe Condition'
      };
    }
    return {'name': name, 'desc': desc, 'action': action, 'reg': reg, 'cause': cause, 'obsType': _obsType};
  }

  Future<void> _analyzeImage() async {
    final networkStatus = await NetworkChecker.getNetworkStatus();

    if (!networkStatus['hasInternet']!) {
      _snack('Offline - Image analysis skipped. Fill form manually.', const Color(0xFFD97706));
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

    // ✅ FIXED: Removed backend reachability pre-check that always failed on Android
    // The actual GeminiVision call has its own retry logic and will fallback if needed

    final steps = ['Uploaded', 'Analyzing image...', 'Classifying hazard...', 'Pre-filling form...'];
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
      final isOnline = result?['_isOnline'] == true;

      // ✅ FIX: If AI failed (offline/exhausted) with no hazards, show clean message
      if (hazards.isEmpty && !isOnline) {
        final user = await LocalDB.getCurrentUser();
        setState(() {
          _isOnlineMode = false;
          _aiBrief = {
            'identified': 'AI unavailable — fill form manually',
            'statutory':  'Refer applicable regulations',
            'type':       'Unsafe Condition',
            'severity':   'MEDIUM',
            'confidence': 0,
          };
          _brief.text       = '';
          _dept.text        = user?['department']?.toString() ?? 'Operations';
          if (_location.text.isEmpty || _location.text == 'To be confirmed (edit if needed)') {
            if (_capturedLocation != null && _capturedLocation!.isValid) {
              _location.text = GeoService.getDisplayAddress(_capturedLocation!);
            } else {
              _location.text = 'To be confirmed (edit if needed)';
            }
          }
          _analyzing = false;
        });
        return;
      }

      // ✅ FIX: Safely access first hazard — guard against null/non-Map entries
      Map<String, dynamic>? first;
      if (hazards.isNotEmpty && hazards.first is Map) {
        try {
          first = Map<String, dynamic>.from(hazards.first as Map);
        } catch (_) {
          first = null;
        }
      }

      String rawName   = first?['name']?.toString() ?? 'Near miss observed';
      String rawDesc   = first?['description']?.toString() ?? result?['summary']?.toString() ?? '';
      String rawAction = first?['correctiveAction']?.toString() ?? '';
      String rawReg    = first?['regulation']?.toString() ?? '';
      String rawCause  = _mapToWsaCause(first?['category']?.toString() ?? '', rawName);

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
          'statutory':  (refinedData['reg']?.toString() ?? '').isEmpty ? 'Refer Factories Act S35-41' : refinedData['reg'].toString(),
          'type':       refinedData['obsType'],
          'severity':   sev,
          'confidence': result?['confidence'] ?? 75,
          'isOnline':   isOnline,
        };
        _brief.text           = '${refinedData['name'] ?? ''}. ${refinedData['desc'] ?? ''}'.trim();
        _description.text     = refinedData['desc']?.toString() ?? '';
        _immediateAction.text = refinedData['action']?.toString() ?? '';
        _dept.text            = user?['department']?.toString() ?? 'Operations';
        // Only set placeholder if GPS hasn't already filled it
        if (_location.text.isEmpty || _location.text == 'To be confirmed (edit if needed)') {
          if (_capturedLocation != null && _capturedLocation!.isValid) {
            _location.text = GeoService.getDisplayAddress(_capturedLocation!);
          } else {
            _location.text = 'To be confirmed (edit if needed)';
          }
        }
        _plant                = plantFromProfile;
        _wsaCause             = refinedData['cause']?.toString() ?? _wsaCause;
        _severity             = sev;
        _obsType              = refinedData['obsType']?.toString() ?? _obsType;
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(children: [
            Icon(Icons.warning_amber_rounded, color: Color(0xFFD97706), size: 22),
            SizedBox(width: 8),
            Text('Possible Duplicate', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ]),
          content: const Text('A near miss from this exact location was already reported within the last 10 minutes.\n\nSubmit anyway?', style: TextStyle(fontSize: 13, height: 1.5)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel', style: TextStyle(color: Colors.grey))),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD97706), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
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

    // Capture GPS location (non-blocking, best-effort)
    try {
      _capturedLocation = await GeoService.getCurrentLocation().timeout(
        const Duration(seconds: 8),
        onTimeout: () => LocationData(error: 'GPS timeout'),
      );
    } catch (_) {
      _capturedLocation = null;
    }

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
      'immediateAction': _immediateAction.text.trim(),
      'type':            'NEAR_MISS',
      'status':          'OPEN',
      'reportedBy':      user?['name'] ?? 'Unknown',
      'reportedByPno':   user?['pno']  ?? '',
      'date':            DateTime.now().toIso8601String(),
      'imageBase64':     _imageBytes != null ? base64Encode(_imageBytes!) : null,
    };

    // Add GPS data if available
    if (_capturedLocation != null && _capturedLocation!.isValid) {
      incident['latitude'] = _capturedLocation!.latitude;
      incident['longitude'] = _capturedLocation!.longitude;
      incident['locationAccuracy'] = _capturedLocation!.accuracy;
      incident['locationAddress'] = _capturedLocation!.address;
      incident['locationTimestamp'] = _capturedLocation!.timestamp.toIso8601String();
    }

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
      setState(() {
        _pickedFile = null; _imageBytes = null; _aiBrief = null;
        _brief.clear(); _dept.clear(); _location.clear();
        _description.clear(); _immediateAction.clear();
      });
      _showSaveSuccessDialog(incident, synced, exportAfter);
    }
    return true;
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        Icon(
          color == AppColors.green ? Icons.check_circle_rounded
            : color == AppColors.red ? Icons.error_rounded
            : Icons.info_rounded,
          color: Colors.white, size: 18),
        const SizedBox(width: 10),
        Expanded(child: Text(msg, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500))),
      ]),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(12),
      duration: const Duration(seconds: 3),
    ));
  }

  // ═══════════════════════════════════════════════════════════════
  //  SHARE HELPERS
  // ═══════════════════════════════════════════════════════════════

  void _showSaveSuccessDialog(Map<String, dynamic> incident, bool synced, bool exported) {
    showDialog(context: context, builder: (ctx) => Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(padding: const EdgeInsets.all(24), child: Column(
        mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: AppColors.green.withOpacity(0.1), shape: BoxShape.circle),
            child: Icon(Icons.check_circle_rounded, color: AppColors.green, size: 48)),
          const SizedBox(height: 16),
          Text(exported ? 'Saved + PDF Exported' : 'Near Miss Reported',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(synced ? 'Synced to cloud ☁️' : 'Saved locally (will sync later)',
            style: TextStyle(fontSize: 13, color: Colors.grey[600])),
          const SizedBox(height: 20),
          // Share buttons
          Text('Share Report', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey[700])),
          const SizedBox(height: 10),
          Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            _shareBtn(iconWidget: _whatsAppIcon(20), label: 'WhatsApp',
              color: const Color(0xFF25D366),
              onTap: () { Navigator.pop(ctx); _shareViaWhatsApp(incident); }),
            _shareBtn(icon: Icons.email_outlined, label: 'Email',
              color: const Color(0xFF1976D2),
              onTap: () { Navigator.pop(ctx); _shareViaEmail(incident); }),
            _shareBtn(icon: Icons.share_rounded, label: 'More',
              color: AppColors.accent,
              onTap: () { Navigator.pop(ctx); _shareGeneric(incident); }),
          ]),
          const SizedBox(height: 16),
          TextButton(onPressed: () => Navigator.pop(ctx),
            child: const Text('Close', style: TextStyle(fontWeight: FontWeight.w600))),
        ],
      )),
    ));
  }

  Widget _shareBtn({IconData? icon, Widget? iconWidget, required String label,
      required Color color, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.4))),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          iconWidget ?? Icon(icon, color: color, size: 20),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700)),
        ]),
      ),
    );
  }

  Widget _whatsAppIcon(double size) {
    return Container(
      width: size, height: size,
      decoration: const BoxDecoration(
        color: Color(0xFF25D366),
        shape: BoxShape.circle,
      ),
      child: Icon(Icons.phone, color: Colors.white, size: size * 0.6),
    );
  }

  String _buildShareText(Map<String, dynamic> incident) {
    final title    = incident['title']?.toString() ?? 'Near Miss Report';
    final severity = incident['severity']?.toString() ?? 'MEDIUM';
    final plant    = incident['plant']?.toString() ?? '';
    final location = incident['location']?.toString() ?? '';
    final desc     = incident['desc']?.toString() ?? '';
    final date     = incident['date']?.toString().split('T').first ?? '';

    return '⚠️ *SAIL Safety Lens — Near Miss Report*\n\n'
        '📋 *Title:* $title\n'
        '🔴 *Severity:* $severity\n'
        '🏭 *Plant:* $plant\n'
        '📍 *Location:* $location\n'
        '📅 *Date:* $date\n\n'
        '📝 *Description:*\n$desc\n\n'
        '—\n_Generated by SAIL Safety Lens_';
  }

  Future<void> _shareViaWhatsApp(Map<String, dynamic> incident) async {
    final text = _buildShareText(incident);
    final encoded = Uri.encodeComponent(text);
    final url = Uri.parse('https://wa.me/?text=$encoded');
    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      } else {
        await Share.share(text);
      }
    } catch (_) {
      await Share.share(text);
    }
  }

  Future<void> _shareViaEmail(Map<String, dynamic> incident) async {
    final text    = _buildShareText(incident);
    final title   = incident['title']?.toString() ?? 'Near Miss Report';
    final subject = 'SAIL Safety Lens: $title';
    final url = Uri(scheme: 'mailto', query: 'subject=${Uri.encodeComponent(subject)}&body=${Uri.encodeComponent(text)}');
    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(url);
      } else {
        await Share.share(text, subject: subject);
      }
    } catch (_) {
      await Share.share(text, subject: subject);
    }
  }

  Future<void> _shareGeneric(Map<String, dynamic> incident) async {
    final text = _buildShareText(incident);
    await Share.share(text);
  }

  // ═══════════════════════════════════════════════════════════════
  //  LISTENING BANNER — shows at top when voice is active
  // ═══════════════════════════════════════════════════════════════
  Widget _listeningBanner(SL sl) {
    if (!_isListening) return const SizedBox.shrink();
    return AnimatedBuilder(
      animation: _micPulse,
      builder: (_, __) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.red.withOpacity(0.12), Colors.red.withOpacity(0.05)]),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.red.withOpacity(0.4))),
        child: Row(children: [
          Transform.scale(
            scale: _micPulse.value,
            child: Container(
              width: 28, height: 28,
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.15),
                shape: BoxShape.circle),
              child: const Icon(Icons.mic, color: Colors.red, size: 16)),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Listening...', style: TextStyle(color: Colors.red.shade700, fontSize: 12, fontWeight: FontWeight.w700)),
              Text('Speak clearly. Tap mic again to stop.',
                style: TextStyle(color: sl.text3, fontSize: 10)),
            ])),
          GestureDetector(
            onTap: () => _toggleVoice(_activeMicField),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8)),
              child: Text('STOP', style: TextStyle(
                color: Colors.red.shade700, fontSize: 10, fontWeight: FontWeight.w800))),
          ),
        ]),
      ),
    );
  }

  Widget _stepLabel(String num, String txt, SL sl) => Row(children: [
    Container(
      width: 22, height: 22,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF7B5BFF), Color(0xFF5B7BFF)]),
        borderRadius: BorderRadius.circular(7)),
      child: Center(child: Text(num, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)))),
    const SizedBox(width: 8),
    Text(txt, style: TextStyle(color: sl.text1, fontSize: 13, fontWeight: FontWeight.w700))
  ]);

  Widget _submitBtn({required String label, required IconData icon, required List<Color> colors, required VoidCallback onTap}) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: colors),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(color: colors.first.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 3)),
        ]),
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 16, color: Colors.white),
        label: Text(label, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(vertical: 15),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)))),
    );
  }

  Widget _guidanceBox(SL sl) => Container(
    margin: const EdgeInsets.only(bottom: 14),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [AppColors.amber.withOpacity(0.08), AppColors.amber.withOpacity(0.03)]),
      border: Border.all(color: AppColors.amber.withOpacity(0.4)),
      borderRadius: BorderRadius.circular(12)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: AppColors.amber.withOpacity(0.15),
            borderRadius: BorderRadius.circular(6)),
          child: const Icon(Icons.lightbulb_outline_rounded, size: 14, color: AppColors.amber)),
        const SizedBox(width: 8),
        const Text('Reporting Guidance', style: TextStyle(color: AppColors.amber, fontSize: 12, fontWeight: FontWeight.w700)),
      ]),
      const SizedBox(height: 8),
      Text(
        'A near miss is an unplanned event that did NOT result in injury but had the potential to do so. Report freely — no blame, only learning.',
        style: TextStyle(color: sl.text2, fontSize: 11, height: 1.5)),
    ]));

  Widget _imageSection(SL sl) {
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: sl.card,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(sl.isDark ? 0.2 : 0.06), blurRadius: 12, offset: const Offset(0, 3)),
        ]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _stepLabel('1', 'Image Evidence (Optional)', sl),
        const SizedBox(height: 12),
        if (_imageBytes == null && !_analyzing) _emptyImage(sl),
        if (_analyzing) _analyzingImage(),
        if (_imageBytes != null && !_analyzing && _aiBrief != null) _imageWithBrief(sl),
      ]));
  }

  Widget _emptyImage(SL sl) => Column(children: [
    GestureDetector(
      onTap: () => _pickImage(ImageSource.camera),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [AppColors.accent.withOpacity(0.06), AppColors.accent.withOpacity(0.02)]),
          border: Border.all(color: AppColors.accent.withOpacity(0.3), width: 1.5),
          borderRadius: BorderRadius.circular(14)),
        child: Column(children: [
          Container(
            width: 56, height: 56,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [AppColors.accent.withOpacity(0.15), AppColors.accent.withOpacity(0.05)]),
              shape: BoxShape.circle),
            child: const Icon(Icons.camera_alt_rounded, size: 28, color: AppColors.accent)),
          const SizedBox(height: 12),
          Text('Tap to capture hazard photo', style: TextStyle(color: sl.text1, fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text('AI will auto-identify hazard & pre-fill the form', style: TextStyle(color: sl.text4, fontSize: 10)),
        ])),
    ),
    const SizedBox(height: 10),
    Row(children: [
      Expanded(child: _actionButton(
        icon: Icons.camera_alt_rounded,
        label: 'Capture',
        filled: true,
        onTap: () => _pickImage(ImageSource.camera),
      )),
      const SizedBox(width: 10),
      Expanded(child: _actionButton(
        icon: Icons.photo_library_rounded,
        label: 'Gallery',
        filled: false,
        onTap: () => _pickImage(ImageSource.gallery),
      )),
    ]),
  ]);

  Widget _actionButton({required IconData icon, required String label, required bool filled, required VoidCallback onTap}) {
    if (filled) {
      return Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFF7B5BFF), Color(0xFF5B7BFF)]),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(color: AppColors.accent.withOpacity(0.25), blurRadius: 6, offset: const Offset(0, 2))]),
        child: ElevatedButton.icon(
          onPressed: onTap,
          icon: Icon(icon, size: 15, color: Colors.white),
          label: Text(label, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent, shadowColor: Colors.transparent,
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)))),
      );
    }
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 15, color: AppColors.accent),
      label: Text(label, style: const TextStyle(color: AppColors.accent, fontSize: 12, fontWeight: FontWeight.w600)),
      style: OutlinedButton.styleFrom(
        side: const BorderSide(color: AppColors.accent, width: 1.5),
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
    );
  }

  Widget _analyzingImage() => Container(
    height: 140,
    decoration: BoxDecoration(
      color: const Color(0xFF252840),
      borderRadius: BorderRadius.circular(12),
      image: _imageBytes != null ? DecorationImage(image: MemoryImage(_imageBytes!), fit: BoxFit.cover) : null),
    child: Container(
      decoration: BoxDecoration(color: Colors.black.withOpacity(0.6), borderRadius: BorderRadius.circular(12)),
      child: Center(child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(width: 32, height: 32, child: CircularProgressIndicator(strokeWidth: 3, color: AppColors.accent)),
          const SizedBox(height: 10),
          Text(_step, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text('Please wait...', style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 10)),
        ]))));

  Widget _imageWithBrief(SL sl) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 220),
        child: ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.memory(_imageBytes!, fit: BoxFit.cover, width: double.infinity)),
      ),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: _isOnlineMode
              ? [AppColors.accent.withOpacity(0.08), AppColors.accent.withOpacity(0.02)]
              : [AppColors.amber.withOpacity(0.08), AppColors.amber.withOpacity(0.02)]),
          border: Border.all(color: _isOnlineMode ? AppColors.accent.withOpacity(0.3) : AppColors.amber.withOpacity(0.3), width: 1.5),
          borderRadius: BorderRadius.circular(14)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.auto_awesome, size: 14, color: _isOnlineMode ? AppColors.accent : AppColors.amber),
            const SizedBox(width: 6),
            Text(_isOnlineMode ? 'AI Assessment' : 'AI Unavailable — Manual Entry',
              style: TextStyle(color: _isOnlineMode ? AppColors.accent : AppColors.amber, fontSize: 12, fontWeight: FontWeight.w700)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.amber.withOpacity(0.12),
                border: Border.all(color: AppColors.amber.withOpacity(0.6)),
                borderRadius: BorderRadius.circular(8)),
              child: Text('${_aiBrief!['severity']} · ${_aiBrief!['confidence']}%',
                style: const TextStyle(color: AppColors.amber, fontSize: 9, fontWeight: FontWeight.w800))),
          ]),
          if (!_isOnlineMode) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.amber.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8)),
              child: Row(children: [
                const Icon(Icons.wifi_off_rounded, color: AppColors.amber, size: 14),
                const SizedBox(width: 8),
                Expanded(child: Text(
                  'AI could not analyze image. Fill the form manually or retry when connected.',
                  style: TextStyle(color: AppColors.amber.withOpacity(0.9), fontSize: 10, height: 1.3))),
              ]),
            ),
          ],
          const SizedBox(height: 10),
          _briefRow('Identified', _aiBrief!['identified'].toString(), sl),
          _briefRow('Statutory',  _aiBrief!['statutory'].toString(),  sl),
          _briefRow('Type',       _aiBrief!['type'].toString(),       sl),
          const SizedBox(height: 10),
          Text('AI brief (editable):', style: TextStyle(color: sl.text3, fontSize: 10, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          TextField(
            controller: _brief,
            maxLines: 4,
            style: TextStyle(color: sl.text1, fontSize: 12, height: 1.5),
            decoration: InputDecoration(
              filled: true,
              fillColor: sl.isDark ? const Color(0xFF1C1F2E) : const Color(0xFFF8F9FC),
              contentPadding: const EdgeInsets.all(12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: sl.border)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.accent, width: 2)),
            )),
          const SizedBox(height: 6),
          Text('Edit any field above or in the form below', textAlign: TextAlign.center, style: TextStyle(color: sl.text4, fontSize: 10)),
        ])),
      const SizedBox(height: 10),
      OutlinedButton.icon(
        onPressed: () => setState(() { _pickedFile = null; _imageBytes = null; _aiBrief = null; _brief.clear(); }),
        icon: const Icon(Icons.delete_outline_rounded, size: 15, color: AppColors.red),
        label: const Text('Remove Image', style: TextStyle(color: AppColors.red, fontSize: 12, fontWeight: FontWeight.w600)),
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: AppColors.red.withOpacity(0.5), width: 1.5),
          padding: const EdgeInsets.symmetric(vertical: 11),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)))),
    ]);

  Widget _briefRow(String k, String v, SL sl) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(width: 80, child: Text(k, style: TextStyle(color: sl.text4, fontSize: 10, fontWeight: FontWeight.w700))),
      Expanded(child: Text(v, style: TextStyle(color: sl.text1, fontSize: 11, height: 1.4))),
    ]));

  // ═══════════════════════════════════════════════════════════════
  //  DETAILS FORM SECTION — with voice mic buttons
  // ═══════════════════════════════════════════════════════════════
  Widget _detailsSection(SL sl) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: sl.card,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(sl.isDark ? 0.2 : 0.06), blurRadius: 12, offset: const Offset(0, 3)),
        ]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _stepLabel('2', 'Observation Particulars', sl),
          const SizedBox(height: 14),
          _buildDropdownField('Plant/Unit', _plant, _plants, (v) => setState(() => _plant = v!), sl),
          _buildTextField('Department/Shop', _dept, Icons.business_rounded, sl),
          _buildTextField('Exact Location', _location, Icons.location_on_outlined, sl,
            suffix: _micButton(_location)),
          _buildDropdownField('Observation Category (WSA 13)', _wsaCause, _wsaCauses, (v) => setState(() => _wsaCause = v!), sl),
          _buildDropdownField('Observation Type', _obsType, const ['Unsafe Act', 'Unsafe Condition'], (v) => setState(() => _obsType = v!), sl),
          _buildDropdownField('Initial Risk Severity', _severity, const ['LOW', 'MEDIUM', 'HIGH', 'CRITICAL'], (v) => setState(() => _severity = v!), sl),
          _buildTextField('Detailed Hazard Description', _description, Icons.description_outlined, sl, maxLines: 3,
            suffix: _micButton(_description)),
          _buildTextField('Immediate Corrective Action', _immediateAction, Icons.flash_on_outlined, sl, maxLines: 2,
            suffix: _micButton(_immediateAction)),
        ],
      ),
    );
  }

  /// ✅ v17: Animated mic button with pulse when active
  Widget _micButton(TextEditingController field) {
    final isActive = _isListening && _activeMicField == field;
    return AnimatedBuilder(
      animation: _micPulse,
      builder: (_, __) => GestureDetector(
        onTap: () => _toggleVoice(field),
        child: Container(
          width: 36, height: 36,
          margin: const EdgeInsets.only(right: 4),
          decoration: BoxDecoration(
            color: isActive ? Colors.red.withOpacity(0.12) : AppColors.accent.withOpacity(0.08),
            shape: BoxShape.circle,
            border: Border.all(
              color: isActive ? Colors.red.withOpacity(0.5) : Colors.transparent,
              width: 1.5)),
          child: Transform.scale(
            scale: isActive ? _micPulse.value * 0.85 : 1.0,
            child: Icon(
              isActive ? Icons.mic : Icons.mic_none_rounded,
              color: isActive ? Colors.red : AppColors.accent,
              size: 18)),
        ),
      ),
    );
  }

  Widget _buildTextField(String label, TextEditingController controller, IconData icon, SL sl, {int maxLines = 1, TextInputType keyboardType = TextInputType.text, Widget? suffix}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        keyboardType: keyboardType,
        style: TextStyle(color: sl.text1, fontSize: 13),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: sl.text3, fontSize: 11.5),
          prefixIcon: Padding(
            padding: const EdgeInsets.only(left: 12, right: 8),
            child: Icon(icon, size: 18, color: AppColors.accent.withOpacity(0.7))),
          prefixIconConstraints: const BoxConstraints(minWidth: 40),
          suffixIcon: suffix,
          filled: true,
          fillColor: sl.isDark ? const Color(0xFF1C1F2E) : const Color(0xFFF8F9FC),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: sl.border.withOpacity(0.5))),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: sl.border.withOpacity(0.5))),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.accent, width: 2)),
        ),
      ),
    );
  }

  Widget _buildDropdownField(String label, String value, List<String> items, ValueChanged<String?> onChanged, SL sl) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: DropdownButtonFormField<String>(
        value: items.contains(value) ? value : items.first,
        items: items.map((e) => DropdownMenuItem(value: e, child: Text(e, style: const TextStyle(fontSize: 12)))).toList(),
        onChanged: onChanged,
        dropdownColor: sl.isDark ? const Color(0xFF252840) : Colors.white,
        style: TextStyle(color: sl.text1, fontSize: 12),
        icon: Icon(Icons.keyboard_arrow_down_rounded, color: sl.text3),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: sl.text3, fontSize: 11.5),
          filled: true,
          fillColor: sl.isDark ? const Color(0xFF1C1F2E) : const Color(0xFFF8F9FC),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: sl.border.withOpacity(0.5))),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: sl.border.withOpacity(0.5))),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.accent, width: 2)),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  BUILD
  // ═══════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final sl = SL.of(context);
    return Container(
      color: Colors.transparent,
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
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 100),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ✅ Show listening banner when voice active
                _listeningBanner(sl),
                _guidanceBox(sl),
                _imageSection(sl),
                _detailsSection(sl),
                const SizedBox(height: 16),
                Row(children: [
                  Expanded(child: _submitBtn(
                    label: 'Save Report',
                    icon:  Icons.save_rounded,
                    colors: const [Color(0xFF16A34A), Color(0xFF059669)],
                    onTap: () => _submit(exportAfter: false),
                  )),
                  const SizedBox(width: 10),
                  Expanded(child: _submitBtn(
                    label: 'Save + PDF',
                    icon:  Icons.picture_as_pdf_rounded,
                    colors: const [Color(0xFF7B5BFF), Color(0xFF06B6D4)],
                    onTap: () => _submit(exportAfter: true),
                  )),
                ]),
                const SizedBox(height: 20),
              ],
            ),
          )),
        ]),
      ),
    );
  }
}
