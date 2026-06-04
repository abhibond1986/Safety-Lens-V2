import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../main.dart';
import '../services/local_ai.dart';
import '../services/local_db.dart';

class ChatTab extends StatefulWidget {
  const ChatTab({super.key});

  @override
  State<ChatTab> createState() => _ChatTabState();
}

class _ChatTabState extends State<ChatTab> {
  final _ctrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final List<Map<String, dynamic>> _messages = [];
  Map<String, dynamic>? _user;
  bool _isAdmin = false;
  int _kbDocCount = 0;

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    final u = await LocalDB.getCurrentUser();
    final docs = await LocalDB.getKnowledgeDocs();
    if (!mounted) return;
    setState(() {
      _user = u;
      // Anyone with "AGM" or "GM" or "Manager" in designation is admin (simplified)
      final desig = (u?['designation']?.toString() ?? '').toLowerCase();
      _isAdmin = desig.contains('agm') || desig.contains('gm') || desig.contains('manager') || desig.contains('admin');
      _kbDocCount = docs.length;
      final firstName = (u?['name']?.toString().split(' ').first) ?? 'there';
      _messages.add({
        'role': 'ai',
        'text': 'नमस्ते $firstName! मैं SAIL Suraksha Saathi हूँ — आपका सुरक्षा साथी।\n\n'
            'Hi! I am SAIL Suraksha Saathi — your safety companion. '
            'Ask me about IS codes, Factories Act, PPE, LOTO, confined space, hot work, '
            'or any SAIL safety procedure. ${_kbDocCount > 0 ? "I can also search through $_kbDocCount uploaded reference documents." : ""}',
      });
    });
  }

  void _send(String q) async {
    if (q.trim().isEmpty) return;
    setState(() {
      _messages.add({'role': 'user', 'text': q.trim()});
      _ctrl.clear();
    });
    _scrollToBottom();

    // Search knowledge base first (uploaded docs)
    final kbResults = await LocalDB.searchKnowledge(q.trim());

    Future.delayed(const Duration(milliseconds: 500), () {
      final builtInAnswer = LocalAI.chat(q.trim());

      String answer;
      List<Map<String, dynamic>>? sources;

      if (kbResults.isNotEmpty) {
        // Combine KB results with built-in answer
        final buffer = StringBuffer();
        buffer.writeln('📚 From your uploaded knowledge base:\n');
        for (var i = 0; i < kbResults.length; i++) {
          final r = kbResults[i];
          buffer.writeln('${i + 1}. From "${r['title']}":');
          buffer.writeln('   ${r['snippet']}\n');
        }
        buffer.writeln('\n💡 Standard guidance:');
        buffer.writeln(builtInAnswer);
        answer = buffer.toString();
        sources = kbResults;
      } else {
        answer = builtInAnswer;
      }

      if (mounted) {
        setState(() => _messages.add({
          'role': 'ai',
          'text': answer,
          if (sources != null) 'sources': sources,
        }));
        _scrollToBottom();
      }
    });
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(_scrollCtrl.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    });
  }

  // =============================================================
  // ADMIN: Knowledge base upload
  // =============================================================
  Future<void> _uploadKnowledgeDoc() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'doc', 'docx', 'txt'],
        withData: true, // Need bytes for web
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      final filename = file.name;

      // For web, we have bytes; for mobile we may have a path
      final bytes = file.bytes;
      if (bytes == null) {
        _showSnack('Cannot read file. Try a different file.', AppColors.red);
        return;
      }

      // Extract text content
      String extractedText = '';
      final ext = filename.split('.').last.toLowerCase();
      if (ext == 'txt') {
        extractedText = String.fromCharCodes(bytes);
      } else {
        // For PDF/DOC/DOCX we can't fully parse in-app without heavy libs.
        // Honest: extract printable ASCII as a basic approximation.
        // For production: a backend service should do proper extraction.
        extractedText = _extractTextFromBytes(bytes);
      }

      if (extractedText.trim().length < 50) {
        _showSnack(
          'Could not extract enough text from this file. PDF/Word parsing on web is limited — try a .txt file for best results.',
          AppColors.amber,
        );
        return;
      }

      await LocalDB.addKnowledgeDoc(
        title: filename,
        content: extractedText,
        source: 'admin_upload',
      );

      final docs = await LocalDB.getKnowledgeDocs();
      if (mounted) {
        setState(() => _kbDocCount = docs.length);
        _showSnack('Added "$filename" to knowledge base ($_kbDocCount total)', AppColors.green);
      }
    } catch (e) {
      _showSnack('Upload failed: $e', AppColors.red);
    }
  }

  /// Honest text extraction — pulls readable ASCII strings from raw bytes.
  /// Works reasonably for PDFs that aren't heavily encoded. For production,
  /// use a backend service or a Dart PDF text-extraction library.
  String _extractTextFromBytes(List<int> bytes) {
    final buffer = StringBuffer();
    String current = '';
    for (final b in bytes) {
      // Printable ASCII range + common whitespace
      if ((b >= 32 && b <= 126) || b == 10 || b == 13 || b == 9) {
        current += String.fromCharCode(b);
      } else {
        if (current.length >= 5) buffer.write('$current ');
        current = '';
      }
    }
    if (current.length >= 5) buffer.write(current);
    // Clean up: collapse multiple spaces, remove obvious binary garbage
    var text = buffer.toString();
    text = text.replaceAll(RegExp(r'\s+'), ' ');
    return text.trim();
  }

  Future<void> _showKnowledgeManager() async {
    final docs = await LocalDB.getKnowledgeDocs();
    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSB) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16, right: 16, top: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Icon(Icons.library_books_outlined, color: AppColors.amber, size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text('Knowledge Base (Admin)',
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 15, fontWeight: FontWeight.w700))),
                IconButton(icon: const Icon(Icons.close, color: AppColors.text3), onPressed: () => Navigator.pop(ctx)),
              ]),
              const Text(
                'Upload reference documents (PDF, Word, TXT) to teach Suraksha Saathi about your plant-specific procedures.',
                style: TextStyle(color: AppColors.text3, fontSize: 11, height: 1.4),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: () async {
                  await _uploadKnowledgeDoc();
                  final fresh = await LocalDB.getKnowledgeDocs();
                  setSB(() => docs..clear()..addAll(fresh));
                },
                icon: const Icon(Icons.upload_file, color: Colors.white),
                label: const Text('Upload document', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.amber,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  minimumSize: const Size(double.infinity, 0),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
              const SizedBox(height: 14),
              Text('UPLOADED (${docs.length})',
                style: const TextStyle(color: AppColors.text4, fontSize: 9, letterSpacing: 0.8, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              if (docs.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(child: Text('No documents yet. Upload reference material to enhance the chatbot.',
                    style: TextStyle(color: AppColors.text4, fontSize: 11), textAlign: TextAlign.center)),
                )
              else
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 240),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: docs.length,
                    itemBuilder: (_, i) {
                      final d = docs[i];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surface,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Row(children: [
                          const Icon(Icons.description_outlined, color: AppColors.amber, size: 16),
                          const SizedBox(width: 8),
                          Expanded(child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(d['title']?.toString() ?? '',
                                style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 11, fontWeight: FontWeight.w600),
                                overflow: TextOverflow.ellipsis),
                              Text('${(d['content']?.toString() ?? '').length} chars · by ${d['uploadedBy']}',
                                style: const TextStyle(color: AppColors.text4, fontSize: 9)),
                            ],
                          )),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, color: AppColors.red, size: 18),
                            onPressed: () async {
                              await LocalDB.deleteKnowledgeDoc(d['id'].toString());
                              final fresh = await LocalDB.getKnowledgeDocs();
                              setSB(() => docs..clear()..addAll(fresh));
                              if (mounted) setState(() => _kbDocCount = fresh.length);
                            },
                          ),
                        ]),
                      );
                    },
                  ),
                ),
            ],
          ),
        );
      }),
    );
  }

  void _showSnack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          // Header bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor, width: 0.5)),
            ),
            child: Row(children: [
              const Icon(Icons.shield_outlined, size: 20, color: AppColors.amber),
              const SizedBox(width: 8),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('SAIL Suraksha Saathi',
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 14, fontWeight: FontWeight.w700)),
                  Text('आपका सुरक्षा साथी · Your safety companion',
                    style: TextStyle(color: AppColors.text4, fontSize: 9)),
                ],
              )),
              if (_isAdmin)
                IconButton(
                  tooltip: 'Manage knowledge base (admin)',
                  onPressed: _showKnowledgeManager,
                  icon: Stack(children: [
                    const Icon(Icons.library_books_outlined, color: AppColors.amber, size: 20),
                    if (_kbDocCount > 0)
                      Positioned(
                        right: 0, top: 0,
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(color: AppColors.green, shape: BoxShape.circle),
                          constraints: const BoxConstraints(minWidth: 14, minHeight: 14),
                          child: Text('$_kbDocCount',
                            style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w700),
                            textAlign: TextAlign.center),
                        ),
                      ),
                  ]),
                ),
            ]),
          ),
          Expanded(
            child: ListView(
              controller: _scrollCtrl,
              padding: const EdgeInsets.all(14),
              children: [
                ..._messages.map((m) => _bubble(m['role'].toString(), m['text'].toString(), m['sources'] as List?)),
                if (_messages.length <= 1) _suggestionChips(),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              border: Border(top: BorderSide(color: Theme.of(context).dividerColor, width: 1)),
            ),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 12),
                  decoration: InputDecoration(
                    hintText: 'Ask Suraksha Saathi anything about safety...',
                    hintStyle: const TextStyle(color: AppColors.text4, fontSize: 11),
                    filled: true,
                    fillColor: Theme.of(context).inputDecorationTheme.fillColor ?? Theme.of(context).colorScheme.surface,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Theme.of(context).dividerColor, width: 1.5),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Theme.of(context).dividerColor, width: 1.5),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: AppColors.amber, width: 1.5),
                    ),
                  ),
                  onSubmitted: _send,
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                onPressed: () => _send(_ctrl.text),
                icon: const Icon(Icons.send, color: Colors.white, size: 18),
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.amber,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _bubble(String role, String text, List? sources) {
    final isUser = role == 'user';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            const CircleAvatar(
              radius: 14,
              backgroundColor: AppColors.amber,
              child: Icon(Icons.shield_outlined, color: Colors.white, size: 14),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: isUser ? AppColors.accent : AppColors.card,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: isUser ? AppColors.accentDark : AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(text,
                    style: TextStyle(
                      color: isUser ? Colors.white : AppColors.text1,
                      fontSize: 12, height: 1.5,
                    ),
                  ),
                  if (sources != null && sources.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: AppColors.amber.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppColors.amber.withOpacity(0.4)),
                      ),
                      child: Text(
                        '📎 ${sources.length} source${sources.length > 1 ? 's' : ''} from knowledge base',
                        style: const TextStyle(color: AppColors.amber, fontSize: 9, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (isUser) const SizedBox(width: 30),
        ],
      ),
    );
  }

  Widget _suggestionChips() {
    final suggestions = [
      'What PPE is required for height work?',
      'Explain Factories Act §35',
      'LOTO procedure for crane',
      'Confined space entry checklist',
      'Hot work permit requirements',
      'WSA 13 causes',
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('SUGGESTED QUESTIONS',
            style: TextStyle(color: AppColors.text4, fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6, runSpacing: 6,
            children: suggestions.map((s) => GestureDetector(
              onTap: () => _send(s),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border),
                ),
                child: Text(s, style: const TextStyle(color: AppColors.text2, fontSize: 10)),
              ),
            )).toList(),
          ),
        ],
      ),
    );
  }
}
