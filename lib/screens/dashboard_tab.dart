import 'package:flutter/material.dart';
import '../main.dart';
import '../services/local_db.dart';
import 'settings_screen.dart';
import 'reports_tab.dart';

class DashboardTab extends StatefulWidget {
  final Map<String, dynamic>? user;
  final VoidCallback toggleTheme;
  final VoidCallback onSignOut;
  const DashboardTab({super.key, this.user, required this.toggleTheme, required this.onSignOut});

  @override
  State<DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<DashboardTab> {
  Map<String, Map<String, int>> _plantStats = {};
  List<Map<String, dynamic>> _allIncidents = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final stats = await LocalDB.getPlantStats();
    final inc = await LocalDB.getIncidents();
    if (!mounted) return;
    setState(() {
      _plantStats = stats;
      _allIncidents = inc;
    });
  }

  int get _critical => _allIncidents.where((i) => i['severity'] == 'CRITICAL').length;
  int get _high => _allIncidents.where((i) => i['severity'] == 'HIGH').length;
  int get _medium => _allIncidents.where((i) => i['severity'] == 'MEDIUM').length;
  int get _low => _allIncidents.where((i) => i['severity'] == 'LOW').length;
  int get _openCount => _allIncidents.where((i) => i['status'] == 'OPEN').length;

  void _openReports(String filter) {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => Scaffold(
        backgroundColor: AppColors.bg,
        appBar: AppBar(
          backgroundColor: AppColors.bg2,
          title: Text(filter == 'ALL' ? 'All Reports' : '$filter Incidents',
            style: const TextStyle(color: AppColors.text1, fontSize: 15, fontWeight: FontWeight.w600)),
          iconTheme: const IconThemeData(color: AppColors.text1),
        ),
        body: ReportsTab(initialFilter: filter),
      ),
    )).then((_) => _load());
  }

  @override
  Widget build(BuildContext context) {
    final score = LocalDB.calcSafetyScore(_critical, _high, _medium, _openCount);

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(14),
          children: [
            _topBar(),
            const SizedBox(height: 14),
            _severitySummary(),
            const SizedBox(height: 12),
            _motivCard(),
            const SizedBox(height: 12),
            _scoreCard(score, _openCount),
            const SizedBox(height: 12),
            _plantStatsCard(),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _topBar() {
    final name = widget.user?['name']?.toString() ?? 'User';
    final desig = widget.user?['designation']?.toString() ?? '';
    final plant = widget.user?['plant']?.toString() ?? '';
    return Row(children: [
      const SailLogoTile(size: 44),
      const SizedBox(width: 10),
      Expanded(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const BrandTitle(size: 18),
          const SizedBox(height: 2),
          Text(name,
            style: const TextStyle(color: AppColors.text1, fontSize: 12, fontWeight: FontWeight.w600)),
          Text('$desig · $plant',
            style: const TextStyle(color: AppColors.text4, fontSize: 9)),
        ],
      )),
      IconButton(
        icon: const Icon(Icons.account_circle_outlined, color: AppColors.text2, size: 26),
        onPressed: _showProfileMenu,
      ),
    ]);
  }

  /// Clickable severity summary row — taps drill into Reports filtered view
  Widget _severitySummary() {
    Widget pill(String label, int count, Color color, IconData icon) {
      return Expanded(
        child: GestureDetector(
          onTap: () => _openReports(label),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 3),
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color, width: 1.5),
              boxShadow: [BoxShadow(color: color.withOpacity(0.15), blurRadius: 8, offset: const Offset(0, 2))],
            ),
            child: Column(children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(height: 4),
              Text('$count',
                style: TextStyle(color: color, fontSize: 22, fontWeight: FontWeight.w800, height: 1)),
              const SizedBox(height: 2),
              Text(label,
                style: TextStyle(color: color, fontSize: 8, fontWeight: FontWeight.w700, letterSpacing: 0.4)),
              const SizedBox(height: 1),
              const Icon(Icons.chevron_right, color: AppColors.text4, size: 11),
            ]),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 4, 6, 8),
          child: Row(children: [
            const Icon(Icons.assessment_outlined, color: AppColors.accent, size: 14),
            const SizedBox(width: 6),
            const Text('INCIDENT SUMMARY',
              style: TextStyle(color: AppColors.text3, fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 0.6)),
            const Spacer(),
            GestureDetector(
              onTap: () => _openReports('ALL'),
              child: const Row(children: [
                Text('View All ',
                  style: TextStyle(color: AppColors.accent, fontSize: 10, fontWeight: FontWeight.w600)),
                Icon(Icons.arrow_forward, color: AppColors.accent, size: 11),
              ]),
            ),
          ]),
        ),
        Row(children: [
          pill('CRITICAL', _critical, AppColors.crit, Icons.dangerous_outlined),
          pill('HIGH', _high, AppColors.red, Icons.warning_amber_outlined),
          pill('MEDIUM', _medium, AppColors.cyan, Icons.info_outline),
          pill('LOW', _low, AppColors.green, Icons.check_circle_outline),
        ]),
        Padding(
          padding: const EdgeInsets.all(6),
          child: Text('Tap any tile to see those specific reports',
            style: TextStyle(color: AppColors.text4, fontSize: 9, fontStyle: FontStyle.italic)),
        ),
      ]),
    );
  }

  void _showProfileMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SailLogoTile(size: 64),
          const SizedBox(height: 12),
          Text(widget.user?['name']?.toString() ?? '',
            style: const TextStyle(color: AppColors.text1, fontSize: 16, fontWeight: FontWeight.w700)),
          Text(widget.user?['designation']?.toString() ?? '',
            style: const TextStyle(color: AppColors.text3, fontSize: 11)),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: widget.toggleTheme,
            icon: const Icon(Icons.brightness_6_outlined, size: 16, color: AppColors.text2),
            label: const Text('Toggle Theme', style: TextStyle(color: AppColors.text2)),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: AppColors.border),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
            },
            icon: const Icon(Icons.cloud_sync_outlined, size: 16, color: AppColors.accent),
            label: const Text('Settings · Sync', style: TextStyle(color: AppColors.accent)),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: AppColors.accent, width: 2),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
          const SizedBox(height: 10),
          ElevatedButton.icon(
            onPressed: () { Navigator.pop(context); widget.onSignOut(); },
            icon: const Icon(Icons.logout, size: 16, color: Colors.white),
            label: const Text('Sign Out', style: TextStyle(color: Colors.white)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.red,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _motivCard() {
    final quotes = [
      'Safety is not a slogan, it is a way of life.',
      'A safe workplace is a productive workplace.',
      'Zero incidents start with one careful step.',
      'Every hazard reported is a life potentially saved.',
    ];
    final q = quotes[DateTime.now().day % quotes.length];
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF1E3A8A), Color(0xFF0D47A1)]),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(children: [
        const Icon(Icons.format_quote, color: Colors.white70, size: 28),
        const SizedBox(width: 10),
        Expanded(child: Text(q,
          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600, height: 1.4))),
      ]),
    );
  }

  Widget _scoreCard(int score, int open) {
    Color color = score >= 75 ? AppColors.green : score >= 50 ? AppColors.amber : AppColors.red;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(children: [
        Container(
          width: 80, height: 80,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withOpacity(0.15),
            border: Border.all(color: color, width: 3),
          ),
          child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('$score', style: TextStyle(color: color, fontSize: 24, fontWeight: FontWeight.w800)),
            Text('/100', style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600)),
          ])),
        ),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('SAFETY SCORE',
            style: TextStyle(color: AppColors.text4, fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 0.6)),
          const SizedBox(height: 4),
          Text(score >= 75 ? 'Excellent' : score >= 50 ? 'Needs Attention' : 'Critical',
            style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text('$open open cases',
            style: const TextStyle(color: AppColors.text3, fontSize: 11)),
        ])),
      ]),
    );
  }

  Widget _plantStatsCard() {
    if (_plantStats.isEmpty) return const SizedBox();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('PLANT-WISE STATISTICS',
          style: TextStyle(color: AppColors.text3, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.6)),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: AppColors.bg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: const BoxDecoration(
                color: AppColors.card2,
                borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
              ),
              child: const Row(children: [
                Expanded(flex: 3, child: Text('PLANT', style: TextStyle(color: AppColors.text3, fontSize: 9, fontWeight: FontWeight.w700))),
                Expanded(child: Text('TOTAL', style: TextStyle(color: AppColors.text3, fontSize: 9, fontWeight: FontWeight.w700), textAlign: TextAlign.center)),
                Expanded(child: Text('OPEN', style: TextStyle(color: AppColors.text3, fontSize: 9, fontWeight: FontWeight.w700), textAlign: TextAlign.center)),
                Expanded(child: Text('CRIT', style: TextStyle(color: AppColors.text3, fontSize: 9, fontWeight: FontWeight.w700), textAlign: TextAlign.center)),
                Expanded(child: Text('HIGH', style: TextStyle(color: AppColors.text3, fontSize: 9, fontWeight: FontWeight.w700), textAlign: TextAlign.center)),
              ]),
            ),
            ..._plantStats.entries.map((e) {
              final p = e.value;
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.border, width: 0.5))),
                child: Row(children: [
                  Expanded(flex: 3, child: Text(e.key,
                    style: const TextStyle(color: AppColors.text1, fontSize: 10, fontWeight: FontWeight.w600))),
                  Expanded(child: Text('${p['total']}',
                    style: const TextStyle(color: AppColors.text1, fontSize: 10), textAlign: TextAlign.center)),
                  Expanded(child: Text('${p['open']}',
                    style: const TextStyle(color: AppColors.amber, fontSize: 10, fontWeight: FontWeight.w700), textAlign: TextAlign.center)),
                  Expanded(child: Text('${p['critical']}',
                    style: const TextStyle(color: AppColors.crit, fontSize: 10, fontWeight: FontWeight.w700), textAlign: TextAlign.center)),
                  Expanded(child: Text('${p['high']}',
                    style: const TextStyle(color: AppColors.red, fontSize: 10, fontWeight: FontWeight.w700), textAlign: TextAlign.center)),
                ]),
              );
            }).toList(),
          ]),
        ),
      ]),
    );
  }
}
