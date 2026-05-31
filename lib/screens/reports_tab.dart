import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../main.dart';
import '../services/local_db.dart';
import '../services/pdf_export.dart';

class ReportsTab extends StatefulWidget {
  final String? initialFilter;
  const ReportsTab({super.key, this.initialFilter});

  @override
  State<ReportsTab> createState() => _ReportsTabState();
}

class _ReportsTabState extends State<ReportsTab> {
  List<Map<String, dynamic>> _incidents = [];
  String _filter = 'ALL';

  @override
  void initState() {
    super.initState();
    _filter = widget.initialFilter ?? 'ALL';
    _load();
  }

  Future<void> _load() async {
    final list = await LocalDB.getIncidents();
    if (!mounted) return;
    setState(() => _incidents = list);
  }

  List<Map<String, dynamic>> get _filtered {
    if (_filter == 'ALL') return _incidents;
    return _incidents.where((i) => i['severity']?.toString().toUpperCase() == _filter).toList();
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

  String _getTypeLabel(Map<String, dynamic> inc) {
    final type = inc['type']?.toString().toUpperCase() ?? '';
    final obsType = inc['obsType']?.toString() ?? '';
    if (type == 'AI_SCAN') return 'AI SCAN';
    if (type == 'NEAR_MISS') {
      if (obsType.toLowerCase().contains('act')) return 'UNSAFE ACT';
      if (obsType.toLowerCase().contains('condition')) return 'UNSAFE CONDITION';
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

  Color _sevColor(String sev) {
    switch (sev) {
      case 'CRITICAL': return AppColors.crit;
      case 'HIGH': return AppColors.red;
      case 'MEDIUM': return AppColors.cyan;
      default: return AppColors.green;
    }
  }

  @override
  Widget build(BuildContext context) {
    final critical = _incidents.where((i) => i['severity'] == 'CRITICAL').length;
    final high = _incidents.where((i) => i['severity'] == 'HIGH').length;
    final medium = _incidents.where((i) => i['severity'] == 'MEDIUM').length;
    final low = _incidents.where((i) => i['severity'] == 'LOW').length;

    return SafeArea(
      child: Column(children: [
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Row(children: [
            const Expanded(child: Text('All Reports',
              style: TextStyle(color: AppColors.text1, fontSize: 20, fontWeight: FontWeight.w700))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.card2,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.border),
              ),
              child: Text('${_filtered.length} of ${_incidents.length}',
                style: const TextStyle(color: AppColors.text2, fontSize: 11, fontWeight: FontWeight.w600)),
            ),
          ]),
        ),
        // Filter pills
        SizedBox(
          height: 80,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            children: [
              _filterPill('ALL', _incidents.length, AppColors.text2),
              _filterPill('CRITICAL', critical, AppColors.crit),
              _filterPill('HIGH', high, AppColors.red),
              _filterPill('MEDIUM', medium, AppColors.cyan),
              _filterPill('LOW', low, AppColors.green),
            ],
          ),
        ),
        const SizedBox(height: 4),
        // Cards list
        Expanded(
          child: _filtered.isEmpty
            ? _emptyState()
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 16),
                itemCount: _filtered.length,
                itemBuilder: (_, i) => _reportCard(_filtered[i]),
              ),
        ),
      ]),
    );
  }

  Widget _filterPill(String label, int count, Color color) {
    final selected = _filter == label;
    return GestureDetector(
      onTap: () => setState(() => _filter = label),
      child: Container(
        width: 90,
        margin: const EdgeInsets.only(right: 8, top: 4, bottom: 4),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: selected ? color : color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color, width: selected ? 2 : 1),
          boxShadow: selected ? [BoxShadow(color: color.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 2))] : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('$count',
              style: TextStyle(
                color: selected ? Colors.white : color,
                fontSize: 22, fontWeight: FontWeight.w800, height: 1,
              )),
            const SizedBox(height: 4),
            Text(label,
              style: TextStyle(
                color: selected ? Colors.white : color,
                fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 0.4,
              )),
          ],
        ),
      ),
    );
  }

  Widget _emptyState() => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.inbox_outlined, size: 56, color: AppColors.text4),
        const SizedBox(height: 12),
        Text(_filter == 'ALL' ? 'No reports yet' : 'No $_filter incidents',
          style: const TextStyle(color: AppColors.text3, fontSize: 14, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(_filter == 'ALL'
          ? 'Submit a Near Miss or AI Scan to see reports'
          : 'Try a different filter',
          style: const TextStyle(color: AppColors.text4, fontSize: 11)),
      ],
    ),
  );

  Widget _reportCard(Map<String, dynamic> inc) {
    final sev = inc['severity']?.toString() ?? 'MEDIUM';
    final sevColor = _sevColor(sev);
    final typeLabel = _getTypeLabel(inc);
    final typeColor = _getTypeColor(inc);
    final dateStr = inc['date'] != null
      ? DateFormat('dd MMM yyyy · HH:mm').format(DateTime.parse(inc['date']))
      : '';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Left severity bar accent
          Container(
            height: 4,
            decoration: BoxDecoration(
              color: sevColor,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            ),
          ),
          InkWell(
            onTap: () => _showIncidentDetail(inc),
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header row: title + severity badge
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: Text(inc['title']?.toString() ?? 'Untitled',
                      style: const TextStyle(color: AppColors.text1, fontSize: 14, fontWeight: FontWeight.w700, height: 1.3),
                      maxLines: 2, overflow: TextOverflow.ellipsis)),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: sevColor,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(sev,
                        style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
                    ),
                  ]),
                  const SizedBox(height: 10),
                  // Type + plant + date row
                  Wrap(spacing: 8, runSpacing: 6, children: [
                    _chip(typeLabel, typeColor),
                    _chip(inc['plant']?.toString() ?? 'Unknown', AppColors.text3),
                    _chip(dateStr, AppColors.text4),
                  ]),
                  const SizedBox(height: 10),
                  // Description preview
                  Text(inc['desc']?.toString() ?? '',
                    style: const TextStyle(color: AppColors.text2, fontSize: 11, height: 1.5),
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 10),
                  // Action row
                  Row(children: [
                    Expanded(child: OutlinedButton.icon(
                      onPressed: () => _showIncidentDetail(inc),
                      icon: const Icon(Icons.visibility_outlined, color: AppColors.text2, size: 14),
                      label: const Text('View Details',
                        style: TextStyle(color: AppColors.text2, fontSize: 11, fontWeight: FontWeight.w600)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppColors.border),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    )),
                    const SizedBox(width: 8),
                    Expanded(child: ElevatedButton.icon(
                      onPressed: () => _generateIndividualPdf(inc),
                      icon: const Icon(Icons.picture_as_pdf, color: Colors.white, size: 14),
                      label: Text(kIsWeb ? 'Download PDF' : 'Share PDF',
                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    )),
                  ]),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: color.withOpacity(0.12),
      borderRadius: BorderRadius.circular(4),
      border: Border.all(color: color.withOpacity(0.4), width: 0.8),
    ),
    child: Text(text,
      style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 0.3)),
  );

  void _showIncidentDetail(Map<String, dynamic> inc) {
    final typeLabel = _getTypeLabel(inc);
    final sev = inc['severity']?.toString() ?? 'MEDIUM';
    final sevColor = _sevColor(sev);
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.bg,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          left: 20, right: 20, top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 14),
            // Severity banner
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: sevColor,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(children: [
                const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Text('$sev SEVERITY',
                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
              ]),
            ),
            const SizedBox(height: 12),
            Text(inc['title']?.toString() ?? 'Incident',
              style: const TextStyle(color: AppColors.text1, fontSize: 17, fontWeight: FontWeight.w700, height: 1.3)),
            const SizedBox(height: 14),
            _detailGrid(inc, typeLabel),
            const SizedBox(height: 14),
            const Text('DESCRIPTION',
              style: TextStyle(color: AppColors.text4, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.6)),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.border)),
              child: Text(inc['desc']?.toString() ?? '',
                style: const TextStyle(color: AppColors.text1, fontSize: 12, height: 1.5)),
            ),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.border, width: 1.5),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('Close', style: TextStyle(color: AppColors.text2, fontWeight: FontWeight.w600)),
              )),
              const SizedBox(width: 10),
              Expanded(flex: 2, child: ElevatedButton.icon(
                onPressed: () { Navigator.pop(context); _generateIndividualPdf(inc); },
                icon: const Icon(Icons.picture_as_pdf, size: 16, color: Colors.white),
                label: Text(kIsWeb ? 'Download as PDF' : 'Share as PDF',
                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              )),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _detailGrid(Map<String, dynamic> inc, String typeLabel) {
    Widget cell(String label, String value) => Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label.toUpperCase(),
            style: const TextStyle(color: AppColors.text4, fontSize: 8, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
          const SizedBox(height: 4),
          Text(value.isEmpty ? '—' : value,
            style: const TextStyle(color: AppColors.text1, fontSize: 11, fontWeight: FontWeight.w600)),
        ],
      ),
    );

    return Column(children: [
      Row(children: [
        Expanded(child: cell('Type', typeLabel)),
        const SizedBox(width: 8),
        Expanded(child: cell('Status', inc['status']?.toString() ?? 'OPEN')),
      ]),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: cell('Plant', inc['plant']?.toString() ?? '')),
        const SizedBox(width: 8),
        Expanded(child: cell('Department', inc['dept']?.toString() ?? '')),
      ]),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: cell('Location', inc['location']?.toString() ?? '')),
        const SizedBox(width: 8),
        Expanded(child: cell('WSA Cause', inc['wsaCategory']?.toString() ?? '')),
      ]),
      const SizedBox(height: 8),
      cell('Reported by', inc['reportedBy']?.toString() ?? ''),
    ]);
  }
}
