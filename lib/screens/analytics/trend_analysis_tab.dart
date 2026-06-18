import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../main.dart' show AppColors, SL;
import '../../services/local_db.dart';
import '../../services/analytics_engine.dart';

class TrendAnalysisTab extends StatefulWidget {
  const TrendAnalysisTab({super.key});

  @override
  State<TrendAnalysisTab> createState() => _TrendAnalysisTabState();
}

class _TrendAnalysisTabState extends State<TrendAnalysisTab> {
  List<Map<String, dynamic>> _incidents = [];
  bool _loading = true;
  String _range = '30d';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final inc = await LocalDB.getIncidents();
    if (mounted) setState(() { _incidents = inc; _loading = false; });
  }

  List<Map<String, dynamic>> get _filtered =>
      AnalyticsEngine.filterByDateRange(_incidents, _range);

  String get _bucket => AnalyticsEngine.bestBucketSize(_range);

  @override
  Widget build(BuildContext context) {
    final sl = SL.of(context);
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _dateRangeSelector(sl),
          const SizedBox(height: 20),
          _sectionTitle('Incident Volume Over Time', sl),
          const SizedBox(height: 12),
          _volumeChart(sl),
          const SizedBox(height: 28),
          _sectionTitle('Severity Breakdown Over Time', sl),
          const SizedBox(height: 12),
          _severityChart(sl),
          const SizedBox(height: 28),
          _sectionTitle('Top Categories Trend', sl),
          const SizedBox(height: 12),
          _categoryTrendBars(sl),
        ],
      ),
    );
  }

  Widget _dateRangeSelector(SL sl) {
    const ranges = ['7d', '30d', '90d', '1yr', 'all'];
    const labels = ['7 Days', '30 Days', '90 Days', '1 Year', 'All'];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: List.generate(ranges.length, (i) {
          final selected = _range == ranges[i];
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(labels[i],
                  style: TextStyle(
                    fontSize: 12,
                    color: selected ? Colors.white : sl.text2,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                  )),
              selected: selected,
              selectedColor: AppColors.accent,
              backgroundColor: sl.card2,
              side: BorderSide(
                  color: selected ? AppColors.accent : sl.border),
              onSelected: (_) => setState(() => _range = ranges[i]),
            ),
          );
        }),
      ),
    );
  }

  Widget _sectionTitle(String title, SL sl) {
    return Text(title,
        style: TextStyle(
          fontSize: 16, fontWeight: FontWeight.w600, color: sl.text1));
  }

  Widget _volumeChart(SL sl) {
    final data = AnalyticsEngine.getIncidentsByTimeBucket(_filtered, _bucket);
    if (data.isEmpty) return _emptyState(sl);

    final spots = <FlSpot>[];
    for (int i = 0; i < data.length; i++) {
      spots.add(FlSpot(i.toDouble(), (data[i]['count'] as int).toDouble()));
    }

    return Container(
      height: 200,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: sl.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: sl.border.withOpacity(0.3)),
      ),
      child: LineChart(
        LineChartData(
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: 1,
            getDrawingHorizontalLine: (_) => FlLine(
              color: sl.border.withOpacity(0.2), strokeWidth: 0.5),
          ),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true, reservedSize: 30,
                getTitlesWidget: (v, _) => Text(
                  v.toInt().toString(),
                  style: TextStyle(fontSize: 10, color: sl.text3),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true, reservedSize: 28,
                interval: (data.length / 5).ceilToDouble().clamp(1, 100),
                getTitlesWidget: (v, _) {
                  final idx = v.toInt();
                  if (idx < 0 || idx >= data.length) return const SizedBox();
                  final label = data[idx]['bucket'].toString();
                  final short = label.length > 5
                      ? label.substring(label.length - 5)
                      : label;
                  return Text(short,
                      style: TextStyle(fontSize: 9, color: sl.text4));
                },
              ),
            ),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(show: false),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              color: AppColors.accent,
              barWidth: 2.5,
              dotData: FlDotData(
                show: spots.length <= 15,
                getDotPainter: (_, __, ___, ____) => FlDotCirclePainter(
                  radius: 3, color: AppColors.accent,
                  strokeWidth: 1.5, strokeColor: Colors.white),
              ),
              belowBarData: BarAreaData(
                show: true,
                color: AppColors.accent.withOpacity(0.15),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _severityChart(SL sl) {
    final trend = AnalyticsEngine.getSeverityTrend(_filtered, _bucket);
    final allBuckets = <String>{};
    for (final entry in trend.values) {
      for (final b in entry) {
        allBuckets.add(b['bucket'].toString());
      }
    }
    final sortedBuckets = allBuckets.toList()..sort();
    if (sortedBuckets.isEmpty) return _emptyState(sl);

    final sevColors = {
      'CRITICAL': AppColors.crit,
      'HIGH': AppColors.red,
      'MEDIUM': AppColors.amber,
      'LOW': AppColors.green,
    };

    List<FlSpot> spotsForSeverity(String sev) {
      final data = trend[sev] ?? [];
      final bucketMap = <String, int>{};
      for (final d in data) bucketMap[d['bucket'].toString()] = d['count'] as int;
      return List.generate(sortedBuckets.length,
          (i) => FlSpot(i.toDouble(),
              (bucketMap[sortedBuckets[i]] ?? 0).toDouble()));
    }

    return Container(
      height: 200,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: sl.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: sl.border.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: sevColors.entries.map((e) => Padding(
              padding: const EdgeInsets.only(left: 10),
              child: Row(children: [
                Container(width: 8, height: 8,
                    decoration: BoxDecoration(
                        color: e.value, shape: BoxShape.circle)),
                const SizedBox(width: 4),
                Text(e.key[0] + e.key.substring(1).toLowerCase(),
                    style: TextStyle(fontSize: 9, color: sl.text3)),
              ]),
            )).toList(),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: LineChart(
              LineChartData(
                gridData: FlGridData(show: false),
                titlesData: const FlTitlesData(show: false),
                borderData: FlBorderData(show: false),
                lineBarsData: sevColors.entries.map((e) => LineChartBarData(
                  spots: spotsForSeverity(e.key),
                  isCurved: true,
                  color: e.value,
                  barWidth: 2,
                  dotData: const FlDotData(show: false),
                  belowBarData: BarAreaData(
                    show: true, color: e.value.withOpacity(0.08)),
                )).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _categoryTrendBars(SL sl) {
    final catTrend = AnalyticsEngine.getCategoryTrend(_filtered, _bucket);
    final catCounts = <String, int>{};
    for (final entry in catTrend.entries) {
      int total = 0;
      for (final b in entry.value) total += b['count'] as int;
      catCounts[entry.key] = total;
    }
    final sorted = catCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top = sorted.take(6).toList();
    if (top.isEmpty) return _emptyState(sl);
    final maxVal = top.first.value;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: sl.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: sl.border.withOpacity(0.3)),
      ),
      child: Column(
        children: top.map((e) {
          final fraction = maxVal > 0 ? e.value / maxVal : 0.0;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                SizedBox(
                  width: 110,
                  child: Text(e.key,
                      style: TextStyle(fontSize: 11, color: sl.text2),
                      overflow: TextOverflow.ellipsis),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: fraction,
                    child: Container(
                      height: 18,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(4),
                        gradient: const LinearGradient(colors: [
                          AppColors.accent, AppColors.cyan]),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text('${e.value}',
                    style: TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w600,
                        color: sl.text1)),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _emptyState(SL sl) {
    return Container(
      height: 120,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: sl.card,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text('No data for selected period',
          style: TextStyle(color: sl.text3, fontSize: 13)),
    );
  }
}
