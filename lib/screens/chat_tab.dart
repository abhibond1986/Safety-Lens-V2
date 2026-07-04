// lib/screens/chat_tab.dart
// v9 — KNOWLEDGE BASE UPGRADE
// Changes from original:
//   ✅ Welcome message updated with full topic list
//   ✅ Suggestion chips expanded to cover SG/01–SG/41 + SMPV topics
//   ✅ _send() now calls Apps Script AI with full regulatory system prompt
//   ✅ Online mode: Suraksha Saathi uses Gemini with SAIL knowledge prompt
//   ✅ Offline mode: LocalAI.chat() with full KB (SG/01–SG/41)
//   ✅ All original UI, upload, admin, KB manager preserved exactly
//   ✅ NEW: ANSWER STYLE rewritten — crisp, structured, max 8 lines

import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../main.dart';
import '../services/local_ai.dart';
import '../services/local_db.dart';
import '../services/knowledge_service.dart';
import '../widgets/universal_app_bar.dart';

class ChatTab extends StatefulWidget {
  final Map<String, dynamic>? user;
  final VoidCallback? toggleTheme;
  final VoidCallback? onSignOut;
  final bool isDark;

  const ChatTab({
    super.key,
    this.user,
    this.toggleTheme,
    this.onSignOut,
    this.isDark = true,
  });
  @override
  State<ChatTab> createState() => _ChatTabState();
}

class _ChatTabState extends State<ChatTab> {
  final _ctrl       = TextEditingController();
  final _scrollCtrl = ScrollController();
  final List<Map<String, dynamic>> _messages = [];
  Map<String, dynamic>? _user;
  bool _isAdmin    = false;
  int  _kbDocCount = 0;
  bool _aiLoading  = false;

  // ── Apps Script backend URL ──────────────────────────────────────
  static const String _backendUrl =
      'https://script.google.com/macros/s/AKfycbzDiT4OSvlDUxvcM9DYJ_-SiB1HyDrgXtYflGfmqJRH9wnZZusj5GqX9frCx64rkd61Rg/exec';

  // ── Suraksha Saathi system prompt ────────────────────────────────
  // Same regulatory knowledge as AI Scan — shared knowledge base
  static const String _systemPrompt =
    'You are SAIL Suraksha Saathi, an expert industrial safety assistant for '
    'Steel Authority of India Limited (SAIL) steel plants. '
    'You answer questions from safety officers, AGMs, GMs, supervisors, and workers.\n\n'

    'YOUR KNOWLEDGE BASE:\n'
    '• Ministry of Steel Safety Guidelines SG/01–SG/25 (2019/2020)\n'
    '• Ministry of Steel Process-Based Safety Guidelines SG/26–SG/41 (2024)\n'
    '• Factories Act 1948 — all safety sections (S21–S39, S111A)\n'
    '• IS 14489:2018 — OHS Code for Steel Plants (Clauses 4–10)\n'
    '• SMPV Rules 2016 — Pressure Vessels & Gas Cylinders (Rules 10–22)\n'
    '• CEA Regulations 2010 — Electrical Safety (Reg 36, 44, 45, 46, 47)\n'
    '• Indian Electricity Rules 1956 — (Rule 29, 44, 50, 61, 64)\n'
    '• BIS PPE Standards: IS 2925, IS 3521, IS 4912, IS 5852, IS 5983, IS 6994, IS 9167\n'
    '• Gas Cylinder Safety: IS 15222, IS 8198, cylinder colour codes\n'
    '• WSA 13 Cause Categories\n'
    '• ILO Code of Practice on Safety & Health in Steel Industry 2005\n\n'

    'KEY REGULATORY RULES — NEVER GET WRONG:\n'
    '1. Working at height → ALWAYS FA 1948 S32 + IS 3521:1999. NEVER S36 for height.\n'
    '2. S36 = confined space / dangerous fumes ONLY\n'
    '3. O2 + flammable gas cylinders: minimum 6 metres separation (SMPV Rule 14 Table-3)\n'
    '4. Cylinder colour: Oxygen = Black body/White shoulder; Acetylene = Maroon; LPG = Silver\n'
    '5. LOTOTO = Lock Out, Tag Out, TRY OUT — each person their own lock\n'
    '6. CO in BF gas: 25–28%; TLV 50 ppm; explosive range 35–74%\n'
    '7. Confined space O2 safe range: 19.5–23.5%\n'
    '8. Ladle preheat minimum: 800°C before receiving hot metal\n'
    '9. Safety helmet colours: White=Officer, Yellow=Supervisor, Blue=Worker, Green=Visitor\n'
    '10. Harness mandatory above 1.8m; anchor min 15kN (IS 3521)\n\n'

    // ─────────────────────────────────────────────────────────────
    // ✅ NEW: STRUCTURED ANSWER STYLE — MAX 8 LINES, NO RAMBLING
    // ─────────────────────────────────────────────────────────────
    'ANSWER STYLE — STRICTLY STRUCTURED, CRISP, NO RAMBLING:\n'
    '⚠️ MAX 8 lines total. Never write paragraphs. Never repeat the question.\n'
    'Use this EXACT structure for every answer:\n\n'

    '【TOPIC NAME】 (one line, bracketed)\n\n'

    '📋 Regulation:\n'
    '• Specific IS / FA / SG / SMPV reference — single line each, max 3 lines\n\n'

    '⚡ Key Points:\n'
    '• Crisp 1-line bullet — max 4 bullets\n'
    '• Use exact numbers, never vague terms\n\n'

    '✅ Action:\n'
    '• 1-2 line corrective action with action verb '
    '(Stop / Provide / Install / Check)\n\n'

    'STRICT RULES:\n'
    '• NEVER write more than 8 total lines\n'
    '• NEVER include disclaimers, preambles, or "Namaste/Hello" greetings\n'
    '• NEVER repeat the user question back\n'
    '• NEVER write "It is important to note that..." or similar fluff\n'
    '• NEVER cite the same regulation twice in one answer\n'
    '• If language is Hindi, respond fully in Hindi (देवनागरी)\n'
    '• If unsure of a specific value, omit it — do NOT speculate\n\n'

    'LINE OF FIRE (LOF) KNOWLEDGE:\n'
    '"Line of Fire" = person positioned where energy release, object movement, '
    'or material flow could strike them.\n'
    'Common LOFs in steel plants:\n'
    '• Suspended load (crane/hoist) path\n'
    '• Moving conveyor/roller table zone\n'
    '• Molten metal/slag/ladle splash radius\n'
    '• Vehicle/loco/wagon swing/travel path\n'
    '• Falling objects from height work\n'
    '• Pressurized system (steam/hydraulic/gas) burst zone\n'
    '• Rotating equipment contact zone\n'
    '• Flying particles from grinding/cutting\n'
    '• Unstable stacked materials collapse zone\n'
    '• Arc flash zone near electrical panels\n'
    'LOF corrective actions: barricading, exclusion zones, interlocks, '
    'spotter deployment, awareness training, standoff distance marking.\n\n'

    'TOPICS YOU CAN ANSWER:\n'
    'Gas cylinder storage and colour codes, working at height, confined space entry, '
    'LOTOTO energy isolation, hot work PTW, blast furnace gas safety, coke oven safety, '
    'hot metal handling, electrical safety CEA regulations, machinery guarding, '
    'PPE selection and standards, crane and lifting, barricading, contractor safety, '
    'incident classification (LTI/FAC/RWC/near miss), WSA 13 causes, '
    'Line of Fire (LOF) hazards and controls, '
    'emergency response (CO exposure, hot metal fire, electrical shock), '
    'IS 14489 clauses, SMPV Rules, Ministry of Steel guidelines SG/01–SG/41';

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    final u    = await LocalDB.getCurrentUser();
    final docs = await LocalDB.getKnowledgeDocs();
    if (!mounted) return;
    setState(() {
      _user = u;
      final desig = (u?['designation']?.toString() ?? '').toLowerCase();
      _isAdmin = desig.contains('agm') || desig.contains('gm') ||
                 desig.contains('manager') || desig.contains('admin') ||
                 (u?['isAdmin']?.toString().toLowerCase() == 'true');
      _kbDocCount = docs.length;
      final firstName = u?['name']?.toString().split(' ').first ?? 'there';
      _messages.add({
        'role': 'ai',
        'text': 'नमस्ते $firstName! मैं SAIL Suraksha Saathi हूँ — आपका सुरक्षा साथी।\n\n'
            'I know the complete SAIL safety knowledge base:\n\n'
            '📋 Ministry of Steel Guidelines SG/01–SG/41\n'
            '⚖️ Factories Act 1948 (S21–S39)\n'
            '🔴 SMPV Rules 2016 (gas cylinders, pressure vessels)\n'
            '⚡ CEA Regulations 2023 (electrical safety)\n'
            '🏭 Process safety: Blast Furnace, Coke Ovens, EAF, BOF, Rolling Mills\n'
            '⚠️ Line of Fire (LOF) hazards & controls\n'
            '🦺 IS 14489:2018, all BIS PPE standards\n'
            '📊 WSA 13 causes + incident classification\n'
            '🚨 Emergency response procedures\n'
            '${_kbDocCount > 0 ? "\n📚 + $_kbDocCount uploaded reference documents" : ""}\n\n'
            'Ask me anything about safety!',
      });
    });
  }

  // ── SEND MESSAGE ─────────────────────────────────────────────────
  void _send(String q) async {
    if (q.trim().isEmpty) return;
    setState(() {
      _messages.add({'role': 'user', 'text': q.trim()});
      _ctrl.clear();
      _aiLoading = true;
    });
    _scrollToBottom();

    // 1. Search uploaded KB docs
    final kbResults = await LocalDB.searchKnowledge(q.trim());

    // 2. Try online AI (Apps Script → Gemini with full safety prompt)
    String? onlineAnswer;
    try {
      onlineAnswer = await _askOnlineAI(q.trim(), kbResults);
    } catch (_) {}

    // 3. Build final answer
    String answer;
    List<Map<String, dynamic>>? sources;

    if (onlineAnswer != null && onlineAnswer.isNotEmpty) {
      // Online AI answered
      if (kbResults.isNotEmpty) {
        final cleanResults = kbResults.where((r) {
          final snippet = r['snippet']?.toString() ?? '';
          return _isReadableText(snippet) && snippet.trim().length > 30;
        }).toList();
        if (cleanResults.isNotEmpty) sources = cleanResults;
      }
      answer = onlineAnswer;
    } else {
      // Offline: LocalAI.chat() with full KB
      final builtIn = LocalAI.chat(q.trim());

      if (kbResults.isNotEmpty) {
        final cleanResults = kbResults.where((r) {
          final snippet = r['snippet']?.toString() ?? '';
          return _isReadableText(snippet) && snippet.trim().length > 30;
        }).toList();

        if (cleanResults.isNotEmpty) {
          final buffer = StringBuffer();
          buffer.writeln('📚 From your uploaded knowledge base:\n');
          for (var i = 0; i < cleanResults.length; i++) {
            final r = cleanResults[i];
            final snippet = _sanitizeSnippet(r['snippet']?.toString() ?? '');
            if (snippet.isEmpty) continue;
            buffer.writeln('${i + 1}. From "${r['title']}":');
            buffer.writeln('   $snippet\n');
          }
          buffer.writeln('\n💡 Standard guidance:');
          buffer.writeln(builtIn);
          answer  = buffer.toString();
          sources = cleanResults;
        } else {
          answer = builtIn;
        }
      } else {
        answer = builtIn;
      }
    }

    if (mounted) {
      setState(() {
        _aiLoading = false;
        _messages.add({
          'role': 'ai',
          'text': answer,
          if (sources != null && sources.isNotEmpty) 'sources': sources,
        });
      });
      _scrollToBottom();
    }
  }

  // ── ONLINE AI CALL (Apps Script → Gemini with safety prompt + KB) ─────
  Future<String?> _askOnlineAI(String question, List kbResults) async {
    try {
      // ★ v25: Get comprehensive KB context from KnowledgeService
      final kbContext = await KnowledgeService.getKbDocsContext(question, maxDocs: 3);

      // Also include any directly-searched results (legacy path)
      String legacyKb = '';
      if (kbResults.isNotEmpty) {
        final cleanKb = kbResults.where((r) {
          final s = r['snippet']?.toString() ?? '';
          return _isReadableText(s) && s.length > 30;
        }).take(2).toList();
        if (cleanKb.isNotEmpty) {
          legacyKb = '\n\nADDITIONAL KB MATCHES:\n' +
              cleanKb.map((r) =>
                  '- ${r['title']}: ${_sanitizeSnippet(r['snippet']?.toString() ?? '')}')
                  .join('\n');
        }
      }

      final fullPrompt = '$_systemPrompt\n\n'
          '$kbContext$legacyKb\n\n'
          'QUESTION: $question\n\n'
          'Answer using the EXACT structured format above. '
          'Max 8 lines. No greetings, no fluff.';

      final body = jsonEncode({
        'action': 'gemini',
        'prompt': fullPrompt,
      });

      final response = await http.post(
        Uri.parse(_backendUrl),
        body: body,
        headers: {'Content-Type': 'text/plain;charset=utf-8'},
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final result = data['result']?.toString() ?? '';
        if (result.isNotEmpty && result.length > 20) return result;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut);
      }
    });
  }

  // ── TEXT QUALITY HELPERS ─────────────────────────────────────────
  bool _isReadableText(String text) {
    if (text.trim().length < 20) return false;
    final lower = text.toLowerCase();
    final pdfMarkers = ['endobj','lendstream','fontdescriptor','winansienco',
        'firstchar','lastchar','basefont','subtype truetype','fontname','capheight',
        'avgwidth','stemv','fontbbox','fontfile2','extgstate','/type /font','endstream'];
    for (final m in pdfMarkers) { if (lower.contains(m)) return false; }
    int badChars = 0;
    final sample = text.length > 300 ? text.substring(0, 300) : text;
    for (int i = 0; i < sample.length; i++) {
      final c = sample.codeUnitAt(i);
      if (c < 9 || (c > 13 && c < 32) || c == 127) badChars++;
    }
    if (badChars / sample.length > 0.15) return false;
    final words = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return false;
    final avgLen = words.fold(0, (s, w) => s + w.length) / words.length;
    if (avgLen > 25) return false;
    if (RegExp(r'[A-Z]{8,}').hasMatch(text)) return false;
    return true;
  }

  String _sanitizeSnippet(String raw) {
    final cleaned = raw.replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ').trim();
    if (cleaned.length <= 400) return cleaned;
    final cut = cleaned.lastIndexOf('.', 400);
    if (cut > 100) return '${cleaned.substring(0, cut + 1)}...';
    return '${cleaned.substring(0, 400)}...';
  }

  // ── PDF TEXT EXTRACTION ─────────────────────────────────────────
  String _extractTextFromBytes(List<int> bytes) {
    try {
      final raw = String.fromCharCodes(
          bytes.where((b) => b >= 32 && b <= 126).toList());
      final extracted = StringBuffer();
      final btEt = RegExp(r'BT\s([\s\S]*?)ET', multiLine: true);
      final tj   = RegExp(r'\(([^)]{1,200})\)\s*(?:Tj|TJ|")');
      for (final block in btEt.allMatches(raw)) {
        final content = block.group(1) ?? '';
        for (final m in tj.allMatches(content)) {
          final word = m.group(1)?.trim() ?? '';
          if (word.length >= 2 && _looksLikeWord(word)) {
            extracted.write('$word ');
          }
        }
      }
      String result = extracted.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
      if (result.length < 100) {
        final wordList = <String>[];
        final wordRx = RegExp(r'\b[A-Za-z]{2,}(?:[A-Za-z0-9 ,.\-:]{0,60})?\b');
        for (final m in wordRx.allMatches(raw)) {
          final w = m.group(0)?.trim() ?? '';
          if (w.length >= 3 && _looksLikeWord(w)) wordList.add(w);
        }
        result = wordList.join(' ').replaceAll(RegExp(r'\s+'), ' ').trim();
      }
      return result;
    } catch (_) { return ''; }
  }

  bool _looksLikeWord(String w) {
    if (w.isEmpty) return false;
    final letters = w.replaceAll(RegExp(r'[^a-zA-Z]'), '');
    if (letters.length / w.length < 0.6) return false;
    if (RegExp(r'[A-Z]{6,}').hasMatch(w)) return false;
    return true;
  }

  String _cleanExtractedText(String text) {
    final words = text.split(RegExp(r'\s+'));
    final clean = words.where((w) {
      if (w.length < 2) return false;
      final letters = RegExp(r'[a-zA-Z]').allMatches(w).length;
      if (letters == 0) return false;
      if (letters / w.length < 0.5) return false;
      final lower = w.toLowerCase();
      final rejects = ['endobj','stream','xref','trailer','startxref',
                       'fontname','encoding','widths','bbox','procset'];
      for (final r in rejects) { if (lower == r) return false; }
      return true;
    });
    return clean.join(' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  // ── KB UPLOAD ────────────────────────────────────────────────────
  Future<void> _uploadKnowledgeDoc() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'doc', 'docx', 'txt'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      final filename = file.name;
      final bytes = file.bytes;
      if (bytes == null) {
        _showSnack('Cannot read file.', AppColors.red); return;
      }
      String extractedText = '';
      final ext = filename.split('.').last.toLowerCase();
      if (ext == 'txt') {
        try { extractedText = utf8.decode(bytes, allowMalformed: false); }
        catch (_) { extractedText = String.fromCharCodes(bytes.where((b) => b >= 32 && b <= 126).toList()); }
      } else {
        extractedText = _extractTextFromBytes(bytes);
        extractedText = _cleanExtractedText(extractedText);
      }
      if (!_isReadableText(extractedText) || extractedText.trim().length < 50) {
        if (mounted) _showPdfHelpDialog(filename); return;
      }
      await LocalDB.addKnowledgeDoc(
        title: filename.replaceAll(RegExp(r'\.(pdf|txt|doc|docx)$', caseSensitive: false), '')
            .replaceAll('_', ' ').trim(),
        content: extractedText,
        source: filename,
      );
      final docs = await LocalDB.getKnowledgeDocs();
      if (mounted) {
        setState(() => _kbDocCount = docs.length);
        _showSnack('Added "$filename" to knowledge base', AppColors.green);
      }
    } catch (e) { _showSnack('Upload failed: $e', AppColors.red); }
  }

  void _showPdfHelpDialog(String filename) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: SL.of(context).card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Icon(Icons.info_outline, color: AppColors.amber, size: 20),
          SizedBox(width: 8),
          Text('Could not read file', style: TextStyle(
              color: AppColors.text1, fontSize: 15, fontWeight: FontWeight.w700)),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('"$filename" appears to be image-based or binary-encoded.',
                style: const TextStyle(color: AppColors.text2, fontSize: 13)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.accent.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.accent.withOpacity(0.3))),
              child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('✅  Better options:', style: TextStyle(
                    color: AppColors.accent, fontSize: 12, fontWeight: FontWeight.w700)),
                SizedBox(height: 6),
                Text('1. Copy text → paste via Admin Panel → Add Text Entry',
                    style: TextStyle(color: AppColors.text2, fontSize: 12, height: 1.4)),
                Text('2. Save as .txt and upload that instead',
                    style: TextStyle(color: AppColors.text2, fontSize: 12, height: 1.4)),
                Text('3. Use a text-based PDF (not scanned/image PDF)',
                    style: TextStyle(color: AppColors.text2, fontSize: 12, height: 1.4)),
              ])),
          ]),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.accent),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Got it', style: TextStyle(color: Colors.white))),
        ],
      ),
    );
  }

  Future<void> _showKnowledgeManager() async {
    final docs = await LocalDB.getKnowledgeDocs();
    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      backgroundColor: SL.of(context).card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSB) {
        return Padding(
          padding: EdgeInsets.only(left: 16, right: 16, top: 16,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 16),
          child: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Icon(Icons.library_books_outlined,
                    color: AppColors.amber, size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text('Knowledge Base (Admin)',
                    style: TextStyle(color: SL.of(context).text1,
                        fontSize: 15, fontWeight: FontWeight.w700))),
                IconButton(icon: const Icon(Icons.close, color: AppColors.text3),
                    onPressed: () => Navigator.pop(ctx)),
              ]),
              const Text('💡 Best results with .txt files or Admin Panel text entries.',
                  style: TextStyle(color: AppColors.text3, fontSize: 11, height: 1.4)),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: () async {
                  await _uploadKnowledgeDoc();
                  final fresh = await LocalDB.getKnowledgeDocs();
                  setSB(() { docs..clear()..addAll(fresh); });
                },
                icon: const Icon(Icons.upload_file, color: Colors.white),
                label: const Text('Upload document (.txt recommended)',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.amber,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  minimumSize: const Size(double.infinity, 0),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
              ),
              const SizedBox(height: 14),
              Text('UPLOADED (${docs.length})',
                  style: const TextStyle(color: AppColors.text4, fontSize: 9,
                      letterSpacing: 0.8, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              docs.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(20),
                    child: Center(child: Text(
                        'No documents yet. Upload reference material to enhance the chatbot.',
                        style: TextStyle(color: AppColors.text4, fontSize: 11),
                        textAlign: TextAlign.center)))
                : ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 240),
                    child: ListView.builder(
                      shrinkWrap: true, itemCount: docs.length,
                      itemBuilder: (_, i) {
                        final d = docs[i];
                        final charCount = (d['content']?.toString() ?? '').length;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: SL.of(context).card2,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: SL.of(context).border)),
                          child: Row(children: [
                            const Icon(Icons.description_outlined,
                                color: AppColors.amber, size: 16),
                            const SizedBox(width: 8),
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(d['title']?.toString() ?? '',
                                  style: TextStyle(color: SL.of(context).text1,
                                      fontSize: 11, fontWeight: FontWeight.w600),
                                  overflow: TextOverflow.ellipsis),
                              Text('$charCount chars · ${d['uploadedBy'] ?? '—'}',
                                  style: const TextStyle(color: AppColors.text4, fontSize: 9)),
                            ])),
                            IconButton(
                              icon: const Icon(Icons.delete_outline,
                                  color: AppColors.red, size: 18),
                              onPressed: () async {
                                await LocalDB.deleteKnowledgeDoc(d['id'].toString());
                                final fresh = await LocalDB.getKnowledgeDocs();
                                setSB(() { docs..clear()..addAll(fresh); });
                                if (mounted) setState(() => _kbDocCount = fresh.length);
                              }),
                          ]));
                      })),
            ]));
      }),
    );
  }

  void _showSnack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: color));
  }

  // ── BUILD ────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final sl = SL.of(context);
    return SafeArea(
      child: Column(children: [
        // ── Header ────────────────────────────────────────────────
        UniversalAppBar(
          title: 'Suraksha Saathi',
          subtitle: 'AI Safety Assistant',
          user: widget.user ?? _user,
          toggleTheme: widget.toggleTheme,
          onSignOut: widget.onSignOut,
          isDark: widget.isDark,
          showExport: false,
        ),

        // ── Messages ──────────────────────────────────────────────
        Expanded(
          child: ListView(
            controller: _scrollCtrl,
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
            children: [
              ..._messages.map((m) => _bubble(
                  m['role'].toString(), m['text'].toString(),
                  m['sources'] as List?)),
              if (_aiLoading) _loadingBubble(),
              if (_messages.length <= 1 && !_aiLoading) _suggestionChips(),
            ],
          ),
        ),

        // ── Input bar ─────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          decoration: BoxDecoration(
            color: sl.bg2,
            border: Border(top: BorderSide(color: sl.border, width: 0.8))),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _ctrl,
                style: TextStyle(color: sl.text1, fontSize: 12),
                decoration: InputDecoration(
                  hintText: 'Ask about gas cylinders, height safety, LOTOTO, BF gas...',
                  hintStyle: TextStyle(color: sl.text4, fontSize: 11),
                  filled: true, fillColor: sl.card2,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: sl.border, width: 1.5)),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: sl.border, width: 1.5)),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: AppColors.amber, width: 2))),
                onSubmitted: _aiLoading ? null : _send)),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _aiLoading ? null : () => _send(_ctrl.text),
              child: Container(
                width: 42, height: 42,
                decoration: BoxDecoration(
                  color: _aiLoading ? sl.border : AppColors.amber,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: _aiLoading ? null : [BoxShadow(
                      color: AppColors.amber.withOpacity(0.35),
                      blurRadius: 10, offset: const Offset(0, 3))]),
                child: _aiLoading
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.send_rounded, color: Colors.white, size: 18))),
          ]),
        ),
      ]),
    );
  }

  // ── LOADING BUBBLE ───────────────────────────────────────────────
  Widget _loadingBubble() {
    final sl = SL.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(width: 30, height: 30,
          decoration: const BoxDecoration(shape: BoxShape.circle,
            gradient: LinearGradient(colors: [AppColors.amber, Color(0xFFFF8C00)])),
          child: const Icon(Icons.shield_outlined, color: Colors.white, size: 14)),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: sl.card,
            borderRadius: BorderRadius.circular(14).copyWith(
                topLeft: const Radius.circular(4)),
            border: Border.all(color: sl.border.withOpacity(0.5))),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(width: 12, height: 12,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppColors.amber)),
            const SizedBox(width: 8),
            Text('Thinking...', style: TextStyle(color: sl.text3, fontSize: 11)),
          ])),
      ]));
  }

  Widget _bubble(String role, String text, List? sources) {
    final isUser = role == 'user';
    final sl     = SL.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment:
          isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            Container(width: 30, height: 30,
              decoration: const BoxDecoration(shape: BoxShape.circle,
                gradient: LinearGradient(
                    colors: [AppColors.amber, Color(0xFFFF8C00)])),
              child: const Icon(Icons.shield_outlined,
                  color: Colors.white, size: 14)),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
              decoration: BoxDecoration(
                color: isUser ? AppColors.accent : sl.card,
                borderRadius: BorderRadius.circular(14).copyWith(
                  topLeft: isUser ? const Radius.circular(14) : const Radius.circular(4),
                  topRight: isUser ? const Radius.circular(4) : const Radius.circular(14)),
                border: Border.all(color: isUser
                    ? AppColors.accentDark : sl.border.withOpacity(0.5))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(text, style: TextStyle(
                    color: isUser ? Colors.white : sl.text1,
                    fontSize: 12.5, height: 1.55)),
                if (sources != null && sources.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppColors.amber.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppColors.amber.withOpacity(0.4))),
                    child: Text(
                      '📎 ${sources.length} source${sources.length > 1 ? "s" : ""} from knowledge base',
                      style: const TextStyle(color: AppColors.amber,
                          fontSize: 9, fontWeight: FontWeight.w600))),
                ],
              ]),
            )),
          if (isUser) const SizedBox(width: 30),
        ]));
  }

  Widget _suggestionChips() {
    final sl = SL.of(context);
    // Expanded suggestion chips covering full knowledge base
    final suggestions = [
      'Gas cylinder colour codes',
      'Working at height — what regulation?',
      'LOTOTO step by step',
      'Blast furnace gas safety',
      'Confined space entry checklist',
      'Hot work permit requirements',
      'CO gas exposure emergency',
      'Incident classification LTI FAC RWC',
      'WSA 13 causes list',
      'Contractor safety requirements',
      'Line of Fire hazards in steel plant',
      'Liquid metal — dry ladle rule',
      'All Ministry of Steel guidelines list',
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('SUGGESTED QUESTIONS',
          style: TextStyle(color: sl.text4, fontSize: 9,
              fontWeight: FontWeight.w700, letterSpacing: 0.8)),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6,
          children: suggestions.map((s) => GestureDetector(
            onTap: () => _send(s),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: sl.card,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: sl.border)),
              child: Text(s, style: TextStyle(color: sl.text2, fontSize: 10)))
          )).toList()),
      ]));
  }
}
