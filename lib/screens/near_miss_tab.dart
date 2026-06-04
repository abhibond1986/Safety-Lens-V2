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
  XFile? _pickedFile;
  Uint8List? _imageBytes;
  bool _analyzing = false;
  String _step = '';
  Map<String, dynamic>? _aiBrief;

  final _brief = TextEditingController();
  final _dept = TextEditingController();
  final _location = TextEditingController();
  final _people = TextEditingController();
  final _description = TextEditingController();
  final _immediateAction = TextEditingController();

  String _plant = 'SAIL Safety Organisation';
  String _wsaCause = 'Slip / Fall';
  String _severity = 'MEDIUM';
  String _obsType = 'Unsafe Condition';

  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isListening = false;
  TextEditingController? _activeMicField;

  final _plants = const [
    'BSP Bhilai', 'DSP Durgapur', 'RSP Rourkela', 'BSL Bokaro', 'ISP Burnpur', 'SAIL Safety Organisation'
  ];
  final _wsaCauses = const [
    'Burn / Fire', 'Chemical', 'Electrical', 'Fall from Height', 'Fall of Material',
    'Gas Related', 'Hit / Caught / Pressed', 'Hot Metal / Slag / Sub',
    'Machine / Equipment', 'Material Handling', 'Road / Rail', 'Slip / Fall', 'Other',
  ];

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: source, imageQuality: 85);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    setState(() {
      _pickedFile = picked;
      _imageBytes = bytes;
      _analyzing = true;
      _aiBrief = null;
    });
    await _analyzeImage();
  }

  Future<void> _analyzeImage() async {
    final steps = ['Uploaded', 'Analyzing image...', 'Classifying hazard...', 'Pre-filling form...'];
    for (var i = 0; i < steps.length - 1; i++) {
      setState(() => _step = steps[i]);
      await Future.delayed(const Duration(milliseconds: 700));
    }
    try {
      setState(() => _step = steps.last);
      Map<String, dynamic>? result;
      if (kIsWeb) {
        result = await GeminiVision.analyseImageBytes(_imageBytes!);
      } else {
        result = await GeminiVision.analyseImage(File(_pickedFile!.path));
      }
      final hazards = (result?['hazards'] as List?) ?? [];
      final first = hazards.isNotEmpty ? Map<String, dynamic>.from(hazards.first) : null;

      // Build a complete pre-fill from analysis
      final name = first?['name']?.toString() ?? 'Near miss observed';
      final desc = first?['description']?.toString() ?? result?['summary']?.toString() ?? '';
      final action = first?['correctiveAction']?.toString() ?? '';
      final regulation = first?['regulation']?.toString() ?? '';
      final sev = (first?['severity']?.toString() ?? 'MEDIUM').toUpperCase();
      final hazardType = first?['type']?.toString() ?? 'Unsafe Condition';

      // Map AI hazard category to WSA cause dropdown
      String wsaCause = _mapToWsaCause(first?['category']?.toString() ?? '', name);

      // User's plant from profile
      final user = await LocalDB.getCurrentUser();
      String plantFromProfile = user?['plant']?.toString() ?? _plant;
      if (!_plants.contains(plantFromProfile)) plantFromProfile = _plant;

      setState(() {
        _aiBrief = {
          'identified': name,
          'statutory': regulation.isEmpty ? 'Refer Factories Act §35-41' : regulation,
          'type': hazardType,
          'severity': sev,
          'confidence': result?['confidence'] ?? 75,
        };
        // PRE-FILL ALL FIELDS from AI analysis — user can edit if needed
        _brief.text = '$name. $desc'.trim();
        _description.text = desc;
        _immediateAction.text = action;
        _dept.text = user?['department']?.toString() ?? 'Operations';
        _location.text = 'To be confirmed (edit if needed)';
        _people.text = '1';
        _plant = plantFromProfile;
        _wsaCause = wsaCause;
        _severity = sev;
        _obsType = hazardType.toLowerCase().contains('act') ? 'Unsafe Act' : 'Unsafe Condition';
        _analyzing = false;
      });
    } catch (e) {
      setState(() {
        _aiBrief = {
          'identified': 'Manual entry — AI offline',
          'statutory': 'Manual entry needed',
          'type': 'Unsafe condition',
          'severity': 'MEDIUM',
          'confidence': 0,
        };
        _brief.text = 'Describe the near miss observed.';
        _analyzing = false;
      });
    }
  }

  /// Map AI hazard category to one of the WSA cause options
  String _mapToWsaCause(String category, String name) {
    final c = category.toUpperCase();
    final n = name.toLowerCase();
    if (c == 'HEIGHT' || n.contains('fall') || n.contains('height')) return 'Fall from Height';
    if (c == 'ELECTRICAL' || n.contains('electric')) return 'Electrical';
    if (c == 'HOT_WORK' || n.contains('hot') || n.contains('weld')) return 'Burn / Fire';
    if (c == 'GAS' || n.contains('gas')) return 'Gas Related';
    if (c == 'MACHINERY' || n.contains('machine') || n.contains('crane')) return 'Machine / Equipment';
    if (c == 'HOUSEKEEPING' || n.contains('spill') || n.contains('slip')) return 'Slip / Fall';
    if (c == 'PPE') return 'Other';
    return 'Other';
  }

  Future<void> _toggleVoice([TextEditingController? field]) async {
    if (field != null) _activeMicField = field;
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Voice input is not available on web. Please type the location.'),
          backgroundColor: AppColors.amber,
        ),
      );
      return;
    }
    if (!_isListening) {
      bool available = await _speech.initialize();
      if (available) {
        setState(() => _isListening = true);
        _speech.listen(
          localeId: 'en_IN',
          onResult: (result) {
            if (mounted) setState(() { (_activeMicField ?? _location).text = result.recognizedWords; });
          },
        );
      }
    } else {
      _speech.stop();
      setState(() => _isListening = false);
    }
  }

  Future<bool> _submit({bool exportAfter = false}) async {
    if (_location.text.trim().isEmpty || _location.text.trim() == 'To be confirmed (edit if needed)') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter the actual location'), backgroundColor: AppColors.red),
      );
      return false;
    }

    final user = await LocalDB.getCurrentUser();
    final incident = {
      'title': _aiBrief?['identified']?.toString() ?? _brief.text.split('.').first,
      'plant': _plant,
      'dept': _dept.text,
      'location': _location.text,
      'severity': _severity,
      'wsaCategory': _wsaCause,
      'obsType': _obsType,
      'desc': '${_brief.text}\n\n${_description.text}',
      'people': _people.text,
      'immediateAction': _immediateAction.text,
      'type': 'NEAR_MISS',
      'status': 'OPEN',
      'reportedBy': user?['name'] ?? 'Unknown',
      'reportedByPno': user?['pno'] ?? '',
      'date': DateTime.now().toIso8601String(),
      'id': DateTime.now().millisecondsSinceEpoch.toString(),
      // Store image bytes as base64 for PDF inclusion later (web-safe)
      'imageBase64': _imageBytes != null ? base64Encode(_imageBytes!) : null,
    };

    await LocalDB.saveIncident(incident);

    // Push to cloud backend (Google Sheets) — silent, queues if offline
    SyncService.pushIncident(incident).catchError((_) => false);

    if (exportAfter) {
      // Generate and download/share PDF including the image
      try {
        await PdfExport.downloadOrShareIncident(
          incident: incident,
          reporterName: user?['name']?.toString() ?? 'SAIL Safety Officer',
          reporterPno: user?['pno']?.toString() ?? '',
          imageBytes: _imageBytes,
        );
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF export failed: $e'), backgroundColor: AppColors.red),
        );
      }
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(exportAfter ? 'Near Miss saved + PDF exported' : 'Near Miss report submitted'),
          backgroundColor: AppColors.green,
        ),
      );
      // Reset form
      setState(() {
        _pickedFile = null; _imageBytes = null;
        _aiBrief = null;
        _brief.clear();
        _dept.clear();
        _location.clear();
        _people.clear();
        _description.clear();
        _immediateAction.clear();
      });
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: const BoxDecoration(
              color: AppColors.bg2,
              border: Border(bottom: BorderSide(color: AppColors.border, width: 0.5)),
            ),
            child: const Row(
              children: [
                Icon(Icons.warning_amber, size: 18, color: AppColors.amber),
                SizedBox(width: 8),
                Expanded(child: Text('Near Miss Report',
                  style: TextStyle(color: AppColors.text1, fontSize: 15, fontWeight: FontWeight.w600))),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 80),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _guidanceBox(),
                  _imageSection(),
                  _detailsSection(),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(child: GradientButton(
                      label: 'Save Report',
                      icon: Icons.save_outlined,
                      onTap: () => _submit(exportAfter: false),
                      colors: const [Color(0xFF16A34A), Color(0xFF059669)],
                    )),
                    const SizedBox(width: 8),
                    Expanded(child: GradientButton(
                      label: 'Save + PDF',
                      icon: Icons.picture_as_pdf,
                      onTap: () => _submit(exportAfter: true),
                      colors: const [AppColors.accent, AppColors.cyan],
                    )),
                  ]),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _guidanceBox() => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(11),
    decoration: BoxDecoration(
      color: AppColors.amber.withOpacity(0.08),
      border: Border.all(color: AppColors.amber),
      borderRadius: BorderRadius.circular(11),
    ),
    child: const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Icon(Icons.info_outline, size: 12, color: Color(0xFFFCD34D)),
          SizedBox(width: 4),
          Text('Reporting guidance',
            style: TextStyle(color: Color(0xFFFCD34D), fontSize: 11, fontWeight: FontWeight.w600)),
        ]),
        SizedBox(height: 4),
        Text('A near miss is an unplanned event that did NOT result in injury but had the potential to do so. Report freely — no blame, only learning.',
          style: TextStyle(color: AppColors.text2, fontSize: 10, height: 1.5)),
      ],
    ),
  );

  Widget _imageSection() {
    return Container(
      padding: const EdgeInsets.all(14),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _step1('1', 'Image evidence (optional)'),
          const SizedBox(height: 10),
          if (_imageBytes == null && !_analyzing) _emptyImage(),
          if (_analyzing) _analyzingImage(),
          if (_imageBytes != null && !_analyzing && _aiBrief != null) _imageWithBrief(),
        ],
      ),
    );
  }

  Widget _emptyImage() => Column(
    children: [
      GestureDetector(
        onTap: () => _pickImage(ImageSource.camera),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.border, width: 2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Column(
            children: [
              Icon(Icons.camera_alt_outlined, size: 30, color: AppColors.accent),
              SizedBox(height: 8),
              Text('Add photo of hazard',
                style: TextStyle(color: AppColors.text1, fontSize: 12, fontWeight: FontWeight.w600)),
              SizedBox(height: 3),
              Text('AI identifies hazard + writes brief',
                style: TextStyle(color: AppColors.text3, fontSize: 9)),
            ],
          ),
        ),
      ),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: ElevatedButton.icon(
          onPressed: () => _pickImage(ImageSource.camera),
          icon: const Icon(Icons.camera_alt, size: 14, color: Colors.white),
          label: const Text('Capture', style: TextStyle(color: Colors.white, fontSize: 12)),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.accent,
            padding: const EdgeInsets.symmetric(vertical: 11),
          ),
        )),
        const SizedBox(width: 8),
        Expanded(child: OutlinedButton.icon(
          onPressed: () => _pickImage(ImageSource.gallery),
          icon: const Icon(Icons.photo_library, size: 14, color: AppColors.accent),
          label: const Text('Gallery', style: TextStyle(color: AppColors.accent, fontSize: 12)),
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: AppColors.accent, width: 2),
            padding: const EdgeInsets.symmetric(vertical: 11),
          ),
        )),
      ]),
    ],
  );

  Widget _analyzingImage() => Container(
    height: 130,
    decoration: BoxDecoration(
      color: AppColors.card2,
      border: Border.all(color: AppColors.border),
      borderRadius: BorderRadius.circular(10),
      image: _imageBytes != null ? DecorationImage(image: MemoryImage(_imageBytes!), fit: BoxFit.cover) : null,
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
            const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3, color: AppColors.accent)),
            const SizedBox(height: 8),
            Text(_step, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    ),
  );

  Widget _imageWithBrief() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.memory(_imageBytes!, height: 130, fit: BoxFit.cover),
      ),
      const SizedBox(height: 10),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.purple.withOpacity(0.1),
          border: Border.all(color: AppColors.purple, width: 2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.auto_awesome, size: 12, color: Color(0xFFC4B5FD)),
                const SizedBox(width: 4),
                const Text('AI assessment',
                  style: TextStyle(color: Color(0xFFC4B5FD), fontSize: 11, fontWeight: FontWeight.w600)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.amber.withOpacity(0.2),
                    border: Border.all(color: AppColors.amber),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('${_aiBrief!['severity']} · ${_aiBrief!['confidence']}%',
                    style: const TextStyle(color: Color(0xFFFCD34D), fontSize: 8, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _briefRow('Identified', _aiBrief!['identified'].toString()),
            _briefRow('Statutory', _aiBrief!['statutory'].toString()),
            _briefRow('Type', _aiBrief!['type'].toString()),
            const SizedBox(height: 8),
            const Text('AI brief (editable):',
              style: TextStyle(color: AppColors.text3, fontSize: 10, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            TextField(
              controller: _brief,
              maxLines: 4,
              style: const TextStyle(color: AppColors.text1, fontSize: 11, height: 1.5),
              decoration: InputDecoration(
                filled: true,
                fillColor: AppColors.bg2,
                contentPadding: const EdgeInsets.all(10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AppColors.border, width: 1.5),
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Text('You can edit the text directly',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.text4, fontSize: 9)),
          ],
        ),
      ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: () => setState(() { _pickedFile = null; _imageBytes = null; _aiBrief = null; _brief.clear(); }),
        icon: const Icon(Icons.delete_outline, size: 14, color: AppColors.accent),
        label: const Text('Remove image', style: TextStyle(color: AppColors.accent)),
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: AppColors.accent, width: 2),
          padding: const EdgeInsets.symmetric(vertical: 10),
        ),
      ),
    ],
  );

  Widget _briefRow(String k, String v) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 80, child: Text(k,
          style: const TextStyle(color: AppColors.text4, fontSize: 9, fontWeight: FontWeight.w600))),
        Expanded(child: Text(v,
          style: const TextStyle(color: AppColors.text1, fontSize: 10, height: 1.4))),
      ],
    ),
  );

  Widget _detailsSection() {
    final hasImage = _imageBytes != null && _aiBrief != null;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _step1('2', 'Incident details'),
          if (hasImage) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.green.withOpacity(0.1),
                border: Border.all(color: AppColors.green.withOpacity(0.4)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(children: [
                Icon(Icons.auto_awesome, color: AppColors.green, size: 14),
                SizedBox(width: 6),
                Expanded(child: Text(
                  'Fields auto-filled from AI analysis. Review and edit any field if needed.',
                  style: TextStyle(color: AppColors.green, fontSize: 10, fontWeight: FontWeight.w600, height: 1.4),
                )),
              ]),
            ),
          ],
          const SizedBox(height: 12),
          _lbl('Plant'),
          _dropdown(_plant, _plants, (v) => setState(() => _plant = v ?? _plant)),
          const SizedBox(height: 10),
          _lbl('Department'),
          _txt(_dept, hint: 'e.g. Rolling Mill, BF, Coke Oven'),
          const SizedBox(height: 10),
          _lbl('Exact location'),
          Row(children: [
            Expanded(child: _txt(_location, hint: 'e.g. BF-2 Cast House, Bay 4')),
            const SizedBox(width: 6),
            IconButton(
              onPressed: () => _toggleVoice(_location),
              icon: Icon(_isListening ? Icons.mic : Icons.mic_none,
                color: _isListening ? AppColors.red : AppColors.amber, size: 18),
              style: IconButton.styleFrom(
                backgroundColor: (_isListening ? AppColors.red : AppColors.amber).withOpacity(0.15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(color: _isListening ? AppColors.red : AppColors.amber, width: 1.5),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          _lbl('Cause category (WSA 13)'),
          _dropdown(_wsaCause, _wsaCauses, (v) => setState(() => _wsaCause = v ?? _wsaCause)),
          const SizedBox(height: 10),
          _lbl('Type of observation'),
          Row(children: [
            _typeChip('Unsafe Condition', Icons.visibility_outlined, AppColors.amber),
            const SizedBox(width: 6),
            _typeChip('Unsafe Act', Icons.person_off_outlined, AppColors.red),
          ]),
          const SizedBox(height: 10),
          _lbl('Severity (potential)'),
          Row(children: [
            for (final s in ['LOW', 'MED', 'HIGH', 'CRIT']) ...[
              _sevBtn(s),
              if (s != 'CRIT') const SizedBox(width: 6),
            ],
          ]),
          const SizedBox(height: 10),
          _lbl('People involved / present'),
          _txt(_people, hint: 'e.g. Operator, contract workers'),
          const SizedBox(height: 10),
          _lbl('Description (additional context)'),
          _txtWithMic(_description, hint: 'Describe what happened... (or use mic)', lines: 3),
          const SizedBox(height: 10),
          _lbl('Immediate action taken at site'),
          _txtWithMic(_immediateAction, hint: 'e.g. Barricaded the area... (or use mic)', lines: 2),
        ],
      ),
    );
  }

  Widget _step1(String num, String label) => Row(
    children: [
      Container(
        width: 22, height: 22,
        decoration: const BoxDecoration(color: AppColors.accent, shape: BoxShape.circle),
        child: Center(child: Text(num,
          style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700))),
      ),
      const SizedBox(width: 8),
      Text(label.toUpperCase(),
        style: const TextStyle(color: AppColors.text4, fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 0.9)),
    ],
  );

  Widget _lbl(String t) => Builder(builder: (ctx) => Padding(
    padding: const EdgeInsets.only(bottom: 5),
    child: Text(t, style: TextStyle(
      color: SL.of(ctx).text3, fontSize: 11, fontWeight: FontWeight.w700)),
  ));

  Widget _txt(TextEditingController c, {String? hint, int lines = 1}) =>
    Builder(builder: (ctx) {
      final sl = SL.of(ctx);
      return TextField(
        controller: c,
        maxLines: lines,
        style: TextStyle(color: sl.text1, fontSize: 13),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: sl.text4, fontSize: 12),
          filled: true,
          fillColor: sl.card2,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: sl.border, width: 1.5)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: sl.border, width: 1.5)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppColors.accent, width: 2)),
        ),
      );
    });

  Widget _txtWithMic(TextEditingController c, {String? hint, int lines = 1}) =>
    Builder(builder: (ctx) {
      final sl = SL.of(ctx);
      final isMicActive = _isListening && _activeMicField == c;
      return Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isMicActive ? AppColors.red.withOpacity(0.6) : sl.border,
            width: isMicActive ? 2 : 1.5)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: TextField(
            controller: c,
            maxLines: lines,
            style: TextStyle(color: sl.text1, fontSize: 13),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(color: sl.text4, fontSize: 12),
              filled: true,
              fillColor: sl.card2,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              border: OutlineInputBorder(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(10),
                  bottomLeft: Radius.circular(10)),
                borderSide: BorderSide.none),
              enabledBorder: OutlineInputBorder(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(10),
                  bottomLeft: Radius.circular(10)),
                borderSide: BorderSide.none),
              focusedBorder: OutlineInputBorder(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(10),
                  bottomLeft: Radius.circular(10)),
                borderSide: BorderSide.none),
            ),
          )),
          GestureDetector(
            onTap: () => _toggleVoice(c),
            child: Container(
              width: 46,
              height: lines > 1 ? (lines * 24.0 + 22) : 46,
              decoration: BoxDecoration(
                color: isMicActive
                  ? AppColors.red.withOpacity(0.15)
                  : AppColors.accent.withOpacity(0.1),
                borderRadius: const BorderRadius.only(
                  topRight: Radius.circular(10),
                  bottomRight: Radius.circular(10))),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    isMicActive ? Icons.mic_rounded : Icons.mic_none_rounded,
                    color: isMicActive ? AppColors.red : AppColors.accent,
                    size: 20),
                  if (isMicActive) ...[
                    const SizedBox(height: 2),
                    Text('Live', style: TextStyle(
                      color: AppColors.red, fontSize: 8,
                      fontWeight: FontWeight.w700)),
                  ],
                ],
              ),
            ),
          ),
        ]),
      );
    });

  Widget _dropdown(String value, List<String> options, ValueChanged<String?> onChange) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12),
    decoration: BoxDecoration(
      color: AppColors.bg2,
      border: Border.all(color: AppColors.border, width: 1.5),
      borderRadius: BorderRadius.circular(8),
    ),
    child: DropdownButton<String>(
      value: value,
      isExpanded: true,
      underline: const SizedBox(),
      dropdownColor: AppColors.card,
      style: const TextStyle(color: AppColors.text1, fontSize: 12),
      items: options.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
      onChanged: onChange,
    ),
  );

  Widget _typeChip(String label, IconData icon, Color color) => GestureDetector(
    onTap: () => setState(() => _obsType = label),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: _obsType == label ? AppColors.accent.withOpacity(0.15) : AppColors.card2,
        border: Border.all(color: _obsType == label ? AppColors.accent : AppColors.border, width: 1.5),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(color: AppColors.text1, fontSize: 11, fontWeight: FontWeight.w500)),
        ],
      ),
    ),
  );

  Widget _sevBtn(String label) {
    final isSel = (_severity == 'MEDIUM' && label == 'MED') ||
                   (_severity == 'CRITICAL' && label == 'CRIT') ||
                   _severity == label;
    final color = label == 'LOW' ? AppColors.green
                : label == 'MED' ? AppColors.amber
                : label == 'HIGH' ? AppColors.red
                : AppColors.crit;
    final fullSev = label == 'MED' ? 'MEDIUM' : label == 'CRIT' ? 'CRITICAL' : label;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _severity = fullSev),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSel ? color.withOpacity(0.2) : Colors.transparent,
            border: Border.all(color: color, width: 2),
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: Alignment.center,
          child: Text(label,
            style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }
}
