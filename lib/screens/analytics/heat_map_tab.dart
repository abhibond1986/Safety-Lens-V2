import 'package:flutter/material.dart';
import '../../main.dart' show AppColors, SL;
import '../../services/local_db.dart';
import '../../services/analytics_engine.dart';

class HeatMapTab extends StatefulWidget {
  const HeatMapTab({super.key});

  @override
  State<HeatMapTab> createState() => _HeatMapTabState();
}

class _HeatMapTabState extends State<HeatMapTab> {
  List<Map<String, dynamic>> _incidents = [];
  bool _loading = true;
  bool _showBySeverity = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final inc = await LocalDB.getIncidents();
    if (mounted) setState(() { _incidents = inc; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    final sl = SL.of(context);
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (_incidents.isEmpty) {
      return Center(child: Text('No data available',
          style: TextStyle(color: sl.text3)));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _toggleRow(sl),
          const SizedBox(height: 16),
          _showBySeverity ? _severityHeatMap(sl) : _categoryHeatMap(sl),
          const SizedBox(height: 16),
          _legend(sl),
        ],
      ),
    );
  }

  Widget _toggleRow(SL sl) {
    return Row(
      children: [
        Text('View by:', style: TextStyle(fontSize: 13, color: sl.text2)),
        const SizedBox(width: 10),
        ChoiceChip(
          label: Text('Category', style: TextStyle(fontSize: 12,
              color: !_showBySeverity ? Colors.white : sl.text2)),
          selected: !_showBySeverity,
          selectedColor: AppColors.accent,
          backgroundColor: sl.card2,
          side: BorderSide(color: !_showBySeverity ? AppColors.accent : sl.border),
          onSelected: (_) => setState(() => _showBySeverity = false),
        ),
        const SizedBox(width: 8),
        ChoiceChip(
          label: Text('Severity', style: TextStyle(fontSize: 12,
              color: _showBySeverity ? Colors.white : sl.text2)),
          selected: _showBySeverity,
          selectedColor: AppColors.accent,
          backgroundColor: sl.card2,
          side: BorderSide(color: _showBySeverity ? AppColors.accent : sl.border),
          onSelected: (_) => setState(() => _showBySeverity = true),
        ),
      ],
    );
  }

  Widget _categoryHeatMap(SL sl) {
    final matrix = AnalyticsEngine.buildHeatMapMatrix(_incidents);
    final plants = matrix.keys.toList()..sort();
    final categories = <String>{};
    for (final row in matrix.values) {
      categories.addAll(row.keys);
    }
    final cols = categories.toList()..sort();

    int maxCount = 0;
    for (final row in matrix.values) {
      for (final v in row.values) {
        if (v > maxCount) maxCount = v;
      }
    }

    return _buildGrid(sl, plants, cols, matrix, maxCount);
  }

  Widget _severityHeatMap(SL sl) {
    final matrix = AnalyticsEngine.buildSeverityHeatMap(_incidents);
    final plants = matrix.keys.toList()..sort();
    const cols = ['CRITICAL', 'HIGH', 'MEDIUM', 'LOW'];

    int maxCount = 0;
    for (final row in matrix.values) {
      for (final v in row.values) {
        if (v > maxCount) maxCount = v;
      }
    }

    return _buildGrid(sl, plants, cols, matrix, maxCount);
  }

  Widget _buildGrid(SL sl, List<String> rows, List<String> cols,
      Map<String, Map<String, int>> matrix, int maxCount) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              SizedBox(width: 90, child: Text('Plant',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: sl.text2))),
              ...cols.map((c) => SizedBox(
                width: 70,
                child: RotatedBox(
                  quarterTurns: -1,
                  child: Text(_shortLabel(c),
                      style: TextStyle(fontSize: 9, color: sl.text3),
                      overflow: TextOverflow.ellipsis),
                ),
              )),
            ],
          ),
          const SizedBox(height: 4),
          // Data rows
          ...rows.map((plant) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Row(
                children: [
                  SizedBox(
                    width: 90,
                    child: Text(_shortPlant(plant),
                        style: TextStyle(fontSize: 10, color: sl.text2),
                        overflow: TextOverflow.ellipsis),
                  ),
                  ...cols.map((col) {
                    final count = matrix[plant]?[col] ?? 0;
                    final color = AnalyticsEngine.heatColor(count, maxCount);
                    return GestureDetector(
                      onTap: () => _showCellDetail(plant, col, count),
                      child: Container(
                        width: 66,
                        height: 32,
                        margin: const EdgeInsets.only(right: 4),
                        decoration: BoxDecoration(
                          color: count == 0
                              ? sl.card2
                              : color,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                              color: sl.border.withOpacity(0.2), width: 0.5),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          count > 0 ? count.toString() : '-',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: count > 0
                                ? (count / maxCount > 0.5
                                    ? Colors.white
                                    : Colors.black87)
                                : sl.text4,
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  void _showCellDetail(String plant, String column, int count) {
    if (count == 0) return;
    final filtered = _incidents.where((i) {
      final matchPlant = i['plant']?.toString() == plant;
      final matchCol = _showBySeverity
          ? i['severity']?.toString().toUpperCase() == column
          : i['wsaCategory']?.toString() == column;
      return matchPlant && matchCol;
    }).toList();

    showModalBottomSheet(
      context: context,
      backgroundColor: SL.of(context).card,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) {
        final sl = SL.of(ctx);
        return Container(
          constraints: const BoxConstraints(maxHeight: 400),
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$plant — $column',
                  style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700, color: sl.text1)),
              Text('$count incident(s)',
                  style: TextStyle(fontSize: 12, color: sl.text3)),
              const SizedBox(height: 12),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: filtered.length,
                  itemBuilder: (_, i) {
                    final inc = filtered[i];
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(inc['title']?.toString() ?? '',
                          style: TextStyle(fontSize: 12, color: sl.text1)),
                      subtitle: Text(inc['date']?.toString().split('T').first ?? '',
                          style: TextStyle(fontSize: 10, color: sl.text3)),
                      trailing: _severityBadge(inc['severity']?.toString() ?? ''),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _severityBadge(String severity) {
    final color = severity == 'CRITICAL'
        ? AppColors.crit
        : severity == 'HIGH'
            ? AppColors.red
            : severity == 'MEDIUM'
                ? AppColors.amber
                : AppColors.green;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(severity,
          style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: color)),
    );
  }

  Widget _legend(SL sl) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: sl.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: sl.border.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('Low', style: TextStyle(fontSize: 10, color: sl.text3)),
          const SizedBox(width: 6),
          ...List.generate(5, (i) {
            final colors = [
              const Color(0xFFFFF9C4),
              const Color(0xFFFFD54F),
              const Color(0xFFFFB74D),
              const Color(0xFFFF8A65),
              const Color(0xFFE53935),
            ];
            return Container(
              width: 24, height: 14,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                color: colors[i],
                borderRadius: BorderRadius.circular(3),
              ),
            );
          }),
          const SizedBox(width: 6),
          Text('High', style: TextStyle(fontSize: 10, color: sl.text3)),
        ],
      ),
    );
  }

  String _shortLabel(String label) {
    if (label.length <= 12) return label;
    return '${label.substring(0, 10)}..';
  }

  String _shortPlant(String plant) {
    final parts = plant.split(' ');
    return parts.first;
  }
}
