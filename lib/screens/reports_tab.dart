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
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final inc = await LocalDB.getIncidents();
    if (mounted) setState(() {
      _incidents = inc;
      _loading = false;
    });
  }

  Future<void> _generatePDF() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Generating PDF...'), duration: Duration(seconds: 1)),
    );
    try {
      if (_incidents.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No incidents to export')),
        );
        return;
      }
      final file = await PdfExport.generateConsolidatedReport(
        incidents: _incidents,
        reportTitle: 'Safety Lens Consolidated Report',
      );
      await PdfExport.sharePdf(file,
          subject: 'Safety Lens Report (${_incidents.length} incidents)');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('PDF failed: $e'), backgroundColor: AppColors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final critical = _incidents.where((i) => i['severity'] == 'CRITICAL').length;
    final high = _incidents.where((i) => i['severity'] == 'HIGH').length;
    final medium = _incidents.where((i) => i['severity'] == 'MEDIUM').length;
    final low = _incidents.where((i) => i['severity'] == 'LOW').length;

    return SafeArea(
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor, width: 0.5)),
            ),
            child: Text('All Reports',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 15, fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
                : SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 80),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _statRow(critical, high, medium, low),
                        const SizedBox(height: 12),
                        _pdfCard(),
                        const SizedBox(height: 12),
                        _reportTable(),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _statRow(int cr, int hi, int me, int lo) {
    Widget chip(int val, String lbl, Color color) => Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          border: Border.all(color: color),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(children: [
          Text('$val', style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.w700)),
          Text(lbl, style: const TextStyle(color: AppColors.text3, fontSize: 8)),
        ]),
      ),
    );
    return Row(children: [
      chip(cr, 'CRITICAL', AppColors.crit), const SizedBox(width: 6),
      chip(hi, 'HIGH', AppColors.red), const SizedBox(width: 6),
      chip(me, 'MEDIUM', AppColors.cyan), const SizedBox(width: 6),
      chip(lo, 'LOW', AppColors.green),
    ]);
  }

  Widget _pdfCard() => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppColors.green.withOpacity(0.05),
      border: Border.all(color: AppColors.green, width: 2),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [
          Icon(Icons.picture_as_pdf, size: 18, color: AppColors.green),
          SizedBox(width: 8),
          Text('Export All Reports',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 13, fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 10),
        ElevatedButton.icon(
          onPressed: _generatePDF,
          icon: const Icon(Icons.file_present, size: 14, color: Colors.white),
          label: const Text('Generate Consolidated PDF',
            style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.green,
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      ],
    ),
  );

  Widget _reportTable() {
    if (_incidents.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Text('No reports yet. Start scanning or report a near miss.',
          style: TextStyle(color: AppColors.text3, fontSize: 11)),
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              border: Border(bottom: BorderSide(color: AppColors.border)),
            ),
            child: Row(children: [
              SizedBox(width: 32),
              Expanded(child: Text('Incident',
                style: TextStyle(color: AppColors.text3, fontSize: 9, fontWeight: FontWeight.w600, letterSpacing: 0.5))),
              SizedBox(width: 60, child: Text('Status',
                style: TextStyle(color: AppColors.text3, fontSize: 9, fontWeight: FontWeight.w600, letterSpacing: 0.5))),
            ]),
          ),
          ..._incidents.map((inc) => _reportRow(inc)).toList(),
        ],
      ),
    );
  }

  Widget _reportRow(Map<String, dynamic> inc) {
    final sev = inc['severity']?.toString() ?? 'MEDIUM';
    final sevColor = _sevColor(sev);
    final dateStr = _formatDate(inc['date']?.toString());

    return InkWell(
      onTap: () => _showIncidentDetail(inc),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor, width: 0.5)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 28, height: 28,
              decoration: BoxDecoration(
                color: sevColor.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                sev == 'CRITICAL' ? Icons.warning : sev == 'HIGH' ? Icons.error_outline
                  : sev == 'MEDIUM' ? Icons.info_outline : Icons.check_circle_outline,
                size: 13, color: sevColor,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(inc['title']?.toString() ?? '',
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 11, fontWeight: FontWeight.w600)),
                  Text('${inc['plant']} · $dateStr · by ${inc['reportedBy']}',
                    style: const TextStyle(color: AppColors.text3, fontSize: 9)),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: sevColor.withOpacity(0.2),
                border: Border.all(color: sevColor),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(sev.substring(0, sev.length > 4 ? 4 : sev.length),
                style: TextStyle(color: sevColor, fontSize: 8, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 6),
            // Quick PDF export icon
            IconButton(
              tooltip: kIsWeb ? 'Download PDF' : 'Share PDF',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              icon: const Icon(Icons.picture_as_pdf, color: AppColors.accent, size: 18),
              onPressed: () => _generateIndividualPdf(inc),
            ),
          ],
        ),
      ),
    );
  }

  void _showIncidentDetail(Map<String, dynamic> inc) {
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(child: Text(inc['title']?.toString() ?? 'Incident',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 16, fontWeight: FontWeight.w700))),
              IconButton(
                icon: const Icon(Icons.close, color: AppColors.text3, size: 20),
                onPressed: () => Navigator.pop(context),
              ),
            ]),
            const SizedBox(height: 8),
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
            // Individual PDF download/share button
            ElevatedButton.icon(
              onPressed: () => _generateIndividualPdf(inc),
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
    );
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

  Widget _detailRow(String k, String v) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(width: 80, child: Text(k,
        style: const TextStyle(color: AppColors.text4, fontSize: 10, fontWeight: FontWeight.w600))),
      Expanded(child: Text(v,
        style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 11))),
    ]),
  );

  String _formatDate(String? iso) {
    if (iso == null) return '';
    try {
      return DateFormat('dd MMM').format(DateTime.parse(iso));
    } catch (_) { return iso; }
  }

  Color _sevColor(String sev) {
    switch (sev.toUpperCase()) {
      case 'CRITICAL': return AppColors.crit;
      case 'HIGH': return AppColors.red;
      case 'MEDIUM': return AppColors.cyan;
      case 'LOW': return AppColors.green;
      default: return AppColors.amber;
    }
  }
}
