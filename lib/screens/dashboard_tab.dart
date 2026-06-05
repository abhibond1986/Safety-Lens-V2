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
  final ValueChanged<int>? onTabChange;
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

  // ─── TOP BAR — redesigned ─────────────────────────────────────────────────
  Widget _topBar(SL sl) {
    final isDark = sl.isDark;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
      decoration: BoxDecoration(
        color: sl.bg2,
        border: Border(bottom: BorderSide(
          color: sl.border.withOpacity(0.4), width: 1))),
      child: Row(children: [

        // ── Logo block: rounded card with gradient border ──────────────────
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: LinearGradient(
              begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: isDark
                ? [const Color(0xFF1E1E3F), const Color(0xFF2A2A50)]
                : [const Color(0xFFEEEDFE), const Color(0xFFE0DFFF)]),
            border: Border.all(
              color: AppColors.accent.withOpacity(isDark ? 0.4 : 0.5),
              width: 1.5)),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(11),
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Image.asset('assets/images/sail_logo.png',
                fit: BoxFit.contain)))),

        const SizedBox(width: 10),

        // ── Brand text ───────────────────────────────────────────────────
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // "SAIL Safety Lens" — using ShaderMask for gradient on "Safety Lens"
            Row(mainAxisSize: MainAxisSize.min, children: [
              Text('SAIL ', style: GoogleFonts.poppins(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: sl.text1,
                height: 1.1)),
              ShaderMask(
                shaderCallback: (b) => const LinearGradient(
                  colors: [AppColors.accent, AppColors.cyan])
                    .createShader(b),
                child: Text('Safety', style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  height: 1.1))),
              ShaderMask(
                shaderCallback: (b) => const LinearGradient(
                  colors: [AppColors.pink, AppColors.amber])
                    .createShader(b),
                child: Text(' Lens', style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  fontStyle: FontStyle.italic,
                  height: 1.1))),
            ]),
            // Tagline — "AI Safety Platform" only (IS 14489 removed)
            Row(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 5, height: 5,
                margin: const EdgeInsets.only(right: 5),
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.accent)),
              Text('AI Safety Platform',
                style: TextStyle(
                  color: sl.text3,
                  fontSize: 9.5,
                  letterSpacing: 1.0,
                  fontWeight: FontWeight.w600)),
            ]),
          ])),

        // ── Theme toggle ────────────────────────────────────────────────
        GestureDetector(
          onTap: widget.toggleTheme,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: 52, height: 28,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: isDark
                ? AppColors.darkCard2
                : AppColors.lightCard2,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isDark
                  ? AppColors.darkBorder
                  : AppColors.accent.withOpacity(0.35),
                width: 1)),
            child: Stack(children: [
              Positioned(left: 3, top: 4,
                child: Icon(Icons.nightlight_round, size: 11,
                  color: isDark ? AppColors.accent : sl.text4)),
              Positioned(right: 3, top: 4,
                child: Icon(Icons.wb_sunny_rounded, size: 11,
                  color: isDark ? sl.text4 : AppColors.amber)),
              AnimatedAlign(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                alignment: isDark
                  ? Alignment.centerLeft : Alignment.centerRight,
                child: Container(
                  width: 20, height: 20,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isDark ? AppColors.accent : AppColors.amber,
                    boxShadow: [BoxShadow(
                      color: (isDark ? AppColors.accent : AppColors.amber)
                          .withOpacity(0.4),
                      blurRadius: 6)]))),
            ])),
        ),

        const SizedBox(width: 4),

        // ── Admin button ─────────────────────────────────────────────────
        if (_isAdmin) IconButton(
          padding: const EdgeInsets.all(4),
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          icon: Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: AppColors.purple.withOpacity(isDark ? 0.15 : 0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: AppColors.purple.withOpacity(0.4))),
            child: const Icon(Icons.admin_panel_settings_outlined,
              color: AppColors.purple, size: 15)),
          onPressed: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const AdminScreen()))),

        // ── Avatar ───────────────────────────────────────────────────────
        GestureDetector(
          onTap: _showProfileSheet,
          child: Container(
            width: 34, height: 34,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [AppColors.accent, AppColors.cyan]),
              boxShadow: [BoxShadow(
                color: AppColors.accent.withOpacity(0.3),
                blurRadius: 8)]),
            child: Center(child: Text(
              (widget.user?['name']?.toString() ?? 'U')[0].toUpperCase(),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w800))))),
      ]),
    );
  }

  // ─── WELCOME ──────────────────────────────────────────────────────────────
  Widget _welcomeSection(SL sl) {
    final name  = widget.user?['name']?.toString().split(' ').first ?? 'User';
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
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.accent.withOpacity(sl.isDark ? 0.12 : 0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: AppColors.accent.withOpacity(sl.isDark ? 0.3 : 0.4))),
            child: Text('$desig · $plant', style: const TextStyle(
              color: AppColors.accent,
              fontSize: 11,
              fontWeight: FontWeight.w600))),
        ])),
      AnimatedBuilder(
        animation: _glowCtrl,
        builder: (_, __) => Container(
          width: 60, height: 60,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.accent.withOpacity(
              sl.isDark ? 0.08 * _glowCtrl.value : 0.06 * _glowCtrl.value)),
          child: Center(child: Container(
            width: 42, height: 42,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [AppColors.accent, AppColors.cyan]),
              boxShadow: [BoxShadow(
                color: AppColors.accent.withOpacity(
                  sl.isDark ? 0.4 * _glowCtrl.value : 0.2 * _glowCtrl.value),
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
          : [Colors.white, const Color(0xFFF5F4FF)]),
      border: Border.all(
        color: AppColors.accent.withOpacity(sl.isDark ? 0.2 : 0.25)),
      padding: const EdgeInsets.all(18),
      shadows: [BoxShadow(
        color: AppColors.accent.withOpacity(sl.isDark ? 0.1 : 0.06),
        blurRadius: 24)],
      child: Row(children: [
        Stack(alignment: Alignment.center, children: [
          SizedBox(width: 88, height: 88,
            child: CircularProgressIndicator(
              value: score / 100,
              strokeWidth: 7,
              backgroundColor: sl.isDark
                ? AppColors.darkCard2
                : const Color(0xFFE8E7FF),
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
      backgroundColor: sl.isDark
        ? AppColors.darkCard2
        : const Color(0xFFE0DFFF),
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
      border: Border.all(color: color.withOpacity(sl.isDark ? 0.25 : 0.35)),
      gradient: LinearGradient(
        begin: Alignment.topLeft, end: Alignment.bottomRight,
        colors: sl.isDark
          ? [AppColors.darkCard, AppColors.darkCard2]
          : [Colors.white, color.withOpacity(0.04)]),
      child: Column(children: [
        Text(value, style: TextStyle(
          color: color, fontSize: 22, fontWeight: FontWeight.w900)),
        Text(label, style: TextStyle(
          // LIGHT MODE FIX: use sl.text3 instead of sl.text4 for better visibility
          color: sl.text3, fontSize: 9, fontWeight: FontWeight.w600)),
      ])));

  // ─── PLANT SUMMARY ────────────────────────────────────────────────────────
  Widget _plantSummary(SL sl) {
    final Map<String, List<Map<String, dynamic>>> byPlant = {};
    for (final inc in _incidents) {
      final plant = inc['plant']?.toString() ?? 'Unknown';
      byPlant.putIfAbsent(plant, () => []).add(inc);
    }
    if (byPlant.isEmpty) return const SizedBox.shrink();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('PLANT / UNIT SUMMARY', style: TextStyle(
        // LIGHT MODE FIX: sl.text3 instead of sl.text4
        color: sl.text3, fontSize: 10,
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
              gradient: LinearGradient(
                begin: Alignment.topLeft, end: Alignment.bottomRight,
                colors: sl.isDark
                  ? [AppColors.darkCard, AppColors.darkCard2]
                  : [Colors.white, const Color(0xFFF8F8FF)]),
              border: Border.all(
                color: sl.isDark
                  ? sl.border.withOpacity(0.5)
                  : const Color(0xFFD0CFFF)),
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
                      // LIGHT MODE FIX: sl.text1 guaranteed visible
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
                  // LIGHT MODE FIX: sl.text3 instead of sl.text4
                  color: sl.text3, size: 18),
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
        gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: sl.isDark
            ? [AppColors.darkCard, AppColors.darkCard2]
            : [Colors.white, const Color(0xFFF0FFFE)]),
        border: Border.all(
          color: AppColors.cyan.withOpacity(sl.isDark ? 0.2 : 0.3)),
        padding: const EdgeInsets.all(14),
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
                style: TextStyle(
                  // LIGHT MODE FIX: sl.text1 for quote text
                  color: sl.text1, fontSize: 13,
                  fontStyle: FontStyle.italic, height: 1.4,
                  fontWeight: FontWeight.w500)),
              const SizedBox(height: 4),
              Text('— ${_quotes[_quoteIndex][1]}',
                style: const TextStyle(
                  color: AppColors.cyan,
                  fontSize: 10, fontWeight: FontWeight.w700)),
            ])),
          Icon(Icons.touch_app_outlined,
            size: 14,
            // LIGHT MODE FIX: sl.text3
            color: sl.text3),
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
          // LIGHT MODE FIX: sl.text3
          color: sl.text3, fontSize: 10,
          fontWeight: FontWeight.w700, letterSpacing: 1.5)),
        const SizedBox(height: 10),
        Row(children: [
          _actionCard(sl, Icons.document_scanner_rounded,
            'AI Scan', 'Scan workplace',
            AppColors.accent, AppColors.cyan,
            () => widget.onTabChange?.call(1)),
          const SizedBox(width: 10),
          _actionCard(sl, Icons.warning_amber_rounded,
            'Near Miss', 'Report hazard',
            AppColors.amber, AppColors.pink,
            () => widget.onTabChange?.call(2)),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          _actionCard(sl, Icons.chat_bubble_rounded,
            'Ask AI', 'Safety queries',
            AppColors.purple, AppColors.cyan,
            () => widget.onTabChange?.call(3)),
          const SizedBox(width: 10),
          _actionCard(sl, Icons.bar_chart_rounded,
            'Reports', 'View history',
            AppColors.green, AppColors.accent,
            () => widget.onTabChange?.call(4)),
        ]),
      ]);
  }

  Widget _actionCard(SL sl, IconData icon, String title,
      String sub, Color c1, Color c2, VoidCallback onTap) {
    return Expanded(child: GestureDetector(
      onTap: onTap,
      child: GlassCard(
        gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: sl.isDark
            ? [AppColors.darkCard, AppColors.darkCard2]
            : [Colors.white, c1.withOpacity(0.04)]),
        border: Border.all(
          color: c1.withOpacity(sl.isDark ? 0.25 : 0.3)),
        padding: const EdgeInsets.all(14),
        shadows: [BoxShadow(
          color: c1.withOpacity(sl.isDark ? 0.08 : 0.05),
          blurRadius: 16)],
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
                // LIGHT MODE FIX: sl.text1
                color: sl.text1, fontSize: 12,
                fontWeight: FontWeight.w700)),
              Text(sub, style: TextStyle(
                // LIGHT MODE FIX: sl.text3 instead of sl.text4
                color: sl.text3, fontSize: 10)),
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
            // LIGHT MODE FIX: sl.text3
            color: sl.text3, fontSize: 10,
            fontWeight: FontWeight.w700, letterSpacing: 1.5)),
          const Spacer(),
          GestureDetector(
            onTap: () => widget.onTabChange?.call(4),
            child: const Text('View all →', style: TextStyle(
              color: AppColors.accent, fontSize: 11,
              fontWeight: FontWeight.w600))),
        ]),
        const SizedBox(height: 10),
        ...recent.map((inc) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: GestureDetector(
            onTap: () => widget.onTabChange?.call(4),
            child: GlassCard(
              gradient: LinearGradient(
                begin: Alignment.topLeft, end: Alignment.bottomRight,
                colors: sl.isDark
                  ? [AppColors.darkCard, AppColors.darkCard2]
                  : [Colors.white, const Color(0xFFF8F8FF)]),
              border: Border.all(
                color: sl.isDark
                  ? sl.border.withOpacity(0.4)
                  : const Color(0xFFD8D7FF)),
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
                      style: TextStyle(
                        // LIGHT MODE FIX: sl.text1
                        color: sl.text1, fontSize: 12,
                        fontWeight: FontWeight.w600),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text(inc['plant']?.toString() ?? '',
                      style: TextStyle(
                        // LIGHT MODE FIX: sl.text3
                        color: sl.text3, fontSize: 10)),
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
          Container(
            width: 56, height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [AppColors.accent, AppColors.cyan]),
              boxShadow: [BoxShadow(
                color: AppColors.accent.withOpacity(0.3),
                blurRadius: 12)]),
            child: Center(child: Text(
              (widget.user?['name']?.toString() ?? 'U')[0].toUpperCase(),
              style: const TextStyle(color: Colors.white, fontSize: 22,
                fontWeight: FontWeight.w800)))),
          const SizedBox(height: 10),
          Text(widget.user?['name'] ?? '', style: TextStyle(
            color: sl.text1, fontSize: 16, fontWeight: FontWeight.w700)),
          Text(widget.user?['designation'] ?? '', style: const TextStyle(
            color: AppColors.accent, fontSize: 12)),
          Text('P.No: ${widget.user?['pno'] ?? ''}', style: TextStyle(
            color: sl.text3, fontSize: 11)),
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
              // LIGHT MODE FIX: use explicit colors
              color: isRed ? AppColors.red : sl.text1),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(
              fontSize: 13,
              color: isRed ? AppColors.red : sl.text1,
              fontWeight: FontWeight.w600)),
          ])));
}
