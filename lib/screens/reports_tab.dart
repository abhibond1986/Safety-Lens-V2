// lib/widgets/report_charts.dart
// ✅ Custom-painted pie chart + bar chart for Reports section.
// No external dependency needed — uses CustomPainter.
// Shows: Severity distribution (donut) + AI Scan vs Near Miss by plant (bar).
import '../widgets/report_charts.dart'
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../main.dart' show AppColors, SL;
import '../services/local_db.dart';
import '../services/i18n.dart';

class ReportCharts extends StatefulWidget {
  const ReportCharts({super.key});

  @override
  State<ReportCharts> createState() => _ReportChartsState();
}

class _ReportChartsState extends State<ReportCharts> {
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

  // ── COMPUTED DATA ──────────────────────────────────────────
  Map<String, int> get _severityCounts {
    final map = <String, int>{'CRITICAL': 0, 'HIGH': 0, 'MEDIUM': 0, 'LOW': 0};
    for (final i in _incidents) {
      final sev = (i['severity']?.toString() ?? 'MEDIUM').toUpperCase();
      if (map.containsKey(sev)) {
        map[sev] = map[sev]! + 1;
      } else {
        map['MEDIUM'] = map['MEDIUM']! + 1;
      }
    }
    return map;
  }

  Map<String, Map<String, int>> get _plantTypeCounts {
    final map = <String, Map<String, int>>{};
    for (final i in _incidents) {
      final plant = i['plant']?.toString() ?? 'Other';
      final type = i['type']?.toString().toUpperCase() ?? 'OTHER';
      map.putIfAbsent(plant, () => {'AI_SCAN': 0, 'NEAR_MISS': 0});
      if (type == 'AI_SCAN') {
        map[plant]!['AI_SCAN'] = (map[plant]!['AI_SCAN'] ?? 0) + 1;
      } else {
        map[plant]!['NEAR_MISS'] = (map[plant]!['NEAR_MISS'] ?? 0) + 1;
      }
    }
    // Sort by total count, take top 6
    final sorted = map.entries.toList()
      ..sort((a, b) => (b.value['AI_SCAN']! + b.value['NEAR_MISS']!)
          .compareTo(a.value['AI_SCAN']! + a.value['NEAR_MISS']!));
    return Map.fromEntries(sorted.take(6));
  }

  int get _aiScanCount => _incidents.where((i) =>
      i['type']?.toString().toUpperCase() == 'AI_SCAN').length;
  int get _nearMissCount => _incidents.where((i) =>
      i['type']?.toString().toUpperCase() == 'NEAR_MISS').length;

  @override
  Widget build(BuildContext context) {
    final sl = SL.of(context);
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)));
    }
    if (_incidents.isEmpty) return const SizedBox.shrink();

    return Column(children: [
      // ── ROW 1: Donut + Type split ──
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Severity Donut Chart
          Expanded(child: _severityDonut(sl)),
          const SizedBox(width: 10),
          // Type breakdown card
          Expanded(child: _typeBreakdown(sl)),
        ],
      ),
      const SizedBox(height: 12),
      // ── ROW 2: Bar chart — AI Scan vs Near Miss by Plant ──
      _plantBarChart(sl),
      const SizedBox(height: 14),
    ]);
  }

  // ═══════════════════════════════════════════════════════════════
  //  SEVERITY DONUT CHART
  // ═══════════════════════════════════════════════════════════════
  Widget _severityDonut(SL sl) {
    final counts = _severityCounts;
    final total = counts.values.fold<int>(0, (s, v) => s + v);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: sl.card,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(
          color: Colors.black.withOpacity(sl.isDark ? 0.2 : 0.06),
          blurRadius: 8, offset: const Offset(0, 2))]),
      child: Column(children: [
        Row(children: [
          Icon(Icons.pie_chart_outline_rounded, size: 14, color: AppColors.accent),
          const SizedBox(width: 6),
          Text('Severity', style: TextStyle(color: sl.text1, fontSize: 12,
              fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 12),
        SizedBox(
          width: 100, height: 100,
          child: CustomPaint(
            painter: _DonutPainter(
              values: [
                counts['CRITICAL']!.toDouble(),
                counts['HIGH']!.toDouble(),
                counts['MEDIUM']!.toDouble(),
                counts['LOW']!.toDouble(),
              ],
              colors: const [
                Color(0xFFDC2626), // critical
                Color(0xFFEF4444), // high
                Color(0xFFF59E0B), // medium
                Color(0xFF10B981), // low
              ],
            ),
            child: Center(child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('$total', style: TextStyle(color: sl.text1, fontSize: 18,
                    fontWeight: FontWeight.w800)),
                Text('Total', style: TextStyle(color: sl.text4, fontSize: 9)),
              ])),
          ),
        ),
        const SizedBox(height: 10),
        // Legend
        Wrap(spacing: 8, runSpacing: 4, children: [
          _legendDot('CRIT', counts['CRITICAL']!, const Color(0xFFDC2626), sl),
          _legendDot('HIGH', counts['HIGH']!, const Color(0xFFEF4444), sl),
          _legendDot('MED', counts['MEDIUM']!, const Color(0xFFF59E0B), sl),
          _legendDot('LOW', counts['LOW']!, const Color(0xFF10B981), sl),
        ]),
      ]),
    );
  }

  Widget _legendDot(String label, int count, Color color, SL sl) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(width: 8, height: 8,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 3),
      Text('$count', style: TextStyle(color: sl.text1, fontSize: 10,
          fontWeight: FontWeight.w700)),
      const SizedBox(width: 2),
      Text(label, style: TextStyle(color: sl.text4, fontSize: 8)),
    ]);

  // ═══════════════════════════════════════════════════════════════
  //  TYPE BREAKDOWN CARD
  // ═══════════════════════════════════════════════════════════════
  Widget _typeBreakdown(SL sl) {
    final total = _incidents.length;
    final aiPct = total == 0 ? 0.0 : _aiScanCount / total;
    final nmPct = total == 0 ? 0.0 : _nearMissCount / total;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: sl.card,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(
          color: Colors.black.withOpacity(sl.isDark ? 0.2 : 0.06),
          blurRadius: 8, offset: const Offset(0, 2))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.analytics_outlined, size: 14, color: AppColors.cyan),
          const SizedBox(width: 6),
          Text('By Type', style: TextStyle(color: sl.text1, fontSize: 12,
              fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 14),
        // AI Scan
        _typeRow('AI Scan', _aiScanCount, aiPct,
            const Color(0xFF7B5BFF), sl),
        const SizedBox(height: 10),
        // Near Miss
        _typeRow('Near Miss', _nearMissCount, nmPct,
            const Color(0xFFF59E0B), sl),
        const SizedBox(height: 14),
        // Total
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: sl.isDark ? Colors.white.withOpacity(0.04) : Colors.grey.withOpacity(0.06),
            borderRadius: BorderRadius.circular(8)),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('Total Reports', style: TextStyle(color: sl.text3, fontSize: 10)),
            Text('$total', style: TextStyle(color: sl.text1, fontSize: 14,
                fontWeight: FontWeight.w800)),
          ])),
      ]),
    );
  }

  Widget _typeRow(String label, int count, double pct, Color color, SL sl) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(width: 10, height: 10,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(color: sl.text2, fontSize: 11, fontWeight: FontWeight.w600)),
        const Spacer(),
        Text('$count', style: TextStyle(color: sl.text1, fontSize: 13, fontWeight: FontWeight.w800)),
      ]),
      const SizedBox(height: 4),
      Container(
        height: 6, width: double.infinity,
        decoration: BoxDecoration(
          color: sl.border.withOpacity(0.3),
          borderRadius: BorderRadius.circular(3)),
        child: FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: pct.clamp(0, 1),
          child: Container(decoration: BoxDecoration(
            color: color, borderRadius: BorderRadius.circular(3))))),
    ]);
  }

  // ═══════════════════════════════════════════════════════════════
  //  PLANT-WISE BAR CHART
  // ═══════════════════════════════════════════════════════════════
  Widget _plantBarChart(SL sl) {
    final data = _plantTypeCounts;
    if (data.isEmpty) return const SizedBox.shrink();

    final maxVal = data.values.fold<int>(0, (m, v) {
      final total = (v['AI_SCAN'] ?? 0) + (v['NEAR_MISS'] ?? 0);
      return total > m ? total : m;
    });

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: sl.card,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(
          color: Colors.black.withOpacity(sl.isDark ? 0.2 : 0.06),
          blurRadius: 8, offset: const Offset(0, 2))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.bar_chart_rounded, size: 14, color: AppColors.accent),
          const SizedBox(width: 6),
          Expanded(child: Text('AI Scan vs Near Miss by Plant',
            style: TextStyle(color: sl.text1, fontSize: 12,
                fontWeight: FontWeight.w700))),
          // Legend
          _miniLegend('AI', const Color(0xFF7B5BFF), sl),
          const SizedBox(width: 8),
          _miniLegend('NM', const Color(0xFFF59E0B), sl),
        ]),
        const SizedBox(height: 14),
        ...data.entries.map((entry) {
          final plant = entry.key;
          final aiCount = entry.value['AI_SCAN'] ?? 0;
          final nmCount = entry.value['NEAR_MISS'] ?? 0;
          final aiPct = maxVal == 0 ? 0.0 : aiCount / maxVal;
          final nmPct = maxVal == 0 ? 0.0 : nmCount / maxVal;

          // Shorten plant name for display
          String shortName = plant;
          if (plant.length > 12) {
            shortName = plant.substring(0, 12);
          }

          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(children: [
              SizedBox(width: 80, child: Text(shortName,
                style: TextStyle(color: sl.text2, fontSize: 10),
                overflow: TextOverflow.ellipsis)),
              const SizedBox(width: 8),
              Expanded(child: Column(children: [
                // AI Scan bar
                _barLine(aiPct, const Color(0xFF7B5BFF), aiCount, sl),
                const SizedBox(height: 3),
                // Near Miss bar
                _barLine(nmPct, const Color(0xFFF59E0B), nmCount, sl),
              ])),
            ]),
          );
        }).toList(),
      ]),
    );
  }

  Widget _barLine(double pct, Color color, int count, SL sl) {
    return Row(children: [
      Expanded(child: Container(
        height: 10,
        decoration: BoxDecoration(
          color: sl.border.withOpacity(0.2),
          borderRadius: BorderRadius.circular(5)),
        child: FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: pct.clamp(0.02, 1),
          child: Container(decoration: BoxDecoration(
            gradient: LinearGradient(colors: [color, color.withOpacity(0.6)]),
            borderRadius: BorderRadius.circular(5)))))),
      const SizedBox(width: 6),
      SizedBox(width: 20, child: Text('$count',
        style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w700))),
    ]);
  }

  Widget _miniLegend(String label, Color color, SL sl) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(width: 8, height: 8,
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
      const SizedBox(width: 3),
      Text(label, style: TextStyle(color: sl.text3, fontSize: 9, fontWeight: FontWeight.w600)),
    ]);
}

// ═══════════════════════════════════════════════════════════════════
//  DONUT PAINTER — draws a donut/pie chart
// ═══════════════════════════════════════════════════════════════════
class _DonutPainter extends CustomPainter {
  final List<double> values;
  final List<Color> colors;
  _DonutPainter({required this.values, required this.colors});

  @override
  void paint(Canvas canvas, Size size) {
    final total = values.fold<double>(0, (s, v) => s + v);
    if (total == 0) return;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2;
    const strokeWidth = 14.0;

    double startAngle = -math.pi / 2; // start from top

    for (int i = 0; i < values.length; i++) {
      if (values[i] == 0) continue;
      final sweepAngle = (values[i] / total) * 2 * math.pi;
      final paint = Paint()
        ..color = colors[i]
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius - strokeWidth / 2),
        startAngle,
        sweepAngle - 0.04, // small gap between segments
        false,
        paint,
      );
      startAngle += sweepAngle;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) =>
      old.values != values || old.colors != colors;
}
