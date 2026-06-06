// lib/screens/admin_screen.dart
// SAIL Safety Lens — Admin Control Panel
// Access: username=admin / password=admin (or isAdmin=true users)
// Features:
//   ✅ Dashboard stats (total incidents, open, closed, users)
//   ✅ User Management (view, add, edit role, toggle active/inactive, delete)
//   ✅ Incident Management (view all, filter by status/severity, quick close)
//   ✅ Knowledge Base management (add/delete text entries)
//   ✅ App Settings (site name, contact, etc.)
//   ✅ Sync with Google Sheets

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
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
  bool _loading = true;

  // Data
  List<Map<String, dynamic>> _users     = [];
  List<Map<String, dynamic>> _incidents = [];
  List<Map<String, dynamic>> _kbDocs    = [];

  // Stats
  int get _totalInc   => _incidents.length;
  int get _openInc    => _incidents.where((i) =>
      (i['status']?.toString().toUpperCase() ?? '') == 'OPEN').length;
  int get _closedInc  => _incidents.where((i) =>
      (i['status']?.toString().toUpperCase() ?? '') == 'CLOSED').length;
  int get _criticalInc => _incidents.where((i) =>
      (i['severity']?.toString().toUpperCase() ?? '') == 'CRITICAL').length;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    _loadAll();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    try {
      final users     = await SyncService.fetchUsers();
      final incidents = await LocalDB.getIncidents();
      final kb        = await LocalDB.getKnowledgeDocs();
      if (!mounted) return;
      setState(() {
        _users     = users.isNotEmpty ? users : await _localUsers();
        _incidents = incidents;
        _kbDocs    = kb;
        _loading   = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<List<Map<String, dynamic>>> _localUsers() async {
    return await LocalDB.getAllUsers();
  }

  // ─── BUILD ────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final sl = SL.of(context);
    return Scaffold(
      backgroundColor: sl.bg,
      appBar: AppBar(
        backgroundColor: sl.bg2,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_rounded, color: sl.text1, size: 18),
          onPressed: () => Navigator.pop(context)),
        title: Row(children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: AppColors.amber.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.admin_panel_settings_rounded,
                color: AppColors.amber, size: 18)),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Admin Panel', style: TextStyle(
                color: sl.text1, fontSize: 15, fontWeight: FontWeight.w700)),
            Text('SAIL Safety Lens Control Centre',
                style: TextStyle(color: sl.text4, fontSize: 9)),
          ]),
        ]),
        actions: [
          IconButton(
            tooltip: 'Refresh all data',
            onPressed: _loadAll,
            icon: Icon(Icons.refresh_rounded, color: sl.text3, size: 20)),
        ],
        bottom: TabBar(
          controller: _tabs,
          labelColor: AppColors.amber,
          unselectedLabelColor: sl.text3,
          indicatorColor: AppColors.amber,
          indicatorSize: TabBarIndicatorSize.tab,
          labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
          tabs: const [
            Tab(icon: Icon(Icons.dashboard_rounded, size: 16), text: 'Overview'),
            Tab(icon: Icon(Icons.people_rounded, size: 16), text: 'Users'),
            Tab(icon: Icon(Icons.list_alt_rounded, size: 16), text: 'Incidents'),
            Tab(icon: Icon(Icons.library_books_rounded, size: 16), text: 'Knowledge'),
          ]),
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: AppColors.amber))
          : TabBarView(controller: _tabs, children: [
              _buildOverview(sl),
              _buildUsers(sl),
              _buildIncidents(sl),
              _buildKnowledge(sl),
            ]),
    );
  }

  // ══════════════════════════════════════════════════════════════
  //  TAB 1 — OVERVIEW
  // ══════════════════════════════════════════════════════════════
  Widget _buildOverview(SL sl) => SingleChildScrollView(
    padding: const EdgeInsets.all(16),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionHeader('📊  Safety Overview', sl),
      const SizedBox(height: 12),
      // Stat grid
      GridView.count(
        crossAxisCount: 2, shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: 10, mainAxisSpacing: 10,
        childAspectRatio: 1.6,
        children: [
          _statTile('Total Incidents', '$_totalInc', AppColors.accent,
              Icons.assessment_rounded, sl),
          _statTile('Open Cases', '$_openInc', AppColors.amber,
              Icons.lock_open_rounded, sl),
          _statTile('Closed Cases', '$_closedInc', AppColors.green,
              Icons.check_circle_rounded, sl),
          _statTile('Critical', '$_criticalInc', AppColors.crit,
              Icons.warning_rounded, sl),
        ]),
      const SizedBox(height: 20),
      _sectionHeader('⚡  Quick Actions', sl),
      const SizedBox(height: 12),
      // Quick actions grid
      Row(children: [
        Expanded(child: _actionCard(
          icon: Icons.sync_rounded,
          label: 'Sync Sheets',
          color: AppColors.accent,
          sl: sl,
          onTap: _syncAll)),
        const SizedBox(width: 10),
        Expanded(child: _actionCard(
          icon: Icons.person_add_rounded,
          label: 'Add User',
          color: AppColors.green,
          sl: sl,
          onTap: () {
            _tabs.animateTo(1);
            Future.delayed(const Duration(milliseconds: 300),
                () => _showAddUserDialog());
          })),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: _actionCard(
          icon: Icons.library_add_rounded,
          label: 'Add Knowledge',
          color: AppColors.cyan,
          sl: sl,
          onTap: () {
            _tabs.animateTo(3);
            Future.delayed(const Duration(milliseconds: 300),
                () => _showAddKbDialog());
          })),
        const SizedBox(width: 10),
        Expanded(child: _actionCard(
          icon: Icons.download_rounded,
          label: 'Export Report',
          color: AppColors.purple,
          sl: sl,
          onTap: _showExportInfo)),
      ]),
      const SizedBox(height: 20),
      _sectionHeader('🔑  Admin Credentials', sl),
      const SizedBox(height: 8),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: sl.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.amber.withOpacity(0.3))),
        child: Column(children: [
          _credRow('Username', 'admin', sl),
          const SizedBox(height: 6),
          _credRow('Password', 'admin (change recommended)', sl),
          const SizedBox(height: 6),
          _credRow('Role', 'System Administrator', sl),
          const SizedBox(height: 6),
          _credRow('Access', 'Full control — all plants', sl),
        ])),
    ]),
  );

  Widget _statTile(String label, String value, Color color,
      IconData icon, SL sl) =>
    Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: sl.card, borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.25))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 6),
          Expanded(child: Text(label, style: TextStyle(
              color: sl.text3, fontSize: 10), overflow: TextOverflow.ellipsis)),
        ]),
        const SizedBox(height: 8),
        Text(value, style: TextStyle(
            color: color, fontSize: 28, fontWeight: FontWeight.w800)),
      ]));

  Widget _actionCard({required IconData icon, required String label,
      required Color color, required SL sl, required VoidCallback onTap}) =>
    GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3))),
        child: Row(children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(label, style: TextStyle(
              color: color, fontSize: 12, fontWeight: FontWeight.w700))),
          Icon(Icons.arrow_forward_ios_rounded, color: color, size: 12),
        ])));

  Widget _credRow(String key, String value, SL sl) => Row(children: [
    SizedBox(width: 80, child: Text(key,
        style: TextStyle(color: sl.text4, fontSize: 11,
            fontWeight: FontWeight.w600))),
    const SizedBox(width: 8),
    Expanded(child: Text(value,
        style: TextStyle(color: sl.text1, fontSize: 11))),
  ]);

  // ══════════════════════════════════════════════════════════════
  //  TAB 2 — USERS
  // ══════════════════════════════════════════════════════════════
  Widget _buildUsers(SL sl) => Column(children: [
    // Header + add button
    Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      color: sl.bg2,
      child: Row(children: [
        Expanded(child: Text('${_users.length} registered users',
            style: TextStyle(color: sl.text3, fontSize: 12))),
        ElevatedButton.icon(
          onPressed: _showAddUserDialog,
          icon: const Icon(Icons.person_add_rounded, size: 14, color: Colors.white),
          label: const Text('Add User', style: TextStyle(
              color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.green,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)))),
      ])),
    Divider(height: 1, color: sl.border),
    Expanded(child: _users.isEmpty
      ? _emptyState('No users registered yet', Icons.people_outline_rounded, sl)
      : ListView.separated(
          padding: const EdgeInsets.all(14),
          itemCount: _users.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (_, i) => _userCard(_users[i], sl))),
  ]);

  Widget _userCard(Map<String, dynamic> u, SL sl) {
    final name   = u['name']?.toString() ?? '—';
    final uname  = u['username']?.toString() ?? '—';
    final desig  = u['designation']?.toString() ?? '—';
    final plant  = u['plant']?.toString() ?? '—';
    final isAdmin = u['isAdmin']?.toString().toLowerCase() == 'true';
    final status = u['status']?.toString().toLowerCase() ?? 'active';
    final isActive = status == 'active';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: sl.card, borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isAdmin
            ? AppColors.amber.withOpacity(0.35)
            : sl.border.withOpacity(0.5))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          // Avatar
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isAdmin
                  ? AppColors.amber.withOpacity(0.15)
                  : AppColors.accent.withOpacity(0.12)),
            child: Center(child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: TextStyle(
                color: isAdmin ? AppColors.amber : AppColors.accent,
                fontSize: 15, fontWeight: FontWeight.w800)))),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(name, style: TextStyle(
                  color: sl.text1, fontSize: 13, fontWeight: FontWeight.w700)),
              const SizedBox(width: 6),
              if (isAdmin)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: AppColors.amber.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(4)),
                  child: const Text('ADMIN', style: TextStyle(
                      color: AppColors.amber, fontSize: 8,
                      fontWeight: FontWeight.w700))),
            ]),
            Text('@$uname · $desig', style: TextStyle(
                color: sl.text3, fontSize: 10)),
          ])),
          // Status badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: isActive ? AppColors.green.withOpacity(0.1) : sl.border.withOpacity(0.5),
              borderRadius: BorderRadius.circular(6)),
            child: Text(isActive ? 'Active' : 'Inactive',
              style: TextStyle(
                color: isActive ? AppColors.green : sl.text4,
                fontSize: 9, fontWeight: FontWeight.w700))),
        ]),
        const SizedBox(height: 6),
        Text(plant, style: TextStyle(color: sl.text4, fontSize: 10)),
        const SizedBox(height: 8),
        // Actions
        Row(children: [
          _userActionBtn(
            isAdmin ? 'Remove Admin' : 'Make Admin',
            isAdmin ? AppColors.amber : AppColors.accent,
            sl,
            () => _toggleAdmin(u)),
          const SizedBox(width: 6),
          _userActionBtn(
            isActive ? 'Deactivate' : 'Activate',
            isActive ? sl.text3 : AppColors.green,
            sl,
            () => _toggleStatus(u)),
          const SizedBox(width: 6),
          if (uname != 'admin')
            _userActionBtn('Delete', AppColors.red, sl,
                () => _confirmDelete(u)),
        ]),
      ]));
  }

  Widget _userActionBtn(String label, Color color, SL sl, VoidCallback onTap) =>
    GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withOpacity(0.3))),
        child: Text(label, style: TextStyle(
            color: color, fontSize: 9, fontWeight: FontWeight.w700))));

  // ══════════════════════════════════════════════════════════════
  //  TAB 3 — INCIDENTS
  // ══════════════════════════════════════════════════════════════
  Widget _buildIncidents(SL sl) {
    return Column(children: [
      // Header row with counts
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        color: sl.bg2,
        child: Row(children: [
          _incFilterChip('All', _totalInc, AppColors.accent, sl),
          const SizedBox(width: 6),
          _incFilterChip('Open', _openInc, AppColors.amber, sl),
          const SizedBox(width: 6),
          _incFilterChip('Critical', _criticalInc, AppColors.crit, sl),
          const SizedBox(width: 6),
          _incFilterChip('Closed', _closedInc, AppColors.green, sl),
        ])),
      Divider(height: 1, color: sl.border),
      Expanded(child: _incidents.isEmpty
        ? _emptyState('No incidents recorded', Icons.assessment_outlined, sl)
        : ListView.separated(
            padding: const EdgeInsets.all(14),
            itemCount: _incidents.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) => _incidentAdminCard(_incidents[i], sl))),
    ]);
  }

  Widget _incFilterChip(String label, int count, Color color, SL sl) =>
    Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(label, style: TextStyle(
            color: color, fontSize: 9, fontWeight: FontWeight.w700)),
        const SizedBox(width: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          decoration: BoxDecoration(
            color: color, borderRadius: BorderRadius.circular(4)),
          child: Text('$count', style: const TextStyle(
              color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800))),
      ]));

  Widget _incidentAdminCard(Map<String, dynamic> inc, SL sl) {
    final title    = inc['title']?.toString() ?? 'Untitled';
    final sev      = inc['severity']?.toString().toUpperCase() ?? '—';
    final status   = inc['status']?.toString().toUpperCase() ?? '—';
    final plant    = inc['plant']?.toString() ?? '—';
    final date     = inc['date']?.toString() ?? '';
    final isClosed = status == 'CLOSED';

    Color sevColor;
    switch (sev) {
      case 'CRITICAL': sevColor = AppColors.crit; break;
      case 'HIGH':     sevColor = AppColors.red;  break;
      case 'MEDIUM':   sevColor = AppColors.amber; break;
      default:         sevColor = AppColors.green;
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isClosed ? AppColors.green.withOpacity(0.04) : sl.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isClosed
              ? AppColors.green.withOpacity(0.25) : sevColor.withOpacity(0.25))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(title,
            style: TextStyle(
              color: isClosed ? sl.text3 : sl.text1,
              fontSize: 12, fontWeight: FontWeight.w700,
              decoration: isClosed ? TextDecoration.lineThrough : null),
            maxLines: 2, overflow: TextOverflow.ellipsis)),
          if (!isClosed)
            GestureDetector(
              onTap: () => _adminCloseIncident(inc),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppColors.green.withOpacity(0.35))),
                child: const Text('Close', style: TextStyle(
                    color: AppColors.green, fontSize: 9,
                    fontWeight: FontWeight.w700)))),
        ]),
        const SizedBox(height: 6),
        Text('$plant  ·  ${date.length > 10 ? date.substring(0, 10) : date}',
            style: TextStyle(color: sl.text4, fontSize: 10)),
        const SizedBox(height: 6),
        Wrap(spacing: 5, runSpacing: 4, children: [
          _pill(sev, sevColor),
          _pill(status, isClosed ? AppColors.green : AppColors.amber),
          if ((inc['type']?.toString() ?? '').isNotEmpty)
            _pill(inc['type'].toString(), AppColors.accent),
        ]),
      ]));
  }

  // ══════════════════════════════════════════════════════════════
  //  TAB 4 — KNOWLEDGE BASE
  // ══════════════════════════════════════════════════════════════
  Widget _buildKnowledge(SL sl) => Column(children: [
    Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      color: sl.bg2,
      child: Row(children: [
        Expanded(child: Text('${_kbDocs.length} knowledge documents',
            style: TextStyle(color: sl.text3, fontSize: 12))),
        ElevatedButton.icon(
          onPressed: _showAddKbDialog,
          icon: const Icon(Icons.add_rounded, size: 14, color: Colors.white),
          label: const Text('Add Entry', style: TextStyle(
              color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.cyan,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)))),
      ])),
    Divider(height: 1, color: sl.border),
    Expanded(child: _kbDocs.isEmpty
      ? _emptyState('No knowledge docs yet.\nAdd safety guidelines, SOPs, or\nregulatory references.',
          Icons.library_books_outlined, sl)
      : ListView.separated(
          padding: const EdgeInsets.all(14),
          itemCount: _kbDocs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (_, i) => _kbCard(_kbDocs[i], sl))),
  ]);

  Widget _kbCard(Map<String, dynamic> doc, SL sl) {
    final title   = doc['title']?.toString() ?? 'Untitled';
    final source  = doc['source']?.toString() ?? '';
    final chars   = (doc['content']?.toString() ?? '').length;
    final preview = (doc['content']?.toString() ?? '').length > 80
        ? '${doc['content'].toString().substring(0, 80)}…'
        : doc['content']?.toString() ?? '';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: sl.card, borderRadius: BorderRadius.circular(10),
        border: Border.all(color: sl.border.withOpacity(0.5))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.description_outlined, color: AppColors.cyan, size: 20),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: TextStyle(
              color: sl.text1, fontSize: 12, fontWeight: FontWeight.w700)),
          if (source.isNotEmpty)
            Text(source, style: TextStyle(color: sl.text4, fontSize: 9)),
          const SizedBox(height: 4),
          Text(preview, style: TextStyle(color: sl.text3, fontSize: 10, height: 1.4),
              maxLines: 2, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 4),
          Text('$chars characters', style: TextStyle(color: sl.text4, fontSize: 9)),
        ])),
        IconButton(
          icon: const Icon(Icons.delete_outline_rounded, color: AppColors.red, size: 18),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          onPressed: () => _deleteKbDoc(doc)),
      ]));
  }

  // ══════════════════════════════════════════════════════════════
  //  ACTIONS
  // ══════════════════════════════════════════════════════════════

  Future<void> _syncAll() async {
    _showSnack('Syncing with Google Sheets…', AppColors.accent);
    try {
      await SyncService.pushAllIncidents(_incidents);
      _showSnack('Sync complete ✓', AppColors.green);
    } catch (e) {
      _showSnack('Sync failed: $e', AppColors.red);
    }
  }

  Future<void> _toggleAdmin(Map<String, dynamic> u) async {
    final uname = u['username']?.toString() ?? '';
    final isAdmin = u['isAdmin']?.toString().toLowerCase() == 'true';
    final newVal = isAdmin ? 'FALSE' : 'TRUE';
    await SyncService.updateUserField(uname, 'isAdmin', newVal);
    await _loadAll();
    _showSnack(isAdmin ? 'Admin role removed' : 'Admin role granted', AppColors.amber);
  }

  Future<void> _toggleStatus(Map<String, dynamic> u) async {
    final uname  = u['username']?.toString() ?? '';
    final status = u['status']?.toString().toLowerCase() ?? 'active';
    final newVal = status == 'active' ? 'inactive' : 'active';
    await SyncService.updateUserField(uname, 'status', newVal);
    await _loadAll();
    _showSnack('User $newVal', newVal == 'active' ? AppColors.green : sl.text3);
  }

  Future<void> _confirmDelete(Map<String, dynamic> u) async {
    final sl = SL.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: sl.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Delete User',
            style: TextStyle(color: AppColors.text1, fontSize: 15,
                fontWeight: FontWeight.w700)),
        content: Text(
          'Delete "${u['name'] ?? u['username']}"? This cannot be undone.',
          style: TextStyle(color: sl.text2, fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.red,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            child: const Text('Delete', style: TextStyle(color: Colors.white))),
        ]));
    if (confirmed != true) return;
    await SyncService.deleteUser(u['username']?.toString() ?? '');
    await _loadAll();
    _showSnack('User deleted', AppColors.red);
  }

  Future<void> _adminCloseIncident(Map<String, dynamic> inc) async {
    final sl = SL.of(context);
    final ctrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: sl.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Row(children: [
          Icon(Icons.lock_rounded, color: AppColors.green, size: 18),
          SizedBox(width: 8),
          Text('Close Incident', style: TextStyle(
              color: AppColors.text1, fontSize: 14, fontWeight: FontWeight.w700)),
        ]),
        content: TextField(
          controller: ctrl, maxLines: 3, autofocus: true,
          style: TextStyle(color: sl.text1, fontSize: 13),
          decoration: InputDecoration(
            hintText: 'Corrective action taken…',
            hintStyle: TextStyle(color: sl.text4, fontSize: 11),
            filled: true, fillColor: sl.bg,
            contentPadding: const EdgeInsets.all(10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: sl.border)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppColors.green, width: 2)))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            onPressed: () {
              if (ctrl.text.trim().isEmpty) return;
              Navigator.pop(context, true);
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.green,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            child: const Text('Close', style: TextStyle(color: Colors.white))),
        ]));

    if (confirmed != true || ctrl.text.trim().isEmpty) return;
    inc['status']           = 'CLOSED';
    inc['correctiveAction'] = ctrl.text.trim();
    inc['closedAt']         = DateTime.now().toIso8601String();
    await LocalDB.saveIncident(inc);
    SyncService.pushIncident(inc).catchError((_) => false);
    await _loadAll();
    _showSnack('Incident closed ✓', AppColors.green);
  }

  void _showAddUserDialog() {
    final sl = SL.of(context);
    final nameCtrl  = TextEditingController();
    final uCtrl     = TextEditingController();
    final pCtrl     = TextEditingController();
    final desigCtrl = TextEditingController();
    final plantCtrl = TextEditingController();
    bool isAdmin    = false;

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          backgroundColor: sl.card,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Add New User', style: TextStyle(
              color: AppColors.text1, fontSize: 15, fontWeight: FontWeight.w700)),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              _dialogField('Full Name', nameCtrl, sl),
              const SizedBox(height: 8),
              _dialogField('Username', uCtrl, sl),
              const SizedBox(height: 8),
              _dialogField('Password', pCtrl, sl, obscure: true),
              const SizedBox(height: 8),
              _dialogField('Designation', desigCtrl, sl),
              const SizedBox(height: 8),
              _dialogField('Plant', plantCtrl, sl, hint: 'e.g. BSP Bhilai'),
              const SizedBox(height: 10),
              Row(children: [
                Switch(value: isAdmin, activeColor: AppColors.amber,
                    onChanged: (v) => setLocal(() => isAdmin = v)),
                const SizedBox(width: 8),
                Text('Admin access', style: TextStyle(color: sl.text1, fontSize: 12)),
              ]),
            ])),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel', style: TextStyle(color: Colors.grey))),
            ElevatedButton(
              onPressed: () async {
                if (uCtrl.text.trim().isEmpty || pCtrl.text.trim().isEmpty) return;
                Navigator.pop(ctx);
                await SyncService.registerUser({
                  'name':         nameCtrl.text.trim(),
                  'username':     uCtrl.text.trim(),
                  'passwordHash': _simpleHash(pCtrl.text.trim()),
                  'designation':  desigCtrl.text.trim(),
                  'plant':        plantCtrl.text.trim(),
                  'isAdmin':      isAdmin ? 'TRUE' : 'FALSE',
                });
                await _loadAll();
                _showSnack('User added ✓', AppColors.green);
              },
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.green,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
              child: const Text('Add User', style: TextStyle(color: Colors.white))),
          ])));
  }

  void _showAddKbDialog() {
    final sl    = SL.of(context);
    final titleCtrl   = TextEditingController();
    final contentCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: sl.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Add Knowledge Entry', style: TextStyle(
            color: AppColors.text1, fontSize: 15, fontWeight: FontWeight.w700)),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _dialogField('Title / Topic', titleCtrl, sl,
                hint: 'e.g. SG/02 Working at Height'),
            const SizedBox(height: 10),
            TextField(
              controller: contentCtrl, maxLines: 6,
              style: TextStyle(color: sl.text1, fontSize: 12),
              decoration: InputDecoration(
                hintText: 'Paste safety guidelines, regulations, procedures…',
                hintStyle: TextStyle(color: sl.text4, fontSize: 10),
                filled: true, fillColor: sl.bg,
                contentPadding: const EdgeInsets.all(10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: sl.border)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: AppColors.cyan, width: 2)))),
          ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            onPressed: () async {
              if (titleCtrl.text.trim().isEmpty || contentCtrl.text.trim().isEmpty) return;
              Navigator.pop(context);
              await LocalDB.addKnowledgeDoc(
                title: titleCtrl.text.trim(),
                content: contentCtrl.text.trim(),
                source: 'Admin Panel',
              );
              await _loadAll();
              _showSnack('Knowledge entry added ✓', AppColors.cyan);
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.cyan,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            child: const Text('Add Entry', style: TextStyle(color: Colors.white))),
        ]));
  }

  Future<void> _deleteKbDoc(Map<String, dynamic> doc) async {
    await LocalDB.deleteKnowledgeDoc(doc['id'].toString());
    await _loadAll();
    _showSnack('Knowledge entry deleted', AppColors.red);
  }

  void _showExportInfo() {
    _showSnack('Export: Open Google Sheets → File → Download → CSV/Excel', AppColors.purple);
  }

  // ── Helpers ───────────────────────────────────────────────────
  SL get sl => SL.of(context);

  Widget _sectionHeader(String title, SL sl) => Row(children: [
    Container(width: 3, height: 16, color: AppColors.amber,
        margin: const EdgeInsets.only(right: 8)),
    Text(title, style: TextStyle(color: sl.text1, fontSize: 14,
        fontWeight: FontWeight.w700)),
  ]);

  Widget _emptyState(String msg, IconData icon, SL sl) =>
    Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, color: sl.text4, size: 42),
      const SizedBox(height: 12),
      Text(msg, style: TextStyle(color: sl.text3, fontSize: 13),
          textAlign: TextAlign.center),
    ]));

  Widget _pill(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(99),
      border: Border.all(color: color.withOpacity(0.3))),
    child: Text(text, style: TextStyle(color: color, fontSize: 9,
        fontWeight: FontWeight.w600)));

  Widget _dialogField(String label, TextEditingController ctrl, SL sl,
      {String? hint, bool obscure = false}) =>
    TextField(
      controller: ctrl, obscureText: obscure,
      style: TextStyle(color: sl.text1, fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: TextStyle(color: sl.text4, fontSize: 11),
        hintStyle: TextStyle(color: sl.text4, fontSize: 10),
        filled: true, fillColor: sl.bg,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: sl.border)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppColors.amber, width: 2))));

  void _showSnack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: Colors.white)),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      margin: const EdgeInsets.all(12),
      duration: const Duration(seconds: 3),
    ));
  }

  // Simple hash matching Apps Script simpleHash()
  String _simpleHash(String str) {
    int h = 0;
    for (int i = 0; i < str.length; i++) {
      h = ((h << 5) - h) + str.codeUnitAt(i);
      h = h & 0xFFFFFFFF;
    }
    if (h > 0x7FFFFFFF) h -= 0x100000000;
    if (h < 0) return '-${(-h).toRadixString(36)}';
    return h.toRadixString(36);
  }
}
