import 'package:flutter/material.dart';
import '../main.dart' show AppColors, SL;
import 'analytics/trend_analysis_tab.dart';
import 'analytics/predictive_tab.dart';
import 'analytics/heat_map_tab.dart';
import 'analytics/report_builder_tab.dart';

class ReportsTab extends StatefulWidget {
  final Map<String, dynamic>? user;
  final VoidCallback toggleTheme;
  final VoidCallback onSignOut;
  final bool isDark;

  static String? pendingStatusFilter;
  static String? pendingSeverityFilter;

  const ReportsTab({
    super.key,
    required this.user,
    required this.toggleTheme,
    required this.onSignOut,
    required this.isDark,
  });

  @override
  State<ReportsTab> createState() => _ReportsTabState();
}

class _ReportsTabState extends State<ReportsTab>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sl = SL.of(context);
    return Scaffold(
      backgroundColor: sl.bg,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  Icon(Icons.analytics_rounded, size: 22, color: AppColors.accent),
                  const SizedBox(width: 8),
                  Text('Analytics & Reports',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: sl.text1,
                      )),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // Tab bar
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: sl.card,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: sl.border.withOpacity(0.3)),
              ),
              child: TabBar(
                controller: _tabController,
                isScrollable: true,
                labelColor: Colors.white,
                unselectedLabelColor: sl.text3,
                labelStyle: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600),
                unselectedLabelStyle: const TextStyle(fontSize: 12),
                indicator: BoxDecoration(
                  color: AppColors.accent,
                  borderRadius: BorderRadius.circular(10),
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                dividerColor: Colors.transparent,
                padding: const EdgeInsets.all(4),
                labelPadding:
                    const EdgeInsets.symmetric(horizontal: 14),
                tabs: const [
                  Tab(text: 'Trends'),
                  Tab(text: 'Predictive'),
                  Tab(text: 'Heat Map'),
                  Tab(text: 'Builder'),
                ],
              ),
            ),
            const SizedBox(height: 8),
            // Tab content
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: const [
                  TrendAnalysisTab(),
                  PredictiveTab(),
                  HeatMapTab(),
                  ReportBuilderTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
