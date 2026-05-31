import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../main.dart';
import '../services/local_db.dart';
import '../services/pdf_export.dart';

class ReportsTab extends StatefulWidget {
  const ReportsTab({super.key});

  @override
  State<ReportsTab> createState() => _ReportsTabState();
}

class _ReportsTabState extends State<ReportsTab> {
  List<Map<String, dynamic>> _incidents = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await LocalDB.getIncidents();
    if (!mounted) return;
    setState(() => _incidents = list);
  }

  Future<void> _generateIndividualPdf(Map<String, dynamic> inc) async {
    final user = await LocalDB.getCurrentUser();
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Generating PDF...'), duration: Duration(seconds: 1)),
      );
      await PdfExport.downloadOrShareIncident(
        incident: inc,
        reporterName: user?['name']?.toString() ?? 'SAIL Safety Officer',
        reporterPno: user?['pno']?.toString() ?? '',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(kIsWeb ? 'PDF downloaded' : 'PDF ready to share'),
            backgroundColor: AppColors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('PDF failed: $e'), backgroundColor: AppColors.red),
      );
    }
  }

  /// Get user-friendly type label from incident data
  String _getTypeLabel(Map<String, dynamic> inc) {
    final type = inc['type']?.toString().toUpperCase() ?? '';
    final obsType = inc['obsType']?.toString() ?? '';
    if (type == 'AI_SCAN') return 'AI SCAN';
    if (type == 'NEAR_MISS') {
      if (obsType.toLowerCase().contains('act')) return 'NEAR MISS / UNSAFE ACT';
      if (obsType.toLowerCase().contains('condition')) return 'NEAR MISS / UNSAFE COND';
      return 'NEAR MISS';
    }
    return type.isEmpty ? 'OTHER' : type;
  }

  Color _getTypeColor(Map<String, dynamic> inc) {
    final type = inc['type']?.toString().toUpperCase() ?? '';
    if (type == 'AI_SCAN') return AppColors.accent;
    if (type == 'NEAR_MISS') return AppColors.amber;
    return AppColors.text3;
  }

  @override
  Widget build(BuildContext context) {
    final critical = _incidents.where((i) => i['severity'] == 'CRITICAL').length;
    final high = _incidents.where((i) => i['severity'] == 'HIGH').length;
    final medium = _incidents.where((i) => i['severity'] == 'MEDIUM').length;
    final low = _incidents.where((i) => i['severity'] == 'LOW').length;

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          Row(children: [
            const Expanded(child: Text('All Reports',
              style: TextStyle(color: AppColors.text1, fontSize: 18, fontWeight: FontWeight.w700))),
            Text('${_incidents.length} total',
              style: const TextStyle(color: AppColors.text3, fontSize: 11)),
          ]),
          const SizedBox(height: 12),
          _statRow(critical, high, medium, low),
          const SizedBox(height: 16),

          if (_incidents.isEmpty)
            Container(
              padding: const EdgeInsets.all(40),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: const Column(children: [
                Icon(Icons.inbox_outlined, size: 48, color: AppColors.text4),
                SizedBox(height: 12),
                Text('No reports yet',
                  style: TextStyle(color: AppColors.text3, fontSize: 13, fontWeight: FontWeight.w600)),
              ]),
            )
          else ...[
            _reportTable(),
          ],
        ],
      ),
    );
  }

  Widget _statRow(int cr, int hi, int me, int lo) {
    Widget chip(int val, String lbl, Color color) => Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 3),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          border: Border.all(color: color),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(children: [
          Text('$val', style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.w700)),
          Text(lbl, style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
    return Row(children: [
      chip(cr, 'CRITICAL', AppColors.crit),
      chip(hi, 'HIGH', AppColors.red),
      chip(me, 'MEDIUM', AppColors.cyan),
      chip(lo, 'LOW', AppColors.green),
    ]);
  }

  Widget _reportTable() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: const BoxDecoration(
            color: AppColors.card2,
            borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
          ),
          child: const Row(children: [
            Expanded(flex: 4, child: Text('REPORT',
              style: TextStyle(color: AppColors.text3, fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 0.5))),
            Expanded(flex: 3, child: Text('TYPE',
              style: TextStyle(color: AppColors.text3, fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 0.5))),
            Expanded(flex: 2, child: Text('SEVERITY',
              style: TextStyle(color: AppColors.text3, fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 0.5))),
            SizedBox(width: 36, child: Text('PDF',
              style: TextStyle(color: AppColors.text3, fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 0.5),
              textAlign: TextAlign.center)),
          ]),
        ),
        ..._incidents.map((inc) => _reportRow(inc)).toList(),
      ]),
    );
  }

  Widget _reportRow(Map<String, dynamic> inc) {
    final sev = inc['severity']?.toString() ?? 'MEDIUM';
    Color sevColor;
    switch (sev) {
      case 'CRITICAL': sevColor = AppColors.crit; break;
      case 'HIGH': sevColor = AppColors.red; break;
      case 'MEDIUM': sevColor = AppColors.cyan; break;
      default: sevColor = AppColors.green;
    }

    final dateStr = inc['date'] != null
      ? DateFormat('dd MMM, HH:mm').format(DateTime.parse(inc['date']))
      : '';

    final typeLabel = _getTypeLabel(inc);
    final typeColor = _getTypeColor(inc);

    return InkWell(
      onTap: () => _showIncidentDetail(inc),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.border, width: 0.5)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Expanded(flex: 4, child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(inc['title']?.toString() ?? 'Untitled',
                style: const TextStyle(color: AppColors.text1, fontSize: 11, fontWeight: FontWeight.w600),
                maxLines: 1, overflow: TextOverflow.ellipsis),
              Text('${inc['plant'] ?? ''} · $dateStr',
                style: const TextStyle(color: AppColors.text4, fontSize: 9),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          )),
          Expanded(flex: 3, child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
              decoration: BoxDecoration(
                color: typeColor.withOpacity(0.15),
                border: Border.all(color: typeColor, width: 1),
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text(typeLabel,
                style: TextStyle(color: typeColor, fontSize: 7, fontWeight: FontWeight.w700, height: 1.2),
                maxLines: 2, overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center),
            ),
          )),
          Expanded(flex: 2, child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            decoration: BoxDecoration(
              color: sevColor.withOpacity(0.2),
              border: Border.all(color: sevColor),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(sev.substring(0, sev.length > 4 ? 4 : sev.length),
              style: TextStyle(color: sevColor, fontSize: 8, fontWeight: FontWeight.w700),
              textAlign: TextAlign.center),
          )),
          SizedBox(width: 36, child: IconButton(
            tooltip: kIsWeb ? 'Download PDF' : 'Share PDF',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
            icon: const Icon(Icons.picture_as_pdf, color: AppColors.accent, size: 18),
            onPressed: () => _generateIndividualPdf(inc),
          )),
        ]),
      ),
    );
  }

  void _showIncidentDetail(Map<String, dynamic> inc) {
    final typeLabel = _getTypeLabel(inc);
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          left: 20, right: 20, top: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(child: Text(inc['title']?.toString() ?? 'Incident',
                  style: const TextStyle(color: AppColors.text1, fontSize: 16, fontWeight: FontWeight.w700))),
                IconButton(
                  icon: const Icon(Icons.close, color: AppColors.text3, size: 20),
                  onPressed: () => Navigator.pop(context),
                ),
              ]),
              const SizedBox(height: 8),
              _detailRow('Type', typeLabel),
              _detailRow('Plant', inc['plant']?.toString() ?? ''),
              _detailRow('Department', inc['dept']?.toString() ?? ''),
              _detailRow('Location', inc['location']?.toString() ?? ''),
              _detailRow('Severity', inc['severity']?.toString() ?? ''),
              _detailRow('WSA Cause', inc['wsaCategory']?.toString() ?? ''),
              _detailRow('Status', inc['status']?.toString() ?? ''),
              _detailRow('Reported by', inc['reportedBy']?.toString() ?? ''),
              const SizedBox(height: 10),
              Text(inc['desc']?.toString() ?? '',
                style: const TextStyle(color: AppColors.text2, fontSize: 11, height: 1.5)),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  _generateIndividualPdf(inc);
                },
                icon: const Icon(Icons.picture_as_pdf, size: 16, color: Colors.white),
                label: Text(
                  kIsWeb ? 'Download as PDF' : 'Share as PDF',
                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  minimumSize: const Size(double.infinity, 0),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailRow(String k, String v) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(width: 100, child: Text(k.toUpperCase(),
        style: const TextStyle(color: AppColors.text4, fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 0.4))),
      Expanded(child: Text(v,
        style: const TextStyle(color: AppColors.text1, fontSize: 11, fontWeight: FontWeight.w500))),
    ]),
  );
}
