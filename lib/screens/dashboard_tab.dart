// lib/screens/dashboard_tab.dart
//
// Changes from original:
// 1. Top section: user's own AI scan + near miss counts highlighted
// 2. Bottom section: plant-wise summary for ALL plants (user's plant highlighted)
// 3. Plant list hardcoded to SAIL plants
// 4. Section headers with icons as requested

import 'package:flutter/material.dart';
import '../main.dart';
import '../services/local_db.dart';
import 'admin_screen.dart';

class DashboardTab extends StatefulWidget {
  final Map<String, dynamic>? user;
  final VoidCallback toggleTheme;
  final VoidCallback onSignOut;
  final void Function(int) onTabChange;

  const DashboardTab({
    super.key,
    required this.user,
    required this.toggleTheme,
    required this.onSignOut,
    required this.onTabChange,
  });
  @override
  State<DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<DashboardTab> {
  List<Map<String, dynamic>> _incidents = [];
  bool _loading = true;

  static const List<String> _allPlants = [
    'BSL - Bokaro Steel Plant',
    'RSP - Rourkela Steel Plant',
    'DSP - Durgapur Steel Plant',
    'BSP - Bhilai Steel Plant',
    'ISP - IISCO Steel Plant, Burnpur',
    'VISL - Visvesvaraya Iron & Steel Plant',
    'SSP - Salem Steel Plant',
    'ASP - Alloy Steels Plant, Durgapur',
    'CFP - Chandrapur Ferro Alloy Plant',
    'SAIL Corporate Office, New Delhi',
    'R&D Centre for Iron & Steel (RDCIS)',
    'Centre for Engineering & Technology (CET)',
    'Management Training Institute (MTI)',
    'SAIL Safety Organisation (SSO)',
    'Others',
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final inc = await LocalDB.getIncidents();
    if (mounted) setState(() { _incidents = inc; _loading = false; });
  }

  // ── User-specific stats ────────────────────────────────────────────
  List<Map<String, dynamic>> get _myIncidents {
    final me = widget.user?['username']?.toString() ?? '';
    if (me.isEmpty) return _incidents;
    return _incidents.where((i) =>
        i['reportedBy']?.toString() == me).toList();
  }

  // ── Plant-wise aggregation ─────────────────────────────────────────
  Map<String, Map<String, int>> get _plantStats {
    final result = <String, Map<String, int>>{};
    for (final p in _allPlants) {
      result[p] = {'total': 0, 'open': 0, 'critical': 0, 'aiScans': 0};
    }
    for (final inc in _incidents) {
      final rawPlant = inc['plant']?.toString() ?? 'Others';
      // Match to known plant or bucket to Others
      final plant = _allPlants.contains(rawPlant) ? rawPlant : 'Others';
      result[plant]!['total'] = (result[plant]!['total'] ?? 0) + 1;
      if (inc['status'] == 'OPEN') {
        result[plant]!['open'] = (result[plant]!['open'] ?? 0) + 1;
      }
      if (inc['severity'] == 'CRITICAL') {
        result[plant]!['critical'] = (result[plant]!['critical'] ?? 0) + 1;
      }
      if (inc['type'] == 'AI_SCAN') {
        result[plant]!['aiScans'] = (result[plant]!['aiScans'] ?? 0) + 1;
      }
    }
    // Only return plants with at least 1 report, plus user's own plant
    final myPlant = widget.user?['plant']?.toString() ?? '';
    return Map.fromEntries(result.entries.where((e) =>
        (e.value['total'] ?? 0) > 0 || e.key == myPlant));
  }

  @override
  Widget build(BuildContext context) {
    final sl = SL.of(context);
    final user = widget.user;
    final name = user?['name']?.toString() ?? 'Safety Officer';
    final desig = user?['designation']?.toString() ?? '';
    final plant = user?['plant']?.toString() ?? '';
    final myInc = _myIncidents;
    final myAiScans  = myInc.where((i) => i['type'] == 'AI_SCAN').length;
    final myNearMiss = myInc.where((i) => i['type'] == 'NEAR_MISS').length;
    final myOpen     = myInc.where((i) => i['status'] == 'OPEN').length;
    final myCritical = myInc.where((i) => i['severity'] == 'CRITICAL').length;
    final isAdmin = desig.toLowerCase().contains('agm') ||
        desig.toLowerCase().contains('gm') ||
        desig.toLowerCase().contains('manager') ||
        desig.toLowerCase().contains('admin');

    return Scaffold(
      backgroundColor: sl.bg,
      body: SafeArea(
        child: _loading
          ? Center(child: CircularProgressIndicator(
              color: AppColors.accent))
          : RefreshIndicator(
              onRefresh: _load,
              color: AppColors.accent,
              child: CustomScrollView(
                slivers: [
                  // ── App bar ────────────────────────────────────────
                  SliverAppBar(
                    backgroundColor: sl.bg2,
                    floating: true,
                    snap: true,
                    elevation: 0,
                    title: Row(children: [
                      Container(
                        width: 34, height: 34,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          color: AppColors.accent.withOpacity(0.15),
                          border: Border.all(
                            color: AppColors.accent.withOpacity(0.3))),
                        child: Padding(
                          padding: const EdgeInsets.all(5),
                          child: Image.asset(
                            'assets/images/sail_logo.png',
                            fit: BoxFit.contain))),
                      const SizedBox(width: 10),
                      Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('SAIL Safety Lens',
                            style: TextStyle(
                              color: sl.text1,
                              fontSize: 14,
                              fontWeight: FontWeight.w700)),
                          Text('AI Safety Platform',
                            style: TextStyle(
                              color: sl.text4, fontSize: 9)),
                        ])),
                    ]),
                    actions: [
                      if (isAdmin)
                        IconButton(
                          tooltip: 'Admin Panel',
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const AdminScreen())),
                          icon: Icon(
                            Icons.admin_panel_settings_outlined,
                            color: AppColors.amber, size: 22)),
                      IconButton(
                        tooltip: 'Toggle theme',
                        onPressed: widget.toggleTheme,
                        icon: Icon(
                          sl.isDark
                            ? Icons.light_mode_outlined
                            : Icons.dark_mode_outlined,
                          color: sl.text3, size: 20)),
                      IconButton(
                        tooltip: 'Sign out',
                        onPressed: widget.onSignOut,
                        icon: Icon(Icons.logout_rounded,
                          color: sl.text3, size: 20)),
                    ],
                  ),

                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
                    sliver: SliverList(delegate: SliverChildListDelegate([

                      // ── Greeting card ────────────────────────────
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              AppColors.accent.withOpacity(0.25),
                              AppColors.cyan.withOpacity(0.1)]),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: AppColors.accent.withOpacity(0.3))),
                        child: Row(children: [
                          Container(
                            width: 46, height: 46,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [AppColors.accent, AppColors.cyan]),
                              shape: BoxShape.circle),
                            child: Center(child: Text(
                              name.isNotEmpty
                                ? name[0].toUpperCase() : '?',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w800)))),
                          const SizedBox(width: 12),
                          Expanded(child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('नमस्ते, $name',
                                style: TextStyle(
                                  color: sl.text1,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700)),
                              if (desig.isNotEmpty)
                                Text(desig,
                                  style: TextStyle(
                                    color: sl.text3, fontSize: 11)),
                              if (plant.isNotEmpty)
                                Container(
                                  margin: const EdgeInsets.only(top: 4),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppColors.accent.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: AppColors.accent.withOpacity(0.3))),
                                  child: Text(plant,
                                    style: const TextStyle(
                                      color: AppColors.accent,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600))),
                            ])),
                        ])),

                      const SizedBox(height: 20),

                      // ── Section: My Activity ─────────────────────
                      _sectionHeader(
                        '👤 My Activity',
                        'Your AI scans and near miss reports', sl),
                      const SizedBox(height: 10),

                      Row(children: [
                        Expanded(child: _myStatCard(
                          '🔍 AI Scans',
                          myAiScans.toString(),
                          AppColors.accent, sl,
                          onTap: () => widget.onTabChange(1))),
                        const SizedBox(width: 10),
                        Expanded(child: _myStatCard(
                          '⚠️ Near Miss',
                          myNearMiss.toString(),
                          AppColors.amber, sl,
                          onTap: () => widget.onTabChange(2))),
                      ]),
                      const SizedBox(height: 10),
                      Row(children: [
                        Expanded(child: _myStatCard(
                          '🔴 Open',
                          myOpen.toString(),
                          AppColors.red, sl,
                          onTap: () => widget.onTabChange(4))),
                        const SizedBox(width: 10),
                        Expanded(child: _myStatCard(
                          '🚨 Critical',
                          myCritical.toString(),
                          AppColors.crit, sl,
                          onTap: () => widget.onTabChange(4))),
                      ]),

                      const SizedBox(height: 24),

                      // ── Section: Quick Actions ───────────────────
                      _sectionHeader(
                        '⚡ Quick Actions', '', sl),
                      const SizedBox(height: 10),

                      Row(children: [
                        Expanded(child: _actionBtn(
                          icon: Icons.document_scanner_rounded,
                          label: 'AI Hazard\nScan',
                          color: AppColors.accent,
                          sl: sl,
                          onTap: () => widget.onTabChange(1))),
                        const SizedBox(width: 10),
                        Expanded(child: _actionBtn(
                          icon: Icons.warning_amber_rounded,
                          label: 'Report\nNear Miss',
                          color: AppColors.amber,
                          sl: sl,
                          onTap: () => widget.onTabChange(2))),
                        const SizedBox(width: 10),
                        Expanded(child: _actionBtn(
                          icon: Icons.chat_bubble_rounded,
                          label: 'Ask\nSuraksha AI',
                          color: AppColors.cyan,
                          sl: sl,
                          onTap: () => widget.onTabChange(3))),
                        const SizedBox(width: 10),
                        Expanded(child: _actionBtn(
                          icon: Icons.bar_chart_rounded,
                          label: 'View\nReports',
                          color: AppColors.purple,
                          sl: sl,
                          onTap: () => widget.onTabChange(4))),
                      ]),

                      const SizedBox(height: 24),

                      // ── Section: Plant-wise Summary ──────────────
                      _sectionHeader(
                        '🏭 Plant-wise Safety Status',
                        'All SAIL plants · Your plant is highlighted', sl),
                      const SizedBox(height: 10),

                      if (_plantStats.isEmpty)
                        _emptyCard(
                          '📊 No data yet',
                          'Submit reports to see plant-wise statistics',
                          sl)
                      else
                        ..._plantStats.entries.map((entry) =>
                            _plantCard(entry.key, entry.value,
                              isMyPlant: entry.key == plant, sl: sl)),

                    ])),
                  ),
                ],
              ),
            ),
      ),
    );
  }

  // ── Widgets ──────────────────────────────────────────────────────────

  Widget _sectionHeader(String title, String sub, SL sl) =>
    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(width: 3, height: 16, color: AppColors.accent),
        const SizedBox(width: 8),
        Text(title, style: TextStyle(
          color: sl.text1,
          fontSize: 14,
          fontWeight: FontWeight.w700)),
      ]),
      if (sub.isNotEmpty) ...[
        const SizedBox(height: 3),
        Padding(
          padding: const EdgeInsets.only(left: 11),
          child: Text(sub, style: TextStyle(
            color: sl.text4, fontSize: 10))),
      ],
    ]);

  Widget _myStatCard(String label, String value, Color color, SL sl,
      {VoidCallback? onTap}) =>
    GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: sl.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3))),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
              style: TextStyle(color: sl.text3, fontSize: 11)),
            const SizedBox(height: 6),
            Text(value,
              style: TextStyle(
                color: color,
                fontSize: 28,
                fontWeight: FontWeight.w800)),
          ])));

  Widget _actionBtn({
    required IconData icon, required String label,
    required Color color, required SL sl,
    required VoidCallback onTap}) =>
    GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3))),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 6),
            Text(label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.w600,
                height: 1.3)),
          ])));

  Widget _plantCard(String plantName, Map<String, int> stats,
      {required bool isMyPlant, required SL sl}) {
    final total    = stats['total'] ?? 0;
    final open     = stats['open'] ?? 0;
    final critical = stats['critical'] ?? 0;
    final aiScans  = stats['aiScans'] ?? 0;

    // Safety score: 100 - (critical*20 + open*5)
    final score = (100 - (critical * 20) - (open * 5)).clamp(0, 100);
    final scoreColor = score >= 80
      ? AppColors.green
      : score >= 60
        ? AppColors.amber
        : AppColors.crit;

    // Short plant name for display
    final shortName = plantName.contains(' - ')
      ? plantName.split(' - ').first
      : plantName.split(' ').first;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isMyPlant
          ? AppColors.accent.withOpacity(0.08)
          : sl.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isMyPlant
            ? AppColors.accent.withOpacity(0.4)
            : sl.border,
          width: isMyPlant ? 1.5 : 1.0)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            // Plant icon
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: (isMyPlant ? AppColors.accent : sl.card3),
                borderRadius: BorderRadius.circular(8)),
              child: Center(child: Text(shortName,
                style: TextStyle(
                  color: isMyPlant ? Colors.white : sl.text2,
                  fontSize: 10,
                  fontWeight: FontWeight.w800)))),
            const SizedBox(width: 10),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(
                    child: Text(plantName,
                      style: TextStyle(
                        color: sl.text1,
                        fontSize: 12,
                        fontWeight: FontWeight.w700),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis)),
                  if (isMyPlant)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.accent,
                        borderRadius: BorderRadius.circular(4)),
                      child: const Text('MY PLANT',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 8,
                          fontWeight: FontWeight.w700))),
                ]),
                const SizedBox(height: 2),
                Text('$total reports total',
                  style: TextStyle(color: sl.text4, fontSize: 10)),
              ])),
            // Safety score circle
            Container(
              width: 46, height: 46,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: scoreColor, width: 2.5),
                color: scoreColor.withOpacity(0.1)),
              child: Center(child: Text('$score',
                style: TextStyle(
                  color: scoreColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w800)))),
          ]),
          if (total > 0) ...[
            const SizedBox(height: 10),
            Row(children: [
              _mini('AI Scans',   '$aiScans',  AppColors.accent, sl),
              _mini('Open',       '$open',     AppColors.amber,  sl),
              _mini('Critical',   '$critical', AppColors.crit,   sl),
            ]),
          ],
        ]));
  }

  Widget _mini(String label, String val, Color color, SL sl) =>
    Expanded(child: Column(children: [
      Text(val, style: TextStyle(
        color: color, fontSize: 16, fontWeight: FontWeight.w800)),
      Text(label, style: TextStyle(
        color: sl.text4, fontSize: 9)),
    ]));

  Widget _emptyCard(String title, String sub, SL sl) =>
    Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: sl.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: sl.border)),
      child: Column(children: [
        Text(title, style: TextStyle(
          color: sl.text2, fontSize: 14, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Text(sub, style: TextStyle(
          color: sl.text4, fontSize: 11), textAlign: TextAlign.center),
      ]));
}
