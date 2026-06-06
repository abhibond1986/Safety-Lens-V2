// lib/screens/admin_screen.dart
// SAIL Safety Lens — Admin Control Panel v2
// Login: username=admin / password=admin
// 4 tabs: Overview · Users · Incidents · Knowledge Base
// + Settings tab for password change & app config

import 'package:flutter/material.dart';
import '../main.dart';
import '../services/local_db.dart';
import '../services/sync_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Entry point — shows login gate, then the panel
// ─────────────────────────────────────────────────────────────────────────────
class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});
  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen>
    with SingleTickerProviderStateMixin {

  // ── Login state ───────────────────────────────────────────────
  bool _loggedIn = false;
  bool _loginLoading = false;
  String _loginError = '';
  final _unameCtrl = TextEditingController(text: 'admin');
  final _pwCtrl    = TextEditingController();
  bool  _pwVisible = false;
  String _adminPassword = 'admin'; // changeable at runtime

  // ── Panel state ───────────────────────────────────────────────
  late TabController _tabs;
  bool _loading = true;

  List<Map<String, dynamic>> _users     = [];
  List<Map<String, dynamic>> _incidents = [];
  List<Map<String, dynamic>> _kbDocs    = [];

  String _incFilter = 'ALL';

  // ── Stats ─────────────────────────────────────────────────────
  int get _totalUsers  => _users.length;
  int get _openInc     => _incidents.where((i) =>
      (i['status']?.toString().toUpperCase() ?? '') == 'OPEN').length;
  int get _closedInc   => _incidents.where((i) =>
      (i['status']?.toString().toUpperCase() ?? '') == 'CLOSED').length;
  int get _criticalInc => _incidents.where((i) =>
      (i['severity']?.toString().toUpperCase() ?? '') == 'CRITICAL').length;

  // ── Settings controllers ──────────────────────────────────────
  final _cfgNameCtrl = TextEditingController(text: 'SAIL Safety Lens V2');
  final _cfgOrgCtrl  = TextEditingController(text: 'SAIL Safety Organisation, Ranchi');
  final _cfgEcrCtrl  = TextEditingController(text: 'ECR Internal: 3333');
  final _pwOldCtrl   = TextEditingController();
  final _pwNewCtrl   = TextEditingController();
  final _pwConCtrl   = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 5, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    _unameCtrl.dispose(); _pwCtrl.dispose();
    _cfgNameCtrl.dispose(); _cfgOrgCtrl.dispose();
    _cfgEcrCtrl.dispose();
    _pwOldCtrl.dispose(); _pwNewCtrl.dispose(); _pwConCtrl.dispose();
    super.dispose();
  }

  // ── LOGIN ─────────────────────────────────────────────────────
  Future<void> _doLogin() async {
    setState(() { _loginLoading = true; _loginError = ''; });
    await Future.delayed(const Duration(milliseconds: 400)); // feel of auth
    final u = _unameCtrl.text.trim();
    final p = _pwCtrl.text;
    if (u == 'admin' && p == _adminPassword) {
      _loadAll();
      setState(() { _loggedIn = true; _loginLoading = false; });
    } else {
      setState(() {
        _loginError  = 'Incorrect username or password.';
        _loginLoading = false;
      });
    }
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    try {
      final users = await SyncService.fetchUsers();
      final incs  = await LocalDB.getIncidents();
      final kb    = await LocalDB.getKnowledgeDocs();
      // Fallback to local cache if backend returned nothing — must be awaited
      // outside setState because setState callback must be synchronous.
      final resolvedUsers = users.isNotEmpty ? users : await _localUsers();
      if (!mounted) return;
      setState(() {
        _users     = resolvedUsers;
        _incidents = incs;
        _kbDocs    = kb;
        _loading   = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<List<Map<String, dynamic>>> _localUsers() async =>
      await LocalDB.getAllUsers();

  // ─────────────────────────────────────────────────────────────
  //  BUILD
  // ─────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (!_loggedIn) return _buildLoginPage();
    return _buildAdminShell();
  }

  // ══════════════════════════════════════════════════════════════
  //  LOGIN PAGE
  // ══════════════════════════════════════════════════════════════
  Widget _buildLoginPage() {
    final sl = SL.of(context);
    return Scaffold(
      backgroundColor: sl.bg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxWidth: 340),
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: sl.card,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: sl.border)),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                // Badge
                Container(
                  width: 56, height: 56,
                  decoration: BoxDecoration(
                    color: AppColors.amber.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(16)),
                  child: const Icon(Icons.admin_panel_settings_rounded,
                      color: AppColors.amber, size: 28)),
                const SizedBox(height: 18),
                Text('Admin Portal',
                  style: TextStyle(color: sl.text1, fontSize: 20,
                      fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text('SAIL Safety Lens',
                  style: TextStyle(color: sl.text3, fontSize: 13)),
                const SizedBox(height: 24),

                // Username
                _loginField('Username', _unameCtrl, sl,
                    icon: Icons.person_outline_rounded),
                const SizedBox(height: 12),

                // Password
                TextField(
                  controller: _pwCtrl,
                  obscureText: !_pwVisible,
                  style: TextStyle(color: sl.text1, fontSize: 14),
                  onSubmitted: (_) => _doLogin(),
                  decoration: InputDecoration(
                    labelText: 'Password',
                    labelStyle: TextStyle(color: sl.text4, fontSize: 12),
                    prefixIcon: Icon(Icons.lock_outline_rounded,
                        color: sl.text4, size: 18),
                    suffixIcon: IconButton(
                      icon: Icon(_pwVisible ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                          color: sl.text4, size: 18),
                      onPressed: () => setState(() => _pwVisible = !_pwVisible)),
                    filled: true, fillColor: sl.bg2,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 14),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: sl.border)),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: sl.border)),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(
                            color: AppColors.amber, width: 2)))),
                const SizedBox(height: 18),

                // Sign in button
                SizedBox(width: double.infinity,
                  height: 46,
                  child: ElevatedButton(
                    onPressed: _loginLoading ? null : _doLogin,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.amber,
                      disabledBackgroundColor: AppColors.amber.withOpacity(0.5),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12))),
                    child: _loginLoading
                      ? const SizedBox(width: 20, height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Text('Sign in', style: TextStyle(
                          color: Colors.white, fontSize: 15,
                          fontWeight: FontWeight.w700)))),

                // Error
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: _loginError.isEmpty
                    ? const SizedBox(height: 8, key: ValueKey('empty'))
                    : Padding(
                        key: ValueKey('err'),
                        padding: const EdgeInsets.only(top: 10),
                        child: Text(_loginError,
                          style: const TextStyle(
                              color: AppColors.red, fontSize: 12),
                          textAlign: TextAlign.center))),

                const SizedBox(height: 14),
                Text('Default: admin / admin',
                  style: TextStyle(color: sl.text4, fontSize: 11)),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _loginField(String label, TextEditingController ctrl, SL sl,
      {IconData? icon}) =>
    TextField(
      controller: ctrl,
      style: TextStyle(color: sl.text1, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: sl.text4, fontSize: 12),
        prefixIcon: icon != null
          ? Icon(icon, color: sl.text4, size: 18) : null,
        filled: true, fillColor: sl.bg2,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: sl.border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: sl.border)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppColors.amber, width: 2))));

  // ══════════════════════════════════════════════════════════════
  //  ADMIN SHELL
  // ══════════════════════════════════════════════════════════════
  Widget _buildAdminShell() {
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
              color: AppColors.amber.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.shield_rounded,
                color: AppColors.amber, size: 18)),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Admin Panel',
              style: TextStyle(color: sl.text1, fontSize: 14,
                  fontWeight: FontWeight.w700)),
            Text('SAIL Safety Lens',
              style: TextStyle(color: sl.text4, fontSize: 9)),
          ]),
        ]),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: Icon(Icons.refresh_rounded, color: sl.text3, size: 20),
            onPressed: _loadAll),
          IconButton(
            tooltip: 'Sign out',
            icon: Icon(Icons.logout_rounded, color: sl.text3, size: 20),
            onPressed: () => setState(() {
              _loggedIn = false; _pwCtrl.clear(); _loginError = '';
            })),
        ],
        bottom: TabBar(
          controller: _tabs,
          labelColor: AppColors.amber,
          unselectedLabelColor: sl.text3,
          indicatorColor: AppColors.amber,
          indicatorSize: TabBarIndicatorSize.tab,
          isScrollable: true,
          labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
          tabs: const [
            Tab(icon: Icon(Icons.dashboard_rounded, size: 15), text: 'Overview'),
            Tab(icon: Icon(Icons.people_rounded, size: 15), text: 'Users'),
            Tab(icon: Icon(Icons.list_alt_rounded, size: 15), text: 'Incidents'),
            Tab(icon: Icon(Icons.library_books_rounded, size: 15), text: 'Knowledge'),
            Tab(icon: Icon(Icons.settings_rounded, size: 15), text: 'Settings'),
          ]),
      ),
      body: _loading
        ? Center(child: CircularProgressIndicator(color: AppColors.amber))
        : TabBarView(controller: _tabs, children: [
            _tabOverview(sl),
            _tabUsers(sl),
            _tabIncidents(sl),
            _tabKnowledge(sl),
            _tabSettings(sl),
          ]),
    );
  }

  // ══════════════════════════════════════════════════════════════
  //  TAB — OVERVIEW
  // ══════════════════════════════════════════════════════════════
  Widget _tabOverview(SL sl) => SingleChildScrollView(
    padding: const EdgeInsets.all(16),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionHead('Dashboard', sl),
      const SizedBox(height: 12),
      GridView.count(
        crossAxisCount: 2, shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: 10, mainAxisSpacing: 10, childAspectRatio: 1.7,
        children: [
          _statTile('Users', '$_totalUsers', const Color(0xFF185FA5),
              Icons.people_rounded, sl),
          _statTile('Open Incidents', '$_openInc', AppColors.amber,
              Icons.lock_open_rounded, sl),
          _statTile('Critical', '$_criticalInc', AppColors.crit,
              Icons.warning_rounded, sl),
          _statTile('Closed', '$_closedInc', AppColors.green,
              Icons.check_circle_rounded, sl),
        ]),
      const SizedBox(height: 24),
      _sectionHead('Quick Actions', sl),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: _actionTile(Icons.person_add_rounded, 'Add User',
            AppColors.green, sl, () {
          _tabs.animateTo(1);
          Future.delayed(const Duration(milliseconds: 350),
              () => _showAddUserDialog());
        })),
        const SizedBox(width: 10),
        Expanded(child: _actionTile(Icons.library_add_rounded, 'Add Knowledge',
            const Color(0xFF0F6E56), sl, () {
          _tabs.animateTo(3);
          Future.delayed(const Duration(milliseconds: 350),
              () => _showAddKbDialog());
        })),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: _actionTile(Icons.sync_rounded, 'Sync Sheets',
            AppColors.accent, sl, _syncAll)),
        const SizedBox(width: 10),
        Expanded(child: _actionTile(Icons.settings_rounded, 'Settings',
            const Color(0xFF534AB7), sl, () => _tabs.animateTo(4))),
      ]),
      const SizedBox(height: 24),
      _sectionHead('Admin Credentials', sl),
      const SizedBox(height: 8),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: sl.card, borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.amber.withOpacity(0.3))),
        child: Column(children: [
          _credRow('Username', 'admin', sl),
          _credRow('Password', '${_adminPassword == 'admin' ? 'admin ⚠ change recommended' : '••••••'}', sl),
          _credRow('Role', 'System Administrator', sl),
          _credRow('Plants', 'All plants — full access', sl),
        ])),
    ]),
  );

  Widget _statTile(String label, String value, Color color, IconData icon, SL sl) =>
    Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: sl.card, borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 6),
          Expanded(child: Text(label,
            style: TextStyle(color: sl.text3, fontSize: 10),
            overflow: TextOverflow.ellipsis)),
        ]),
        const SizedBox(height: 8),
        Text(value, style: TextStyle(color: color, fontSize: 26,
            fontWeight: FontWeight.w700)),
      ]));

  Widget _actionTile(IconData icon, String label, Color color, SL sl,
      VoidCallback onTap) =>
    GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.25))),
        child: Row(children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(label, style: TextStyle(
              color: color, fontSize: 12, fontWeight: FontWeight.w700))),
          Icon(Icons.chevron_right_rounded, color: color, size: 16),
        ])));

  Widget _credRow(String k, String v, SL sl) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(children: [
      SizedBox(width: 90, child: Text(k, style: TextStyle(
          color: sl.text4, fontSize: 11))),
      Expanded(child: Text(v, style: TextStyle(
          color: sl.text1, fontSize: 11, fontWeight: FontWeight.w600))),
    ]));

  // ══════════════════════════════════════════════════════════════
  //  TAB — USERS
  // ══════════════════════════════════════════════════════════════
  Widget _tabUsers(SL sl) => Column(children: [
    _listHeader('${_users.length} users', sl,
      action: _showAddUserDialog, actionLabel: 'Add User',
      actionColor: AppColors.green),
    Expanded(child: _users.isEmpty
      ? _empty('No users registered', Icons.people_outline_rounded, sl)
      : ListView.separated(
          padding: const EdgeInsets.all(14),
          itemCount: _users.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (_, i) => _userCard(_users[i], i, sl))),
  ]);

  Widget _userCard(Map<String, dynamic> u, int i, SL sl) {
    final name    = u['name']?.toString() ?? '—';
    final uname   = u['username']?.toString() ?? '—';
    final desig   = u['designation']?.toString() ?? '—';
    final plant   = u['plant']?.toString() ?? '—';
    final isAdmin = u['isAdmin']?.toString().toLowerCase() == 'true' ||
                    u['role']?.toString() == 'admin';
    final isActive = (u['status']?.toString().toLowerCase() ?? 'active') == 'active';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: sl.card, borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isAdmin
            ? AppColors.amber.withOpacity(0.3) : sl.border.withOpacity(0.5))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 38, height: 38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: (isAdmin ? AppColors.amber : AppColors.accent).withOpacity(0.12)),
            child: Center(child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: TextStyle(
                color: isAdmin ? AppColors.amber : AppColors.accent,
                fontSize: 16, fontWeight: FontWeight.w800)))),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(child: Text(name, style: TextStyle(
                  color: sl.text1, fontSize: 13, fontWeight: FontWeight.w700),
                  overflow: TextOverflow.ellipsis)),
              if (isAdmin) ...[
                const SizedBox(width: 6),
                _pill('ADMIN', AppColors.amber),
              ],
            ]),
            Text('@$uname · $desig', style: TextStyle(
                color: sl.text3, fontSize: 10)),
          ])),
          _pill(isActive ? 'Active' : 'Inactive',
              isActive ? AppColors.green : sl.text3),
        ]),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.only(left: 48),
          child: Text(plant, style: TextStyle(color: sl.text4, fontSize: 10))),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.only(left: 48),
          child: Wrap(spacing: 6, children: [
            _actionChip(
                isAdmin ? 'Revoke Admin' : 'Make Admin', AppColors.amber, sl,
                () => _toggleAdmin(u)),
            _actionChip(
                isActive ? 'Deactivate' : 'Activate',
                isActive ? sl.text3 : AppColors.green, sl,
                () => _toggleStatus(u)),
            if (uname != 'admin')
              _actionChip('Delete', AppColors.red, sl, () => _deleteUser(u)),
          ])),
      ]));
  }

  Widget _actionChip(String label, Color color, SL sl, VoidCallback onTap) =>
    GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08), borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withOpacity(0.3))),
        child: Text(label, style: TextStyle(
            color: color, fontSize: 9, fontWeight: FontWeight.w700))));

  // ══════════════════════════════════════════════════════════════
  //  TAB — INCIDENTS
  // ══════════════════════════════════════════════════════════════
  Widget _tabIncidents(SL sl) {
    final filtered = _incFilter == 'ALL' ? _incidents
        : _incidents.where((i) =>
            i['status']?.toString().toUpperCase() == _incFilter ||
            i['severity']?.toString().toUpperCase() == _incFilter).toList();

    return Column(children: [
      // Filter chips
      Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        color: sl.bg2,
        child: Row(children: [
          _filterChip('ALL', 'All', sl),
          const SizedBox(width: 6),
          _filterChip('OPEN', 'Open', sl),
          const SizedBox(width: 6),
          _filterChip('CLOSED', 'Closed', sl),
          const SizedBox(width: 6),
          _filterChip('CRITICAL', 'Critical', sl),
        ])),
      Divider(height: 1, color: sl.border),
      Expanded(child: filtered.isEmpty
        ? _empty('No incidents match the filter', Icons.assessment_outlined, sl)
        : ListView.separated(
            padding: const EdgeInsets.all(14),
            itemCount: filtered.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) => _incCard(filtered[i], sl))),
    ]);
  }

  Widget _filterChip(String value, String label, SL sl) {
    final active = _incFilter == value;
    return GestureDetector(
      onTap: () => setState(() => _incFilter = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: active ? AppColors.amber.withOpacity(0.1) : sl.card,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: active ? AppColors.amber : sl.border,
              width: active ? 1.5 : 0.8)),
        child: Text(label, style: TextStyle(
            color: active ? AppColors.amber : sl.text2,
            fontSize: 11, fontWeight: active ? FontWeight.w700 : FontWeight.w400))));
  }

  Widget _incCard(Map<String, dynamic> inc, SL sl) {
    final title   = inc['title']?.toString() ?? 'Untitled';
    final sev     = inc['severity']?.toString().toUpperCase() ?? '—';
    final status  = inc['status']?.toString().toUpperCase() ?? '—';
    final plant   = inc['plant']?.toString() ?? '—';
    final _rawDate = inc['date']?.toString() ?? '';
    final date    = _rawDate.length > 10 ? _rawDate.substring(0, 10) : _rawDate;
    final isClosed = status == 'CLOSED';

    final sevColor = switch (sev) {
      'CRITICAL' => AppColors.crit,
      'HIGH'     => AppColors.red,
      'MEDIUM'   => AppColors.amber,
      _          => AppColors.green,
    };

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isClosed ? AppColors.green.withOpacity(0.04) : sl.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: isClosed ? AppColors.green.withOpacity(0.2)
                : sevColor.withOpacity(0.25))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(title, style: TextStyle(
            color: isClosed ? sl.text3 : sl.text1,
            fontSize: 12, fontWeight: FontWeight.w700,
            decoration: isClosed ? TextDecoration.lineThrough : null),
            maxLines: 2, overflow: TextOverflow.ellipsis)),
          if (!isClosed)
            GestureDetector(
              onTap: () => _closeIncident(inc),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppColors.green.withOpacity(0.3))),
                child: const Text('Close', style: TextStyle(
                    color: AppColors.green, fontSize: 9,
                    fontWeight: FontWeight.w700)))),
        ]),
        const SizedBox(height: 5),
        Text('$plant · $date', style: TextStyle(color: sl.text4, fontSize: 10)),
        const SizedBox(height: 6),
        Wrap(spacing: 5, children: [
          _pill(sev, sevColor),
          _pill(status, isClosed ? AppColors.green : AppColors.amber),
        ]),
      ]));
  }


  // ══════════════════════════════════════════════════════════════
  //  TAB — KNOWLEDGE BASE
  // ══════════════════════════════════════════════════════════════
  Widget _tabKnowledge(SL sl) => Column(children: [
    _listHeader('${_kbDocs.length} documents', sl,
        action: _showAddKbDialog, actionLabel: 'Add Entry',
        actionColor: const Color(0xFF0F6E56)),
    Expanded(child: _kbDocs.isEmpty
      ? _empty(
          'No knowledge documents yet.\nAdd safety guidelines, SOPs,\nor regulatory references.',
          Icons.library_books_outlined, sl)
      : ListView.separated(
          padding: const EdgeInsets.all(14),
          itemCount: _kbDocs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (_, i) => _kbCard(_kbDocs[i], i, sl))),
  ]);

  Widget _kbCard(Map<String, dynamic> doc, int i, SL sl) {
    final title   = doc['title']?.toString() ?? 'Untitled';
    final source  = doc['source']?.toString() ?? '';
    final chars   = (doc['content']?.toString() ?? '').length;
    final preview = (doc['content']?.toString() ?? '');
    final preview2 = preview.length > 90
        ? '${preview.substring(0, 90)}…' : preview;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: sl.card, borderRadius: BorderRadius.circular(12),
        border: Border.all(color: sl.border.withOpacity(0.5))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 34, height: 34,
          decoration: BoxDecoration(
            color: const Color(0xFFE1F5EE),
            borderRadius: BorderRadius.circular(8)),
          child: const Icon(Icons.description_outlined,
              color: Color(0xFF0F6E56), size: 18)),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: TextStyle(color: sl.text1, fontSize: 12,
              fontWeight: FontWeight.w700)),
          if (source.isNotEmpty)
            Text(source, style: TextStyle(color: sl.text4, fontSize: 9)),
          const SizedBox(height: 4),
          Text(preview2, style: TextStyle(color: sl.text3, fontSize: 10, height: 1.45),
              maxLines: 2, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 3),
          Text('$chars chars', style: TextStyle(color: sl.text4, fontSize: 9)),
        ])),
        const SizedBox(width: 6),
        IconButton(
          icon: const Icon(Icons.delete_outline_rounded,
              color: AppColors.red, size: 18),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          onPressed: () => _deleteKbDoc(doc)),
      ]));
  }

  // ══════════════════════════════════════════════════════════════
  //  TAB — SETTINGS
  // ══════════════════════════════════════════════════════════════
  Widget _tabSettings(SL sl) => SingleChildScrollView(
    padding: const EdgeInsets.all(16),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionHead('App Configuration', sl),
      const SizedBox(height: 10),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: sl.card, borderRadius: BorderRadius.circular(14),
          border: Border.all(color: sl.border.withOpacity(0.5))),
        child: Column(children: [
          _settingField('App name', _cfgNameCtrl, sl),
          const SizedBox(height: 10),
          _settingField('Organisation', _cfgOrgCtrl, sl),
          const SizedBox(height: 10),
          _settingField('Emergency contact (ECR)', _cfgEcrCtrl, sl),
          const SizedBox(height: 14),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            _smBtn('Save', AppColors.amber, () {
              _showSnack('Settings saved ✓', AppColors.green);
            }),
          ]),
        ])),

      const SizedBox(height: 20),
      _sectionHead('Change Admin Password', sl),
      const SizedBox(height: 10),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: sl.card, borderRadius: BorderRadius.circular(14),
          border: Border.all(color: sl.border.withOpacity(0.5))),
        child: Column(children: [
          _settingField('Current password', _pwOldCtrl, sl, obscure: true),
          const SizedBox(height: 10),
          _settingField('New password', _pwNewCtrl, sl, obscure: true),
          const SizedBox(height: 10),
          _settingField('Confirm new password', _pwConCtrl, sl, obscure: true),
          const SizedBox(height: 14),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            _smBtn('Update password', AppColors.amber, _changePassword),
          ]),
        ])),
    ]));

  Widget _settingField(String label, TextEditingController ctrl, SL sl,
      {bool obscure = false}) =>
    TextField(
      controller: ctrl, obscureText: obscure,
      style: TextStyle(color: sl.text1, fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: sl.text4, fontSize: 11),
        filled: true, fillColor: sl.bg,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: sl.border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: sl.border)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppColors.amber, width: 2))));

  // ══════════════════════════════════════════════════════════════
  //  DIALOGS
  // ══════════════════════════════════════════════════════════════
  void _showAddUserDialog() {
    final sl = SL.of(context);
    final nameCtrl = TextEditingController();
    final uCtrl    = TextEditingController();
    final pCtrl    = TextEditingController();
    final dCtrl    = TextEditingController();
    final plCtrl   = TextEditingController();
    bool isAdmin   = false;

    showDialog(context: context, builder: (_) =>
      StatefulBuilder(builder: (ctx, setS) => AlertDialog(
        backgroundColor: sl.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Add New User', style: TextStyle(
            color: AppColors.text1, fontSize: 15, fontWeight: FontWeight.w700)),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          _dlgField('Full name', nameCtrl, sl), const SizedBox(height: 8),
          _dlgField('Username', uCtrl, sl), const SizedBox(height: 8),
          _dlgField('Password', pCtrl, sl, obscure: true), const SizedBox(height: 8),
          _dlgField('Designation', dCtrl, sl, hint: 'e.g. AGM Safety'),
          const SizedBox(height: 8),
          _dlgField('Plant', plCtrl, sl, hint: 'e.g. BSP Bhilai'),
          const SizedBox(height: 12),
          Row(children: [
            Switch(value: isAdmin, activeColor: AppColors.amber,
                onChanged: (v) => setS(() => isAdmin = v)),
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
              try {
                await SyncService.registerUser({
                  'name':         nameCtrl.text.trim(),
                  'username':     uCtrl.text.trim(),
                  'passwordHash': _simpleHash(pCtrl.text.trim()),
                  'designation':  dCtrl.text.trim(),
                  'plant':        plCtrl.text.trim(),
                  'isAdmin':      isAdmin ? 'TRUE' : 'FALSE',
                });
              } catch (_) {}
              await _loadAll();
              _showSnack('User added ✓', AppColors.green);
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.green,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            child: const Text('Add User', style: TextStyle(color: Colors.white))),
        ])));
  }

  void _showAddKbDialog() {
    final sl = SL.of(context);
    final titleCtrl   = TextEditingController();
    final contentCtrl = TextEditingController();

    showDialog(context: context, builder: (_) => AlertDialog(
      backgroundColor: sl.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Add Knowledge Entry', style: TextStyle(
          color: AppColors.text1, fontSize: 15, fontWeight: FontWeight.w700)),
      content: SizedBox(width: double.maxFinite, child: Column(mainAxisSize: MainAxisSize.min, children: [
        _dlgField('Title / topic', titleCtrl, sl,
            hint: 'e.g. SG/02 Working at Height'),
        const SizedBox(height: 10),
        TextField(
          controller: contentCtrl, maxLines: 6,
          style: TextStyle(color: sl.text1, fontSize: 12),
          decoration: InputDecoration(
            hintText: 'Paste safety guidelines, regulations, SOPs…',
            hintStyle: TextStyle(color: sl.text4, fontSize: 10),
            filled: true, fillColor: sl.bg,
            contentPadding: const EdgeInsets.all(10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: sl.border)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFF0F6E56), width: 2)))),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey))),
        ElevatedButton(
          onPressed: () async {
            if (titleCtrl.text.trim().isEmpty || contentCtrl.text.trim().isEmpty) return;
            Navigator.pop(context);
            await LocalDB.addKnowledgeDoc(
              title:   titleCtrl.text.trim(),
              content: contentCtrl.text.trim(),
              source:  'Admin Panel',
            );
            await _loadAll();
            _showSnack('Knowledge entry added ✓', const Color(0xFF0F6E56));
          },
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F6E56),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
          child: const Text('Save Entry', style: TextStyle(color: Colors.white))),
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
    final wasAdmin = u['isAdmin']?.toString().toLowerCase() == 'true' ||
                     u['role']?.toString() == 'admin';
    try {
      await SyncService.updateUserField(
          u['username']?.toString() ?? '', 'isAdmin', wasAdmin ? 'FALSE' : 'TRUE');
    } catch (_) {}
    await _loadAll();
    _showSnack(wasAdmin ? 'Admin role removed' : 'Admin role granted', AppColors.amber);
  }

  Future<void> _toggleStatus(Map<String, dynamic> u) async {
    final isActive = (u['status']?.toString().toLowerCase() ?? 'active') == 'active';
    try {
      await SyncService.updateUserField(
          u['username']?.toString() ?? '', 'status',
          isActive ? 'inactive' : 'active');
    } catch (_) {}
    await _loadAll();
    _showSnack('User ${isActive ? 'deactivated' : 'activated'}',
        isActive ? sl.text3 : AppColors.green);
  }

  Future<void> _deleteUser(Map<String, dynamic> u) async {
    final sl = SL.of(context);
    final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
      backgroundColor: sl.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      title: const Text('Delete User', style: TextStyle(
          color: AppColors.text1, fontSize: 15, fontWeight: FontWeight.w700)),
      content: Text('Delete "${u['name'] ?? u['username']}"? This cannot be undone.',
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
    if (ok != true) return;
    try { await SyncService.deleteUser(u['username']?.toString() ?? ''); } catch (_) {}
    await _loadAll();
    _showSnack('User deleted', AppColors.red);
  }

  Future<void> _closeIncident(Map<String, dynamic> inc) async {
    final sl = SL.of(context);
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
      backgroundColor: sl.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      title: Row(children: const [
        Icon(Icons.lock_rounded, color: AppColors.green, size: 16),
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
    if (ok != true) return;
    inc['status']           = 'CLOSED';
    inc['correctiveAction'] = ctrl.text.trim();
    inc['closedAt']         = DateTime.now().toIso8601String();
    await LocalDB.saveIncident(inc);
    SyncService.pushIncident(inc).catchError((_) => false);
    await _loadAll();
    _showSnack('Incident closed ✓', AppColors.green);
  }

  Future<void> _deleteKbDoc(Map<String, dynamic> doc) async {
    await LocalDB.deleteKnowledgeDoc(doc['id'].toString());
    await _loadAll();
    _showSnack('Knowledge entry deleted', AppColors.red);
  }

  void _changePassword() {
    final old = _pwOldCtrl.text;
    final nw  = _pwNewCtrl.text;
    final cn  = _pwConCtrl.text;
    if (old != _adminPassword) {
      _showSnack('Current password is incorrect', AppColors.red); return;
    }
    if (nw.isEmpty) {
      _showSnack('New password cannot be empty', AppColors.red); return;
    }
    if (nw != cn) {
      _showSnack('Passwords do not match', AppColors.red); return;
    }
    setState(() => _adminPassword = nw);
    _pwOldCtrl.clear(); _pwNewCtrl.clear(); _pwConCtrl.clear();
    _showSnack('Password updated ✓', AppColors.green);
  }

  // ── Helpers ───────────────────────────────────────────────────
  SL get sl => SL.of(context);

  Widget _sectionHead(String title, SL sl) => Row(children: [
    Container(width: 3, height: 16, color: AppColors.amber,
        margin: const EdgeInsets.only(right: 8)),
    Text(title, style: TextStyle(color: sl.text1, fontSize: 14,
        fontWeight: FontWeight.w700)),
  ]);

  Widget _listHeader(String title, SL sl,
      {VoidCallback? action, String? actionLabel, Color? actionColor}) =>
    Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      color: sl.bg2,
      child: Row(children: [
        Expanded(child: Text(title, style: TextStyle(color: sl.text3, fontSize: 12))),
        if (action != null)
          ElevatedButton.icon(
            onPressed: action,
            icon: const Icon(Icons.add_rounded, size: 14, color: Colors.white),
            label: Text(actionLabel ?? 'Add', style: const TextStyle(
                color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
            style: ElevatedButton.styleFrom(
              backgroundColor: actionColor ?? AppColors.amber,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)))),
      ]));

  Widget _empty(String msg, IconData icon, SL sl) =>
    Center(child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: sl.text4, size: 40),
        const SizedBox(height: 12),
        Text(msg, style: TextStyle(color: sl.text3, fontSize: 13),
            textAlign: TextAlign.center),
      ])));

  Widget _pill(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(99),
      border: Border.all(color: color.withOpacity(0.3))),
    child: Text(text, style: TextStyle(
        color: color, fontSize: 9, fontWeight: FontWeight.w700)));

  Widget _dlgField(String label, TextEditingController ctrl, SL sl,
      {bool obscure = false, String? hint}) =>
    TextField(
      controller: ctrl, obscureText: obscure,
      style: TextStyle(color: sl.text1, fontSize: 13),
      decoration: InputDecoration(
        labelText: label, hintText: hint,
        labelStyle: TextStyle(color: sl.text4, fontSize: 11),
        hintStyle: TextStyle(color: sl.text4, fontSize: 10),
        filled: true, fillColor: sl.bg,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: sl.border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: sl.border)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppColors.amber, width: 2))));

  Widget _smBtn(String label, Color color, VoidCallback onTap) =>
    ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
      child: Text(label, style: const TextStyle(
          color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)));

  void _showSnack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: Colors.white)),
      backgroundColor: color, behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      margin: const EdgeInsets.all(12),
      duration: const Duration(seconds: 3)));
  }

  // Matches Apps Script simpleHash()
  String _simpleHash(String s) {
    int h = 0;
    for (int i = 0; i < s.length; i++) {
      h = ((h << 5) - h) + s.codeUnitAt(i);
      h = h & 0xFFFFFFFF;
    }
    if (h > 0x7FFFFFFF) h -= 0x100000000;
    return h < 0 ? '-${(-h).toRadixString(36)}' : h.toRadixString(36);
  }
}
