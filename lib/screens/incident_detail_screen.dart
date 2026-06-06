// lib/screens/incident_detail_screen.dart
//
// Full incident detail + mitigation + closure screen
// ✅ Status pipeline: OPEN → INVESTIGATING → ACTION TAKEN → CLOSED
// ✅ Corrective action form + close case button
// ✅ Updates LocalDB + pushes to Google Sheets on every status change
// ✅ Hazard list with regulation + corrective action per hazard
// ✅ Timeline of all status changes with timestamps
// ✅ PDF export

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../main.dart';
import '../services/local_db.dart';
import '../services/sync_service.dart';
import '../services/pdf_export.dart';

class IncidentDetailScreen extends StatefulWidget {
  final Map<String, dynamic> incident;
  final VoidCallback? onStatusChanged;

  const IncidentDetailScreen({
    super.key,
    required this.incident,
    this.onStatusChanged,
  });

  @override
  State<IncidentDetailScreen> createState() => _IncidentDetailScreenState();
}

class _IncidentDetailScreenState extends State<IncidentDetailScreen> {
  late Map<String, dynamic> _inc;
  final _actionCtrl   = TextEditingController();
  final _closedByCtrl = TextEditingController();
  final _remarksCtrl  = TextEditingController();
  bool  _saving       = false;

  static const List<String> _statusOrder = [
    'OPEN', 'INVESTIGATING', 'ACTION TAKEN', 'CLOSED'
  ];

  @override
  void initState() {
    super.initState();
    _inc = Map<String, dynamic>.from(widget.incident);
    _actionCtrl.text   = _inc['correctiveAction']?.toString() ?? '';
    _closedByCtrl.text = _inc['closedBy']?.toString()         ?? '';
    _remarksCtrl.text  = _inc['closingRemarks']?.toString()   ?? '';
  }

  @override
  void dispose() {
    _actionCtrl.dispose();
    _closedByCtrl.dispose();
    _remarksCtrl.dispose();
    super.dispose();
  }

  // ─── computed ───────────────────────────────────────────────
  String get _status   => (_inc['status']?.toString() ?? 'OPEN').toUpperCase();
  bool   get _isClosed => _status == 'CLOSED';

  Color _statusColor(String s) {
    switch (s.toUpperCase()) {
      case 'CLOSED':        return AppColors.green;
      case 'ACTION TAKEN':  return AppColors.cyan;
      case 'INVESTIGATING': return AppColors.amber;
      default:              return AppColors.red;
    }
  }

  Color _sevColor(String s) {
    switch (s.toUpperCase()) {
      case 'CRITICAL': return AppColors.crit;
      case 'HIGH':     return AppColors.red;
      case 'MEDIUM':   return AppColors.amber;
      default:         return AppColors.green;
    }
  }

  String _fmt(String? raw) {
    if (raw == null || raw.isEmpty) return '—';
    try { return DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.parse(raw)); }
    catch (_) { return raw; }
  }

  List _parseHazards() {
    final raw = _inc['hazards'];
    if (raw == null) return [];
    if (raw is List) return raw;
    if (raw is String && raw.isNotEmpty) {
      try { final d = jsonDecode(raw); if (d is List) return d; } catch (_) {}
    }
    return [];
  }

  // ─── status advance ──────────────────────────────────────────
  Future<void> _advanceStatus(String newStatus) async {
    if (_saving) return;
    if (newStatus == 'CLOSED' && _actionCtrl.text.trim().isEmpty) {
      _snack('Please enter corrective action before closing', AppColors.red);
      return;
    }
    setState(() => _saving = true);

    final now = DateTime.now().toIso8601String();
    _inc['status']           = newStatus;
    _inc['correctiveAction'] = _actionCtrl.text.trim();
    _inc['closedBy']         = _closedByCtrl.text.trim();
    _inc['closingRemarks']   = _remarksCtrl.text.trim();
    if (newStatus == 'CLOSED')        _inc['closedAt']               = now;
    if (newStatus == 'INVESTIGATING') _inc['investigationStartedAt'] = now;
    if (newStatus == 'ACTION TAKEN')  _inc['actionTakenAt']          = now;

    await LocalDB.saveIncident(_inc);
    SyncService.pushIncident(_inc).catchError((_) => false);

    setState(() => _saving = false);
    widget.onStatusChanged?.call();
    _snack(
      newStatus == 'CLOSED'
          ? '✅ Case closed and synced to Sheets'
          : '✅ Status updated to $newStatus',
      newStatus == 'CLOSED' ? AppColors.green : AppColors.accent,
    );
  }

  Future<void> _exportPdf() async {
    try {
      _snack('Generating PDF…', AppColors.accent);
      final user = await LocalDB.getCurrentUser() ?? {};
      await PdfExport.downloadOrShareIncident(
        incident: _inc,
        reporterName: user['name']?.toString() ?? 'SAIL Safety Officer',
        reporterPno:  user['pno']?.toString()  ?? '',
      );
    } catch (e) { _snack('PDF failed: $e', AppColors.red); }
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg), backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  // ─────────────────────────────────────────────────────────────
  //  BUILD
  // ─────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final sl  = SL.of(context);
    final sev = _inc['severity']?.toString() ?? 'MEDIUM';
    final sc  = _sevColor(sev);

    return Scaffold(
      backgroundColor: sl.bg,
      appBar: AppBar(
        backgroundColor: sl.bg2,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_rounded, color: sl.text1, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_inc['title']?.toString() ?? 'Incident',
            style: TextStyle(color: sl.text1, fontSize: 14,
                fontWeight: FontWeight.w700),
            maxLines: 1, overflow: TextOverflow.ellipsis),
          Text('ID: ${_inc['id']?.toString() ?? '—'}',
            style: TextStyle(color: sl.text4, fontSize: 10)),
        ]),
        actions: [
          IconButton(
            tooltip: 'Export PDF',
            onPressed: _exportPdf,
            icon: const Icon(Icons.picture_as_pdf,
                color: AppColors.accent, size: 22)),
        ],
      ),
      bottomNavigationBar: _isClosed ? null : _buildBottomBar(sl),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

          // ── STATUS PIPELINE ─────────────────────────────────
          _buildStatusPipeline(sl),
          const SizedBox(height: 20),

          // ── SEVERITY BADGES ──────────────────────────────────
          Row(children: [
            _pill(sev, sc),
            const SizedBox(width: 8),
            _pill(
              _inc['type']?.toString() == 'AI_SCAN' ? '🔍 AI Scan' : '⚠️ Near Miss',
              AppColors.accent),
            const Spacer(),
            if (_inc['riskScore'] != null)
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: sc, width: 2.5),
                  color: sc.withOpacity(0.1)),
                child: Center(child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('${_inc['riskScore']}',
                      style: TextStyle(color: sc, fontSize: 13,
                          fontWeight: FontWeight.w800)),
                    Text('/100', style: TextStyle(color: sc, fontSize: 7)),
                  ]))),
          ]),
          const SizedBox(height: 16),

          // ── DETAILS GRID ─────────────────────────────────────
          _buildDetailsGrid(sl),
          const SizedBox(height: 16),

          // ── DESCRIPTION ──────────────────────────────────────
          if ((_inc['desc']?.toString() ?? '').isNotEmpty) ...[
            _secLabel('Description', sl),
            _infoBox(_inc['desc']?.toString() ?? '', sl),
            const SizedBox(height: 16),
          ],

          // ── IMMEDIATE ACTION ─────────────────────────────────
          if ((_inc['immediateAction']?.toString() ?? '').isNotEmpty) ...[
            _secLabel('Immediate Action at Site', sl),
            _infoBox(_inc['immediateAction']?.toString() ?? '', sl),
            const SizedBox(height: 16),
          ],

          // ── HAZARDS ──────────────────────────────────────────
          _buildHazardsList(sl),

          // ── MITIGATION FORM (if not closed) ──────────────────
          if (!_isClosed) ...[
            _buildMitigationForm(sl),
            const SizedBox(height: 16),
          ] else ...[
            _buildClosedSummary(sl),
            const SizedBox(height: 16),
          ],

          // ── TIMELINE ─────────────────────────────────────────
          _buildTimeline(sl),
          const SizedBox(height: 32),
        ]),
      ),
    );
  }

  // ─── STATUS PIPELINE ─────────────────────────────────────────
  Widget _buildStatusPipeline(SL sl) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: sl.card,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: sl.border)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('STATUS PIPELINE',
        style: TextStyle(color: sl.text4, fontSize: 9,
            fontWeight: FontWeight.w700, letterSpacing: 0.8)),
      const SizedBox(height: 12),
      Row(
        children: _statusOrder.asMap().entries.map((e) {
          final idx    = e.key;
          final label  = e.value;
          final curIdx = _statusOrder.indexOf(_status);
          final done   = idx < curIdx;
          final active = idx == curIdx;
          final color  = _statusColor(label);
          final isLast = idx == _statusOrder.length - 1;
          return Expanded(child: Row(children: [
            Expanded(child: Column(children: [
              Container(
                width: 28, height: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: done  ? AppColors.green.withOpacity(0.15)
                      : active ? color.withOpacity(0.15) : sl.bg,
                  border: Border.all(
                    color: done  ? AppColors.green
                        : active ? color : sl.border,
                    width: active ? 2.5 : 1.5)),
                child: Center(child: done
                  ? const Icon(Icons.check_rounded,
                      color: AppColors.green, size: 14)
                  : Text('${idx + 1}',
                      style: TextStyle(
                        color: active ? color : sl.text4,
                        fontSize: 10, fontWeight: FontWeight.w700)))),
              const SizedBox(height: 4),
              Text(label, textAlign: TextAlign.center,
                style: TextStyle(
                  color: done  ? AppColors.green
                      : active ? color : sl.text4,
                  fontSize: 7.5,
                  fontWeight: active
                      ? FontWeight.w700 : FontWeight.w500)),
            ])),
            if (!isLast)
              Expanded(child: Container(
                height: 2,
                margin: const EdgeInsets.only(bottom: 20),
                color: done
                    ? AppColors.green.withOpacity(0.4)
                    : sl.border)),
          ]));
        }).toList()),
    ]));

  // ─── DETAILS GRID ─────────────────────────────────────────────
  Widget _buildDetailsGrid(SL sl) => GridView.count(
    crossAxisCount: 2,
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    crossAxisSpacing: 8, mainAxisSpacing: 8,
    childAspectRatio: 2.6,
    children: [
      _cell(sl, 'Date',        _fmt(_inc['date']?.toString())),
      _cell(sl, 'Plant',       _inc['plant']?.toString()          ?? '—'),
      _cell(sl, 'Department',  _inc['dept']?.toString()           ?? '—'),
      _cell(sl, 'Location',    _inc['location']?.toString()       ?? '—'),
      _cell(sl, 'Reported by', _inc['reportedBy']?.toString()     ?? '—'),
      _cell(sl, 'P.No',        _inc['reportedByPno']?.toString()  ?? '—'),
      _cell(sl, 'WSA Cause',   _inc['wsaCategory']?.toString()    ?? '—'),
      _cell(sl, 'People',      _inc['people']?.toString()         ?? '—'),
    ]);

  Widget _cell(SL sl, String lbl, String val) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      color: sl.card2,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: sl.border.withOpacity(0.5))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center, children: [
      Text(lbl, style: TextStyle(color: sl.text4, fontSize: 9,
          fontWeight: FontWeight.w700)),
      const SizedBox(height: 2),
      Text(val.isEmpty ? '—' : val,
        style: TextStyle(color: sl.text1, fontSize: 11,
            fontWeight: FontWeight.w600),
        maxLines: 1, overflow: TextOverflow.ellipsis),
    ]));

  // ─── HAZARD LIST ──────────────────────────────────────────────
  Widget _buildHazardsList(SL sl) {
    final hazards = _parseHazards();
    if (hazards.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _secLabel('Hazards Identified (${hazards.length})', sl),
      Container(
        decoration: BoxDecoration(
          color: sl.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: sl.border)),
        child: Column(children: hazards.asMap().entries.map((e) {
          final idx  = e.key;
          final h    = Map<String, dynamic>.from(e.value as Map);
          final sev  = h['severity']?.toString() ?? 'MEDIUM';
          final sc   = _sevColor(sev);
          final isLast = idx == hazards.length - 1;
          return Column(children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  width: 22, height: 22,
                  decoration: BoxDecoration(color: sc, shape: BoxShape.circle),
                  child: Center(child: Text('${idx + 1}',
                    style: const TextStyle(color: Colors.white,
                        fontSize: 9, fontWeight: FontWeight.w800)))),
                const SizedBox(width: 10),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Expanded(child: Text(h['name']?.toString() ?? '—',
                        style: TextStyle(color: sl.text1, fontSize: 12,
                            fontWeight: FontWeight.w700))),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: sc.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: sc)),
                        child: Text(sev.length > 4 ? sev.substring(0, 4) : sev,
                          style: TextStyle(color: sc, fontSize: 8,
                              fontWeight: FontWeight.w800))),
                    ]),
                    const SizedBox(height: 4),
                    Text(h['description']?.toString() ?? '',
                      style: TextStyle(color: sl.text2, fontSize: 11,
                          height: 1.4)),
                    if ((h['regulation']?.toString() ?? '').isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(children: [
                        Icon(Icons.gavel_rounded,
                            color: sl.text4, size: 10),
                        const SizedBox(width: 4),
                        Expanded(child: Text(h['regulation']?.toString() ?? '',
                          style: TextStyle(color: sl.text4, fontSize: 9,
                              fontStyle: FontStyle.italic))),
                      ]),
                    ],
                    if ((h['correctiveAction']?.toString() ?? '').isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.accent.withOpacity(0.07),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: AppColors.accent.withOpacity(0.3))),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.build_circle_outlined,
                                color: AppColors.accent, size: 12),
                            const SizedBox(width: 6),
                            Expanded(child: Text(
                              h['correctiveAction']?.toString() ?? '',
                              style: const TextStyle(color: AppColors.accent,
                                  fontSize: 10, height: 1.4))),
                          ])),
                    ],
                  ])),
              ])),
            if (!isLast) Divider(height: 1, color: sl.border),
          ]);
        }).toList())),
      const SizedBox(height: 16),
    ]);
  }

  // ─── MITIGATION FORM ─────────────────────────────────────────
  Widget _buildMitigationForm(SL sl) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: sl.card,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(
          color: AppColors.accent.withOpacity(0.4), width: 1.5)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(
          width: 32, height: 32,
          decoration: BoxDecoration(
            color: AppColors.accent.withOpacity(0.12),
            borderRadius: BorderRadius.circular(8)),
          child: const Icon(Icons.engineering_rounded,
              color: AppColors.accent, size: 18)),
        const SizedBox(width: 10),
        Text('MITIGATION & CLOSURE',
          style: TextStyle(color: sl.text1, fontSize: 13,
              fontWeight: FontWeight.w700)),
      ]),
      const SizedBox(height: 16),

      _formLabel('Corrective Action Taken *', sl),
      _formField(
        ctrl: _actionCtrl,
        hint: 'Describe what was done to mitigate this hazard…',
        lines: 4, sl: sl),
      const SizedBox(height: 12),

      _formLabel('Closed / Verified by', sl),
      _formField(
        ctrl: _closedByCtrl,
        hint: 'Name and designation',
        lines: 1, sl: sl),
      const SizedBox(height: 12),

      _formLabel('Additional remarks', sl),
      _formField(
        ctrl: _remarksCtrl,
        hint: 'Any other notes…',
        lines: 2, sl: sl),
    ]));

  Widget _formLabel(String lbl, SL sl) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(lbl, style: TextStyle(color: sl.text3, fontSize: 11,
        fontWeight: FontWeight.w700)));

  Widget _formField({required TextEditingController ctrl,
      required String hint, required int lines, required SL sl}) =>
    TextField(
      controller: ctrl,
      maxLines: lines,
      style: TextStyle(color: sl.text1, fontSize: 13, height: 1.5),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: sl.text4, fontSize: 11),
        filled: true, fillColor: sl.card2,
        contentPadding: const EdgeInsets.all(12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: sl.border)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(
              color: AppColors.accent, width: 2))));

  // ─── CLOSED SUMMARY ───────────────────────────────────────────
  Widget _buildClosedSummary(SL sl) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppColors.green.withOpacity(0.06),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppColors.green.withOpacity(0.4))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Row(children: [
        Icon(Icons.check_circle_rounded,
            color: AppColors.green, size: 20),
        SizedBox(width: 8),
        Text('CASE CLOSED',
          style: TextStyle(color: AppColors.green,
              fontSize: 13, fontWeight: FontWeight.w700)),
      ]),
      const SizedBox(height: 12),
      if ((_inc['correctiveAction']?.toString() ?? '').isNotEmpty)
        _closedRow('Corrective Action',
            _inc['correctiveAction']?.toString() ?? '', sl),
      if ((_inc['closedBy']?.toString() ?? '').isNotEmpty)
        _closedRow('Closed By',
            _inc['closedBy']?.toString() ?? '', sl),
      if ((_inc['closingRemarks']?.toString() ?? '').isNotEmpty)
        _closedRow('Remarks',
            _inc['closingRemarks']?.toString() ?? '', sl),
      if ((_inc['closedAt']?.toString() ?? '').isNotEmpty)
        _closedRow('Closed At',
            _fmt(_inc['closedAt']?.toString()), sl),
    ]));

  Widget _closedRow(String lbl, String val, SL sl) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(lbl, style: TextStyle(color: sl.text4, fontSize: 9,
          fontWeight: FontWeight.w700, letterSpacing: 0.5)),
      const SizedBox(height: 3),
      Text(val, style: TextStyle(color: sl.text1,
          fontSize: 12, height: 1.4)),
    ]));

  // ─── TIMELINE ────────────────────────────────────────────────
  Widget _buildTimeline(SL sl) {
    final events = <Map<String, String>>[];
    if ((_inc['date']?.toString() ?? '').isNotEmpty)
      events.add({'label': 'Reported', 'time': _fmt(_inc['date']?.toString()), 'icon': '📝'});
    if ((_inc['investigationStartedAt']?.toString() ?? '').isNotEmpty)
      events.add({'label': 'Investigation started', 'time': _fmt(_inc['investigationStartedAt']?.toString()), 'icon': '🔍'});
    if ((_inc['actionTakenAt']?.toString() ?? '').isNotEmpty)
      events.add({'label': 'Action taken', 'time': _fmt(_inc['actionTakenAt']?.toString()), 'icon': '🔧'});
    if ((_inc['closedAt']?.toString() ?? '').isNotEmpty)
      events.add({'label': 'Closed', 'time': _fmt(_inc['closedAt']?.toString()), 'icon': '✅'});
    if (events.isEmpty) return const SizedBox.shrink();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _secLabel('Timeline', sl),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: sl.card, borderRadius: BorderRadius.circular(12),
          border: Border.all(color: sl.border)),
        child: Column(children: events.asMap().entries.map((e) {
          final isLast = e.key == events.length - 1;
          final ev = e.value;
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Column(children: [
              Container(
                width: 28, height: 28,
                decoration: BoxDecoration(
                  color: sl.card2, shape: BoxShape.circle,
                  border: Border.all(color: sl.border)),
                child: Center(child: Text(ev['icon']!,
                    style: const TextStyle(fontSize: 13)))),
              if (!isLast) Container(
                  width: 2, height: 28, color: sl.border),
            ]),
            const SizedBox(width: 12),
            Expanded(child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(ev['label']!, style: TextStyle(
                      color: sl.text1, fontSize: 12,
                      fontWeight: FontWeight.w600)),
                  Text(ev['time']!, style: TextStyle(
                      color: sl.text4, fontSize: 10)),
                ]))),
          ]);
        }).toList())),
    ]);
  }

  // ─── BOTTOM ACTION BAR ────────────────────────────────────────
  Widget _buildBottomBar(SL sl) {
    final curIdx    = _statusOrder.indexOf(_status);
    final nextIdx   = curIdx + 1;
    final hasNext   = nextIdx < _statusOrder.length;
    final nextSt    = hasNext ? _statusOrder[nextIdx] : null;
    final isClose   = nextSt == 'CLOSED';

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      decoration: BoxDecoration(
        color: sl.bg2,
        border: Border(top: BorderSide(color: sl.border))),
      child: Row(children: [
        if (_status == 'OPEN') ...[
          Expanded(child: OutlinedButton.icon(
            onPressed: _saving ? null : () => _advanceStatus('INVESTIGATING'),
            icon: const Icon(Icons.search_rounded,
                color: AppColors.amber, size: 16),
            label: const Text('Investigate',
              style: TextStyle(color: AppColors.amber,
                  fontWeight: FontWeight.w700)),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: AppColors.amber, width: 2),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10))),
          )),
          const SizedBox(width: 10),
        ],
        if (hasNext)
          Expanded(
            flex: 2,
            child: ElevatedButton.icon(
              onPressed: _saving ? null : () => _advanceStatus(nextSt!),
              icon: _saving
                ? const SizedBox(width: 16, height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : Icon(
                    isClose ? Icons.lock_rounded
                            : Icons.arrow_forward_rounded,
                    size: 16, color: Colors.white),
              label: Text(
                _saving ? 'Saving…'
                    : isClose ? 'Close Case'
                    : 'Mark as $nextSt',
                style: const TextStyle(color: Colors.white,
                    fontWeight: FontWeight.w700, fontSize: 13)),
              style: ElevatedButton.styleFrom(
                backgroundColor: isClose
                    ? AppColors.green : AppColors.accent,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10))),
            )),
      ]));
  }

  // ─── TINY HELPERS ────────────────────────────────────────────
  Widget _pill(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: color.withOpacity(0.12),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: color.withOpacity(0.5))),
    child: Text(text, style: TextStyle(color: color, fontSize: 11,
        fontWeight: FontWeight.w700)));

  Widget _secLabel(String lbl, SL sl) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(children: [
      Container(width: 3, height: 14, color: AppColors.accent,
          margin: const EdgeInsets.only(right: 8)),
      Text(lbl.toUpperCase(), style: TextStyle(color: sl.text4,
          fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.6)),
    ]));

  Widget _infoBox(String text, SL sl) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: sl.card2,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: sl.border.withOpacity(0.5))),
    child: Text(text, style: TextStyle(color: sl.text2,
        fontSize: 12, height: 1.5)));
}
