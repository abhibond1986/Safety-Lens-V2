import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../main.dart' show AppColors, SL;
import '../../services/local_db.dart';
import '../../services/analytics_engine.dart';

class ReportBuilderTab extends StatefulWidget {
  const ReportBuilderTab({super.key});

  @override
  State<ReportBuilderTab> createState() => _ReportBuilderTabState();
}

class _ReportBuilderTabState extends State<ReportBuilderTab> {
  List<Map<String, dynamic>> _incidents = [];
  bool _loading = true;

  // Filters
  String _dateRange = 'all';
  final Set<String> _selectedPlants = {};
  final Set<String> _selectedSeverities = {};
  final Set<String> _selectedCategories = {};
  final Set<String> _selectedTypes = {};
  final Set<String> _selectedStatuses = {};
  String _groupBy = 'plant';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final inc = await LocalDB.getIncidents();
    if (mounted) setState(() { _incidents = inc; _loading = false; });
  }

  List<Map<String, dynamic>> get _filtered {
    var data = AnalyticsEngine.filterByDateRange(_incidents, _dateRange);
    data = AnalyticsEngine.filterIncidents(data,
      plants: _selectedPlants.isEmpty ? null : _selectedPlants.toList(),
      severities: _selectedSeverities.isEmpty ? null : _selectedSeverities.toList(),
      categories: _selectedCategories.isEmpty ? null : _selectedCategories.toList(),
      types: _selectedTypes.isEmpty ? null : _selectedTypes.toList(),
      statuses: _selectedStatuses.isEmpty ? null : _selectedStatuses.toList(),
    );
    return data;
  }

  Set<String> get _allPlants =>
      _incidents.map((i) => i['plant']?.toString() ?? 'Unknown').toSet();
  Set<String> get _allCategories =>
      _incidents.map((i) => i['wsaCategory']?.toString() ?? 'Other').toSet();

  @override
  Widget build(BuildContext context) {
    final sl = SL.of(context);
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }

    final filtered = _filtered;
    final grouped = AnalyticsEngine.groupIncidents(filtered, _groupBy);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _filtersSection(sl),
          const SizedBox(height: 16),
          _groupBySelector(sl),
          const SizedBox(height: 16),
          _summaryRow(sl, filtered),
          const SizedBox(height: 16),
          _chartView(sl, grouped),
          const SizedBox(height: 16),
          _tableView(sl, grouped),
        ],
      ),
    );
  }

  Widget _filtersSection(SL sl) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: sl.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: sl.border.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.filter_alt_outlined, size: 16, color: sl.text3),
              const SizedBox(width: 6),
              Text('Filters', style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600, color: sl.text1)),
              const Spacer(),
              if (_hasActiveFilters)
                GestureDetector(
                  onTap: _clearFilters,
                  child: Text('Clear all',
                      style: TextStyle(fontSize: 11, color: AppColors.accent)),
                ),
            ],
          ),
          const SizedBox(height: 10),
          // Date range
          _filterLabel('Date Range', sl),
          const SizedBox(height: 4),
          _dateRangeChips(sl),
          const SizedBox(height: 10),
          // Plant
          _filterLabel('Plant', sl),
          const SizedBox(height: 4),
          _multiChips(sl, _allPlants.toList(), _selectedPlants),
          const SizedBox(height: 10),
          // Severity
          _filterLabel('Severity', sl),
          const SizedBox(height: 4),
          _multiChips(sl, ['CRITICAL', 'HIGH', 'MEDIUM', 'LOW'], _selectedSeverities),
          const SizedBox(height: 10),
          // Type
          _filterLabel('Type', sl),
          const SizedBox(height: 4),
          _multiChips(sl, ['AI_SCAN', 'NEAR_MISS'], _selectedTypes),
          const SizedBox(height: 10),
          // Status
          _filterLabel('Status', sl),
          const SizedBox(height: 4),
          _multiChips(sl, ['OPEN', 'INVESTIGATING', 'CLOSED'], _selectedStatuses),
        ],
      ),
    );
  }

  Widget _filterLabel(String label, SL sl) {
    return Text(label, style: TextStyle(fontSize: 11, color: sl.text3, fontWeight: FontWeight.w500));
  }

  Widget _dateRangeChips(SL sl) {
    const ranges = ['7d', '30d', '90d', '1yr', 'all'];
    const labels = ['7D', '30D', '90D', '1Y', 'All'];
    return Wrap(
      spacing: 6,
      children: List.generate(ranges.length, (i) {
        final selected = _dateRange == ranges[i];
        return ChoiceChip(
          label: Text(labels[i], style: TextStyle(fontSize: 10,
              color: selected ? Colors.white : sl.text3)),
          selected: selected,
          selectedColor: AppColors.accent,
          backgroundColor: sl.card2,
          side: BorderSide(color: selected ? AppColors.accent : sl.border),
          visualDensity: VisualDensity.compact,
          onSelected: (_) => setState(() => _dateRange = ranges[i]),
        );
      }),
    );
  }

  Widget _multiChips(SL sl, List<String> options, Set<String> selected) {
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: options.map((opt) {
        final isSelected = selected.contains(opt);
        return FilterChip(
          label: Text(_chipLabel(opt), style: TextStyle(fontSize: 10,
              color: isSelected ? Colors.white : sl.text3)),
          selected: isSelected,
          selectedColor: AppColors.accent,
          backgroundColor: sl.card2,
          side: BorderSide(color: isSelected ? AppColors.accent : sl.border),
          visualDensity: VisualDensity.compact,
          onSelected: (val) => setState(() {
            val ? selected.add(opt) : selected.remove(opt);
          }),
        );
      }).toList(),
    );
  }

  Widget _groupBySelector(SL sl) {
    const options = ['plant', 'category', 'severity', 'month', 'status'];
    const labels = ['Plant', 'Category', 'Severity', 'Month', 'Status'];
    return Row(
      children: [
        Text('Group by:', style: TextStyle(fontSize: 12, color: sl.text2)),
        const SizedBox(width: 10),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: List.generate(options.length, (i) {
                final selected = _groupBy == options[i];
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(labels[i], style: TextStyle(fontSize: 11,
                        color: selected ? Colors.white : sl.text2)),
                    selected: selected,
                    selectedColor: AppColors.cyan,
                    backgroundColor: sl.card2,
                    side: BorderSide(color: selected ? AppColors.cyan : sl.border),
                    visualDensity: VisualDensity.compact,
                    onSelected: (_) => setState(() => _groupBy = options[i]),
                  ),
                );
              }),
            ),
          ),
        ),
      ],
    );
  }

  Widget _summaryRow(SL sl, List<Map<String, dynamic>> filtered) {
    final total = filtered.length;
    final critical = filtered.where(
        (i) => i['severity']?.toString().toUpperCase() == 'CRITICAL').length;
    final open = filtered.where(
        (i) => i['status']?.toString().toUpperCase() == 'OPEN').length;

    return Row(
      children: [
        _summaryCard(sl, 'Total', total.toString(), AppColors.accent),
        const SizedBox(width: 8),
        _summaryCard(sl, 'Critical', critical.toString(), AppColors.crit),
        const SizedBox(width: 8),
        _summaryCard(sl, 'Open', open.toString(), AppColors.amber),
      ],
    );
  }

  Widget _summaryCard(SL sl, String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Text(value, style: TextStyle(
                fontSize: 20, fontWeight: FontWeight.w700, color: color)),
            Text(label, style: TextStyle(fontSize: 10, color: sl.text3)),
          ],
        ),
      ),
    );
  }

  Widget _chartView(SL sl, Map<String, List<Map<String, dynamic>>> grouped) {
    if (grouped.isEmpty) {
      return Container(
        height: 100,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: sl.card, borderRadius: BorderRadius.circular(12)),
        child: Text('No matching data',
            style: TextStyle(color: sl.text3, fontSize: 13)),
      );
    }

    final sorted = grouped.entries.toList()
      ..sort((a, b) => b.value.length.compareTo(a.value.length));
    final top = sorted.take(8).toList();
    final maxVal = top.isNotEmpty ? top.first.value.length : 1;

    return Container(
      height: 180,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: sl.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: sl.border.withOpacity(0.3)),
      ),
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: maxVal.toDouble() + 1,
          barGroups: List.generate(top.length, (i) => BarChartGroupData(
            x: i,
            barRods: [BarChartRodData(
              toY: top[i].value.length.toDouble(),
              color: AppColors.accent,
              width: 16,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
            )],
          )),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(showTitles: true, reservedSize: 24,
                getTitlesWidget: (v, _) => Text(v.toInt().toString(),
                    style: TextStyle(fontSize: 9, color: sl.text4))),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(showTitles: true, reservedSize: 40,
                getTitlesWidget: (v, _) {
                  final idx = v.toInt();
                  if (idx < 0 || idx >= top.length) return const SizedBox();
                  final label = top[idx].key;
                  final short = label.length > 6
                      ? '${label.substring(0, 5)}..'
                      : label;
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(short,
                        style: TextStyle(fontSize: 8, color: sl.text3),
                        textAlign: TextAlign.center),
                  );
                }),
            ),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          gridData: FlGridData(
            show: true, drawVerticalLine: false,
            getDrawingHorizontalLine: (_) => FlLine(
                color: sl.border.withOpacity(0.2), strokeWidth: 0.5),
          ),
          borderData: FlBorderData(show: false),
        ),
      ),
    );
  }

  Widget _tableView(SL sl, Map<String, List<Map<String, dynamic>>> grouped) {
    if (grouped.isEmpty) return const SizedBox();

    final sorted = grouped.entries.toList()
      ..sort((a, b) => b.value.length.compareTo(a.value.length));

    return Container(
      decoration: BoxDecoration(
        color: sl.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: sl.border.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          // Table header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: sl.card2,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                Expanded(flex: 3, child: Text(_groupBy.toUpperCase(),
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: sl.text3))),
                Expanded(flex: 1, child: Text('COUNT',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: sl.text3),
                    textAlign: TextAlign.center)),
                Expanded(flex: 1, child: Text('CRIT',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.crit),
                    textAlign: TextAlign.center)),
                Expanded(flex: 1, child: Text('OPEN',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.amber),
                    textAlign: TextAlign.center)),
              ],
            ),
          ),
          // Table rows
          ...sorted.map((entry) {
            final critical = entry.value.where(
                (i) => i['severity']?.toString().toUpperCase() == 'CRITICAL').length;
            final open = entry.value.where(
                (i) => i['status']?.toString().toUpperCase() == 'OPEN').length;
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                border: Border(
                    bottom: BorderSide(color: sl.border.withOpacity(0.15))),
              ),
              child: Row(
                children: [
                  Expanded(flex: 3, child: Text(entry.key,
                      style: TextStyle(fontSize: 11, color: sl.text1),
                      overflow: TextOverflow.ellipsis)),
                  Expanded(flex: 1, child: Text('${entry.value.length}',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: sl.text1),
                      textAlign: TextAlign.center)),
                  Expanded(flex: 1, child: Text('$critical',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                          color: critical > 0 ? AppColors.crit : sl.text4),
                      textAlign: TextAlign.center)),
                  Expanded(flex: 1, child: Text('$open',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                          color: open > 0 ? AppColors.amber : sl.text4),
                      textAlign: TextAlign.center)),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  bool get _hasActiveFilters =>
      _dateRange != 'all' ||
      _selectedPlants.isNotEmpty ||
      _selectedSeverities.isNotEmpty ||
      _selectedCategories.isNotEmpty ||
      _selectedTypes.isNotEmpty ||
      _selectedStatuses.isNotEmpty;

  void _clearFilters() {
    setState(() {
      _dateRange = 'all';
      _selectedPlants.clear();
      _selectedSeverities.clear();
      _selectedCategories.clear();
      _selectedTypes.clear();
      _selectedStatuses.clear();
    });
  }

  String _chipLabel(String s) {
    if (s.length <= 12) return s;
    return '${s.substring(0, 10)}..';
  }
}
