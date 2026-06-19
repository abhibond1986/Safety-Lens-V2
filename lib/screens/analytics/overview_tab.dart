import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../main.dart' show AppColors, SL;
import '../../services/local_db.dart';

class OverviewTab extends StatefulWidget {
  const OverviewTab({super.key});
  @override
  State<OverviewTab> createState() => _OverviewTabState();
}

class _OverviewTabState extends State<OverviewTab> {
  List<Map<String, dynamic>> _incidents = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final inc = await LocalDB.getIncidents();
    if (mounted) setState(() { _incidents = inc; _loading = false; });
  }

  // ── COMPUTED KPIs ─────────────────────────────────────────────
  int get _total => _incidents.length;

  int get _open => _incidents.where((i) {
    final s = (i['status']?.toString().toUpperCase() ?? 'OPEN');
    return s != 'CLOSED';
  }).length;

  int get _closed => _incidents.where((i) =>
      i['status']?.toString().toUpperCase() == 'CLOSED').length;

  double get _closureRate => _total == 0 ? 0 : (_closed / _total * 100);

  int get _daysSinceCritical {
    final crits = _incidents.where((i) =>
        i['severity']?.toString().toUpperCase() == 'CRITICAL').toList();
    if (crits.isEmpty) return 365;
    crits.sort((a, b) =>
        (b['date']?.toString() ?? '').compareTo(a['date']?.toString() ?? ''));
    final last = DateTime.tryParse(crits.first['date']?.toString() ?? '');
    if (last == null) return 365;
    return DateTime.now().difference(last).inDays;
  }

  double get _avgClosureTime {
    final closedInc = _incidents.where((i) =>
        i['status']?.toString().toUpperCase() == 'CLOSED' &&
        i['closedAt'] != null && i['date'] != null).toList();
    if (closedInc.isEmpty) return 0;
    double totalDays = 0;
    for (final i in closedInc) {
      final opened = DateTime.tryParse(i['date'].toString());
      final closed = DateTime.tryParse(i['closedAt'].toString());
      if (opened != null && closed != null) {
        totalDays += closed.difference(opened).inDays.abs();
      }
    }
    return totalDays / closedInc.length;
  }

  // Status counts
  int _statusCount(String status) => _incidents.where((i) =>
      (i['status']?.toString().toUpperCase() ?? 'OPEN') == status).length;

  // Severity counts
  Map<String, int> get _severityCounts {
    final m = <String, int>{'CRITICAL': 0, 'HIGH': 0, 'MEDIUM': 0, 'LOW': 0};
    for (final i in _incidents) {
      final s = (i['severity']?.toString().toUpperCase() ?? 'MEDIUM');
      m[s] = (m[s] ?? 0) + 1;
    }
    return m;
  }

  // Monthly trend (last 6 months)
  List<MapEntry<String, int>> get _monthlyTrend {
    final now = DateTime.now();
    final result = <String, int>{};
    for (int m = 5; m >= 0; m--) {
      final month = DateTime(now.year, now.month - m, 1);
      final key = '${_monthName(month.month)} ${month.year.toString().substring(2)}';
      result[key] = 0;
    }
    for (final i in _incidents) {
      final d = DateTime.tryParse(i['date']?.toString() ?? '');
      if (d == null) continue;
      final monthsDiff = (now.year - d.year) * 12 + (now.month - d.month);
      if (monthsDiff >= 0 && monthsDiff < 6) {
        final key = '${_monthName(d.month)} ${d.year.toString().substring(2)}';
        if (result.containsKey(key)) result[key] = result[key]! + 1;
      }
    }
    return result.entries.toList();
  }

  String _monthName(int m) {
    const names = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                   'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return names[((m - 1) % 12) + 1];
  }

  // Top problem areas
  String get _worstPlant {
    final m = <String, int>{};
    for (final i in _incidents) {
      if ((i['status']?.toString().toUpperCase() ?? 'OPEN') == 'CLOSED') continue;
      final p = i['plant']?.toString() ?? '';
      if (p.isNotEmpty) m[p] = (m[p] ?? 0) + 1;
    }
    if (m.isEmpty) return '—';
    final sorted = m.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return '${sorted.first.key} (${sorted.first.value} open)';
  }

  String get _worstCategory {
    final m = <String, int>{};
    for (final i in _incidents) {
      final c = i['wsaCategory']?.toString() ?? '';
      if (c.isNotEmpty) m[c] = (m[c] ?? 0) + 1;
    }
    if (m.isEmpty) return '—';
    final sorted = m.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return '${sorted.first.key} (${sorted.first.value})';
  }

  String get _longestOpen {
    final openInc = _incidents.where((i) =>
        (i['status']?.toString().toUpperCase() ?? 'OPEN') != 'CLOSED').toList();
    if (openInc.isEmpty) return '—';
    openInc.sort((a, b) =>
        (a['date']?.toString() ?? '').compareTo(b['date']?.toString() ?? ''));
    final oldest = openInc.first;
    final d = DateTime.tryParse(oldest['date']?.toString() ?? '');
    if (d == null) return oldest['title']?.toString() ?? '—';
    final days = DateTime.now().difference(d).inDays;
    return '${oldest['title'] ?? 'Untitled'} ($days days)';
  }

  @override
  Widget build(BuildContext context) {
    final sl = SL.of(context);
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (_incidents.isEmpty) {
      return Center(child: Text('No data recorded yet',
          style: TextStyle(color: sl.text3, fontSize: 14)));
    }

    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.accent,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _kpiStrip(sl),
          const SizedBox(height: 16),
          _statusPipeline(sl),
          const SizedBox(height: 16),
          _monthlyTrendChart(sl),
          const SizedBox(height: 16),
          _severityDonut(sl),
          const SizedBox(height: 16),
          _problemAreas(sl),
          const SizedBox(height: 20),
        ]),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  KPI STRIP — 5 metric cards
  // ═══════════════════════════════════════════════════════════════
  Widget _kpiStrip(SL sl) {
    return Column(children: [
      Row(children: [
        _kpiCard(sl, 'Total', '$_total', Icons.assessment_rounded,
            const Color(0xFF6366F1)),
        const SizedBox(width: 8),
        _kpiCard(sl, 'Open', '$_open', Icons.warning_amber_rounded,
            AppColors.amber),
        const SizedBox(width: 8),
        _kpiCard(sl, 'Avg Close', '${_avgClosureTime.toStringAsFixed(1)}d',
            Icons.timer_outlined, AppColors.cyan),
      ]),
      const SizedBox(height: 8),
      Row(children: [
        _kpiCard(sl, 'LTI-Free', '$_daysSinceCritical d',
            Icons.shield_outlined, AppColors.green),
        const SizedBox(width: 8),
        _kpiCard(sl, 'Closure %', '${_closureRate.toStringAsFixed(0)}%',
            Icons.check_circle_outline, const Color(0xFF10B981)),
        const SizedBox(width: 8),
        Expanded(child: Container()),
      ]),
    ]);
  }

  Widget _kpiCard(SL sl, String label, String value, IconData icon, Color color) {
    return Expanded(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: sl.glassColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withOpacity(0.3)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(height: 8),
              Text(value, style: TextStyle(
                  color: sl.text1, fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(label, style: TextStyle(
                  color: sl.text3, fontSize: 10, fontWeight: FontWeight.w600)),
            ]),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  STATUS PIPELINE — OPEN → INVESTIGATING → ACTION TAKEN → CLOSED
  // ═══════════════════════════════════════════════════════════════
  Widget _statusPipeline(SL sl) {
    final stages = [
      ('OPEN', _statusCount('OPEN'), AppColors.amber),
      ('INVESTIGATING', _statusCount('INVESTIGATING'), AppColors.cyan),
      ('ACTION TAKEN', _statusCount('ACTION TAKEN'), const Color(0xFF8B5CF6)),
      ('CLOSED', _statusCount('CLOSED'), AppColors.green),
    ];

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: sl.glassColor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: sl.glassBorder),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Status Pipeline', style: TextStyle(
                color: sl.text1, fontSize: 13, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            Row(
              children: stages.asMap().entries.map((e) {
                final idx = e.key;
                final (label, count, color) = e.value;
                return Expanded(child: Row(children: [
                  if (idx > 0)
                    Icon(Icons.chevron_right, color: sl.text4, size: 14),
                  Expanded(child: Column(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: color.withOpacity(0.3)),
                      ),
                      child: Center(child: Text('$count',
                          style: TextStyle(color: color, fontSize: 16,
                              fontWeight: FontWeight.w800))),
                    ),
                    const SizedBox(height: 4),
                    Text(label, style: TextStyle(
                        color: sl.text4, fontSize: 8, fontWeight: FontWeight.w600),
                        textAlign: TextAlign.center),
                  ])),
                ]));
              }).toList(),
            ),
          ]),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  MONTHLY TREND — bar chart, last 6 months
  // ═══════════════════════════════════════════════════════════════
  Widget _monthlyTrendChart(SL sl) {
    final data = _monthlyTrend;
    final maxVal = data.fold<int>(1, (m, e) => e.value > m ? e.value : m);

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: sl.glassColor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: sl.glassBorder),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.trending_up_rounded, color: AppColors.accent, size: 16),
              const SizedBox(width: 6),
              Text('Monthly Trend', style: TextStyle(
                  color: sl.text1, fontSize: 13, fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 14),
            SizedBox(
              height: 100,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: data.map((e) {
                  final h = maxVal == 0 ? 4.0 : (e.value / maxVal) * 80 + 4;
                  final isLast = e == data.last;
                  return Expanded(child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                      if (e.value > 0)
                        Text('${e.value}', style: TextStyle(
                            color: sl.text3, fontSize: 9, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 3),
                      Container(
                        height: h,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: isLast
                                ? [AppColors.accent, AppColors.accent.withOpacity(0.4)]
                                : [AppColors.cyan.withOpacity(0.7), AppColors.cyan.withOpacity(0.2)],
                          ),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(e.key, style: TextStyle(
                          color: isLast ? AppColors.accent : sl.text4,
                          fontSize: 8, fontWeight: FontWeight.w600)),
                    ]),
                  ));
                }).toList(),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  SEVERITY DONUT
  // ═══════════════════════════════════════════════════════════════
  Widget _severityDonut(SL sl) {
    final counts = _severityCounts;
    final total = counts.values.fold<int>(0, (s, v) => s + v);
    if (total == 0) return const SizedBox();

    final sections = [
      PieChartSectionData(value: (counts['CRITICAL'] ?? 0).toDouble(),
          color: AppColors.crit, radius: 22, title: ''),
      PieChartSectionData(value: (counts['HIGH'] ?? 0).toDouble(),
          color: AppColors.red, radius: 22, title: ''),
      PieChartSectionData(value: (counts['MEDIUM'] ?? 0).toDouble(),
          color: AppColors.amber, radius: 22, title: ''),
      PieChartSectionData(value: (counts['LOW'] ?? 0).toDouble(),
          color: AppColors.green, radius: 22, title: ''),
    ];

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: sl.glassColor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: sl.glassBorder),
          ),
          child: Row(children: [
            SizedBox(width: 100, height: 100,
              child: PieChart(PieChartData(
                sections: sections,
                centerSpaceRadius: 24,
                sectionsSpace: 2,
              )),
            ),
            const SizedBox(width: 16),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Severity Split', style: TextStyle(
                    color: sl.text1, fontSize: 13, fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),
                _sevRow('Critical', counts['CRITICAL']!, AppColors.crit, sl),
                _sevRow('High', counts['HIGH']!, AppColors.red, sl),
                _sevRow('Medium', counts['MEDIUM']!, AppColors.amber, sl),
                _sevRow('Low', counts['LOW']!, AppColors.green, sl),
              ],
            )),
          ]),
        ),
      ),
    );
  }

  Widget _sevRow(String label, int count, Color color, SL sl) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(
            color: color, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(color: sl.text2, fontSize: 11)),
        const Spacer(),
        Text('$count', style: TextStyle(
            color: sl.text1, fontSize: 12, fontWeight: FontWeight.w700)),
      ]),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  TOP 3 PROBLEM AREAS
  // ═══════════════════════════════════════════════════════════════
  Widget _problemAreas(SL sl) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: sl.glassColor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: sl.glassBorder),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.priority_high_rounded, color: AppColors.red, size: 16),
              const SizedBox(width: 6),
              Text('Attention Areas', style: TextStyle(
                  color: sl.text1, fontSize: 13, fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 12),
            _problemRow(sl, 'Worst Plant', _worstPlant,
                Icons.factory_outlined, AppColors.red),
            const SizedBox(height: 8),
            _problemRow(sl, 'Top Hazard', _worstCategory,
                Icons.category_outlined, AppColors.amber),
            const SizedBox(height: 8),
            _problemRow(sl, 'Longest Open', _longestOpen,
                Icons.schedule_outlined, const Color(0xFF8B5CF6)),
          ]),
        ),
      ),
    );
  }

  Widget _problemRow(SL sl, String label, String value, IconData icon, Color color) {
    return Row(children: [
      Container(
        width: 30, height: 30,
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(8)),
        child: Icon(icon, color: color, size: 15),
      ),
      const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(color: sl.text4, fontSize: 9,
            fontWeight: FontWeight.w600)),
        Text(value, style: TextStyle(color: sl.text1, fontSize: 12,
            fontWeight: FontWeight.w600),
            maxLines: 1, overflow: TextOverflow.ellipsis),
      ])),
    ]);
  }
}
