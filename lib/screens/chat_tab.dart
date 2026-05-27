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
  final List<Map<String, String>> _messages = [];
  Map<String, dynamic>? _user;

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    final u = await LocalDB.getCurrentUser();
    if (mounted) setState(() {
      _user = u;
      final firstName = (u?['name']?.toString().split(' ').first) ?? 'there';
      _messages.add({
        'role': 'ai',
        'text': 'Hi $firstName! Ask me about IS codes, Factories Act, PPE, LOTO, confined space, or any safety regulation. I follow IS 14489, Ministry of Steel guidelines, and state factory rules.',
      });
    });
  }

  void _send(String q) {
    if (q.trim().isEmpty) return;
    setState(() {
      _messages.add({'role': 'user', 'text': q.trim()});
      _ctrl.clear();
    });
    _scrollToBottom();
    // Use LocalAI knowledge base for safety Q&A
    Future.delayed(const Duration(milliseconds: 600), () {
      final answer = LocalAI.chat(q.trim());
      if (mounted) {
        setState(() => _messages.add({'role': 'ai', 'text': answer}));
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
            child: Row(
              children: const [
                Icon(Icons.auto_awesome, size: 18, color: AppColors.purple),
                SizedBox(width: 8),
                Text('Safety AI Assistant',
                  style: TextStyle(color: AppColors.text1, fontSize: 15, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              controller: _scrollCtrl,
              padding: const EdgeInsets.all(14),
              children: [
                ..._messages.map((m) => _bubble(m['role']!, m['text']!)),
                if (_messages.length <= 1) _suggestionChips(),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: const BoxDecoration(
              color: AppColors.bg2,
              border: Border(top: BorderSide(color: AppColors.border, width: 1)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _ctrl,
                    style: const TextStyle(color: AppColors.text1, fontSize: 12),
                    decoration: InputDecoration(
                      hintText: 'Ask anything about safety...',
                      hintStyle: const TextStyle(color: AppColors.text4),
                      filled: true,
                      fillColor: AppColors.card2,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: AppColors.border, width: 1.5),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: AppColors.border, width: 1.5),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
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
                    backgroundColor: AppColors.accent,
                    padding: const EdgeInsets.all(12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _bubble(String role, String text) {
    final isUser = role == 'user';
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.85),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isUser ? AppColors.accent : AppColors.card,
          border: isUser ? null : Border.all(color: AppColors.border),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(12),
            topRight: const Radius.circular(12),
            bottomLeft: Radius.circular(isUser ? 12 : 3),
            bottomRight: Radius.circular(isUser ? 3 : 12),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isUser) Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(Icons.auto_awesome, size: 11, color: AppColors.accent),
                  SizedBox(width: 4),
                  Text('Safety AI',
                    style: TextStyle(color: AppColors.accent, fontSize: 10, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            Text(text,
              style: TextStyle(
                color: isUser ? Colors.white : AppColors.text1,
                fontSize: 11, height: 1.55,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _suggestionChips() {
    final suggestions = [
      'What PPE is needed in rolling mill?',
      'Confined space entry procedure',
      'LOTO 7 steps',
      'Factories Act Section 35',
      'Hot work fire watch duration',
      'WSA 13 root causes',
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('SUGGESTED QUESTIONS',
            style: TextStyle(color: AppColors.text4, fontSize: 9, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6, runSpacing: 6,
            children: suggestions.map((s) => GestureDetector(
              onTap: () => _send(s),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.card2,
                  border: Border.all(color: AppColors.border),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(s, style: const TextStyle(color: AppColors.text2, fontSize: 10, fontWeight: FontWeight.w500)),
              ),
            )).toList(),
          ),
        ],
      ),
    );
  }
}
