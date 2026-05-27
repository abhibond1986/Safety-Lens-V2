import 'package:flutter/material.dart';
import '../main.dart';
import '../services/local_db.dart';

class DashboardTab extends StatefulWidget {
  final Map<String, dynamic>? user;
  final VoidCallback toggleTheme;
  final VoidCallback onSignOut;
  const DashboardTab({super.key, this.user, required this.toggleTheme, required this.onSignOut});

  @override
  State<DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<DashboardTab> {
  int _quoteIndex = 0;
  Map<String, Map<String, int>> _plantStats = {};
  List<Map<String, dynamic>> _incidents = [];

  final _quotes = const [
    ['Safety isn\'t expensive, it\'s priceless. A moment of caution is better than a lifetime of regret.', 'SAIL Safety Pledge'],
    ['Zero harm starts with one safe action — yours, right now.', 'Ministry of Steel India'],
    ['A safe worker is a productive worker. Your family is waiting at home.', 'IS 14489 Foreword'],
    ['Every hazard reported today prevents an accident tomorrow.', 'SAIL Safety Manual'],
    ['Safety is not a slogan, it\'s a way of life at SAIL.', 'SAIL Vision Statement'],
    ['Prepare and prevent, don\'t repair and repent.', 'Factories Act Preamble'],
  ];

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    final stats = await LocalDB.getPlantStats();
    final inc = await LocalDB.getIncidents();
    if (mounted) setState(() {
      _plantStats = stats;
      _incidents = inc;
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.user;
    final critical = _incidents.where((i) => i['severity'] == 'CRITICAL').length;
    final high = _incidents.where((i) => i['severity'] == 'HIGH').length;
    final medium = _incidents.where((i) => i['severity'] == 'MEDIUM').length;
    final open = _incidents.where((i) => i['status'] == 'OPEN').length;
    final score = LocalDB.calcSafetyScore(critical, high, medium, open);

    return SafeArea(
      child: Column(
        children: [
          _topBar(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 80),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Welcome,', style: TextStyle(color: AppColors.text3, fontSize: 11)),
                  Text(user?['name']?.toString() ?? 'User',
                      style: const TextStyle(color: AppColors.text1, fontSize: 20, fontWeight: FontWeight.w600)),
                  Text('${user?['designation'] ?? ''} · ${user?['plant'] ?? ''}',
                      style: const TextStyle(color: AppColors.accent, fontSize: 11, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 14),
                  _motivCard(),
                  _scoreCard(score, open),
                  _plantStatsCard(),
                  _actionCards(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _topBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: const BoxDecoration(
        color: AppColors.bg2,
        border: Border(bottom: BorderSide(color: AppColors.border, width: 0.5)),
      ),
      child: Row(
        children: [
          const SailLogoTile(size: 38),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                BrandTitle(size: 16),
                Text('SAIL · IS 14489',
                  style: TextStyle(color: AppColors.text4, fontSize: 8, letterSpacing: 1.5, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.brightness_6_outlined, color: AppColors.text1, size: 18),
            onPressed: widget.toggleTheme,
          ),
          IconButton(
            icon: const Icon(Icons.account_circle_outlined, color: AppColors.text1, size: 22),
            onPressed: _showProfileMenu,
          ),
        ],
      ),
    );
  }

  void _showProfileMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(14))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.user?['name'] ?? '',
              style: const TextStyle(color: AppColors.text1, fontSize: 16, fontWeight: FontWeight.w600)),
            Text(widget.user?['designation'] ?? '',
              style: const TextStyle(color: AppColors.text3, fontSize: 12)),
            const SizedBox(height: 4),
            Text('P.No: ${widget.user?['pno'] ?? ''}',
              style: const TextStyle(color: AppColors.text4, fontSize: 10)),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () { Navigator.pop(context); widget.onSignOut(); },
              icon: const Icon(Icons.logout, size: 16, color: Colors.white),
              label: const Text('Sign Out', style: TextStyle(color: Colors.white)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.red,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _motivCard() {
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.purple.withOpacity(0.15), AppColors.accent.withOpacity(0.15)],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        border: Border.all(color: AppColors.accent),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('SAFETY THOUGHT',
                style: TextStyle(color: AppColors.accent, fontSize: 8, letterSpacing: 1.2, fontWeight: FontWeight.w700)),
              const SizedBox(height: 5),
              Text('"${_quotes[_quoteIndex][0]}"',
                style: const TextStyle(color: AppColors.text1, fontSize: 12, fontWeight: FontWeight.w500, fontStyle: FontStyle.italic, height: 1.55)),
              const SizedBox(height: 5),
              Text('— ${_quotes[_quoteIndex][1]}',
                style: const TextStyle(color: AppColors.text3, fontSize: 9)),
            ],
          ),
          Positioned(
            top: 0, right: 0,
            child: GestureDetector(
              onTap: () => setState(() => _quoteIndex = (_quoteIndex + 1) % _quotes.length),
              child: Container(
                width: 24, height: 24,
                decoration: BoxDecoration(
                  color: AppColors.card2,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.border),
                ),
                child: const Icon(Icons.refresh, size: 13, color: AppColors.text2),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _scoreCard(int score, int open) {
    final scoreColor = score >= 85 ? AppColors.green : score >= 70 ? AppColors.amber : AppColors.red;
    return Container(
      padding: const EdgeInsets.all(14),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.accent, width: 1.5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 68, height: 68,
            child: Stack(alignment: Alignment.center, children: [
              SizedBox(
                width: 68, height: 68,
                child: CircularProgressIndicator(
                  value: score / 100,
                  strokeWidth: 6,
                  backgroundColor: AppColors.card3,
                  valueColor: AlwaysStoppedAnimation<Color>(scoreColor),
                ),
              ),
              Text('$score', style: TextStyle(color: scoreColor, fontSize: 18, fontWeight: FontWeight.w700)),
            ]),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(score >= 85 ? 'Good safety score' : score >= 70 ? 'Needs attention' : 'Critical action needed',
                  style: TextStyle(color: scoreColor, fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 3),
                Text('Org-wide · ${_incidents.length} reports · 5 plants',
                  style: TextStyle(color: AppColors.text3, fontSize: 9)),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.amber.withOpacity(0.2),
                    border: Border.all(color: AppColors.amber),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('$open OPEN cases',
                    style: const TextStyle(color: Color(0xFFFCD34D), fontSize: 9, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _plantStatsCard() {
    if (_plantStats.isEmpty) return const SizedBox();
    return Container(
      padding: const EdgeInsets.all(14),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.factory_outlined, size: 14, color: AppColors.accent),
              SizedBox(width: 6),
              Text('PLANT-WISE STATS',
                style: TextStyle(color: AppColors.text4, fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 0.9)),
            ],
          ),
          const SizedBox(height: 10),
          Table(
            border: TableBorder(horizontalInside: BorderSide(color: AppColors.border, width: 0.5)),
            columnWidths: const {
              0: FlexColumnWidth(2.2),
              1: FlexColumnWidth(1),
              2: FlexColumnWidth(1),
              3: FlexColumnWidth(1),
            },
            children: [
              TableRow(
                decoration: const BoxDecoration(color: AppColors.card2),
                children: [
                  _th('Plant'), _th('Score', center: true), _th('Open', center: true), _th('Critical', center: true),
                ],
              ),
              ..._plantStats.entries.map((e) {
                final s = e.value;
                final score = LocalDB.calcSafetyScore(s['critical']!, s['high']!, 0, s['open']!);
                final scoreColor = score >= 85 ? AppColors.green : score >= 70 ? AppColors.amber : AppColors.red;
                return TableRow(children: [
                  _td(e.key, bold: true),
                  Padding(padding: const EdgeInsets.all(6), child: Center(child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: scoreColor.withOpacity(0.2),
                      border: Border.all(color: scoreColor),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('$score',
                      style: TextStyle(color: scoreColor, fontSize: 8, fontWeight: FontWeight.w700)),
                  ))),
                  _td('${s['open']}', center: true),
                  Padding(padding: const EdgeInsets.all(6), child: Center(child: Text('${s['critical']}',
                    style: TextStyle(
                      color: s['critical']! > 0 ? AppColors.red : AppColors.text2,
                      fontWeight: s['critical']! > 0 ? FontWeight.w700 : FontWeight.normal,
                      fontSize: 10)))),
                ]);
              }).toList(),
            ],
          ),
        ],
      ),
    );
  }

  Widget _th(String text, {bool center = false}) => Padding(
    padding: const EdgeInsets.all(6),
    child: Text(text,
      textAlign: center ? TextAlign.center : TextAlign.left,
      style: const TextStyle(color: AppColors.text3, fontSize: 9, fontWeight: FontWeight.w600)),
  );

  Widget _td(String text, {bool bold = false, bool center = false}) => Padding(
    padding: const EdgeInsets.all(6),
    child: Text(text,
      textAlign: center ? TextAlign.center : TextAlign.left,
      style: TextStyle(color: AppColors.text1, fontSize: 10, fontWeight: bold ? FontWeight.w600 : FontWeight.normal)),
  );

  Widget _actionCards() {
    return const SizedBox.shrink();
  }
}
