import 'dart:ui';
import 'package:flutter/material.dart';
import '../main.dart' show AppColors, SL;
import 'analytics/overview_tab.dart';
import 'analytics/incident_log_tab.dart';
import 'analytics/data_analysis_tab.dart';
import 'analytics/plant_wise_tab.dart';

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
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Column(
          children: [
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
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: sl.glassColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: sl.glassBorder),
                  ),
                  child: TabBar(
                    controller: _tabController,
                    labelColor: Colors.white,
                    unselectedLabelColor: sl.text3,
                    labelStyle: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w700),
                    unselectedLabelStyle: const TextStyle(fontSize: 11),
                    indicator: BoxDecoration(
                      color: AppColors.accent,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    indicatorSize: TabBarIndicatorSize.tab,
                    dividerColor: Colors.transparent,
                    isScrollable: false,
                    padding: const EdgeInsets.all(3),
                    tabs: const [
                      Tab(text: 'Overview'),
                      Tab(text: 'Log'),
                      Tab(text: 'Analysis'),
                      Tab(text: 'Plant Wise'),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: const [
                  OverviewTab(),
                  IncidentLogTab(),
                  DataAnalysisTab(),
                  PlantWiseTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
