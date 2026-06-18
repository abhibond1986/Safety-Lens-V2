import 'package:flutter/material.dart';
import '../../main.dart' show AppColors, SL;
import '../../services/local_db.dart';
import '../../services/analytics_engine.dart';

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

    final riskScores = AnalyticsEngine.computePlantRiskScores(_incidents);
    final risingCats = AnalyticsEngine.detectRisingCategories(_incidents);
    final hotSpots = AnalyticsEngine.predictHotSpots(_incidents);
    final dataVolume = _incidents.length;
    final confidence = dataVolume >= 50 ? 'High' : dataVolume >= 20 ? 'Medium' : 'Low';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _confidenceBanner(sl, confidence, dataVolume),
          const SizedBox(height: 20),
          _sectionTitle('Plant Risk Scores', sl),
          const SizedBox(height: 12),
          _riskScoreCards(sl, riskScores),
          const SizedBox(height: 24),
          _sectionTitle('Rising Risk Categories', sl),
          const SizedBox(height: 12),
          _risingRisksList(sl, risingCats),
          const SizedBox(height: 24),
          _sectionTitle('Predicted Hot Spots', sl),
          const SizedBox(height: 12),
          _hotSpotsList(sl, hotSpots),
        ],
      ),
    );
  }

  Widget _confidenceBanner(SL sl, String confidence, int volume) {
    final color = confidence == 'High'
        ? AppColors.green
        : confidence == 'Medium'
            ? AppColors.amber
            : AppColors.red;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.insights, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Prediction confidence: $confidence ($volume data points)',
              style: TextStyle(fontSize: 12, color: sl.text2, fontWeight: FontWeight.w500),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: color.withOpacity(0.2),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(confidence,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title, SL sl) {
    return Text(title,
        style: TextStyle(
            fontSize: 16, fontWeight: FontWeight.w600, color: sl.text1));
  }

  Widget _riskScoreCards(SL sl, Map<String, double> scores) {
    final sorted = scores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final maxScore = sorted.isNotEmpty ? sorted.first.value : 1.0;

    return Column(
      children: sorted.map((e) {
        final normalized = maxScore > 0 ? e.value / maxScore : 0.0;
        final riskLevel = normalized > 0.7
            ? 'Critical'
            : normalized > 0.4
                ? 'High'
                : normalized > 0.2
                    ? 'Medium'
                    : 'Low';
        final riskColor = normalized > 0.7
            ? AppColors.crit
            : normalized > 0.4
                ? AppColors.red
                : normalized > 0.2
                    ? AppColors.amber
                    : AppColors.green;

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
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
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(e.key,
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600,
                            color: sl.text1)),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: riskColor.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(riskLevel,
                        style: TextStyle(
                            fontSize: 10, fontWeight: FontWeight.w700,
                            color: riskColor)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: normalized,
                  minHeight: 6,
                  backgroundColor: sl.border.withOpacity(0.2),
                  valueColor: AlwaysStoppedAnimation(riskColor),
                ),
              ),
              const SizedBox(height: 4),
              Text('Score: ${e.value.toStringAsFixed(1)}',
                  style: TextStyle(fontSize: 10, color: sl.text3)),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _risingRisksList(SL sl, List<Map<String, dynamic>> rising) {
    if (rising.isEmpty) {
      return _infoCard(sl, 'No rising risk categories detected', Icons.check_circle, AppColors.green);
    }
    return Column(
      children: rising.take(5).map((r) {
        final change = r['changePercent'] as int;
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: sl.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.amber.withOpacity(0.3)),
          ),
          child: Row(
            children: [
              Icon(Icons.trending_up, size: 20, color: AppColors.amber),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r['category'].toString(),
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600,
                            color: sl.text1)),
                    Text('${r['recentCount']} incidents (last 30d) vs ${r['priorCount']} (prior 60d)',
                        style: TextStyle(fontSize: 10, color: sl.text3)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.red.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text('+$change%',
                    style: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w700,
                        color: AppColors.red)),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _hotSpotsList(SL sl, List<Map<String, dynamic>> hotSpots) {
    if (hotSpots.isEmpty) {
      return _infoCard(sl, 'No accelerating hot spots detected', Icons.shield, AppColors.green);
    }
    return Column(
      children: hotSpots.take(5).map((h) {
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: sl.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.crit.withOpacity(0.3)),
          ),
          child: Row(
            children: [
              Icon(Icons.local_fire_department, size: 20, color: AppColors.crit),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(h['plant'].toString(),
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600,
                            color: sl.text1)),
                    Text('${h['recentCount']} incidents (last 30d) — accelerating',
                        style: TextStyle(fontSize: 10, color: sl.text3)),
                  ],
                ),
              ),
              Icon(Icons.arrow_upward, size: 16, color: AppColors.crit),
              Text('${h['acceleration']}%',
                  style: const TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w700,
                      color: AppColors.crit)),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _infoCard(SL sl, String text, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(child: Text(text,
              style: TextStyle(fontSize: 12, color: sl.text2))),
        ],
      ),
    );
  }
}
