import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../main.dart';
import '../services/local_db.dart';
import '../services/pdf_export.dart';

class ReportsTab extends StatefulWidget {
  final String? initialFilter; // e.g. 'CRITICAL', 'HIGH', 'MEDIUM', 'LOW'
  const ReportsTab({super.key, this.initialFilter});
  @override
  State<ReportsTab> createState() => _ReportsTabState();
}

class _ReportsTabState extends State<ReportsTab> {
  List<Map<String, dynamic>> _all = [];
  List<Map<String, dynamic>> _filtered = [];
  bool _loading = true;
  String? _activeFilter; // null = show all
  String _sortBy = 'date'; // date | severity | score

  @override
  void initState() {
    super.initState();
    _activeFilter = widget.initialFilter;
    _load();
  }

  Future<void> _load() async {
    final inc = await LocalDB.getIncidents();
    if (!mounted) return;
    setState(() {
      _all = inc;
      _applyFilter();
      _loading = false;
    });
  }

  void _applyFilter() {
    var list = _activeFilter == null
        ? List<Map<String, dynamic>>.from(_all)
        : _all.where((i) => i['severity'] == _activeFilter).toList();

    // Sort
    list.sort((a, b) {
      if (_sortBy == 'score') {
        final sa = int.tryParse(a['riskScore']?.toString() ?? '0') ?? 0;
        final sb = int.tryParse(b['riskScore']?.toString() ?? '0') ?? 0;
        return sb.compareTo(sa);
      } else if (_sortBy == 'severity') {
        const order = {'CRITICAL': 0, 'HIGH': 1, 'MEDIUM': 2, 'LOW': 3};
        final sa = order[a['severity']] ?? 4;
        final sb = order[b['severity']] ?? 4;
        return sa.compareTo(sb);
      } else {
        // date (newest first)
        final da = a['date']?.toString() ?? '';
        final db = b['date']?.toString() ?? '';
        return db.compareTo(da);
      }
    });
    _filtered = list;
  }

  void _setFilter(String? f) => setState(() {
    _activeFilter = _activeFilter == f ? null : f;
    _applyFilter();
  });

  Future<void> _generatePDF() async {
    if (_filtered.isEmpty) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Generating PDF...'),
        duration: Duration(seconds: 1)));
    try {
      final file = await PdfExport.generateConsolidatedReport(
        incidents: _filtered,
        reportTitle: _activeFilter != null
            ? '$_activeFilter Risk Incidents Report'
            : 'Safety Lens Consolidated Report',
      );
      await PdfExport.sharePdf(file,
          subject: 'Safety Lens Report (${_filtered.length} incidents)');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('PDF failed: $e'),
          backgroundColor: AppColors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    final sl = SL.of(context);
    final critical = _all.where((i) => i['severity'] == 'CRITICAL').length;
    final high     = _all.where((i) => i['severity'] == 'HIGH').length;
    final medium   = _all.where((i) => i['severity'] == 'MEDIUM').length;
    final low      = _all.where((i) => i['severity'] == 'LOW').length;
    final total    = _all.length;

    return SafeArea(
      child: Column(children: [
        // ── TOP BAR ──────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          decoration: BoxDecoration(
            color: sl.bg2,
            border: Border(bottom: BorderSide(
              color: sl.border.withOpacity(0.4), width: 1))),
          child: Row(children: [
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Reports', style: TextStyle(
                  color: sl.text1, fontSize: 18,
                  fontWeight: FontWeight.w800)),
                Text('$total incidents recorded', style: TextStyle(
                  color: sl.text4, fontSize: 11)),
              ])),
            // Sort button
            PopupMenuButton<String>(
              initialValue: _sortBy,
              color: sl.card2,
              onSelected: (v) => setState(() {
                _sortBy = v; _applyFilter();
              }),
              itemBuilder: (_) => [
                PopupMenuItem(value: 'date',
                  child: Text('Sort: Newest first',
                    style: TextStyle(color: sl.text1, fontSize: 12))),
                PopupMenuItem(value: 'severity',
                  child: Text('Sort: By severity',
                    style: TextStyle(color: sl.text1, fontSize: 12))),
                PopupMenuItem(value: 'score',
                  child: Text('Sort: By risk score',
                    style: TextStyle(color: sl.text1, fontSize: 12))),
              ],
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: sl.card2,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: sl.border.withOpacity(0.5))),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.sort_rounded, size: 14, color: sl.text3),
                  const SizedBox(width: 4),
                  Text('Sort', style: TextStyle(
                    color: sl.text3, fontSize: 11)),
                ])),
            ),
            const SizedBox(width: 8),
            // Export button
            GestureDetector(
              onTap: _generatePDF,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.accent, AppColors.cyan]),
                  borderRadius: BorderRadius.circular(8)),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.picture_as_pdf, size: 14, color: Colors.white),
                  SizedBox(width: 4),
                  Text('PDF', style: TextStyle(
                    color: Colors.white, fontSize: 11,
                    fontWeight: FontWeight.w700)),
                ])),
            ),
          ]),
        ),

        // ── CLICKABLE FILTER PILLS ────────────────────────────────
        Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          color: sl.bg,
          child: Row(children: [
            _filterPill(sl, 'ALL', total, null,
              AppColors.accent, _activeFilter == null),
            const SizedBox(width: 6),
            _filterPill(sl, 'CRIT', critical, 'CRITICAL',
              AppColors.crit, _activeFilter == 'CRITICAL'),
            const SizedBox(width: 6),
            _filterPill(sl, 'HIGH', high, 'HIGH',
              AppColors.red, _activeFilter == 'HIGH'),
            const SizedBox(width: 6),
            _filterPill(sl, 'MED', medium, 'MEDIUM',
              AppColors.amber, _activeFilter == 'MEDIUM'),
            const SizedBox(width: 6),
            _filterPill(sl, 'LOW', low, 'LOW',
              AppColors.green, _activeFilter == 'LOW'),
          ]),
        ),

        // ── TABLE ────────────────────────────────────────────────
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(
                  color: AppColors.accent))
              : _filtered.isEmpty
                  ? _emptyState(sl)
                  : Column(children: [
                      // Table header
                      _tableHeader(sl),
                      // Table rows
                      Expanded(child: ListView.separated(
                        padding: EdgeInsets.zero,
                        itemCount: _filtered.length,
                        separatorBuilder: (_, __) => Divider(
                          height: 1, color: sl.border.withOpacity(0.3)),
                        itemBuilder: (_, i) => _reportRow(_filtered[i], sl),
                      )),
                    ]),
        ),
      ]),
    );
  }

  // ── CLICKABLE FILTER PILL ──────────────────────────────────────
  Widget _filterPill(SL sl, String label, int count,
      String? filter, Color color, bool active) {
    return Expanded(child: GestureDetector(
      onTap: () => _setFilter(filter),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: active ? color.withOpacity(0.2) : sl.card,
          border: Border.all(
            color: active ? color : sl.border.withOpacity(0.4),
            width: active ? 2 : 1),
          borderRadius: BorderRadius.circular(10)),
        child: Column(children: [
          Text('$count', style: TextStyle(
            color: active ? color : sl.text2,
            fontSize: 20, fontWeight: FontWeight.w900)),
          Text(label, style: TextStyle(
            color: active ? color.withOpacity(0.8) : sl.text4,
            fontSize: 8, fontWeight: FontWeight.w700,
            letterSpacing: 0.5)),
        ]),
      ),
    ));
  }

  // ── TABLE HEADER ───────────────────────────────────────────────
  Widget _tableHeader(SL sl) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      color: sl.card2,
      child: Row(children: [
        const SizedBox(width: 28),
        Expanded(flex: 4, child: Text('INCIDENT',
          style: TextStyle(color: sl.text4, fontSize: 9,
            fontWeight: FontWeight.w800, letterSpacing: 0.8))),
        SizedBox(width: 60, child: Text('DATE',
          style: TextStyle(color: sl.text4, fontSize: 9,
            fontWeight: FontWeight.w800, letterSpacing: 0.8))),
        SizedBox(width: 44, child: Center(child: Text('SCORE',
          style: TextStyle(color: sl.text4, fontSize: 9,
            fontWeight: FontWeight.w800, letterSpacing: 0.8)))),
        SizedBox(width: 44, child: Center(child: Text('RISK',
          style: TextStyle(color: sl.text4, fontSize: 9,
            fontWeight: FontWeight.w800, letterSpacing: 0.8)))),
        const SizedBox(width: 32),
      ]),
    );
  }

  // ── REPORT ROW ─────────────────────────────────────────────────
  Widget _reportRow(Map<String, dynamic> inc, SL sl) {
    final sev      = inc['severity']?.toString() ?? 'MEDIUM';
    final sevColor = SeverityBadge.color(sev);
    final dateStr  = _formatDate(inc['date']?.toString());
    final score    = inc['riskScore']?.toString() ?? '—';
    final plant    = inc['plant']?.toString() ?? '';
    final reporter = inc['reportedBy']?.toString() ?? '';
    final isAI     = inc['type']?.toString() == 'AI_SCAN';

    return InkWell(
      onTap: () => _showDetail(inc, sl),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Row(children: [
          // Severity dot
          Container(
            width: 8, height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: sevColor,
              boxShadow: [BoxShadow(
                color: sevColor.withOpacity(0.5),
                blurRadius: 4)]),
          ),
          const SizedBox(width: 10),
          // Incident info
          Expanded(flex: 4, child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                if (isAI) Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4, vertical: 1),
                  margin: const EdgeInsets.only(right: 4),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(4)),
                  child: const Text('AI', style: TextStyle(
                    color: AppColors.accent, fontSize: 7,
                    fontWeight: FontWeight.w800))),
                Expanded(child: Text(
                  inc['title']?.toString() ?? 'Incident',
                  style: TextStyle(color: sl.text1, fontSize: 12,
                    fontWeight: FontWeight.w600),
                  maxLines: 1, overflow: TextOverflow.ellipsis)),
              ]),
              const SizedBox(height: 2),
              Text('$plant · $reporter', style: TextStyle(
                color: sl.text4, fontSize: 10),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            ])),
          // Date
          SizedBox(width: 60, child: Text(dateStr,
            style: TextStyle(color: sl.text3, fontSize: 10),
            textAlign: TextAlign.center)),
          // Risk score
          SizedBox(width: 44, child: Center(child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            decoration: BoxDecoration(
              color: score != '—'
                ? sevColor.withOpacity(0.1) : Colors.transparent,
              borderRadius: BorderRadius.circular(6)),
            child: Text(score == '—' ? '—' : '$score',
              style: TextStyle(
                color: score != '—' ? sevColor : sl.text4,
                fontSize: 11, fontWeight: FontWeight.w800),
              textAlign: TextAlign.center),
          ))),
          // Severity badge
          SizedBox(width: 44, child: SeverityBadge(sev, small: true)),
          // PDF button
          GestureDetector(
            onTap: () => _exportSinglePdf(inc),
            child: Container(
              width: 28, height: 28,
              decoration: BoxDecoration(
                color: AppColors.accent.withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: AppColors.accent.withOpacity(0.3))),
              child: const Icon(Icons.picture_as_pdf,
                color: AppColors.accent, size: 14)),
          ),
        ]),
      ),
    );
  }

  // ── DETAIL SHEET ───────────────────────────────────────────────
  void _showDetail(Map<String, dynamic> inc, SL sl) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        minChildSize: 0.4,
        builder: (ctx, scroll) => Container(
          decoration: BoxDecoration(
            color: sl.card,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(20))),
          child: Column(children: [
            // Handle
            Container(
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: sl.border,
                borderRadius: BorderRadius.circular(2))),
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
              child: Row(children: [
                SeverityBadge(inc['severity']?.toString() ?? 'LOW'),
                const SizedBox(width: 10),
                Expanded(child: Text(
                  inc['title']?.toString() ?? '',
                  style: TextStyle(color: sl.text1, fontSize: 15,
                    fontWeight: FontWeight.w700))),
                IconButton(
                  icon: Icon(Icons.close, color: sl.text4),
                  onPressed: () => Navigator.pop(ctx)),
              ])),
            const NeonDivider(),
            // Content
            Expanded(child: ListView(
              controller: scroll,
              padding: const EdgeInsets.all(16),
              children: [
                _detailGrid(inc, sl),
                const SizedBox(height: 12),
                if ((inc['desc']?.toString() ?? '').isNotEmpty) ...[
                  Text('SUMMARY', style: TextStyle(
                    color: sl.text4, fontSize: 10,
                    fontWeight: FontWeight.w800, letterSpacing: 1)),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: sl.card2,
                      borderRadius: BorderRadius.circular(10)),
                    child: Text(
                      inc['desc']?.toString() ?? '',
                      style: TextStyle(color: sl.text2, fontSize: 12,
                        height: 1.5))),
                  const SizedBox(height: 12),
                ],
                // Export button
                GradientButton(
                  label: 'Export PDF Report',
                  icon: Icons.picture_as_pdf,
                  onTap: () {
                    Navigator.pop(ctx);
                    _exportSinglePdf(inc);
                  },
                  colors: const [AppColors.accent, AppColors.cyan]),
              ])),
          ]),
        ),
      ),
    );
  }

  Widget _detailGrid(Map<String, dynamic> inc, SL sl) {
    final date = _formatDate(inc['date']?.toString());
    final score = inc['riskScore']?.toString() ?? '—';
    final conf = inc['confidence']?.toString() ?? '—';
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 8,
      mainAxisSpacing: 8,
      childAspectRatio: 2.8,
      children: [
        _detailCell(sl, 'Date', date),
        _detailCell(sl, 'Plant', inc['plant']?.toString() ?? ''),
        _detailCell(sl, 'Risk Score', score),
        _detailCell(sl, 'Confidence', conf != '—' ? '$conf%' : '—'),
        _detailCell(sl, 'Status', inc['status']?.toString() ?? 'OPEN'),
        _detailCell(sl, 'Type', inc['type']?.toString() ?? ''),
        _detailCell(sl, 'Reporter', inc['reportedBy']?.toString() ?? ''),
        _detailCell(sl, 'Department', inc['dept']?.toString() ?? '—'),
      ]);
  }

  Widget _detailCell(SL sl, String label, String value) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      color: sl.card2,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: sl.border.withOpacity(0.4))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(label, style: TextStyle(
          color: sl.text4, fontSize: 9,
          fontWeight: FontWeight.w700)),
        const SizedBox(height: 2),
        Text(value.isEmpty ? '—' : value,
          style: TextStyle(color: sl.text1, fontSize: 12,
            fontWeight: FontWeight.w600),
          maxLines: 1, overflow: TextOverflow.ellipsis),
      ]));

  Future<void> _exportSinglePdf(Map<String, dynamic> inc) async {
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Generating PDF...'),
          duration: Duration(seconds: 1)));
      final user = await LocalDB.getCurrentUser();
      await PdfExport.downloadOrShareIncident(
        incident: inc,
        reporterName: user?['name']?.toString() ?? 'SAIL Safety Officer',
        reporterPno: user?['pno']?.toString() ?? '',
      );
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('PDF failed: $e'),
          backgroundColor: AppColors.red));
    }
  }

  Widget _emptyState(SL sl) => Center(child: Padding(
    padding: const EdgeInsets.all(32),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 72, height: 72,
        decoration: BoxDecoration(
          color: sl.card2, shape: BoxShape.circle),
        child: Icon(Icons.bar_chart_outlined,
          color: sl.text4, size: 32)),
      const SizedBox(height: 16),
      Text(
        _activeFilter != null
            ? 'No $_activeFilter incidents'
            : 'No reports yet',
        style: TextStyle(color: sl.text2, fontSize: 15,
          fontWeight: FontWeight.w600)),
      const SizedBox(height: 6),
      Text('Start with an AI Scan or Near Miss report',
        style: TextStyle(color: sl.text4, fontSize: 12)),
    ])));

  String _formatDate(String? raw) {
    if (raw == null || raw.isEmpty) return '—';
    try {
      final d = DateTime.parse(raw);
      return DateFormat('dd MMM').format(d);
    } catch (_) { return raw.substring(0, 8); }
  }

  Color _sevColor(String s) => SeverityBadge.color(s);
}
