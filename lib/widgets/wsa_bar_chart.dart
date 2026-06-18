// lib/widgets/wsa_bar_chart.dart
// WSA-13 Bar Chart widget for the dashboard.
// Shows count of incidents by WSA category with a plant filter dropdown.
// Filter options: "Entire SAIL" or individual plants.

import 'package:flutter/material.dart';
import '../main.dart' show AppColors, SL;
import '../services/i18n.dart';
import '../services/local_db.dart';

class WsaBarChart extends StatefulWidget {
  const WsaBarChart({super.key});

  @override
  State<WsaBarChart> createState() => _WsaBarChartState();
}

class _WsaBarChartState extends State<WsaBarChart> {
  List<Map<String, dynamic>> _incidents = [];
  String _selectedPlant = 'all'; // 'all' = Entire SAIL
  bool _loading = true;

  // All 13 WSA categories
  static const List<Map<String, String>> wsaCategories = [
    {'key': 'wsa.fallFromHeight',   'match': 'Fall from Height'},
    {'key': 'wsa.slipFall',         'match': 'Slip / Fall'},
    {'key': 'wsa.hitCaughtPressed', 'match': 'Hit / Caught / Pressed'},
    {'key': 'wsa.hotMetalSlag',     'match': 'Hot Metal / Slag'},
    {'key': 'wsa.electrical',       'match': 'Electrical'},
    {'key': 'wsa.gas',              'match': 'Gas'},
    {'key': 'wsa.explosion',        'match': 'Explosion'},
    {'key': 'wsa.machinery',        'match': 'Machinery'},
    {'key': 'wsa.transport',        'match': 'Transport'},
    {'key': 'wsa.confinedSpace',    'match': 'Confined Space'},
    {'key': 'wsa.chemical',         'match': 'Chemical'},
    {'key': 'wsa.ergonomic',        'match': 'Ergonomic'},
    {'key': 'wsa.other',            'match': 'Other'},
  ];

  static const List<Map<String, String>> _plants = [
    {'code': 'all',  'name': 'Entire SAIL'},
    {'code': 'BSP',  'name': 'BSP — Bhilai'},
    {'code': 'DSP',  'name': 'DSP — Durgapur'},
    {'code': 'RSP',  'name': 'RSP — Rourkela'},
    {'code': 'BSL',  'name': 'BSL — Bokaro'},
    {'code': 'ISP',  'name': 'ISP — Burnpur'},
    {'code': 'ASP',  'name': 'ASP — Durgapur'},
    {'code': 'SSP',  'name': 'SSP — Salem'},
    {'code': 'CFP',  'name': 'CFP — Chandrapur'},
  ];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final inc = await LocalDB.getIncidents();
    if (mounted) setState(() { _incidents = inc; _loading = false; });
  }

  List<Map<String, dynamic>> get _filteredIncidents {
    if (_selectedPlant == 'all') return _incidents;
    return _incidents.where((i) {
      final plant = (i['plant']?.toString() ?? '').toUpperCase();
      return plant.contains(_selectedPlant.toUpperCase());
    }).toList();
  }

  Map<String, int> get _wsaCounts {
    final filtered = _filteredIncidents;
    final counts = <String, int>{};
    for (final cat in wsaCategories) {
      final matchStr = cat['match']!.toLowerCase();
      counts[cat['key']!] = filtered.where((i) {
        final wsa = (i['wsaCategory']?.toString() ?? '').toLowerCase();
        // Flexible matching: check if WSA category contains the match string
        // or the match string contains the WSA category
        return wsa.contains(matchStr) || matchStr.contains(wsa) ||
               _fuzzyMatch(wsa, matchStr);
      }).length;
    }
    return counts;
  }

  bool _fuzzyMatch(String a, String b) {
    // Match keywords: e.g. "fall" matches "Fall from Height"
    final words = b.split(RegExp(r'[\s/]+'));
    for (final w in words) {
      if (w.length > 2 && a.contains(w)) return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final sl = SL.of(context);

    if (_loading) {
      return Container(
        padding: const EdgeInsets.all(24),
        child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    final counts = _wsaCounts;
    final maxCount = counts.values.fold(0, (a, b) => a > b ? a : b);
    final totalFiltered = _filteredIncidents.length;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: sl.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: sl.border),
        boxShadow: [BoxShadow(
          color: Colors.black.withOpacity(sl.isDark ? 0.2 : 0.06),
          blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with title + filter
          Row(children: [
            Icon(Icons.bar_chart_rounded, color: AppColors.accent, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text(
              I18n.t('dashboard.wsaChart'),
              style: TextStyle(color: sl.text1, fontSize: 15,
                fontWeight: FontWeight.w700))),
            // Plant filter dropdown
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.accent.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.accent.withOpacity(0.3))),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedPlant,
                  isDense: true,
                  dropdownColor: sl.card,
                  style: TextStyle(color: AppColors.accent, fontSize: 11,
                    fontWeight: FontWeight.w600),
                  icon: Icon(Icons.arrow_drop_down,
                    color: AppColors.accent, size: 16),
                  items: _plants.map((p) => DropdownMenuItem(
                    value: p['code'],
                    child: Text(
                      p['code'] == 'all'
                        ? I18n.t('dashboard.entireSail')
                        : p['name']!,
                      style: TextStyle(color: sl.text1, fontSize: 11)),
                  )).toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => _selectedPlant = val);
                  },
                ),
              ),
            ),
          ]),

          const SizedBox(height: 4),
          Text(
            '${I18n.t('home.totalCases')}: $totalFiltered',
            style: TextStyle(color: sl.text3, fontSize: 11)),
          const SizedBox(height: 16),

          // Bar chart
          ...wsaCategories.map((cat) {
            final count = counts[cat['key']!] ?? 0;
            final fraction = maxCount > 0 ? count / maxCount : 0.0;
            final barColor = _barColor(count, maxCount);

            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                // Category label
                SizedBox(
                  width: 90,
                  child: Text(
                    I18n.t(cat['key']!),
                    style: TextStyle(color: sl.text2, fontSize: 10,
                      fontWeight: FontWeight.w500),
                    maxLines: 1, overflow: TextOverflow.ellipsis)),
                const SizedBox(width: 8),
                // Bar
                Expanded(
                  child: Stack(
                    children: [
                      Container(
                        height: 20,
                        decoration: BoxDecoration(
                          color: sl.card2,
                          borderRadius: BorderRadius.circular(4))),
                      FractionallySizedBox(
                        widthFactor: fraction.clamp(0.0, 1.0),
                        child: Container(
                          height: 20,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [barColor.withOpacity(0.8), barColor]),
                            borderRadius: BorderRadius.circular(4)),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Count
                SizedBox(
                  width: 24,
                  child: Text(
                    '$count',
                    style: TextStyle(color: sl.text1, fontSize: 11,
                      fontWeight: FontWeight.w700),
                    textAlign: TextAlign.right)),
              ]),
            );
          }),
        ],
      ),
    );
  }

  Color _barColor(int count, int max) {
    if (count == 0) return AppColors.green;
    final ratio = max > 0 ? count / max : 0.0;
    if (ratio > 0.7) return AppColors.red;
    if (ratio > 0.4) return AppColors.amber;
    return AppColors.cyan;
  }
}
