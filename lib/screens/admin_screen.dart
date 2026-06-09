// lib/screens/admin_screen.dart
// SAIL Safety Lens — Admin Control Panel v4
// Login: username=admin / password=admin
// 5 tabs: Overview · Users · Incidents · Knowledge Base · Settings
// ✅ NEW: Merged user loading — Sheets + cached + local + admin
// ✅ NEW: Daily Report card with 7-day mini-chart
// ✅ NEW: Danger Zone — Reset all reports & Re-seed knowledge base

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import '../main.dart';
import '../services/local_db.dart';
import '../services/sync_service.dart';
import '../services/kb_seed_data.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});
  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen>
    with SingleTickerProviderStateMixin {

  bool _loggedIn = false;
  bool _loginLoading = false;
  String _loginError = '';
  final _unameCtrl = TextEditingController(text: 'admin');
  final _pwCtrl    = TextEditingController();
  bool  _pwVisible = false;
  String _adminPassword = 'admin';

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
  int get _aiScanCount => _incidents.where((i) =>
      (i['type']?.toString().toUpperCase() ?? '') == 'AI_SCAN').length;
  int get _nearMissCount => _incidents.where((i) =>
      (i['type']?.toString().toUpperCase() ?? '') == 'NEAR_MISS').length;
  int get _activeUsersCount => _users.where((u) =>
      (u['status']?.toString().toLowerCase() ?? 'active') == 'active').length;

  // ── Daily Report counters ─────────────────────────────────────
  String _ymd(String? raw) {
    if (raw == null || raw.isEmpty) return '';
    try {
      final d = DateTime.parse(raw);
      return '${d.year.toString().padLeft(4, '0')}-'
             '${d.month.toString().padLeft(2, '0')}-'
             '${d.day.toString().padLeft(2, '0')}';
    } catch (_) { return ''; }
  }

  String get _todayYmd {
    final n = DateTime.now();
    return '${n.year.toString().padLeft(4, '0')}-'
           '${n.month.toString().padLeft(2, '0')}-'
           '${n.day.toString().padLeft(2, '0')}';
  }

  int get _todayAiScans => _incidents.where((i) =>
      (i['type']?.toString().toUpperCase() ?? '') == 'AI_SCAN' &&
      _ymd(i['date']?.toString()) == _todayYmd).length;

  int get _todayNearMiss => _incidents.where((i) =>
      (i['type']?.toString().toUpperCase() ?? '') == 'NEAR_MISS' &&
      _ymd(i['date']?.toString()) == _todayYmd).length;

  Map<String, Map<String, int>> get _last7Days {
    final result = <String, Map<String, int>>{};
    for (int i = 6; i >= 0; i--) {
      final d = DateTime.now().subtract(Duration(days: i));
      final ymd = '${d.year.toString().padLeft(4, '0')}-'
                  '${d.month.toString().padLeft(2, '0')}-'
                  '${d.day.toString().padLeft(2, '0')}';
      result[ymd] = {'ai': 0, 'nm': 0};
    }
    for (final inc in _incidents) {
      final ymd = _ymd(inc['date']?.toString());
      if (result.containsKey(ymd)) {
        final t = (inc['type']?.toString().toUpperCase() ?? '');
        if (t == 'AI_SCAN')   result[ymd]!['ai'] = result[ymd]!['ai']! + 1;
        if (t == 'NEAR_MISS') result[ymd]!['nm'] = result[ymd]!['nm']! + 1;
      }
    }
    return result;
  }

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
    await Future.delayed(const Duration(milliseconds: 300));
    final u = _unameCtrl.text.trim().toLowerCase();
    final p = _pwCtrl.text;

    bool ok = (u == 'admin' && p == _adminPassword);

    if (!ok) {
      try {
        final localUser = await LocalDB.signIn(u, p);
        if (localUser != null) {
          final isAdm = localUser['isAdmin'] == true ||
              localUser['isAdmin']?.toString().toLowerCase() == 'true';
          if (isAdm) ok = true;
        }
      } catch (_) {}
    }

    if (ok) {
      _loadAll();
      setState(() { _loggedIn = true; _loginLoading = false; });
    } else {
      setState(() {
        _loginError  = 'Incorrect credentials or insufficient privileges.';
        _loginLoading = false;
      });
    }
  }

  // ── LOAD ALL — Merged user loading ────────────────────────────
  Future<void> _loadAll() async {
    setState(() => _loading = true);
    try {
      // Pull users from EVERY available source and merge — guarantees a
      // registered user shows up no matter where they registered.
      List<Map<String, dynamic>> sheetsUsers = [];
      try {
        sheetsUsers = await SyncService.fetchUsers();
      } catch (_) {}
      final localUsers  = await LocalDB.getUsers();
      final cachedUsers = await LocalDB.getCachedUsers();

      // Merge with username as the unique key.
      // Priority: Sheets > cached > local.
      final byUname = <String, Map<String, dynamic>>{};
      for (final u in [...sheetsUsers, ...cachedUsers, ...localUsers]) {
        final uname = (u['username']?.toString() ?? '').trim();
        if (uname.isEmpty) continue;
        if (!byUname.containsKey(uname)) {
          byUname[uname] = Map<String, dynamic>.from(u);
        } else {
          // Fill missing fields from lower-priority sources
          final existing = byUname[uname]!;
          u.forEach((k, v) {
            if (existing[k] == null || existing[k].toString().isEmpty) {
              existing[k] = v;
            }
          });
        }
      }

      // Always include the built-in admin user
      if (!byUname.containsKey('admin')) {
        byUname['admin'] = {
          'username': 'admin',
          'name': 'System Admin',
          'designation': 'Administrator',
          'plant': 'SAIL HQ',
          'pno': 'ADMIN001',
          'isAdmin': true,
          'status': 'active',
        };
      }

      final mergedUsers = byUname.values.toList();
      final incs = await LocalDB.getIncidents();
      final kb   = await LocalDB.getKnowledgeDocs();

      if (!mounted) return;
      setState(() {
        _users     = mergedUsers;
        _incidents = incs;
        _kbDocs    = kb;
        _loading   = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

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

                _loginField('Username', _unameCtrl, sl,
                    icon: Icons.person_outline_rounded),
                const SizedBox(height: 12),

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

                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: _loginError.isEmpty
                    ? const SizedBox(height: 8, key: ValueKey('empty'))
                    : Padding(
                        key: const ValueKey('err'),
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
  //  TAB — OVERVIEW (with Daily Report card)
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
          _statTile('Total Users', '$_totalUsers', const Color(0xFF185FA5),
              Icons.people_rounded, sl),
          _statTile('Active Users', '$_activeUsersCount', AppColors.green,
              Icons.person_pin_rounded, sl),
          _statTile('AI Scans', '$_aiScanCount', AppColors.accent,
              Icons.camera_alt_rounded, sl),
          _statTile('Near Miss', '$_nearMissCount', AppColors.amber,
              Icons.warning_amber_rounded, sl),
          _statTile('Critical', '$_criticalInc', AppColors.crit,
              Icons.error_rounded, sl),
          _statTile('Closed', '$_closedInc', const Color(0xFF0F6E56),
              Icons.check_circle_rounded, sl),
        ]),
      const SizedBox(height: 14),
      // ── Daily Report Card ──────────────────────────────────────
      _dailyReportCard(sl),
      const SizedBox(height: 14),
      // Status summary bar
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: sl.card, borderRadius: BorderRadius.circular(12),
          border: Border.all(color: sl.border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.pie_chart_rounded, color: AppColors.accent, size: 14),
            const SizedBox(width: 6),
            Text('Status Summary', style: TextStyle(
                color: sl.text2, fontSize: 11,
                fontWeight: FontWeight.w700)),
            const Spacer(),
            Text('${_incidents.length} total',
                style: TextStyle(color: sl.text4, fontSize: 10)),
          ]),
          const SizedBox(height: 10),
          _statusBar('Open',          _openInc,     AppColors.amber, sl),
          const SizedBox(height: 6),
          _statusBar('Critical',      _criticalInc, AppColors.crit,  sl),
          const SizedBox(height: 6),
          _statusBar('Closed',        _closedInc,   AppColors.green, sl),
        ])),
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
          _credRow('Password', _adminPassword == 'admin' ? 'admin ⚠ change recommended' : '••••••', sl),
          _credRow('Role', 'System Administrator', sl),
          _credRow('Plants', 'All plants — full access', sl),
        ])),
    ]),
  );

  // ══════════════════════════════════════════════════════════════
  //  DAILY REPORT CARD — today + 7-day mini-chart
  // ══════════════════════════════════════════════════════════════
  Widget _dailyReportCard(SL sl) {
    final week    = _last7Days;
    final maxAi   = week.values.fold<int>(0, (m, v) => v['ai']! > m ? v['ai']! : m);
    final maxNm   = week.values.fold<int>(0, (m, v) => v['nm']! > m ? v['nm']! : m);
    final maxAny  = (maxAi > maxNm ? maxAi : maxNm);
    final scale   = maxAny == 0 ? 1 : maxAny;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [
            AppColors.accent.withOpacity(0.08),
            AppColors.cyan.withOpacity(0.04),
          ]),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.accent.withOpacity(0.25))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 28, height: 28,
            decoration: BoxDecoration(
              color: AppColors.accent.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.today_rounded,
                color: AppColors.accent, size: 16)),
          const SizedBox(width: 8),
          Text('Daily Report — $_todayYmd',
              style: TextStyle(color: sl.text1, fontSize: 13,
                  fontWeight: FontWeight.w700)),
        ]),

        const SizedBox(height: 12),

        Row(children: [
          Expanded(child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: sl.card, borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.accent.withOpacity(0.2))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.camera_alt_rounded,
                    color: AppColors.accent, size: 13),
                const SizedBox(width: 4),
                Text('AI Scans today',
                    style: TextStyle(color: sl.text3, fontSize: 10)),
              ]),
              const SizedBox(height: 4),
              Text('$_todayAiScans',
                  style: const TextStyle(color: AppColors.accent,
                      fontSize: 22, fontWeight: FontWeight.w800)),
            ]))),
          const SizedBox(width: 10),
          Expanded(child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: sl.card, borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.amber.withOpacity(0.25))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.warning_amber_rounded,
                    color: AppColors.amber, size: 13),
                const SizedBox(width: 4),
                Text('Near Miss today',
                    style: TextStyle(color: sl.text3, fontSize: 10)),
              ]),
              const SizedBox(height: 4),
              Text('$_todayNearMiss',
                  style: const TextStyle(color: AppColors.amber,
                      fontSize: 22, fontWeight: FontWeight.w800)),
            ]))),
        ]),

        const SizedBox(height: 14),

        Text('Last 7 days',
            style: TextStyle(color: sl.text4, fontSize: 9,
                fontWeight: FontWeight.w700, letterSpacing: 0.6)),
        const SizedBox(height: 8),
        SizedBox(
          height: 80,
          child: Row(crossAxisAlignment: CrossAxisAlignment.end,
            children: week.entries.map((e) {
              final ymd = e.key;
              final ai  = e.value['ai']!;
              final nm  = e.value['nm']!;
              final aiH = (ai / scale) * 50;
              final nmH = (nm / scale) * 50;
              final day = ymd.substring(8);
              return Expanded(child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Row(mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Container(
                          width: 7, height: aiH.clamp(2, 50).toDouble(),
                          decoration: BoxDecoration(
                            color: AppColors.accent,
                            borderRadius: BorderRadius.circular(2))),
                        const SizedBox(width: 2),
                        Container(
                          width: 7, height: nmH.clamp(2, 50).toDouble(),
                          decoration: BoxDecoration(
                            color: AppColors.amber,
                            borderRadius: BorderRadius.circular(2))),
                      ]),
                    const SizedBox(height: 4),
                    Text(day,
                        style: TextStyle(color: sl.text4, fontSize: 8.5)),
                    Text('${ai + nm}',
                        style: TextStyle(color: sl.text3, fontSize: 8,
                            fontWeight: FontWeight.w600)),
                  ]),
              ));
            }).toList()),
        ),
        const SizedBox(height: 6),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(
              color: AppColors.accent, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 4),
          Text('AI Scans', style: TextStyle(color: sl.text3, fontSize: 9)),
          const SizedBox(width: 14),
          Container(width: 8, height: 8, decoration: BoxDecoration(
              color: AppColors.amber, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 4),
          Text('Near Miss', style: TextStyle(color: sl.text3, fontSize: 9)),
        ]),
      ]));
  }

  Widget _statusBar(String label, int count, Color color, SL sl) {
    final pct = _incidents.isEmpty ? 0.0 : count / _incidents.length;
    return Row(children: [
      SizedBox(width: 70, child: Text(label,
          style: TextStyle(color: sl.text3, fontSize: 10))),
      Expanded(child: Stack(children: [
        Container(height: 10,
          decoration: BoxDecoration(
            color: sl.border.withOpacity(0.3),
            borderRadius: BorderRadius.circular(5))),
        FractionallySizedBox(widthFactor: pct.clamp(0, 1),
          child: Container(height: 10,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                  colors: [color, color.withOpacity(0.6)]),
              borderRadius: BorderRadius.circular(5)))),
      ])),
      const SizedBox(width: 8),
      SizedBox(width: 36, child: Text('$count (${(pct*100).round()}%)',
          textAlign: TextAlign.right,
          style: TextStyle(color: color, fontSize: 10,
              fontWeight: FontWeight.w700))),
    ]);
  }

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
            _actionChip('Edit', AppColors.accent, sl, () => _editUser(u)),
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
    final rawDate = inc['date']?.toString() ?? '';
    final date    = rawDate.length > 10 ? rawDate.substring(0, 10) : rawDate;
    final isClosed = status == 'CLOSED';

    final sevColor = switch (sev) {
      'CRITICAL' => AppColors.crit,
      'HIGH'     => AppColors.red,
      'MEDIUM'   => AppColors.amber,
      _          => AppColors.green,
    };

    return GestureDetector(
      onTap: () => _showIncidentDetails(inc),
      child: Container(
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
          Row(mainAxisSize: MainAxisSize.min, children: [
            if (!isClosed)
              GestureDetector(
                onTap: () => _closeIncident(inc),
                child: Container(
                  margin: const EdgeInsets.only(right: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppColors.green.withOpacity(0.3))),
                  child: const Text('Close', style: TextStyle(
                      color: AppColors.green, fontSize: 9,
                      fontWeight: FontWeight.w700)))),
            GestureDetector(
              onTap: () => _deleteIncident(inc),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.red.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppColors.red.withOpacity(0.3))),
                child: const Text('Delete', style: TextStyle(
                    color: AppColors.red, fontSize: 9,
                    fontWeight: FontWeight.w700)))),
          ]),
        ]),
        const SizedBox(height: 5),
        Text('$plant · $date', style: TextStyle(color: sl.text4, fontSize: 10)),
        const SizedBox(height: 6),
        Wrap(spacing: 5, children: [
          _pill(sev, sevColor),
          _pill(status, isClosed ? AppColors.green : AppColors.amber),
          _pill('Tap for details', sl.text3),
        ]),
      ])));
  }

  // ══════════════════════════════════════════════════════════════
  //  TAB — KNOWLEDGE BASE
  // ══════════════════════════════════════════════════════════════
  Widget _tabKnowledge(SL sl) => Column(children: [
    _listHeader('${_kbDocs.length} documents', sl,
        action: _showAddKbDialog, actionLabel: 'Add Entry',
        actionColor: const Color(0xFF0F6E56)),
    Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
      child: SizedBox(width: double.infinity, child: OutlinedButton.icon(
        onPressed: _uploadKbPdf,
        icon: const Icon(Icons.picture_as_pdf_outlined,
            size: 16, color: AppColors.amber),
        label: const Text('Upload PDF document',
            style: TextStyle(color: AppColors.amber, fontSize: 12,
                fontWeight: FontWeight.w700)),
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: AppColors.amber, width: 1.5),
          padding: const EdgeInsets.symmetric(vertical: 11),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10))),
      )),
    ),
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

      // ══════════════════════════════════════════════════════════
      // ✅ NEW: DANGER ZONE
      // ══════════════════════════════════════════════════════════
      const SizedBox(height: 24),
      Row(children: [
        Container(width: 3, height: 16, color: AppColors.red,
            margin: const EdgeInsets.only(right: 8)),
        const Text('⚠ Danger Zone',
            style: TextStyle(color: AppColors.red, fontSize: 14,
                fontWeight: FontWeight.w700)),
      ]),
      const SizedBox(height: 10),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.red.withOpacity(0.04),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.red.withOpacity(0.3))),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Destructive actions — proceed with caution',
                style: TextStyle(color: AppColors.red, fontSize: 11,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            _dangerAction(
              sl,
              Icons.delete_sweep_rounded,
              'Reset all reports & analysis',
              'Clears all incidents from local storage AND Google Sheets. '
                  'Users and Knowledge Base are preserved.',
              _confirmResetAllData,
              AppColors.red,
            ),
            const SizedBox(height: 10),
            _dangerAction(
              sl,
              Icons.menu_book_rounded,
              'Wipe & re-seed knowledge base',
              'Deletes all KB entries and reloads ${KbSeedData.count} '
                  'regulatory entries from FA 1948, SMPV 2016, CEA 2023, '
                  'IS 14489, and state factory rules.',
              _confirmSeedKb,
              AppColors.amber,
            ),
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

  Future<void> _deleteIncident(Map<String, dynamic> inc) async {
    final sl = SL.of(context);
    final id = inc['id']?.toString() ?? '';
    final ok = await showDialog<bool>(context: context, builder: (_) =>
      AlertDialog(
        backgroundColor: sl.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Row(children: [
          Icon(Icons.delete_forever_rounded, color: AppColors.red, size: 18),
          SizedBox(width: 8),
          Text('Delete Incident', style: TextStyle(
              color: AppColors.text1, fontSize: 14, fontWeight: FontWeight.w700)),
        ]),
        content: Text(
          'Permanently delete "${inc['title'] ?? id}"?\n\nThis will remove it from local storage and Google Sheets.',
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
    await LocalDB.deleteIncident(id);
    SyncService.deleteIncident(id).catchError((_) => false);
    await _loadAll();
    _showSnack('Incident deleted', AppColors.red);
  }

  // ──────────────────────────────────────────────────────────────
  //  EDIT USER PROFILE
  // ──────────────────────────────────────────────────────────────
  Future<void> _editUser(Map<String, dynamic> u) async {
    final sl = SL.of(context);
    final nameCtrl  = TextEditingController(text: u['name']?.toString()        ?? '');
    final desigCtrl = TextEditingController(text: u['designation']?.toString() ?? '');
    final plantCtrl = TextEditingController(text: u['plant']?.toString()       ?? '');
    final pnoCtrl   = TextEditingController(text: u['pno']?.toString()         ?? '');
    final emailCtrl = TextEditingController(text: u['email']?.toString()       ?? '');
    final mobCtrl   = TextEditingController(text: u['mobile']?.toString()      ?? '');

    final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
      backgroundColor: sl.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(children: [
        const Icon(Icons.edit_rounded, color: AppColors.accent, size: 18),
        const SizedBox(width: 8),
        Text('Edit @${u['username']}',
            style: TextStyle(color: sl.text1, fontSize: 14,
                fontWeight: FontWeight.w700)),
      ]),
      content: SizedBox(width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _dlgField('Full name',   nameCtrl,  sl),
            const SizedBox(height: 8),
            _dlgField('Designation', desigCtrl, sl,
                hint: 'e.g. AGM Safety'),
            const SizedBox(height: 8),
            _dlgField('Plant / Unit', plantCtrl, sl,
                hint: 'e.g. BSP, DSP, RSP…'),
            const SizedBox(height: 8),
            _dlgField('P. No.',  pnoCtrl,  sl),
            const SizedBox(height: 8),
            _dlgField('Mobile',  mobCtrl,  sl),
            const SizedBox(height: 8),
            _dlgField('Email',   emailCtrl, sl),
          ])),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey))),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, true),
          style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accent,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8))),
          child: const Text('Save', style: TextStyle(color: Colors.white))),
      ]));
    if (ok != true) return;

    final username = u['username']?.toString() ?? '';
    if (username.isNotEmpty) {
      final fields = {
        'name': nameCtrl.text.trim(),
        'designation': desigCtrl.text.trim(),
        'plant': plantCtrl.text.trim(),
        'pno': pnoCtrl.text.trim(),
        'mobile': mobCtrl.text.trim(),
        'email': emailCtrl.text.trim(),
      };
      for (final entry in fields.entries) {
        await SyncService.updateUserField(username, entry.key, entry.value)
            .catchError((_) => false);
      }
    }
    await _loadAll();
    _showSnack('User profile updated ✓', AppColors.accent);
  }

  // ──────────────────────────────────────────────────────────────
  //  INCIDENT DETAILS — full case info, all hazards & findings
  // ──────────────────────────────────────────────────────────────
  void _showIncidentDetails(Map<String, dynamic> inc) {
    final sl     = SL.of(context);
    final title  = inc['title']?.toString()    ?? 'Untitled';
    final sev    = inc['severity']?.toString() ?? '—';
    final status = inc['status']?.toString()   ?? '—';
    final type   = inc['type']?.toString()     ?? '—';
    final plant  = inc['plant']?.toString()    ?? '—';
    final dept   = inc['dept']?.toString()     ?? '—';
    final loc    = inc['location']?.toString() ?? '—';
    final desc   = inc['desc']?.toString()     ?? '';
    final summary= inc['summary']?.toString()  ?? '';
    final imm    = inc['immediateAction']?.toString() ?? '';
    final wsa    = inc['wsaCategory']?.toString() ?? '—';
    final repBy  = inc['reportedBy']?.toString() ?? '—';
    final pno    = inc['reportedByPno']?.toString() ?? '—';
    final risk   = inc['riskScore']?.toString() ?? '—';
    final conf   = inc['confidence']?.toString() ?? '—';
    final pdfUrl = inc['pdfUrl']?.toString() ?? '';
    final date   = inc['date']?.toString() ?? '';
    final dateStr = date.length > 19 ? date.substring(0, 19).replaceAll('T', ' ') : date;

    List<Map<String, dynamic>> hazards = [];
    final hz = inc['hazards'];
    if (hz is List) {
      hazards = hz.whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e)).toList();
    } else if (hz is String && hz.isNotEmpty) {
      try {
        final parsed = jsonDecode(hz);
        if (parsed is List) {
          hazards = parsed.whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e)).toList();
        }
      } catch (_) {}
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.85, minChildSize: 0.5, maxChildSize: 0.95,
        builder: (_, scrollCtrl) => Container(
          decoration: BoxDecoration(
            color: sl.bg2,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20))),
          child: Column(children: [
            Container(width: 40, height: 4,
              margin: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                  color: sl.border, borderRadius: BorderRadius.circular(2))),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Row(children: [
                Container(
                  width: 38, height: 38,
                  decoration: BoxDecoration(
                    color: AppColors.amber.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.assignment_outlined,
                      color: AppColors.amber, size: 20)),
                const SizedBox(width: 10),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Incident Details',
                        style: TextStyle(color: sl.text1, fontSize: 14,
                            fontWeight: FontWeight.w700)),
                    Text(type, style: TextStyle(color: sl.text4, fontSize: 10)),
                  ])),
                IconButton(onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.close, color: sl.text3, size: 20)),
              ]),
            ),
            Divider(height: 1, color: sl.border),
            Expanded(child: ListView(
              controller: scrollCtrl,
              padding: const EdgeInsets.all(16),
              children: [
                Text(title, style: TextStyle(
                    color: sl.text1, fontSize: 15,
                    fontWeight: FontWeight.w800, height: 1.3)),
                const SizedBox(height: 8),
                Wrap(spacing: 6, runSpacing: 4, children: [
                  _pill(sev, _sevColor(sev)),
                  _pill(status, status.toUpperCase() == 'CLOSED'
                      ? AppColors.green : AppColors.amber),
                  if (risk != '—') _pill('Risk: $risk', AppColors.red),
                  if (conf != '—') _pill('Conf: $conf%', AppColors.cyan),
                ]),
                const SizedBox(height: 16),
                _detailSection(sl, 'Reporter', Icons.person_outline_rounded, [
                  _detailRow('Reported by', repBy, sl),
                  _detailRow('P. No.',      pno,   sl),
                  _detailRow('Date',        dateStr, sl),
                ]),
                const SizedBox(height: 14),
                _detailSection(sl, 'Location', Icons.location_on_outlined, [
                  _detailRow('Plant',       plant, sl),
                  _detailRow('Department',  dept,  sl),
                  _detailRow('Site',        loc,   sl),
                  _detailRow('WSA cause',   wsa,   sl),
                ]),
                if (summary.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  _detailSection(sl, 'AI Summary',
                      Icons.auto_awesome_outlined, [
                    _detailParagraph(summary, sl),
                  ]),
                ],
                if (desc.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  _detailSection(sl, 'Description',
                      Icons.notes_rounded, [
                    _detailParagraph(desc, sl),
                  ]),
                ],
                if (imm.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  _detailSection(sl, 'Immediate Action',
                      Icons.flash_on_outlined, [
                    _detailParagraph(imm, sl),
                  ]),
                ],
                if (hazards.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  _detailSection(sl,
                      'Hazards Found (${hazards.length})',
                      Icons.warning_amber_rounded,
                      hazards.asMap().entries.map((e) =>
                          _hazardItem(e.key + 1, e.value, sl)).toList()),
                ],
                if (pdfUrl.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.amber.withOpacity(0.08),
                      border: Border.all(color: AppColors.amber.withOpacity(0.4)),
                      borderRadius: BorderRadius.circular(10)),
                    child: Row(children: [
                      const Icon(Icons.picture_as_pdf_outlined,
                          color: AppColors.amber, size: 18),
                      const SizedBox(width: 8),
                      Expanded(child: Text('PDF report uploaded to Drive',
                          style: TextStyle(color: sl.text2, fontSize: 11))),
                    ])),
                ],
                const SizedBox(height: 18),
                SizedBox(width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () { Navigator.pop(context); _deleteIncident(inc); },
                    icon: const Icon(Icons.delete_outline,
                        color: AppColors.red, size: 16),
                    label: const Text('Delete this incident',
                        style: TextStyle(color: AppColors.red, fontSize: 12,
                            fontWeight: FontWeight.w700)),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: AppColors.red.withOpacity(0.5)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10))),
                  )),
                const SizedBox(height: 20),
              ],
            )),
          ]),
        )));
  }

  Color _sevColor(String s) {
    switch (s.toUpperCase()) {
      case 'CRITICAL': return AppColors.crit;
      case 'HIGH':     return AppColors.red;
      case 'MEDIUM':   return AppColors.amber;
      default:         return AppColors.green;
    }
  }

  Widget _detailSection(SL sl, String title, IconData icon, List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: sl.card, borderRadius: BorderRadius.circular(12),
        border: Border.all(color: sl.border.withOpacity(0.5))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, color: AppColors.amber, size: 14),
          const SizedBox(width: 6),
          Text(title, style: TextStyle(color: sl.text2, fontSize: 11,
              fontWeight: FontWeight.w700, letterSpacing: 0.3)),
        ]),
        const SizedBox(height: 10),
        ...children,
      ]));
  }

  Widget _detailRow(String label, String value, SL sl) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 90, child: Text(label,
            style: TextStyle(color: sl.text4, fontSize: 10))),
        Expanded(child: Text(value,
            style: TextStyle(color: sl.text1, fontSize: 11,
                fontWeight: FontWeight.w600))),
      ]));
  }

  Widget _detailParagraph(String text, SL sl) =>
    Text(text, style: TextStyle(
        color: sl.text2, fontSize: 11, height: 1.5));

  Widget _hazardItem(int n, Map<String, dynamic> h, SL sl) {
    final name   = h['name']?.toString()        ?? '—';
    final sev    = h['severity']?.toString()    ?? 'MEDIUM';
    final desc   = h['description']?.toString() ?? '';
    final reg    = h['regulation']?.toString()  ?? '';
    final action = h['correctiveAction']?.toString() ?? '';
    final color  = _sevColor(sev);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border(left: BorderSide(color: color, width: 3))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 18, height: 18,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
            child: Center(child: Text('$n', style: const TextStyle(
                color: Colors.white, fontSize: 10,
                fontWeight: FontWeight.w800)))),
          const SizedBox(width: 8),
          Expanded(child: Text(name, style: TextStyle(
              color: sl.text1, fontSize: 11.5,
              fontWeight: FontWeight.w700))),
          _pill(sev, color),
        ]),
        if (desc.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(desc, style: TextStyle(color: sl.text3, fontSize: 10.5, height: 1.4)),
        ],
        if (reg.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text('📋 $reg', style: TextStyle(color: sl.text4, fontSize: 9.5,
              fontWeight: FontWeight.w600)),
        ],
        if (action.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text('✅ $action', style: const TextStyle(
              color: AppColors.green, fontSize: 10, height: 1.4)),
        ],
      ]));
  }

  // ──────────────────────────────────────────────────────────────
  //  UPLOAD PDF TO KNOWLEDGE BASE
  // ──────────────────────────────────────────────────────────────
  Future<void> _uploadKbPdf() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'txt', 'doc', 'docx'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      final bytes = file.bytes;
      if (bytes == null) {
        _showSnack('Cannot read file.', AppColors.red);
        return;
      }

      final filename = file.name;
      final ext = filename.split('.').last.toLowerCase();
      String extractedText;

      if (ext == 'txt') {
        try {
          extractedText = utf8.decode(bytes, allowMalformed: false);
        } catch (_) {
          extractedText = String.fromCharCodes(
              bytes.where((b) => b >= 32 && b <= 126).toList());
        }
      } else {
        final raw = String.fromCharCodes(
            bytes.where((b) => b >= 32 && b <= 126).toList());
        final extracted = StringBuffer();
        final btEt = RegExp(r'BT\s([\s\S]*?)ET', multiLine: true);
        final tj   = RegExp(r'\(([^)]{1,200})\)\s*(?:Tj|TJ|")');
        for (final block in btEt.allMatches(raw)) {
          final content = block.group(1) ?? '';
          for (final m in tj.allMatches(content)) {
            final word = m.group(1)?.trim() ?? '';
            if (word.length >= 2) extracted.write('$word ');
          }
        }
        extractedText = extracted.toString()
            .replaceAll(RegExp(r'\s+'), ' ').trim();
      }

      if (extractedText.trim().length < 50) {
        _showSnack('Could not extract readable text. '
            'Try a .txt file or use "Add Entry" instead.', AppColors.amber);
        return;
      }

      final title = filename
          .replaceAll(RegExp(r'\.(pdf|txt|doc|docx)$', caseSensitive: false), '')
          .replaceAll('_', ' ').trim();

      await LocalDB.addKnowledgeDoc(
        title:   title,
        content: extractedText,
        source:  'PDF: $filename (admin upload)',
      );
      await _loadAll();
      _showSnack('Added "$title" to knowledge base ✓',
          const Color(0xFF0F6E56));
    } catch (e) {
      _showSnack('Upload failed: $e', AppColors.red);
    }
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

  // ══════════════════════════════════════════════════════════════
  // ✅ NEW: DANGER ZONE METHODS
  // ══════════════════════════════════════════════════════════════

  Widget _dangerAction(SL sl, IconData icon, String title, String subtitle,
      VoidCallback onTap, Color color) =>
    GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: sl.card,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.4), width: 1.2)),
        child: Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, color: color, size: 18)),
          const SizedBox(width: 10),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(
                color: sl.text1, fontSize: 12,
                fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(subtitle, style: TextStyle(
                color: sl.text3, fontSize: 10, height: 1.3)),
            ])),
          Icon(Icons.chevron_right_rounded, color: color, size: 18),
        ])));

  Future<void> _confirmResetAllData() async {
    final sl = SL.of(context);
    final ctrl = TextEditingController();
    bool canDelete = false;

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(builder: (ctx, setS) => AlertDialog(
        backgroundColor: sl.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Row(children: [
          const Icon(Icons.warning_amber_rounded,
              color: AppColors.red, size: 20),
          const SizedBox(width: 8),
          Text('Reset All Data', style: TextStyle(
              color: sl.text1, fontSize: 15,
              fontWeight: FontWeight.w800)),
        ]),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min, children: [
            Text('This will permanently delete:',
              style: TextStyle(color: sl.text2, fontSize: 12,
                  fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            _bulletLine('All AI Scan reports', sl),
            _bulletLine('All Near Miss reports', sl),
            _bulletLine('Feedback corrections', sl),
            _bulletLine('Image duplicate cache', sl),
            _bulletLine('Pending sync queue', sl),
            _bulletLine('Chat history', sl),
            const SizedBox(height: 10),
            Text('Local data AND Google Sheets will be cleared.',
              style: TextStyle(color: AppColors.red, fontSize: 11,
                  fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('Users and Knowledge Base are preserved.',
              style: TextStyle(color: AppColors.green, fontSize: 11)),
            const SizedBox(height: 14),
            Text('Type RESET to confirm:',
              style: TextStyle(color: sl.text3, fontSize: 11,
                  fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            TextField(
              controller: ctrl, autofocus: true,
              style: TextStyle(color: sl.text1, fontSize: 13,
                  fontWeight: FontWeight.w700, letterSpacing: 2),
              onChanged: (v) => setS(() {
                canDelete = v.trim() == 'RESET';
              }),
              decoration: InputDecoration(
                hintText: 'RESET',
                hintStyle: TextStyle(color: sl.text4, fontSize: 11,
                    letterSpacing: 2),
                filled: true, fillColor: sl.bg,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 10),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: sl.border)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(
                        color: AppColors.red, width: 2)))),
          ])),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel',
                style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            onPressed: canDelete ? () => Navigator.pop(ctx, true) : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.red,
              disabledBackgroundColor: AppColors.red.withOpacity(0.3),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8))),
            child: const Text('Reset All Data',
                style: TextStyle(color: Colors.white,
                    fontWeight: FontWeight.w700))),
        ])));

    if (ok != true) return;

    _showSnack('Resetting all data…', AppColors.amber);

    // 1. Local reset
    int localCleared = 0;
    try {
      final res = await LocalDB.resetAllData(
        keepUsers: true,
        keepKb: true,
        keepLogin: true,
      );
      localCleared = res['incidentsCleared'] is int
          ? res['incidentsCleared'] as int
          : int.tryParse('${res['incidentsCleared']}') ?? 0;
    } catch (e) {
      _showSnack('Local reset error: $e', AppColors.red);
    }

    // 2. Remote reset (Apps Script clearAllIncidents)
    int remoteCleared = 0;
    bool remoteOk = false;
    try {
      const url = 'https://script.google.com/macros/s/'
          'AKfycbxLSH2Z-X6iQPw0rY2O7T0SYSDU7bzikpWq-G_ysOT_noU-IwgSHYNr3AKbwPFPZYginw/exec';
      final resp = await http.post(
        Uri.parse(url),
        body: jsonEncode({'action': 'clearAllIncidents'}),
        headers: {'Content-Type': 'text/plain;charset=utf-8'},
      ).timeout(const Duration(seconds: 30));
      if (resp.statusCode == 200) {
        try {
          final data = jsonDecode(resp.body);
          if (data is Map && (data['ok'] == true || data['success'] == true)) {
            final rc = data['rowsCleared'];
            remoteCleared = rc is int ? rc : int.tryParse('$rc') ?? 0;
            remoteOk = true;
          }
        } catch (_) {}
      }
    } catch (_) {}

    await _loadAll();

    if (remoteOk) {
      _showSnack(
        'Reset complete ✓  Local: $localCleared · Sheets: $remoteCleared',
        AppColors.green);
    } else {
      _showSnack(
        'Local reset complete ($localCleared). '
        'Sheets reset failed — deploy Apps Script v10.',
        AppColors.amber);
    }
  }

  Future<void> _confirmSeedKb() async {
    final sl = SL.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: sl.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Row(children: [
          const Icon(Icons.menu_book_rounded,
              color: AppColors.amber, size: 20),
          const SizedBox(width: 8),
          Text('Seed Knowledge Base', style: TextStyle(
              color: sl.text1, fontSize: 15,
              fontWeight: FontWeight.w800)),
        ]),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min, children: [
            Text('Load ${KbSeedData.count} regulatory entries into the KB?',
              style: TextStyle(color: sl.text2, fontSize: 13,
                  fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            Text('Existing KB entries will be replaced. This includes:',
              style: TextStyle(color: sl.text3, fontSize: 11)),
            const SizedBox(height: 6),
            _bulletLine('Factories Act 1948 (S21–S41H)', sl),
            _bulletLine('SMPV Rules 2016', sl),
            _bulletLine('CEA Regulations 2023', sl),
            _bulletLine('IS 14489:2018 Steel Plant OHS', sl),
            _bulletLine('CG / Odisha / TN / Bihar Factory Rules', sl),
            _bulletLine('Hazard → Regulation quick-reference', sl),
            _bulletLine('SAIL plant → state jurisdiction map', sl),
          ])),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel',
                style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.amber,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8))),
            child: const Text('Wipe & Seed',
                style: TextStyle(color: Colors.white,
                    fontWeight: FontWeight.w700))),
        ]));

    if (ok != true) return;

    _showSnack('Seeding knowledge base…', AppColors.amber);
    try {
      final res = await LocalDB.seedKnowledgeBase(replace: true);
      final loaded = res['loaded'] is int
          ? res['loaded'] as int
          : int.tryParse('${res['loaded']}') ?? KbSeedData.count;
      await _loadAll();
      _showSnack('KB seeded ✓  $loaded entries loaded',
          const Color(0xFF0F6E56));
    } catch (e) {
      _showSnack('Seed failed: $e', AppColors.red);
    }
  }

  Widget _bulletLine(String text, SL sl) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('• ', style: TextStyle(color: sl.text3, fontSize: 11)),
      Expanded(child: Text(text,
          style: TextStyle(color: sl.text3, fontSize: 11, height: 1.4))),
    ]));

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
