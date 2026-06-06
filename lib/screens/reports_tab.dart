// lib/screens/reports_tab.dart
//
// ✅ Tappable rows → IncidentDetailScreen (mitigation + close)
// ✅ Status filter pills (ALL / OPEN / INVESTIGATING / CLOSED)
// ✅ Severity filter pills
// ✅ Status badge on every row
// ✅ Auto-refresh after case is closed
// ✅ Google Sheets sync on every save (via SyncService in detail screen)

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../main.dart';
import '../services/local_db.dart';
import '../services/pdf_export.dart';
import 'incident_detail_screen.dart';

class ReportsTab extends StatefulWidget {
  final String? initialFilter;
  const ReportsTab({super.key, this.initialFilter});
  @override
  State<ReportsTab> createState() => _ReportsTabState();
}

class _ReportsTabState extends State<ReportsTab>
    with SingleTickerProviderStateMixin {
  List<Map<String, dynamic>> _all      = [];
  List<Map<String, dynamic>> _filtered = [];
  bool    _loading      = true;
  String? _sevFilter;    // null = all severities
  String? _statusFilter; // null = all statuses
  String  _sortBy       = 'date';
  late TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _sevFilter = widget.initialFilter;
    _load();
  }

  @override
  void dispose() { _tabCtrl.dispose(); super.dispose(); }

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
    var list = List<Map<String, dynamic>>.from(_all);

    // Severity filter
    if (_sevFilter != null) {
      list = list.where((i) =>
          i['severity']?.toString() == _sevFilter).toList();
    }

    // Status filter
    if (_statusFilter != null) {
      list = list.where((i) {
        final s = i['status']?.toString().toUpperCase() ?? 'OPEN';
        if (_statusFilter == 'OPEN') {
          return s == 'OPEN' || s == 'INVESTIGATING' || s == 'ACTION TAKEN';
        }
        return s == _statusFilter;
      }).toList();
    }

    // Sort
    list.sort((a, b) {
      if (_sortBy == 'score') {
        final sa = int.tryParse(a['riskScore']?.toString() ?? '0') ?? 0;
        final sb = int.tryParse(b['riskScore']?.toString() ?? '0') ?? 0;
        return sb.compareTo(sa);
      } else if (_sortBy == 'severity') {
        const order = {'CRITICAL': 0, 'HIGH': 1, 'MEDIUM': 2, 'LOW': 3};
        return (order[a['severity']] ?? 4)
            .compareTo(order[b['severity']] ?? 4);
      } else {
        return (b['date']?.toString() ?? '')
            .compareTo(a['date']?.toString() ?? '');
      }
    });
    _filtered = list;
  }

  void _setSevFilter(String? f) => setState(() {
    _sevFilter = _sevFilter == f ? null : f;
    _applyFilter();
  });

  void _setStatusFilter(String? f) => setState(() {
    _statusFilter = _statusFilter == f ? null : f;
    _applyFilter();
  });

  // ── Computed counts ──────────────────────────────────────────
  int get _crit    => _all.where((i) => i['severity'] == 'CRITICAL').length;
  int get _high    => _all.where((i) => i['severity'] == 'HIGH').length;
  int get _medium  => _all.where((i) => i['severity'] == 'MEDIUM').length;
  int get _low     => _all.where((i) => i['severity'] == 'LOW').length;
  int get _open    => _all.where((i) {
    final s = i['status']?.toString().toUpperCase() ?? 'OPEN';
    return s == 'OPEN' || s == 'INVESTIGATING' || s == 'ACTION TAKEN';
  }).length;
  int get _closed  => _all.where((i) =>
      i['status']?.toString().toUpperCase() == 'CLOSED').length;

  Future<void> _generatePDF() async {
    if (_filtered.isEmpty) return;
    _snack('Generating PDF…', AppColors.accent);
    try {
      final file = await PdfExport.generateConsolidatedReport(
        incidents: _filtered,
        reportTitle: _sevFilter != null
            ? '$_sevFilter Risk Report'
            : 'Safety Lens Consolidated Report',
      );
      await PdfExport.sharePdf(file,
          subject: 'Safety Lens Report (${_filtered.length} incidents)');
    } catch (e) {
      _snack('PDF failed: $e', AppColors.red);
    }
  }

  void _openDetail(Map<String, dynamic> inc) {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => IncidentDetailScreen(
        incident: inc,
        onStatusChanged: _load, // refresh list when status changes
      ))).then((_) => _load()); // also refresh on back navigation
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg), backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10)),
    ));
  }

  // ─────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final sl = SL.of(context);

    // Neutral background — not pure black
    // Override scaffold bg inline:
    return Container(
      color: sl.isDark
          ? const Color(0xFF1C1F2E) : const Color(0xFFF5F6FA),
      child: SafeArea(child: Column(children: [

      // ── INFOGRAPHIC HEADER ───────────────────────────────────
      _buildInfoHeader(sl),

      // ── STATUS PILLS ─────────────────────────────────────────
      Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
        color: sl.bg,
        child: Row(children: [
          _statusPill(sl, 'ALL', _all.length, null,
              sl.text2, _statusFilter == null),
          const SizedBox(width: 6),
          _statusPill(sl, 'OPEN', _open, 'OPEN',
              AppColors.amber, _statusFilter == 'OPEN'),
          const SizedBox(width: 6),
          _statusPill(sl, 'CLOSED', _closed, 'CLOSED',
              AppColors.green, _statusFilter == 'CLOSED'),
        ])),

      // ── SEVERITY PILLS ───────────────────────────────────────
      Container(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        color: sl.bg,
        child: Row(children: [
          _sevPill(sl, 'ALL',  _all.length, null,
              AppColors.accent, _sevFilter == null),
          const SizedBox(width: 6),
          _sevPill(sl, 'CRIT', _crit,   'CRITICAL',
              AppColors.crit,  _sevFilter == 'CRITICAL'),
          const SizedBox(width: 6),
          _sevPill(sl, 'HIGH', _high,   'HIGH',
              AppColors.red,   _sevFilter == 'HIGH'),
          const SizedBox(width: 6),
          _sevPill(sl, 'MED',  _medium, 'MEDIUM',
              AppColors.amber, _sevFilter == 'MEDIUM'),
          const SizedBox(width: 6),
          _sevPill(sl, 'LOW',  _low,    'LOW',
              AppColors.green, _sevFilter == 'LOW'),
        ])),

      // ── TABLE ────────────────────────────────────────────────
      Expanded(child: _loading
        ? const Center(child: CircularProgressIndicator(
            color: AppColors.accent))
        : _filtered.isEmpty
          ? _emptyState(sl)
          : Column(children: [
              _tableHeader(sl),
              Expanded(child: RefreshIndicator(
                onRefresh: _load,
                color: AppColors.accent,
                child: ListView.separated(
                  padding: EdgeInsets.zero,
                  itemCount: _filtered.length,
                  separatorBuilder: (_, __) => Divider(
                    height: 1,
                    color: sl.border.withOpacity(0.3)),
                  itemBuilder: (_, i) =>
                      _reportRow(_filtered[i], sl),
                ))),
            ])),
    ]));
  }


  // ── INFOGRAPHIC HEADER ────────────────────────────────────────
  Widget _buildInfoHeader(SL sl) {
    final isDark = sl.isDark;
    final cardBg = isDark ? const Color(0xFF252840) : Colors.white;
    final bgPage = isDark ? const Color(0xFF1C1F2E) : const Color(0xFFF5F6FA);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: BoxDecoration(
        color: cardBg,
        border: Border(bottom: BorderSide(
            color: sl.border.withOpacity(0.35)))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: AppColors.accent.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.bar_chart_rounded,
                  color: AppColors.accent, size: 20)),
            const SizedBox(width: 10),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Reports', style: TextStyle(
                    color: sl.text1, fontSize: 16,
                    fontWeight: FontWeight.w800)),
                Text('${_all.length} total · $_open open · $_closed closed',
                  style: TextStyle(color: sl.text4, fontSize: 10)),
              ])),
            // Refresh
            GestureDetector(
              onTap: _load,
              child: Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: sl.isDark
                      ? const Color(0xFF2A2D42)
                      : const Color(0xFFF0F1F5),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: sl.border.withOpacity(0.4))),
                child: Icon(Icons.refresh_rounded,
                    color: sl.text3, size: 16))),
            const SizedBox(width: 6),
            // Sort
            PopupMenuButton<String>(
              initialValue: _sortBy,
              color: sl.isDark
                  ? const Color(0xFF2A2D42) : Colors.white,
              onSelected: (v) => setState(() {
                _sortBy = v; _applyFilter();
              }),
              itemBuilder: (_) => [
                PopupMenuItem(value: 'date',
                  child: Text('Newest first',
                      style: TextStyle(color: sl.text1, fontSize: 12))),
                PopupMenuItem(value: 'severity',
                  child: Text('By severity',
                      style: TextStyle(color: sl.text1, fontSize: 12))),
                PopupMenuItem(value: 'score',
                  child: Text('By risk score',
                      style: TextStyle(color: sl.text1, fontSize: 12))),
              ],
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 7),
                decoration: BoxDecoration(
                  color: sl.isDark
                      ? const Color(0xFF2A2D42)
                      : const Color(0xFFF0F1F5),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: sl.border.withOpacity(0.4))),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.sort_rounded,
                      size: 14, color: sl.text3),
                  const SizedBox(width: 3),
                  Text('Sort', style: TextStyle(
                      color: sl.text3, fontSize: 11)),
                ]))),
            const SizedBox(width: 6),
            // PDF
            GestureDetector(
              onTap: _generatePDF,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 9, vertical: 7),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.accent, AppColors.cyan]),
                  borderRadius: BorderRadius.circular(8)),
                child: const Row(
                    mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.picture_as_pdf,
                      size: 13, color: Colors.white),
                  SizedBox(width: 3),
                  Text('PDF', style: TextStyle(
                      color: Colors.white, fontSize: 11,
                      fontWeight: FontWeight.w700)),
                ]))),
          ]),
          const SizedBox(height: 10),
          // Mini stat bar
          Row(children: [
            _miniStat('📊', 'Total', '${_all.length}',
                sl.text2, sl),
            const SizedBox(width: 6),
            _miniStat('🔴', 'Critical', '$_crit',
                AppColors.crit, sl),
            const SizedBox(width: 6),
            _miniStat('🟠', 'High', '$_high',
                AppColors.red, sl),
            const SizedBox(width: 6),
            _miniStat('🟡', 'Open', '$_open',
                AppColors.amber, sl),
            const SizedBox(width: 6),
            _miniStat('✅', 'Closed', '$_closed',
                const Color(0xFF16A34A), sl),
          ]),
        ]));
  }

  Widget _miniStat(String emoji, String lbl,
      String val, Color color, SL sl) =>
    Expanded(child: Container(
      padding: const EdgeInsets.symmetric(vertical: 7),
      decoration: BoxDecoration(
        color: color.withOpacity(0.07),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.2))),
      child: Column(children: [
        Text(val, style: TextStyle(color: color,
            fontSize: 15, fontWeight: FontWeight.w800)),
        Text('$emoji $lbl', style: TextStyle(
            color: color.withOpacity(0.8),
            fontSize: 7.5, fontWeight: FontWeight.w600)),
      ])));

  // ── STATUS PILL ──────────────────────────────────────────────
  Widget _statusPill(SL sl, String label, int count,
      String? filter, Color color, bool active) =>
    Expanded(child: GestureDetector(
      onTap: () => _setStatusFilter(filter),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 7),
        decoration: BoxDecoration(
          color: active ? color.withOpacity(0.15) : sl.card,
          border: Border.all(
            color: active ? color : sl.border.withOpacity(0.4),
            width: active ? 2 : 1),
          borderRadius: BorderRadius.circular(8)),
        child: Column(children: [
          Text('$count', style: TextStyle(
            color: active ? color : sl.text2,
            fontSize: 16, fontWeight: FontWeight.w900)),
          Text(label, style: TextStyle(
            color: active ? color.withOpacity(0.8) : sl.text4,
            fontSize: 8, fontWeight: FontWeight.w700,
            letterSpacing: 0.5)),
        ]))));

  // ── SEVERITY PILL ────────────────────────────────────────────
  Widget _sevPill(SL sl, String label, int count,
      String? filter, Color color, bool active) =>
    Expanded(child: GestureDetector(
      onTap: () => _setSevFilter(filter),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 7),
        decoration: BoxDecoration(
          color: active ? color.withOpacity(0.15) : sl.card,
          border: Border.all(
            color: active ? color : sl.border.withOpacity(0.4),
            width: active ? 2 : 1),
          borderRadius: BorderRadius.circular(8)),
        child: Column(children: [
          Text('$count', style: TextStyle(
            color: active ? color : sl.text2,
            fontSize: 16, fontWeight: FontWeight.w900)),
          Text(label, style: TextStyle(
            color: active ? color.withOpacity(0.8) : sl.text4,
            fontSize: 8, fontWeight: FontWeight.w700,
            letterSpacing: 0.5)),
        ]))));

  // ── TABLE HEADER ─────────────────────────────────────────────
  Widget _tableHeader(SL sl) => Container(
    padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
    color: sl.card2,
    child: Row(children: [
      const SizedBox(width: 10),
      Expanded(flex: 4, child: _hdr('INCIDENT', sl)),
      SizedBox(width: 52, child: _hdr('STATUS', sl)),
      SizedBox(width: 44, child: _hdr('RISK', sl, center: true)),
      SizedBox(width: 44, child: _hdr('SEV', sl, center: true)),
      const SizedBox(width: 30),
    ]));

  Widget _hdr(String t, SL sl, {bool center = false}) =>
    Text(t, textAlign: center ? TextAlign.center : TextAlign.left,
      style: TextStyle(color: sl.text4, fontSize: 9,
          fontWeight: FontWeight.w800, letterSpacing: 0.8));

  // ── REPORT ROW ───────────────────────────────────────────────
  Widget _reportRow(Map<String, dynamic> inc, SL sl) {
    final sev       = inc['severity']?.toString() ?? 'MEDIUM';
    final status    = inc['status']?.toString().toUpperCase() ?? 'OPEN';
    final sevColor  = SeverityBadge.color(sev);
    final statColor = _statusColor(status);
    final score     = inc['riskScore']?.toString() ?? '—';
    final plant     = inc['plant']?.toString() ?? '';
    final reporter  = inc['reportedBy']?.toString() ?? '';
    final isAI      = inc['type']?.toString() == 'AI_SCAN';
    final isClosed  = status == 'CLOSED';
    final dateStr   = _formatDate(inc['date']?.toString());

    return InkWell(
      onTap: () => _openDetail(inc),
      child: Container(
        color: isClosed
            ? AppColors.green.withOpacity(0.03) : Colors.transparent,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Row(children: [
          // Severity dot
          Container(
            width: 8, height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle, color: sevColor,
              boxShadow: [BoxShadow(
                  color: sevColor.withOpacity(0.5), blurRadius: 4)])),
          const SizedBox(width: 8),
          // Title + meta
          Expanded(flex: 4, child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                if (isAI) _typeBadge('AI', AppColors.accent),
                if (!isAI) _typeBadge('NM', AppColors.amber),
                const SizedBox(width: 4),
                Expanded(child: Text(
                  inc['title']?.toString() ?? 'Incident',
                  style: TextStyle(
                    color: isClosed ? sl.text3 : sl.text1,
                    fontSize: 12, fontWeight: FontWeight.w600,
                    decoration: isClosed
                        ? TextDecoration.lineThrough : null),
                  maxLines: 1, overflow: TextOverflow.ellipsis)),
              ]),
              const SizedBox(height: 2),
              Text('$plant · $dateStr',
                style: TextStyle(color: sl.text4, fontSize: 10),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            ])),

          // Status badge
          SizedBox(width: 52, child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 4, vertical: 2),
            decoration: BoxDecoration(
              color: statColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(5),
              border: Border.all(
                  color: statColor.withOpacity(0.4))),
            child: Text(
              status == 'ACTION TAKEN' ? 'ACTD'
                  : status == 'INVESTIGATING' ? 'INVG'
                  : status,
              textAlign: TextAlign.center,
              style: TextStyle(color: statColor,
                  fontSize: 8, fontWeight: FontWeight.w800)))),

          // Risk score
          SizedBox(width: 44, child: Center(child: score == '—'
            ? Text('—', style: TextStyle(
                color: sl.text4, fontSize: 11))
            : Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  color: sevColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6)),
                child: Text(score,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: sevColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w800))))),

          // Severity badge
          SizedBox(width: 44,
              child: SeverityBadge(sev, small: true)),

          // Chevron
          Icon(Icons.chevron_right_rounded,
              color: sl.text4, size: 16),
        ])));
  }

  Widget _typeBadge(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
    decoration: BoxDecoration(
      color: color.withOpacity(0.12),
      borderRadius: BorderRadius.circular(4)),
    child: Text(label, style: TextStyle(
        color: color, fontSize: 7,
        fontWeight: FontWeight.w800)));

  Color _statusColor(String s) {
    switch (s.toUpperCase()) {
      case 'CLOSED':        return AppColors.green;
      case 'ACTION TAKEN':  return AppColors.cyan;
      case 'INVESTIGATING': return AppColors.amber;
      default:              return AppColors.red;
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
        _sevFilter != null ? 'No $_sevFilter incidents'
            : _statusFilter != null ? 'No $_statusFilter incidents'
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
      return DateFormat('dd MMM').format(DateTime.parse(raw));
    } catch (_) { return raw.substring(0, 8); }
  }
}
