import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../main.dart';
import '../services/local_db.dart';
import '../services/sync_service.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});
  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  List<Map<String, dynamic>> _docs = [];
  List<Map<String, dynamic>> _users = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _load();
  }

  @override
  void dispose() { _tabs.dispose(); super.dispose(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    final docs  = await LocalDB.getKnowledgeDocs();
    final users = await LocalDB.getUsers();
    if (!mounted) return;
    setState(() { _docs = docs; _users = users; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg2,
        elevation: 0,
        title: Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF7C3AED), Color(0xFF2563EB)]),
              borderRadius: BorderRadius.circular(6)),
            child: const Text('ADMIN', style: TextStyle(
              color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800,
              letterSpacing: 1))),
          const SizedBox(width: 10),
          const Text('Control Panel', style: TextStyle(
            color: AppColors.text1, fontSize: 16, fontWeight: FontWeight.w700)),
        ]),
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: AppColors.accent,
          labelColor: AppColors.accent,
          unselectedLabelColor: AppColors.text4,
          labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          tabs: const [
            Tab(icon: Icon(Icons.library_books_outlined, size: 16), text: 'Knowledge Base'),
            Tab(icon: Icon(Icons.people_outline, size: 16), text: 'Users'),
            Tab(icon: Icon(Icons.analytics_outlined, size: 16), text: 'Analytics'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
          : TabBarView(
              controller: _tabs,
              children: [
                _knowledgeTab(),
                _usersTab(),
                _analyticsTab(),
              ],
            ),
    );
  }

  // ─── KNOWLEDGE BASE TAB ──────────────────────────────────────────────────
  Widget _knowledgeTab() {
    return Column(children: [
      // Header
      Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
        color: AppColors.card,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Knowledge Base', style: TextStyle(
            color: AppColors.text1, fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('${_docs.length} documents loaded. The Ask AI feature uses these to answer questions.',
            style: const TextStyle(color: AppColors.text3, fontSize: 12)),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _addBtn(
              icon: Icons.edit_note_rounded,
              label: 'Add Text Entry',
              color: AppColors.accent,
              onTap: _showAddTextDialog)),
            const SizedBox(width: 8),
            Expanded(child: _addBtn(
              icon: Icons.sync,
              label: 'Sync from Cloud',
              color: AppColors.green,
              onTap: _syncFromCloud)),
          ]),
        ]),
      ),
      // Docs list
      Expanded(child: _docs.isEmpty
          ? _emptyState(
              icon: Icons.library_books_outlined,
              title: 'No knowledge documents yet',
              subtitle: 'Add documents to power the AI chatbot with SAIL-specific knowledge')
          : ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: _docs.length,
              separatorBuilder: (_, __) => const SizedBox(height: 6),
              itemBuilder: (_, i) => _docCard(_docs[i], i),
            )),
    ]);
  }

  Widget _docCard(Map<String, dynamic> doc, int index) {
    final title = doc['title']?.toString() ?? 'Untitled';
    final content = doc['content']?.toString() ?? '';
    final source = doc['source']?.toString() ?? '';
    final date = doc['uploadedAt']?.toString() ?? '';
    final words = content.split(' ').length;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
        leading: Container(
          width: 44, height: 44,
          decoration: BoxDecoration(
            color: AppColors.accent.withOpacity(0.12),
            borderRadius: BorderRadius.circular(10)),
          child: const Icon(Icons.description_outlined,
            color: AppColors.accent, size: 22)),
        title: Text(title, style: const TextStyle(
          color: AppColors.text1, fontSize: 13, fontWeight: FontWeight.w600)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 3),
            Text('$words words · $source',
              style: const TextStyle(color: AppColors.text3, fontSize: 11)),
            if (date.isNotEmpty) Text(date.split('T').first,
              style: const TextStyle(color: AppColors.text4, fontSize: 10)),
          ]),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 18, color: AppColors.amber),
            onPressed: () => _showEditDialog(doc)),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 18, color: AppColors.red),
            onPressed: () => _confirmDelete(doc)),
        ]),
      ),
    );
  }

  Future<void> _showAddTextDialog() async {
    final titleCtrl   = TextEditingController();
    final contentCtrl = TextEditingController();
    final sourceCtrl  = TextEditingController(text: 'Manual entry');

    await showDialog(context: context, builder: (ctx) => Dialog(
      backgroundColor: AppColors.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 500,
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Container(width: 4, height: 24, color: AppColors.accent),
            const SizedBox(width: 10),
            const Text('Add Knowledge Entry', style: TextStyle(
              color: AppColors.text1, fontSize: 16, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 16),
          _dialogHint('💡 Add SAIL safety procedures, IS code summaries, plant-specific rules, emergency contacts — anything the AI should know.'),
          const SizedBox(height: 12),
          _dialogField('Title (e.g. "IS 14489 Key Requirements")', titleCtrl),
          const SizedBox(height: 10),
          _dialogField('Source (e.g. "IS 14489:1998", "SAIL SOP-2024")', sourceCtrl),
          const SizedBox(height: 10),
          _dialogField('Content', contentCtrl, maxLines: 8,
            hint: 'Paste the full text here. The AI will search this when users ask questions.\n\nExample:\n"IS 14489:1998 Clause 6.2 - Machine Guarding: All rotating and moving parts must be guarded with fixed or interlocked guards. LOTO procedure must be applied during maintenance..."'),
          const SizedBox(height: 16),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: AppColors.text3))),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              icon: const Icon(Icons.save_outlined, size: 14),
              label: const Text('Save to Knowledge Base'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10)),
              onPressed: () async {
                if (titleCtrl.text.trim().isEmpty || contentCtrl.text.trim().isEmpty) return;
                await LocalDB.addKnowledgeDoc(
                  title: titleCtrl.text.trim(),
                  content: contentCtrl.text.trim(),
                  source: sourceCtrl.text.trim(),
                );
                Navigator.pop(ctx);
                await _load();
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Document added to Knowledge Base'),
                    backgroundColor: AppColors.green));
              }),
          ]),
        ]),
      ),
    ));
  }

  Future<void> _showEditDialog(Map<String, dynamic> doc) async {
    final titleCtrl   = TextEditingController(text: doc['title']?.toString() ?? '');
    final contentCtrl = TextEditingController(text: doc['content']?.toString() ?? '');
    final sourceCtrl  = TextEditingController(text: doc['source']?.toString() ?? '');

    await showDialog(context: context, builder: (ctx) => Dialog(
      backgroundColor: AppColors.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 500,
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Container(width: 4, height: 24, color: AppColors.amber),
            const SizedBox(width: 10),
            const Text('Edit Knowledge Entry', style: TextStyle(
              color: AppColors.text1, fontSize: 16, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 16),
          _dialogField('Title', titleCtrl),
          const SizedBox(height: 10),
          _dialogField('Source', sourceCtrl),
          const SizedBox(height: 10),
          _dialogField('Content', contentCtrl, maxLines: 8),
          const SizedBox(height: 16),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: AppColors.text3))),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              icon: const Icon(Icons.save_outlined, size: 14),
              label: const Text('Update'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.amber,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10)),
              onPressed: () async {
                await LocalDB.updateKnowledgeDoc(
                  id: doc['id'].toString(),
                  title: titleCtrl.text.trim(),
                  content: contentCtrl.text.trim(),
                  source: sourceCtrl.text.trim(),
                );
                Navigator.pop(ctx);
                await _load();
              }),
          ]),
        ]),
      ),
    ));
  }

  Future<void> _confirmDelete(Map<String, dynamic> doc) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text('Delete document?', style: TextStyle(color: AppColors.text1)),
        content: Text('Delete "${doc['title']}"? This cannot be undone.',
          style: const TextStyle(color: AppColors.text3)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.white))),
        ],
      ));
    if (confirmed == true) {
      await LocalDB.deleteKnowledgeDoc(doc['id'].toString());
      await _load();
    }
  }

  Future<void> _syncFromCloud() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Syncing knowledge from cloud...'),
        backgroundColor: AppColors.accent));
    try {
      await SyncService.syncKnowledgeFromCloud();
      await _load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Knowledge synced from cloud'),
          backgroundColor: AppColors.green));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Sync failed: $e'),
          backgroundColor: AppColors.red));
    }
  }

  // ─── USERS TAB ───────────────────────────────────────────────────────────
  Widget _usersTab() {
    return _users.isEmpty
        ? _emptyState(
            icon: Icons.people_outline,
            title: 'No registered users',
            subtitle: 'Users will appear here once they register')
        : ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: _users.length,
            separatorBuilder: (_, __) => const SizedBox(height: 6),
            itemBuilder: (_, i) => _userCard(_users[i]),
          );
  }

  Widget _userCard(Map<String, dynamic> user) {
    final name  = user['name']?.toString() ?? 'Unknown';
    final desig = user['designation']?.toString() ?? '';
    final plant = user['plant']?.toString() ?? '';
    final pno   = user['pno']?.toString() ?? '';
    final isAdmin = user['isAdmin'] == true || user['isAdmin'] == 'true';

    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border)),
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
        leading: Container(
          width: 44, height: 44,
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [
              AppColors.accent.withOpacity(0.3),
              AppColors.purple.withOpacity(0.3)]),
            shape: BoxShape.circle),
          child: Center(child: Text(
            name.isNotEmpty ? name[0].toUpperCase() : '?',
            style: const TextStyle(color: Colors.white, fontSize: 18,
              fontWeight: FontWeight.w800)))),
        title: Row(children: [
          Text(name, style: const TextStyle(
            color: AppColors.text1, fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(width: 6),
          if (isAdmin) Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: AppColors.amber.withOpacity(0.15),
              border: Border.all(color: AppColors.amber, width: 0.5),
              borderRadius: BorderRadius.circular(4)),
            child: const Text('ADMIN', style: TextStyle(
              color: AppColors.amber, fontSize: 8, fontWeight: FontWeight.w700))),
        ]),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 2),
            Text('$desig · $plant', style: const TextStyle(
              color: AppColors.text3, fontSize: 11)),
            if (pno.isNotEmpty) Text('P.No: $pno',
              style: const TextStyle(color: AppColors.text4, fontSize: 10)),
          ]),
      ),
    );
  }

  // ─── ANALYTICS TAB ───────────────────────────────────────────────────────
  Widget _analyticsTab() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: LocalDB.getIncidents(),
      builder: (context, snap) {
        if (!snap.hasData) return const Center(
          child: CircularProgressIndicator(color: AppColors.accent));
        final incidents = snap.data!;
        final total    = incidents.length;
        final critical = incidents.where((i) => i['severity'] == 'CRITICAL').length;
        final high     = incidents.where((i) => i['severity'] == 'HIGH').length;
        final medium   = incidents.where((i) => i['severity'] == 'MEDIUM').length;
        final low      = incidents.where((i) => i['severity'] == 'LOW').length;
        final open     = incidents.where((i) => i['status'] == 'OPEN').length;
        final aiScans  = incidents.where((i) => i['type'] == 'AI_SCAN').length;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Incident Analytics', style: TextStyle(
                color: AppColors.text1, fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 16),
              // Stats grid
              GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 1.3,
                children: [
                  _statCard('Total', '$total', AppColors.accent, Icons.list_alt),
                  _statCard('Open', '$open', AppColors.amber, Icons.pending_outlined),
                  _statCard('AI Scans', '$aiScans', AppColors.purple, Icons.camera_alt_outlined),
                  _statCard('Critical', '$critical', AppColors.crit, Icons.crisis_alert),
                  _statCard('High', '$high', AppColors.red, Icons.warning_amber),
                  _statCard('Medium', '$medium', AppColors.cyan, Icons.info_outline),
                ],
              ),
              const SizedBox(height: 20),
              // Severity breakdown
              _sectionHeader('Severity Breakdown'),
              const SizedBox(height: 10),
              if (total > 0) ...[
                _severityBar('CRITICAL', critical, total, AppColors.crit),
                const SizedBox(height: 6),
                _severityBar('HIGH', high, total, AppColors.red),
                const SizedBox(height: 6),
                _severityBar('MEDIUM', medium, total, AppColors.cyan),
                const SizedBox(height: 6),
                _severityBar('LOW', low, total, AppColors.green),
              ] else
                const Text('No incidents yet.',
                  style: TextStyle(color: AppColors.text3, fontSize: 13)),
              const SizedBox(height: 20),
              _sectionHeader('Knowledge Base Status'),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border)),
                child: Row(children: [
                  Container(
                    width: 48, height: 48,
                    decoration: BoxDecoration(
                      color: AppColors.green.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12)),
                    child: const Icon(Icons.library_books,
                      color: AppColors.green, size: 24)),
                  const SizedBox(width: 14),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${_docs.length} Documents', style: const TextStyle(
                      color: AppColors.text1, fontSize: 16,
                      fontWeight: FontWeight.w700)),
                    Text(
                      _docs.isEmpty
                          ? 'Add documents to improve AI responses'
                          : 'Knowledge base is active — AI will use these',
                      style: const TextStyle(color: AppColors.text3, fontSize: 12)),
                  ]),
                ]),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _statCard(String label, String value, Color color, IconData icon) =>
    Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3))),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(
            color: color, fontSize: 20, fontWeight: FontWeight.w800)),
          Text(label, style: const TextStyle(
            color: AppColors.text4, fontSize: 10)),
        ]));

  Widget _severityBar(String label, int count, int total, Color color) {
    final pct = total > 0 ? count / total : 0.0;
    return Row(children: [
      SizedBox(width: 70, child: Text(label,
        style: TextStyle(color: color, fontSize: 11,
          fontWeight: FontWeight.w700))),
      Expanded(child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(
          value: pct,
          backgroundColor: AppColors.card2,
          valueColor: AlwaysStoppedAnimation<Color>(color),
          minHeight: 10))),
      const SizedBox(width: 8),
      Text('$count', style: const TextStyle(
        color: AppColors.text2, fontSize: 12, fontWeight: FontWeight.w700)),
    ]);
  }

  Widget _sectionHeader(String t) => Row(children: [
    Container(width: 3, height: 16, color: AppColors.accent),
    const SizedBox(width: 8),
    Text(t, style: const TextStyle(
      color: AppColors.text1, fontSize: 14, fontWeight: FontWeight.w700)),
  ]);

  // ─── HELPERS ─────────────────────────────────────────────────────────────
  Widget _addBtn({required IconData icon, required String label,
      required Color color, required VoidCallback onTap}) =>
    ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 14, color: Colors.white),
      label: Text(label, style: const TextStyle(
        color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        padding: const EdgeInsets.symmetric(vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10))));

  Widget _dialogField(String label, TextEditingController c,
      {int maxLines = 1, String? hint}) =>
    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label.toUpperCase(), style: const TextStyle(
        color: AppColors.text4, fontSize: 9,
        fontWeight: FontWeight.w700, letterSpacing: 0.5)),
      const SizedBox(height: 4),
      TextField(
        controller: c,
        maxLines: maxLines,
        style: const TextStyle(color: AppColors.text1, fontSize: 12),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: AppColors.text4, fontSize: 11),
          filled: true,
          fillColor: AppColors.bg2,
          contentPadding: const EdgeInsets.all(10),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppColors.border)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppColors.border)),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppColors.accent, width: 1.5))),
      ),
    ]);

  Widget _dialogHint(String t) => Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: AppColors.accent.withOpacity(0.08),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: AppColors.accent.withOpacity(0.3))),
    child: Text(t, style: const TextStyle(
      color: AppColors.text2, fontSize: 11, height: 1.5)));

  Widget _emptyState({required IconData icon, required String title,
      required String subtitle}) =>
    Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 72, height: 72,
            decoration: BoxDecoration(
              color: AppColors.card2,
              shape: BoxShape.circle),
            child: Icon(icon, color: AppColors.text4, size: 32)),
          const SizedBox(height: 16),
          Text(title, style: const TextStyle(
            color: AppColors.text2, fontSize: 15, fontWeight: FontWeight.w600),
            textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(subtitle, style: const TextStyle(
            color: AppColors.text4, fontSize: 12),
            textAlign: TextAlign.center),
        ]),
      ));
}
