// lib/screens/home_tab.dart
// Glass-morphism Home screen with infographics, charts, quick actions, and
// safety statistics. Uses I18n for full Hindi/English support.

import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import '../main.dart' show AppColors, SL;
import '../services/local_db.dart';
import '../services/i18n.dart';
import '../widgets/universal_app_bar.dart';

class HomeTab extends StatefulWidget {
  final Map<String, dynamic>? user;
  final VoidCallback toggleTheme;
  final VoidCallback onSignOut;
  final bool isDark;
  final void Function(int tabIndex) onTabChange;

  const HomeTab({
    super.key,
    required this.user,
    required this.toggleTheme,
    required this.onSignOut,
    required this.isDark,
    required this.onTabChange,
  });

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  List<Map<String, dynamic>> _incidents = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    I18n.instance.addListener(_rebuild);
    _load();
  }

  @override
  void dispose() {
    I18n.instance.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() { if (mounted) setState(() {}); }

  Future<void> _load() async {
    final inc = await LocalDB.getIncidents();
    if (!mounted) return;
    setState(() { _incidents = inc; _loading = false; });
  }

  // ── COMPUTED STATS ─────────────────────────────────────────────
  int get _total    => _incidents.length;
  int get _open     => _incidents.where((i) {
    final s = i['status']?.toString().toUpperCase() ?? 'OPEN';
    return s == 'OPEN' || s == 'INVESTIGATING' || s == 'ACTION TAKEN';
  }).length;
  int get _closed   => _incidents.where((i) =>
      i['status']?.toString().toUpperCase() == 'CLOSED').length;
  int get _critical => _incidents.where((i) =>
      i['severity']?.toString().toUpperCase() == 'CRITICAL').length;

  int get _thisWeek {
    final cutoff = DateTime.now().subtract(const Duration(days: 7));
    return _incidents.where((i) {
      final d = DateTime.tryParse(i['date']?.toString() ?? '');
      return d != null && d.isAfter(cutoff);
    }).length;
  }

  /// Days since the most recent critical case (LTI proxy)
  int get _daysSinceLTI {
    final crits = _incidents.where((i) =>
        i['severity']?.toString().toUpperCase() == 'CRITICAL').toList();
    if (crits.isEmpty) return 365;
    crits.sort((a, b) =>
        (b['date']?.toString() ?? '').compareTo(a['date']?.toString() ?? ''));
    final last = DateTime.tryParse(crits.first['date']?.toString() ?? '');
    if (last == null) return 365;
    return DateTime.now().difference(last).inDays;
  }

  /// 0-100 safety score (higher = better)
  int get _safetyScore {
    if (_total == 0) return 100;
    final critPenalty = (_critical / _total) * 60;
    final openPenalty = (_open / _total) * 25;
    return (100 - critPenalty - openPenalty).clamp(0, 100).round();
  }

  /// Hazard counts per plant (top 5)
  List<MapEntry<String, int>> get _byPlant {
    final m = <String, int>{};
    for (final i in _incidents) {
      final p = i['plant']?.toString() ?? '—';
      if (p.isEmpty) continue;
      m[p] = (m[p] ?? 0) + 1;
    }
    final list = m.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return list.take(5).toList();
  }

  /// Last 7 days incident counts
  List<int> get _weeklyTrend {
    final result = List<int>.filled(7, 0);
    final now = DateTime.now();
    for (final i in _incidents) {
      final d = DateTime.tryParse(i['date']?.toString() ?? '');
      if (d == null) continue;
      final diff = now.difference(d).inDays;
      if (diff >= 0 && diff < 7) result[6 - diff]++;
    }
    return result;
  }

  String get _greetingKey {
    final h = DateTime.now().hour;
    if (h < 12) return 'home.greeting.morning';
    if (h < 18) return 'home.greeting.afternoon';
    return 'home.greeting.evening';
  }

  // ── BUILD ─────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final sl = SL.of(context);
    final firstName = (widget.user?['name']?.toString() ?? 'User').split(' ').first;

    return Scaffold(
      backgroundColor: sl.bg,
      appBar: UniversalAppBar(
        title: I18n.t('app.name'),
        subtitle: I18n.t('app.tagline'),
        user: widget.user,
        toggleTheme: widget.toggleTheme,
        onSignOut: widget.onSignOut,
        isDark: widget.isDark,
      ),
      body: _loading
        ? Center(child: CircularProgressIndicator(color: AppColors.accent))
        : RefreshIndicator(
            onRefresh: _load,
            color: AppColors.accent,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              child: Column(children: [
                _heroSection(sl, firstName),
                const SizedBox(height: 16),
                _statsGrid(sl),
                const SizedBox(height: 18),
                _safetyScoreCard(sl),
                const SizedBox(height: 18),
                _quickActionsGrid(sl),
                const SizedBox(height: 18),
                _weeklyTrendCard(sl),
                const SizedBox(height: 18),
                _topPlantsCard(sl),
                const SizedBox(height: 18),
                _recentActivity(sl),
                const SizedBox(height: 24),
              ]),
            )),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  HERO — gradient + greeting + days since LTI
  // ═══════════════════════════════════════════════════════════════
  Widget _heroSection(SL sl, String firstName) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 26),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [
            Color(0xFF7B5BFF),  // purple
            Color(0xFF5B7BFF),  // blue
            Color(0xFF34D399),  // green-teal
          ],
          stops: [0.0, 0.55, 1.0],
        )),
      child: Stack(children: [
        // Decorative blurred circles
        Positioned(top: -30, right: -20,
          child: _glow(80, Colors.white.withOpacity(0.18))),
        Positioned(bottom: -40, left: -30,
          child: _glow(120, Colors.white.withOpacity(0.12))),

        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Greeting
          Row(children: [
            const Icon(Icons.waving_hand_rounded,
                color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Text(I18n.t(_greetingKey),
                style: const TextStyle(color: Colors.white70, fontSize: 13,
                    fontWeight: FontWeight.w500)),
          ]),
          const SizedBox(height: 4),
          Text(firstName,
              style: const TextStyle(color: Colors.white, fontSize: 26,
                  fontWeight: FontWeight.w800, height: 1.1)),
          const SizedBox(height: 18),

          // Glass card — days since LTI
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                      color: Colors.white.withOpacity(0.25), width: 1)),
                child: Row(children: [
                  // Big number
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('$_daysSinceLTI',
                      style: const TextStyle(color: Colors.white, fontSize: 36,
                          fontWeight: FontWeight.w800, height: 1)),
                    const SizedBox(height: 2),
                    Text(I18n.t('home.daysSinceLti'),
                      style: const TextStyle(color: Colors.white70,
                          fontSize: 10, fontWeight: FontWeight.w600,
                          letterSpacing: 0.5)),
                  ]),
                  const Spacer(),
                  // Icon
                  Container(
                    width: 50, height: 50,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(14)),
                    child: const Icon(Icons.shield_rounded,
                        color: Colors.white, size: 28)),
                ]),
              ))),
        ]),
      ]),
    );
  }

  Widget _glow(double size, Color color) => Container(
    width: size, height: size,
    decoration: BoxDecoration(shape: BoxShape.circle, color: color));

  // ═══════════════════════════════════════════════════════════════
  //  STATS GRID — 4 cards
  // ═══════════════════════════════════════════════════════════════
  Widget _statsGrid(SL sl) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Column(children: [
        Row(children: [
          Expanded(child: _statTile(
              sl, I18n.t('home.totalCases'), '$_total',
              Icons.assessment_rounded, const Color(0xFF6366F1))),
          const SizedBox(width: 8),
          Expanded(child: _statTile(
              sl, I18n.t('home.openCases'), '$_open',
              Icons.lock_open_rounded, const Color(0xFFF59E0B))),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: _statTile(
              sl, I18n.t('home.criticalCases'), '$_critical',
              Icons.warning_rounded, const Color(0xFFEF4444))),
          const SizedBox(width: 8),
          Expanded(child: _statTile(
              sl, I18n.t('home.closedCases'), '$_closed',
              Icons.check_circle_rounded, const Color(0xFF10B981))),
        ]),
      ]),
    );
  }

  Widget _statTile(SL sl, String label, String value, IconData icon, Color color) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: sl.card.withOpacity(0.7),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withOpacity(0.25), width: 1)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                width: 32, height: 32,
                decoration: BoxDecoration(
                    color: color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10)),
                child: Icon(icon, color: color, size: 18)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(4)),
                child: Text(I18n.t('home.thisWeek'),
                    style: TextStyle(color: color, fontSize: 7,
                        fontWeight: FontWeight.w700, letterSpacing: 0.3))),
            ]),
            const SizedBox(height: 12),
            Text(value,
                style: TextStyle(color: sl.text1, fontSize: 26,
                    fontWeight: FontWeight.w800, height: 1)),
            const SizedBox(height: 3),
            Text(label,
                style: TextStyle(color: sl.text3, fontSize: 10,
                    fontWeight: FontWeight.w600)),
          ]),
        )),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  SAFETY SCORE GAUGE
  // ═══════════════════════════════════════════════════════════════
  Widget _safetyScoreCard(SL sl) {
    final score = _safetyScore;
    Color scoreColor;
    String label;
    if (score >= 80)      { scoreColor = const Color(0xFF10B981); label = 'Excellent'; }
    else if (score >= 60) { scoreColor = const Color(0xFFF59E0B); label = 'Good'; }
    else if (score >= 40) { scoreColor = const Color(0xFFF97316); label = 'Average'; }
    else                  { scoreColor = const Color(0xFFEF4444); label = 'Needs Attention'; }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: sl.card.withOpacity(0.7),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: sl.border, width: 1)),
            child: Row(children: [
              // Circular gauge
              SizedBox(width: 90, height: 90,
                child: CustomPaint(
                  painter: _GaugePainter(
                    progress: score / 100,
                    color: scoreColor,
                    trackColor: sl.border,
                  ),
                  child: Center(child: Column(
                    mainAxisSize: MainAxisSize.min, children: [
                    Text('$score',
                        style: TextStyle(color: scoreColor, fontSize: 26,
                            fontWeight: FontWeight.w800, height: 1)),
                    Text('/100',
                        style: TextStyle(color: sl.text4, fontSize: 9)),
                  ])),
                )),
              const SizedBox(width: 16),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(I18n.t('home.safetyScore'),
                    style: TextStyle(color: sl.text3, fontSize: 11,
                        fontWeight: FontWeight.w600, letterSpacing: 0.5)),
                const SizedBox(height: 4),
                Text(label,
                    style: TextStyle(color: scoreColor, fontSize: 18,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                _miniProgressRow(sl, 'Open vs Closed',
                    _total == 0 ? 1 : _closed / _total,
                    AppColors.green),
                const SizedBox(height: 5),
                _miniProgressRow(sl, 'Critical Ratio',
                    _total == 0 ? 0 : 1 - (_critical / _total),
                    AppColors.red),
              ])),
            ]),
          ))),
    );
  }

  Widget _miniProgressRow(SL sl, String label, double v, Color color) {
    return Row(children: [
      Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(color: sl.text4, fontSize: 9)),
        const SizedBox(height: 2),
        Container(
          height: 5, width: double.infinity,
          decoration: BoxDecoration(
              color: sl.border, borderRadius: BorderRadius.circular(3)),
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: v.clamp(0, 1),
            child: Container(decoration: BoxDecoration(
                color: color, borderRadius: BorderRadius.circular(3))),
          )),
      ])),
      const SizedBox(width: 6),
      Text('${(v * 100).clamp(0, 100).round()}%',
          style: TextStyle(color: color, fontSize: 10,
              fontWeight: FontWeight.w700)),
    ]);
  }

  // ═══════════════════════════════════════════════════════════════
  //  QUICK ACTIONS — 2x2 grid
  // ═══════════════════════════════════════════════════════════════
  Widget _quickActionsGrid(SL sl) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _sectionTitle(sl, I18n.t('home.quickActions'), Icons.flash_on_rounded),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _actionCard(sl,
              icon: Icons.camera_alt_rounded,
              label: I18n.t('home.startScan'),
              color: const Color(0xFF8B5CF6),
              onTap: () => widget.onTabChange(1))),
          const SizedBox(width: 8),
          Expanded(child: _actionCard(sl,
              icon: Icons.warning_amber_rounded,
              label: I18n.t('home.reportNearMiss'),
              color: const Color(0xFFF59E0B),
              onTap: () => widget.onTabChange(2))),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: _actionCard(sl,
              icon: Icons.assessment_rounded,
              label: I18n.t('home.viewReports'),
              color: const Color(0xFF06B6D4),
              onTap: () => widget.onTabChange(4))),
          const SizedBox(width: 8),
          Expanded(child: _actionCard(sl,
              icon: Icons.support_agent_rounded,
              label: I18n.t('home.askExpert'),
              color: const Color(0xFF10B981),
              onTap: () => widget.onTabChange(3))),
        ]),
      ]),
    );
  }

  Widget _actionCard(SL sl, {required IconData icon, required String label,
      required Color color, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
          child: Container(
            height: 90,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft, end: Alignment.bottomRight,
                colors: [color.withOpacity(0.12), color.withOpacity(0.03)]),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: color.withOpacity(0.3), width: 1)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(10)),
                child: Icon(icon, color: color, size: 20)),
              Text(label,
                style: TextStyle(color: sl.text1, fontSize: 12,
                    fontWeight: FontWeight.w700, height: 1.2)),
            ]),
          ))),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  WEEKLY TREND CHART
  // ═══════════════════════════════════════════════════════════════
  Widget _weeklyTrendCard(SL sl) {
    final data = _weeklyTrend;
    final maxV = data.fold<int>(1, (m, v) => v > m ? v : m);
    final dayLabels = ['M','T','W','T','F','S','S'];
    final todayDow  = (DateTime.now().weekday - 1) % 7;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: sl.card.withOpacity(0.7),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: sl.border, width: 1)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.trending_up_rounded, color: AppColors.accent, size: 16),
                const SizedBox(width: 6),
                Text(I18n.t('home.weeklyTrend'),
                    style: TextStyle(color: sl.text1, fontSize: 13,
                        fontWeight: FontWeight.w700)),
                const Spacer(),
                Text('$_thisWeek ${I18n.t('home.thisWeek').toLowerCase()}',
                    style: TextStyle(color: sl.text4, fontSize: 10)),
              ]),
              const SizedBox(height: 16),
              SizedBox(height: 90, child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: List.generate(7, (i) {
                  final v = data[i];
                  final h = maxV == 0 ? 4.0 : (v / maxV) * 70 + 4;
                  final isToday = i == 6;
                  return Expanded(child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end, children: [
                      Text(v > 0 ? '$v' : '',
                          style: TextStyle(color: sl.text3, fontSize: 9,
                              fontWeight: FontWeight.w700)),
                      const SizedBox(height: 3),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 600),
                        height: h,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter, end: Alignment.bottomCenter,
                            colors: isToday
                              ? [AppColors.accent, AppColors.accent.withOpacity(0.4)]
                              : [AppColors.cyan.withOpacity(0.7),
                                 AppColors.cyan.withOpacity(0.2)]),
                          borderRadius: BorderRadius.circular(4))),
                      const SizedBox(height: 4),
                      Text(dayLabels[(todayDow - (6 - i) + 7) % 7],
                          style: TextStyle(
                              color: isToday ? AppColors.accent : sl.text4,
                              fontSize: 9,
                              fontWeight: isToday ? FontWeight.w800 : FontWeight.w500)),
                    ]),
                  ));
                }))),
            ]),
          ))),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  TOP PLANTS — horizontal bar chart
  // ═══════════════════════════════════════════════════════════════
  Widget _topPlantsCard(SL sl) {
    final list = _byPlant;
    if (list.isEmpty) return const SizedBox.shrink();
    final maxV = list.first.value;
    final colors = [
      AppColors.crit, AppColors.red, AppColors.amber,
      AppColors.cyan, AppColors.green
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: sl.card.withOpacity(0.7),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: sl.border, width: 1)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.factory_outlined, color: AppColors.accent, size: 16),
                const SizedBox(width: 6),
                Text(I18n.t('home.byPlant'),
                    style: TextStyle(color: sl.text1, fontSize: 13,
                        fontWeight: FontWeight.w700)),
              ]),
              const SizedBox(height: 14),
              ...List.generate(list.length, (i) {
                final entry = list[i];
                final pct   = entry.value / maxV;
                final color = colors[i % colors.length];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(children: [
                    SizedBox(width: 100,
                      child: Text(entry.key,
                        style: TextStyle(color: sl.text2, fontSize: 11),
                        overflow: TextOverflow.ellipsis)),
                    const SizedBox(width: 8),
                    Expanded(child: Stack(children: [
                      Container(height: 14,
                        decoration: BoxDecoration(
                          color: sl.border.withOpacity(0.4),
                          borderRadius: BorderRadius.circular(7))),
                      FractionallySizedBox(
                        widthFactor: pct,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 800),
                          height: 14,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                                colors: [color, color.withOpacity(0.6)]),
                            borderRadius: BorderRadius.circular(7))),
                      ),
                    ])),
                    const SizedBox(width: 8),
                    SizedBox(width: 20,
                      child: Text('${entry.value}',
                          textAlign: TextAlign.right,
                          style: TextStyle(color: color, fontSize: 12,
                              fontWeight: FontWeight.w800))),
                  ]),
                );
              }),
            ]),
          ))),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  RECENT ACTIVITY
  // ═══════════════════════════════════════════════════════════════
  Widget _recentActivity(SL sl) {
    final recent = _incidents.toList()
      ..sort((a, b) =>
          (b['date']?.toString() ?? '').compareTo(a['date']?.toString() ?? ''));
    final list = recent.take(3).toList();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          _sectionTitle(sl, I18n.t('home.recentActivity'),
              Icons.history_rounded),
          const Spacer(),
          GestureDetector(
            onTap: () => widget.onTabChange(4),
            child: Row(children: [
              Text(I18n.t('home.viewAll'),
                  style: const TextStyle(color: AppColors.accent,
                      fontSize: 11, fontWeight: FontWeight.w600)),
              const Icon(Icons.chevron_right_rounded,
                  color: AppColors.accent, size: 14),
            ])),
        ]),
        const SizedBox(height: 10),
        if (list.isEmpty)
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 16),
              decoration: BoxDecoration(
                color: sl.card.withOpacity(0.6),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: sl.border)),
              child: Center(child: Column(children: [
                Icon(Icons.inbox_outlined, color: sl.text4, size: 32),
                const SizedBox(height: 8),
                Text(I18n.t('home.noData'),
                    style: TextStyle(color: sl.text3, fontSize: 12)),
              ])),
            ))
        else
          ...list.map((i) => _recentItem(sl, i)),
      ]),
    );
  }

  Widget _recentItem(SL sl, Map<String, dynamic> i) {
    final sev = i['severity']?.toString().toUpperCase() ?? 'MEDIUM';
    final status = i['status']?.toString().toUpperCase() ?? 'OPEN';
    Color sevColor;
    switch (sev) {
      case 'CRITICAL': sevColor = AppColors.crit; break;
      case 'HIGH':     sevColor = AppColors.red;  break;
      case 'MEDIUM':   sevColor = AppColors.amber; break;
      default:         sevColor = AppColors.green;
    }
    final date = (i['date']?.toString() ?? '');
    final dateStr = date.length > 10 ? date.substring(0, 10) : date;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: sl.card.withOpacity(0.6),
              borderRadius: BorderRadius.circular(12),
              border: Border(left: BorderSide(color: sevColor, width: 3),
                top: BorderSide(color: sl.border.withOpacity(0.5)),
                right: BorderSide(color: sl.border.withOpacity(0.5)),
                bottom: BorderSide(color: sl.border.withOpacity(0.5)))),
            child: Row(children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: sevColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10)),
                child: Icon(
                    sev == 'CRITICAL' ? Icons.warning_rounded
                        : sev == 'HIGH' ? Icons.error_outline_rounded
                        : Icons.info_outline_rounded,
                    color: sevColor, size: 18)),
              const SizedBox(width: 10),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(i['title']?.toString() ?? 'Untitled',
                    style: TextStyle(color: sl.text1, fontSize: 12,
                        fontWeight: FontWeight.w700),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text('${i['plant'] ?? '—'} · $dateStr',
                    style: TextStyle(color: sl.text4, fontSize: 10)),
              ])),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: sevColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(4)),
                child: Text(sev,
                    style: TextStyle(color: sevColor, fontSize: 8,
                        fontWeight: FontWeight.w800))),
            ]),
          ))),
    );
  }

  Widget _sectionTitle(SL sl, String title, IconData icon) => Row(children: [
    Container(width: 3, height: 14,
        decoration: BoxDecoration(
          color: AppColors.accent,
          borderRadius: BorderRadius.circular(2))),
    const SizedBox(width: 8),
    Icon(icon, color: AppColors.accent, size: 14),
    const SizedBox(width: 6),
    Text(title, style: TextStyle(color: sl.text1, fontSize: 14,
        fontWeight: FontWeight.w700)),
  ]);
}

// ═══════════════════════════════════════════════════════════════════
//  CIRCULAR GAUGE PAINTER for Safety Score
// ═══════════════════════════════════════════════════════════════════
class _GaugePainter extends CustomPainter {
  final double progress; // 0..1
  final Color color;
  final Color trackColor;
  _GaugePainter({required this.progress, required this.color,
      required this.trackColor});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 6;

    final track = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, track);

    final arc = Paint()
      ..shader = SweepGradient(
        colors: [color.withOpacity(0.4), color],
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * progress,
      false,
      arc,
    );
  }

  @override
  bool shouldRepaint(covariant _GaugePainter old) =>
      old.progress != progress || old.color != color;
}
