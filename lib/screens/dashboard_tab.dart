import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../main.dart';
import '../services/local_db.dart';
import 'settings_screen.dart';
import 'admin_screen.dart';

class DashboardTab extends StatefulWidget {
  final Map<String, dynamic>? user;
  final VoidCallback toggleTheme;
  final VoidCallback onSignOut;
  final ValueChanged<int>? onTabChange; // 0=home 1=scan 2=nearmiss 3=chat 4=reports
  const DashboardTab({super.key, this.user,
    required this.toggleTheme, required this.onSignOut,
    this.onTabChange});
  @override
  State<DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<DashboardTab>
    with SingleTickerProviderStateMixin {
  int _quoteIndex = 0;
  List<Map<String, dynamic>> _incidents = [];
  late AnimationController _glowCtrl;

  final _quotes = const [
    ['Safety isn\'t expensive, it\'s priceless.', 'SAIL Safety Pledge'],
    ['Zero harm starts with one safe action — yours.', 'Ministry of Steel India'],
    ['Your family is waiting at home.', 'IS 14489 Foreword'],
    ['Every hazard reported prevents an accident.', 'SAIL Safety Manual'],
    ['Safety is not a slogan, it\'s a way of life.', 'SAIL Vision'],
    ['Prepare and prevent, don\'t repair and repent.', 'Factories Act'],
  ];

  @override
  void initState() {
    super.initState();
    _glowCtrl = AnimationController(vsync: this,
      duration: const Duration(milliseconds: 2500))..repeat(reverse: true);
    _loadStats();
  }

  @override
  void dispose() { _glowCtrl.dispose(); super.dispose(); }

  Future<void> _loadStats() async {
    final inc = await LocalDB.getIncidents();
    if (mounted) setState(() => _incidents = inc);
  }

  bool get _isAdmin {
    final d = (widget.user?['designation']?.toString() ?? '').toLowerCase();
    return d.contains('agm') || d.contains('gm') ||
           d.contains('manager') || d.contains('admin');
  }

  @override
  Widget build(BuildContext context) {
    final sl = SL.of(context);
    final critical = _incidents.where((i) => i['severity'] == 'CRITICAL').length;
    final high     = _incidents.where((i) => i['severity'] == 'HIGH').length;
    final medium   = _incidents.where((i) => i['severity'] == 'MEDIUM').length;
    final open     = _incidents.where((i) => i['status'] == 'OPEN').length;
    final score    = LocalDB.calcSafetyScore(critical, high, medium, open);

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: sl.bgGradient)),
      child: SafeArea(
        child: Column(children: [
          _topBar(sl),
          Expanded(child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _welcomeSection(sl),
                const SizedBox(height: 20),
                _scoreHero(sl, score, open),
                const SizedBox(height: 16),
                _statsRow(sl, critical, high, medium, open),
                const SizedBox(height: 16),
                _plantSummary(sl),
                const SizedBox(height: 16),
                _quoteCard(sl),
                const SizedBox(height: 16),
                _quickActions(sl),
                const SizedBox(height: 16),
                if (_incidents.isNotEmpty) _recentIncidents(sl),
              ],
            ),
          )),
        ]),
      ),
    );
  }

  // ─── TOP BAR ─────────────────────────────────────────────────────────────
  Widget _topBar(SL sl) {
    final isDark = sl.isDark;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      decoration: BoxDecoration(
        color: sl.bg2,
        border: Border(bottom: BorderSide(
          color: sl.border.withOpacity(0.4), width: 1))),
      child: Row(children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: AppColors.accent.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.accent.withOpacity(0.3))),
          child: Padding(
            padding: const EdgeInsets.all(5),
            child: Image.asset('assets/images/sail_logo.png', fit: BoxFit.contain))),
        const SizedBox(width: 10),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const BrandTitle(size: 15),
            Text('IS 14489 · AI Safety Platform', style: TextStyle(
              color: sl.text4, fontSize: 9, letterSpacing: 1.2,
              fontWeight: FontWeight.w600)),
          ])),
        // Theme toggle switch
        GestureDetector(
          onTap: widget.toggleTheme,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: 52, height: 28,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isDark
                  ? [AppColors.darkCard2, AppColors.darkCard3]
                  : [AppColors.accent.withOpacity(0.2), AppColors.cyan.withOpacity(0.2)]),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isDark ? AppColors.darkBorder : AppColors.accent.withOpacity(0.4))),
            child: Stack(children: [
              // Track icons
              Positioned(left: 3, top: 4,
                child: Icon(Icons.nightlight_round,
                  size: 11,
                  color: isDark ? AppColors.accent : sl.text4)),
              Positioned(right: 3, top: 4,
                child: Icon(Icons.wb_sunny_rounded,
                  size: 11,
                  color: isDark ? sl.text4 : AppColors.amber)),
              // Thumb
              AnimatedAlign(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                alignment: isDark
                  ? Alignment.centerLeft : Alignment.centerRight,
                child: Container(
                  width: 20, height: 20,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: isDark
                        ? [AppColors.accent, AppColors.cyan]
                        : [AppColors.amber, AppColors.pink]),
                    boxShadow: [BoxShadow(
                      color: (isDark ? AppColors.accent : AppColors.amber)
                          .withOpacity(0.5),
                      blurRadius: 6)]))),
            ])),
        ),
        const SizedBox(width: 6),
        if (_isAdmin) IconButton(
          icon: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: AppColors.purple.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.purple.withOpacity(0.4))),
            child: const Icon(Icons.admin_panel_settings_outlined,
              color: AppColors.purple, size: 15)),
          onPressed: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const AdminScreen()))),
        IconButton(
          icon: CircleAvatar(
            radius: 15,
            backgroundColor: AppColors.accent.withOpacity(0.15),
            child: Text(
              (widget.user?['name']?.toString() ?? 'U')[0].toUpperCase(),
              style: const TextStyle(
                color: AppColors.accent, fontSize: 13,
                fontWeight: FontWeight.w800))),
          onPressed: _showProfileSheet),
      ]),
    );
  }

  // ─── WELCOME ──────────────────────────────────────────────────────────────
  Widget _welcomeSection(SL sl) {
    final name = widget.user?['name']?.toString().split(' ').first ?? 'User';
    final desig = widget.user?['designation']?.toString() ?? '';
    final plant = widget.user?['plant']?.toString() ?? '';
    return Row(children: [
      Expanded(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Good day,', style: TextStyle(
            color: sl.text3, fontSize: 13)),
          Text(name, style: GoogleFonts.poppins(
            color: sl.text1, fontSize: 24,
            fontWeight: FontWeight.w800, height: 1.1)),
          const SizedBox(height: 3),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.accent.withOpacity(0.15),
                         AppColors.cyan.withOpacity(0.08)]),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: AppColors.accent.withOpacity(0.3))),
            child: Text('$desig · $plant', style: TextStyle(
              color: AppColors.accent, fontSize: 11,
              fontWeight: FontWeight.w600))),
        ])),
      // Animated glow orb
      AnimatedBuilder(
        animation: _glowCtrl,
        builder: (_, __) => Container(
          width: 60, height: 60,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(colors: [
              AppColors.accent.withOpacity(0.3 * _glowCtrl.value),
              Colors.transparent])),
          child: Center(child: Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [AppColors.accent, AppColors.cyan]),
              boxShadow: [BoxShadow(
                color: AppColors.accent.withOpacity(0.4 * _glowCtrl.value),
                blurRadius: 16)]),
            child: const Icon(Icons.shield_outlined,
              color: Colors.white, size: 20)))),
      ),
    ]);
  }

  // ─── SCORE HERO ───────────────────────────────────────────────────────────
  Widget _scoreHero(SL sl, int score, int open) {
    final color = score >= 80 ? AppColors.green
        : score >= 60 ? AppColors.amber
        : AppColors.red;

    return GlassCard(
      gradient: LinearGradient(
        begin: Alignment.topLeft, end: Alignment.bottomRight,
        colors: sl.isDark
          ? [const Color(0xFF1A1A40), const Color(0xFF22224A)]
          : [const Color(0xFFFAFAFF), const Color(0xFFF0EFFF)]),
      border: Border.all(
        color: AppColors.accent.withOpacity(0.2), width: 1),
      padding: const EdgeInsets.all(18),
      shadows: [BoxShadow(
        color: AppColors.accent.withOpacity(0.1),
        blurRadius: 30, spreadRadius: 0)],
      child: Row(children: [
        // Score circle
        Stack(alignment: Alignment.center, children: [
          SizedBox(width: 88, height: 88,
            child: CircularProgressIndicator(
              value: score / 100,
              strokeWidth: 7,
              backgroundColor: sl.card2,
              valueColor: AlwaysStoppedAnimation<Color>(color))),
          Column(mainAxisSize: MainAxisSize.min, children: [
            Text('$score', style: TextStyle(
              color: color, fontSize: 26,
              fontWeight: FontWeight.w900)),
            Text('/100', style: TextStyle(
              color: sl.text4, fontSize: 9)),
          ]),
        ]),
        const SizedBox(width: 18),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Safety Score', style: TextStyle(
              color: sl.text3, fontSize: 12)),
            Text(score >= 80 ? 'EXCELLENT' : score >= 60 ? 'GOOD' : 'NEEDS ATTENTION',
              style: TextStyle(color: color, fontSize: 18,
                fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            _miniBar(sl, score / 100, color),
            const SizedBox(height: 6),
            Row(children: [
              Icon(Icons.pending_outlined, size: 12, color: sl.text3),
              const SizedBox(width: 4),
              Text('$open open incidents', style: TextStyle(
                color: sl.text3, fontSize: 11)),
            ]),
          ])),
      ]),
    );
  }

  Widget _miniBar(SL sl, double value, Color color) => ClipRRect(
    borderRadius: BorderRadius.circular(4),
    child: LinearProgressIndicator(
      value: value,
      minHeight: 6,
      backgroundColor: sl.card2,
      valueColor: AlwaysStoppedAnimation<Color>(color)));

  // ─── STATS ROW ────────────────────────────────────────────────────────────
  Widget _statsRow(SL sl, int crit, int high, int med, int open) {
    return Row(children: [
      _statPill(sl, '$crit', 'Critical', AppColors.crit),
      const SizedBox(width: 8),
      _statPill(sl, '$high', 'High', AppColors.red),
      const SizedBox(width: 8),
      _statPill(sl, '$med', 'Medium', AppColors.amber),
      const SizedBox(width: 8),
      _statPill(sl, '${_incidents.length}', 'Total', AppColors.accent),
    ]);
  }

  Widget _statPill(SL sl, String value, String label, Color color) =>
    Expanded(child: GlassCard(
      padding: const EdgeInsets.symmetric(vertical: 12),
      border: Border.all(color: color.withOpacity(0.25)),
      child: Column(children: [
        Text(value, style: TextStyle(
          color: color, fontSize: 22, fontWeight: FontWeight.w900)),
        Text(label, style: TextStyle(
          color: sl.text4, fontSize: 9, fontWeight: FontWeight.w600)),
      ])));


  // ─── PLANT SUMMARY ───────────────────────────────────────────────────────────
  Widget _plantSummary(SL sl) {
    final Map<String, List<Map<String,dynamic>>> byPlant = {};
    for (final inc in _incidents) {
      final plant = inc['plant']?.toString() ?? 'Unknown';
      byPlant.putIfAbsent(plant, () => []).add(inc);
    }
    if (byPlant.isEmpty) return const SizedBox.shrink();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('PLANT / UNIT SUMMARY', style: TextStyle(
        color: sl.text4, fontSize: 10,
        fontWeight: FontWeight.w700, letterSpacing: 1.5)),
      const SizedBox(height: 10),
      ...byPlant.entries.map((entry) {
        final plant = entry.key;
        final list  = entry.value;
        final crit  = list.where((i) => i['severity'] == 'CRITICAL').length;
        final high  = list.where((i) => i['severity'] == 'HIGH').length;
        final med   = list.where((i) => i['severity'] == 'MEDIUM').length;
        final open  = list.where((i) => i['status'] == 'OPEN').length;
        final score = LocalDB.calcSafetyScore(crit, high, med, open);
        final scoreColor = score >= 80 ? AppColors.green
            : score >= 60 ? AppColors.amber : AppColors.crit;

        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: GestureDetector(
            onTap: () => widget.onTabChange?.call(4),
            child: GlassCard(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Row(children: [
                Container(
                  width: 46, height: 46,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: scoreColor, width: 2),
                    color: scoreColor.withOpacity(0.1)),
                  child: Center(child: Text('$score',
                    style: TextStyle(color: scoreColor,
                      fontSize: 13, fontWeight: FontWeight.w900)))),
                const SizedBox(width: 12),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(plant, style: TextStyle(
                      color: sl.text1, fontSize: 13,
                      fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Wrap(spacing: 4, children: [
                      _miniPill('${list.length} total', sl.text3),
                      if (crit > 0) _miniPill('$crit CRIT', AppColors.crit),
                      if (high > 0) _miniPill('$high HIGH', AppColors.red),
                      _miniPill('$open open', AppColors.amber),
                    ]),
                  ])),
                Icon(Icons.chevron_right_rounded,
                  color: sl.text4, size: 18),
              ]),
            ),
          ));
      }).toList(),
    ]);
  }

  Widget _miniPill(String t, Color c) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: c.withOpacity(0.12),
      borderRadius: BorderRadius.circular(10)),
    child: Text(t, style: TextStyle(
      color: c, fontSize: 9, fontWeight: FontWeight.w700)));

  // ─── QUOTE CARD ───────────────────────────────────────────────────────────
  Widget _quoteCard(SL sl) {
    return GestureDetector(
      onTap: () => setState(() =>
        _quoteIndex = (_quoteIndex + 1) % _quotes.length),
      child: GlassCard(
        padding: const EdgeInsets.all(14),
        border: Border.all(color: AppColors.cyan.withOpacity(0.2)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.accent, AppColors.cyan]),
              borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.format_quote_rounded,
              color: Colors.white, size: 16)),
          const SizedBox(width: 10),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('"${_quotes[_quoteIndex][0]}"',
                style: TextStyle(color: sl.text1, fontSize: 13,
                  fontStyle: FontStyle.italic, height: 1.4,
                  fontWeight: FontWeight.w500)),
              const SizedBox(height: 4),
              Text('— ${_quotes[_quoteIndex][1]}',
                style: TextStyle(color: AppColors.cyan,
                  fontSize: 10, fontWeight: FontWeight.w700)),
            ])),
          Icon(Icons.touch_app_outlined, size: 14, color: sl.text4),
        ]),
      ),
    );
  }

  // ─── QUICK ACTIONS ────────────────────────────────────────────────────────
  Widget _quickActions(SL sl) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('QUICK ACTIONS', style: TextStyle(
          color: sl.text4, fontSize: 10,
          fontWeight: FontWeight.w700, letterSpacing: 1.5)),
        const SizedBox(height: 10),
        Row(children: [
          _actionCard(sl, Icons.document_scanner_rounded,
            'AI Scan', 'Scan workplace', AppColors.accent, AppColors.cyan,
            () => widget.onTabChange?.call(1)),
          const SizedBox(width: 10),
          _actionCard(sl, Icons.warning_amber_rounded,
            'Near Miss', 'Report hazard', AppColors.amber, AppColors.pink,
            () => widget.onTabChange?.call(2)),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          _actionCard(sl, Icons.chat_bubble_rounded,
            'Ask AI', 'Safety queries', AppColors.purple, AppColors.cyan,
            () => widget.onTabChange?.call(3)),
          const SizedBox(width: 10),
          _actionCard(sl, Icons.bar_chart_rounded,
            'Reports', 'View history', AppColors.green, AppColors.accent,
            () => widget.onTabChange?.call(4)),
        ]),
      ]);
  }

  Widget _actionCard(SL sl, IconData icon, String title,
      String sub, Color c1, Color c2, VoidCallback onTap) {
    return Expanded(child: GestureDetector(
      onTap: onTap,
      child: GlassCard(
        padding: const EdgeInsets.all(14),
        border: Border.all(color: c1.withOpacity(0.25)),
        shadows: [BoxShadow(
          color: c1.withOpacity(0.08), blurRadius: 16)],
        child: Row(children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [c1, c2]),
              borderRadius: BorderRadius.circular(11),
              boxShadow: [BoxShadow(
                color: c1.withOpacity(0.3), blurRadius: 10)]),
            child: Icon(icon, color: Colors.white, size: 20)),
          const SizedBox(width: 10),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(
                color: sl.text1, fontSize: 12,
                fontWeight: FontWeight.w700)),
              Text(sub, style: TextStyle(
                color: sl.text4, fontSize: 10)),
            ])),
        ]),
      ),
    ));
  }

  // ─── RECENT INCIDENTS ─────────────────────────────────────────────────────
  Widget _recentIncidents(SL sl) {
    final recent = _incidents.take(3).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Text('RECENT ACTIVITY', style: TextStyle(
            color: sl.text4, fontSize: 10,
            fontWeight: FontWeight.w700, letterSpacing: 1.5)),
          const Spacer(),
          Text('View all →', style: const TextStyle(
            color: AppColors.accent, fontSize: 11,
            fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 10),
        ...recent.map((inc) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: GestureDetector(
            onTap: () => widget.onTabChange?.call(4),
            child: GlassCard(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Row(children: [
              Container(
                width: 8, height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: SeverityBadge.color(
                    inc['severity']?.toString() ?? 'LOW'))),
              const SizedBox(width: 10),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(inc['title']?.toString() ?? '',
                    style: TextStyle(color: sl.text1, fontSize: 12,
                      fontWeight: FontWeight.w600),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(inc['plant']?.toString() ?? '',
                    style: TextStyle(color: sl.text4, fontSize: 10)),
                ])),
              SeverityBadge(inc['severity']?.toString() ?? 'LOW', small: true),
            ]),
          )),
        )).toList(),
      ]);
  }

  // ─── PROFILE SHEET ────────────────────────────────────────────────────────
  void _showProfileSheet() {
    final sl = SL.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        margin: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: sl.card,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: sl.border.withOpacity(0.5))),
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4,
            decoration: BoxDecoration(
              color: sl.border,
              borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          CircleAvatar(radius: 28,
            backgroundColor: AppColors.accent.withOpacity(0.15),
            child: Text(
              (widget.user?['name']?.toString() ?? 'U')[0].toUpperCase(),
              style: const TextStyle(color: AppColors.accent, fontSize: 22,
                fontWeight: FontWeight.w800))),
          const SizedBox(height: 10),
          Text(widget.user?['name'] ?? '', style: TextStyle(
            color: sl.text1, fontSize: 16, fontWeight: FontWeight.w700)),
          Text(widget.user?['designation'] ?? '', style: TextStyle(
            color: AppColors.accent, fontSize: 12)),
          Text('P.No: ${widget.user?['pno'] ?? ''}', style: TextStyle(
            color: sl.text4, fontSize: 11)),
          const SizedBox(height: 20),
          const NeonDivider(),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: _sheetBtn(sl, Icons.settings_outlined,
              'Settings', () {
                Navigator.pop(context);
                Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const SettingsScreen()));
              })),
            const SizedBox(width: 10),
            Expanded(child: _sheetBtn(sl, Icons.logout_rounded,
              'Sign Out', () {
                Navigator.pop(context);
                widget.onSignOut();
              }, isRed: true)),
          ]),
        ]),
      ),
    );
  }

  Widget _sheetBtn(SL sl, IconData icon, String label,
      VoidCallback onTap, {bool isRed = false}) =>
    GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isRed
            ? AppColors.red.withOpacity(0.1)
            : sl.card2,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isRed
              ? AppColors.red.withOpacity(0.3)
              : sl.border.withOpacity(0.5))),
        child: Row(mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16,
              color: isRed ? AppColors.red : sl.text2),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(
              fontSize: 13,
              color: isRed ? AppColors.red : sl.text1,
              fontWeight: FontWeight.w600)),
          ])));
}
