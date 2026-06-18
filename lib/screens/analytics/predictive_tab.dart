import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../main.dart' show AppColors, SL;
import '../../services/local_db.dart';

class PredictiveTab extends StatefulWidget {
  const PredictiveTab({super.key});

  @override
  State<PredictiveTab> createState() => _PredictiveTabState();
}

class _PredictiveTabState extends State<PredictiveTab> {
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

  /// Top 5 hazard categories per plant
  Map<String, List<MapEntry<String, int>>> get _top5PerPlant {
    final plantCats = <String, Map<String, int>>{};
    for (final i in _incidents) {
      final plant = i['plant']?.toString() ?? 'Unknown';
      final cat = i['wsaCategory']?.toString() ?? 'Other';
      plantCats.putIfAbsent(plant, () => <String, int>{});
      plantCats[plant]![cat] = (plantCats[plant]![cat] ?? 0) + 1;
    }

    final result = <String, List<MapEntry<String, int>>>{};
    for (final entry in plantCats.entries) {
      final sorted = entry.value.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      result[entry.key] = sorted.take(5).toList();
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final sl = SL.of(context);
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (_incidents.isEmpty) {
      return Center(child: Text('No data available',
          style: TextStyle(color: sl.text3, fontSize: 14)));
    }

    final top5Data = _top5PerPlant;
    final plants = top5Data.keys.toList()..sort();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Top 5 Hazards per Plant',
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w700, color: sl.text1)),
          const SizedBox(height: 4),
          Text('Predicted high-risk categories based on recorded incidents',
              style: TextStyle(fontSize: 11, color: sl.text3)),
          const SizedBox(height: 16),
          ...plants.map((plant) => _plantSection(sl, plant, top5Data[plant]!)),
        ],
      ),
    );
  }

  Widget _plantSection(SL sl, String plant, List<MapEntry<String, int>> top5) {
    if (top5.isEmpty) return const SizedBox();
    final maxVal = top5.first.value;
    final total = top5.fold<int>(0, (s, e) => s + e.value);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: sl.glassColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: sl.glassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Plant header
          Row(children: [
            Icon(Icons.factory_outlined, size: 16, color: AppColors.accent),
            const SizedBox(width: 6),
            Expanded(child: Text(plant,
                style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w700, color: sl.text1))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.accent.withOpacity(0.1),
                borderRadius: BorderRadius.circular(6)),
              child: Text('$total incidents',
                  style: const TextStyle(
                      fontSize: 10, fontWeight: FontWeight.w600,
                      color: AppColors.accent)),
            ),
          ]),
          const SizedBox(height: 14),

          // Pie chart + legend row
          Row(
            children: [
              SizedBox(
                width: 90, height: 90,
                child: PieChart(PieChartData(
                  sections: List.generate(top5.length, (i) {
                    return PieChartSectionData(
                      value: top5[i].value.toDouble(),
                      color: _barColors[i % _barColors.length],
                      radius: 18,
                      title: '',
                    );
                  }),
                  centerSpaceRadius: 18,
                  sectionsSpace: 1.5,
                )),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: List.generate(top5.length, (i) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(children: [
                        Container(width: 8, height: 8,
                            decoration: BoxDecoration(
                                color: _barColors[i % _barColors.length],
                                borderRadius: BorderRadius.circular(2))),
                        const SizedBox(width: 5),
                        Expanded(child: Text(top5[i].key,
                            style: TextStyle(fontSize: 10, color: sl.text2),
                            overflow: TextOverflow.ellipsis)),
                        Text('${top5[i].value}',
                            style: TextStyle(fontSize: 10,
                                fontWeight: FontWeight.w700, color: sl.text1)),
                      ]),
                    );
                  }),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Bar chart
          ...List.generate(top5.length, (i) {
            final fraction = maxVal > 0 ? top5[i].value / maxVal : 0.0;
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(children: [
                SizedBox(width: 14,
                    child: Text('${i + 1}',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                            color: _barColors[i % _barColors.length]))),
                const SizedBox(width: 6),
                Expanded(
                  child: Stack(children: [
                    Container(
                      height: 16,
                      decoration: BoxDecoration(
                        color: sl.border.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(4)),
                    ),
                    FractionallySizedBox(
                      widthFactor: fraction.clamp(0.05, 1.0),
                      child: Container(
                        height: 16,
                        decoration: BoxDecoration(
                          color: _barColors[i % _barColors.length],
                          borderRadius: BorderRadius.circular(4)),
                      ),
                    ),
                  ]),
                ),
                const SizedBox(width: 6),
                Text('${top5[i].value}',
                    style: TextStyle(fontSize: 10,
                        fontWeight: FontWeight.w700, color: sl.text1)),
              ]),
            );
          }),
        ],
      ),
    );
  }

  static const _barColors = [
    AppColors.crit,
    AppColors.amber,
    AppColors.accent,
    AppColors.cyan,
    AppColors.green,
  ];
}
