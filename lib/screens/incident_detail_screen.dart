// lib/screens/incident_detail_screen.dart
// REDESIGNED: compact cards, light/neutral theme aware, no blank space

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
    super.key, required this.incident, this.onStatusChanged,
  });
  @override
  State<IncidentDetailScreen> createState() => _IncidentDetailScreenState();
}

class _IncidentDetailScreenState extends State<IncidentDetailScreen> {
  late Map<String, dynamic> _inc;
  final _actionCtrl   = TextEditingController();
  final _closedByCtrl = TextEditingController();
  final _remarksCtrl  = TextEditingController();
  bool _saving = false;

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
    _actionCtrl.dispose(); _closedByCtrl.dispose(); _remarksCtrl.dispose();
    super.dispose();
  }

  String get _status   => (_inc['status']?.toString() ?? 'OPEN').toUpperCase();
  bool   get _isClosed => _status == 'CLOSED';

  Color _statusColor(String s) {
    switch (s.toUpperCase()) {
      case 'CLOSED':        return const Color(0xFF16A34A);
      case 'ACTION TAKEN':  return const Color(0xFF0891B2);
      case 'INVESTIGATING': return const Color(0xFFD97706);
      default:              return const Color(0xFFDC2626);
    }
  }
  Color _sevColor(String s) {
    switch (s.toUpperCase()) {
      case 'CRITICAL': return AppColors.crit;
      case 'HIGH':     return AppColors.red;
      case 'MEDIUM':   return AppColors.amber;
      default:         return const Color(0xFF16A34A);
    }
  }
  String _fmt(String? r) {
    if (r == null || r.isEmpty) return '—';
    try { return DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.parse(r)); }
    catch (_) { return r; }
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

  Future<void> _advanceStatus(String newStatus) async {
    if (_saving) return;
    if (newStatus == 'CLOSED' && _actionCtrl.text.trim().isEmpty) {
      _snack('Enter corrective action first', AppColors.red); return;
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
      newStatus == 'CLOSED' ? '✅ Case closed & synced to Sheets'
          : '✅ Status → $newStatus',
      newStatus == 'CLOSED' ? const Color(0xFF16A34A) : AppColors.accent,
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
      content: Text(msg, style: const TextStyle(fontSize: 13)),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      margin: const EdgeInsets.all(12),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final sl  = SL.of(context);
    final sev = _inc['severity']?.toString() ?? 'MEDIUM';
    final sc  = _sevColor(sev);

    // ── Light neutral background regardless of dark/light mode ──
    final bgColor = sl.isDark
        ? const Color(0xFF1C1F2E)   // dark: deep blue-grey, not black
        : const Color(0xFFF5F6FA);  // light: soft grey-white

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: sl.isDark
            ? const Color(0xFF252840) : Colors.white,
        elevation: 0,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_rounded,
              color: sl.text1, size: 18),
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
      bottomNavigationBar: _isClosed ? null : _buildBottomBar(sl, bgColor),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

          // ── STATUS PIPELINE (compact) ─────────────────────────
          _buildStatusPipeline(sl, bgColor),
          const SizedBox(height: 12),

          // ── HEADER ROW ───────────────────────────────────────
          Row(children: [
            _pill(sev, sc),
            const SizedBox(width: 6),
            _pill(
              _inc['type']?.toString() == 'AI_SCAN'
                  ? '🔍 AI Scan' : '⚠️ Near Miss',
              AppColors.accent),
            const Spacer(),
            if (_inc['riskScore'] != null)
              _scoreCircle(_inc['riskScore'], sc),
          ]),
          const SizedBox(height: 12),

          // ── EVIDENCE PHOTO (if available) ────────────────────
          _buildEvidencePhoto(sl, bgColor),

          // ── COMPACT INFO ROWS (not giant grid) ───────────────
          _buildCompactInfo(sl, bgColor),
          const SizedBox(height: 12),

          // ── DESCRIPTION ──────────────────────────────────────
          if ((_inc['desc']?.toString() ?? '').isNotEmpty) ...[
            _secLabel('Description', sl),
            _infoBox(_inc['desc']?.toString() ?? '', sl, bgColor),
            const SizedBox(height: 10),
          ],

          // ── IMMEDIATE ACTION ─────────────────────────────────
          if ((_inc['immediateAction']?.toString() ?? '').isNotEmpty) ...[
            _secLabel('Immediate Action at Site', sl),
            _infoBox(_inc['immediateAction']?.toString() ?? '', sl, bgColor),
            const SizedBox(height: 10),
          ],

          // ── HAZARDS LIST ─────────────────────────────────────
          _buildHazardsList(sl, bgColor),

          // ── MITIGATION / CLOSED ──────────────────────────────
          if (!_isClosed)
            _buildMitigationForm(sl, bgColor)
          else
            _buildClosedSummary(sl, bgColor),
          const SizedBox(height: 10),

          // ── TIMELINE ─────────────────────────────────────────
          _buildTimeline(sl, bgColor),
          const SizedBox(height: 80),
        ]),
      ),
    );
  }

  // ─── STATUS PIPELINE ─────────────────────────────────────────
  Widget _buildStatusPipeline(SL sl, Color bg) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: _card(sl, bg),
    child: Row(
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
              width: 24, height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: done  ? const Color(0xFF16A34A).withOpacity(0.12)
                    : active ? color.withOpacity(0.12) : Colors.transparent,
                border: Border.all(
                  color: done  ? const Color(0xFF16A34A)
                      : active ? color
                      : sl.border.withOpacity(0.5),
                  width: active ? 2 : 1)),
              child: Center(child: done
                ? const Icon(Icons.check_rounded,
                    color: Color(0xFF16A34A), size: 12)
                : Text('${idx+1}', style: TextStyle(
                    color: active ? color : sl.text4,
                    fontSize: 9, fontWeight: FontWeight.w700)))),
            const SizedBox(height: 3),
            Text(label, textAlign: TextAlign.center,
              style: TextStyle(
                color: done  ? const Color(0xFF16A34A)
                    : active ? color : sl.text4,
                fontSize: 7,
                fontWeight: active ? FontWeight.w800 : FontWeight.w500),
              maxLines: 1, overflow: TextOverflow.ellipsis),
          ])),
          if (!isLast) Expanded(child: Container(
            height: 1.5,
            margin: const EdgeInsets.only(bottom: 16),
            color: done
                ? const Color(0xFF16A34A).withOpacity(0.4)
                : sl.border.withOpacity(0.4))),
        ]));
      }).toList()));

  // ─── EVIDENCE PHOTO ──────────────────────────────────────────
  Widget _buildEvidencePhoto(SL sl, Color bg) {
    final imgB64 = _inc['imageBase64']?.toString() ?? '';
    final thumbB64 = _inc['thumbnailBase64']?.toString() ?? '';
    final b64 = imgB64.isNotEmpty ? imgB64 : thumbB64;
    if (b64.isEmpty) return const SizedBox.shrink();

    return Column(children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxHeight: 220),
          decoration: BoxDecoration(
            color: sl.isDark ? const Color(0xFF252840) : Colors.white,
            border: Border.all(color: sl.isDark
                ? Colors.white10 : Colors.black12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Image.memory(
            base64Decode(b64),
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          ),
        ),
      ),
      const SizedBox(height: 12),
    ]);
  }

  // ─── COMPACT INFO (replaces giant GridView) ──────────────────
  Widget _buildCompactInfo(SL sl, Color bg) {
    final rows = [
      ['📅 Date',         _fmt(_inc['date']?.toString())],
      ['🏭 Plant',        _inc['plant']?.toString() ?? '—'],
      ['🏢 Department',   _inc['dept']?.toString() ?? '—'],
      ['📍 Location',     _inc['location']?.toString() ?? '—'],
      ['👤 Reported by',  _inc['reportedBy']?.toString() ?? '—'],
      ['🔖 P.No',         _inc['reportedByPno']?.toString() ?? '—'],
      ['⚠️ WSA Cause',    _inc['wsaCategory']?.toString() ?? '—'],
      ['👥 People',       _inc['people']?.toString() ?? '—'],
    ].where((r) => r[1] != '—' && r[1].isNotEmpty).toList();

    return Container(
      decoration: _card(sl, bg),
      child: Column(
        children: rows.asMap().entries.map((e) {
          final isLast = e.key == rows.length - 1;
          final r = e.value;
          return Column(children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 9),
              child: Row(children: [
                Text(r[0], style: TextStyle(
                    color: sl.text4, fontSize: 11)),
                const SizedBox(width: 10),
                Expanded(child: Text(r[1],
                  textAlign: TextAlign.right,
                  style: TextStyle(color: sl.text1, fontSize: 12,
                      fontWeight: FontWeight.w600),
                  maxLines: 2, overflow: TextOverflow.ellipsis)),
              ])),
            if (!isLast) Divider(height: 1,
                color: sl.border.withOpacity(0.35),
                indent: 14, endIndent: 14),
          ]);
        }).toList()));
  }

  // ─── HAZARD LIST ─────────────────────────────────────────────
  Widget _buildHazardsList(SL sl, Color bg) {
    final hazards = _parseHazards();
    if (hazards.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _secLabel('Hazards Identified (${hazards.length})', sl),
      Container(
        decoration: _card(sl, bg),
        child: Column(children: hazards.asMap().entries.map((e) {
          final idx  = e.key;
          final h    = Map<String, dynamic>.from(e.value as Map);
          final sev  = h['severity']?.toString() ?? 'MEDIUM';
          final sc   = _sevColor(sev);
          final isLast = idx == hazards.length - 1;
          return Column(children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 20, height: 20,
                    decoration: BoxDecoration(
                        color: sc, shape: BoxShape.circle),
                    child: Center(child: Text('${idx+1}',
                      style: const TextStyle(color: Colors.white,
                          fontSize: 9, fontWeight: FontWeight.w800)))),
                  const SizedBox(width: 8),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Expanded(child: Text(h['name']?.toString() ?? '—',
                          style: TextStyle(color: sl.text1, fontSize: 12,
                              fontWeight: FontWeight.w700))),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: sc.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(5),
                            border: Border.all(color: sc)),
                          child: Text(
                            sev.length > 4 ? sev.substring(0, 4) : sev,
                            style: TextStyle(color: sc, fontSize: 8,
                                fontWeight: FontWeight.w800))),
                      ]),
                      if ((h['description']?.toString() ?? '').isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(h['description']?.toString() ?? '',
                          style: TextStyle(color: sl.text2, fontSize: 11,
                              height: 1.4)),
                      ],
                      if ((h['regulation']?.toString() ?? '').isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Row(children: [
                          const Text('⚖️ ', style: TextStyle(fontSize: 9)),
                          Expanded(child: Text(
                            h['regulation']?.toString() ?? '',
                            style: TextStyle(color: sl.text4, fontSize: 9,
                                fontStyle: FontStyle.italic))),
                        ]),
                      ],
                      if ((h['correctiveAction']?.toString() ?? '').isNotEmpty) ...[
                        const SizedBox(height: 5),
                        Container(
                          padding: const EdgeInsets.all(7),
                          decoration: BoxDecoration(
                            color: AppColors.accent.withOpacity(0.07),
                            borderRadius: BorderRadius.circular(7),
                            border: Border.all(
                                color: AppColors.accent.withOpacity(0.25))),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('🔧 ',
                                  style: TextStyle(fontSize: 10)),
                              Expanded(child: Text(
                                h['correctiveAction']?.toString() ?? '',
                                style: const TextStyle(
                                    color: AppColors.accent,
                                    fontSize: 10, height: 1.4))),
                            ])),
                      ],
                    ])),
                ])),
            if (!isLast) Divider(height: 1,
                color: sl.border.withOpacity(0.35),
                indent: 12, endIndent: 12),
          ]);
        }).toList())),
      const SizedBox(height: 10),
    ]);
  }

  // ─── MITIGATION FORM ─────────────────────────────────────────
  Widget _buildMitigationForm(SL sl, Color bg) => Container(
    decoration: _card(sl, bg,
        borderColor: AppColors.accent.withOpacity(0.4)),
    padding: const EdgeInsets.all(14),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(
          width: 28, height: 28,
          decoration: BoxDecoration(
            color: AppColors.accent.withOpacity(0.1),
            borderRadius: BorderRadius.circular(7)),
          child: const Icon(Icons.engineering_rounded,
              color: AppColors.accent, size: 16)),
        const SizedBox(width: 8),
        Text('Mitigation & Closure',
          style: TextStyle(color: sl.text1, fontSize: 13,
              fontWeight: FontWeight.w700)),
      ]),
      const SizedBox(height: 12),
      _formLabel('Corrective Action Taken *', sl),
      _formField(_actionCtrl,
          'Describe what was done to mitigate…', 3, sl, bg),
      const SizedBox(height: 10),
      _formLabel('Closed / Verified by', sl),
      _formField(_closedByCtrl, 'Name and designation', 1, sl, bg),
      const SizedBox(height: 10),
      _formLabel('Additional remarks', sl),
      _formField(_remarksCtrl, 'Any other notes…', 2, sl, bg),
    ]));

  Widget _formLabel(String lbl, SL sl) => Padding(
    padding: const EdgeInsets.only(bottom: 5),
    child: Text(lbl, style: TextStyle(color: sl.text3, fontSize: 11,
        fontWeight: FontWeight.w600)));

  Widget _formField(TextEditingController c, String hint,
      int lines, SL sl, Color bg) {
    final fieldBg = sl.isDark
        ? const Color(0xFF2A2D42) : const Color(0xFFF0F1F5);
    return TextField(
      controller: c, maxLines: lines,
      style: TextStyle(color: sl.text1, fontSize: 13, height: 1.5),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: sl.text4, fontSize: 11),
        filled: true, fillColor: fieldBg,
        contentPadding: const EdgeInsets.all(11),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(9),
          borderSide: BorderSide(color: sl.border.withOpacity(0.5))),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(9),
          borderSide: BorderSide(color: sl.border.withOpacity(0.5))),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(9),
          borderSide: const BorderSide(
              color: AppColors.accent, width: 2))));
  }

  // ─── CLOSED SUMMARY ──────────────────────────────────────────
  Widget _buildClosedSummary(SL sl, Color bg) => Container(
    decoration: _card(sl, bg,
        borderColor: const Color(0xFF16A34A).withOpacity(0.4)),
    padding: const EdgeInsets.all(14),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Row(children: [
        Icon(Icons.check_circle_rounded,
            color: Color(0xFF16A34A), size: 18),
        SizedBox(width: 7),
        Text('Case Closed', style: TextStyle(
            color: Color(0xFF16A34A), fontSize: 13,
            fontWeight: FontWeight.w700)),
      ]),
      const SizedBox(height: 10),
      ...([
        ['Corrective Action', _inc['correctiveAction']],
        ['Closed By',         _inc['closedBy']],
        ['Remarks',           _inc['closingRemarks']],
        ['Closed At',         _inc['closedAt'] != null
            ? _fmt(_inc['closedAt']?.toString()) : null],
      ].where((r) => r[1] != null && r[1].toString().isNotEmpty)
        .map((r) => Padding(
          padding: const EdgeInsets.only(bottom: 7),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 110,
                child: Text(r[0].toString(),
                  style: TextStyle(color: sl.text4, fontSize: 10,
                      fontWeight: FontWeight.w600))),
              Expanded(child: Text(r[1].toString(),
                style: TextStyle(color: sl.text1, fontSize: 12,
                    height: 1.4))),
            ])))
        .toList()),
    ]));

  // ─── TIMELINE ────────────────────────────────────────────────
  Widget _buildTimeline(SL sl, Color bg) {
    final events = <Map<String, String>>[];
    void add(String? ts, String label, String icon) {
      if (ts == null || ts.isEmpty) return;
      events.add({'label': label, 'time': _fmt(ts), 'icon': icon});
    }
    add(_inc['date']?.toString(),                  'Reported',               '📝');
    add(_inc['investigationStartedAt']?.toString(), 'Investigation started',  '🔍');
    add(_inc['actionTakenAt']?.toString(),           'Action taken',           '🔧');
    add(_inc['closedAt']?.toString(),               'Closed',                 '✅');
    if (events.isEmpty) return const SizedBox.shrink();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _secLabel('Timeline', sl),
      Container(
        decoration: _card(sl, bg),
        padding: const EdgeInsets.all(14),
        child: Column(children: events.asMap().entries.map((e) {
          final isLast = e.key == events.length - 1;
          final ev = e.value;
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Column(children: [
              Container(
                width: 26, height: 26,
                decoration: BoxDecoration(
                  color: sl.isDark
                      ? const Color(0xFF2A2D42)
                      : const Color(0xFFF0F1F5),
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: sl.border.withOpacity(0.5))),
                child: Center(child: Text(ev['icon']!,
                    style: const TextStyle(fontSize: 12)))),
              if (!isLast) Container(
                  width: 2, height: 24,
                  color: sl.border.withOpacity(0.4)),
            ]),
            const SizedBox(width: 10),
            Expanded(child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 16),
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

  // ─── BOTTOM ACTION BAR ───────────────────────────────────────
  Widget _buildBottomBar(SL sl, Color bg) {
    final curIdx  = _statusOrder.indexOf(_status);
    final nextIdx = curIdx + 1;
    final hasNext = nextIdx < _statusOrder.length;
    final nextSt  = hasNext ? _statusOrder[nextIdx] : null;
    final isClose = nextSt == 'CLOSED';

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 26),
      decoration: BoxDecoration(
        color: sl.isDark ? const Color(0xFF252840) : Colors.white,
        border: Border(top: BorderSide(
            color: sl.border.withOpacity(0.4)))),
      child: Row(children: [
        if (_status == 'OPEN') ...[
          Expanded(child: OutlinedButton.icon(
            onPressed: _saving
                ? null : () => _advanceStatus('INVESTIGATING'),
            icon: const Icon(Icons.search_rounded,
                color: Color(0xFFD97706), size: 15),
            label: const Text('Investigate',
              style: TextStyle(color: Color(0xFFD97706),
                  fontWeight: FontWeight.w700, fontSize: 12)),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(
                  color: Color(0xFFD97706), width: 1.5),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10))),
          )),
          const SizedBox(width: 8),
        ],
        if (hasNext)
          Expanded(flex: 2, child: ElevatedButton.icon(
            onPressed: _saving ? null : () => _advanceStatus(nextSt!),
            icon: _saving
              ? const SizedBox(width: 14, height: 14,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : Icon(isClose ? Icons.lock_rounded
                    : Icons.arrow_forward_rounded,
                  size: 15, color: Colors.white),
            label: Text(
              _saving ? 'Saving…'
                  : isClose ? 'Close Case'
                  : 'Mark as $nextSt',
              style: const TextStyle(color: Colors.white,
                  fontWeight: FontWeight.w700, fontSize: 12)),
            style: ElevatedButton.styleFrom(
              backgroundColor: isClose
                  ? const Color(0xFF16A34A) : AppColors.accent,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10))),
          )),
      ]));
  }

  // ─── HELPERS ────────────────────────────────────────────────
  BoxDecoration _card(SL sl, Color bg, {Color? borderColor}) =>
    BoxDecoration(
      color: sl.isDark ? const Color(0xFF252840) : Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
          color: borderColor ?? sl.border.withOpacity(0.4)),
      boxShadow: [BoxShadow(
        color: Colors.black.withOpacity(sl.isDark ? 0.15 : 0.04),
        blurRadius: 8, offset: const Offset(0, 2))]);

  Widget _pill(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      color: color.withOpacity(0.1),
      borderRadius: BorderRadius.circular(7),
      border: Border.all(color: color.withOpacity(0.5))),
    child: Text(text, style: TextStyle(color: color,
        fontSize: 11, fontWeight: FontWeight.w700)));

  Widget _scoreCircle(dynamic score, Color color) => Container(
    width: 40, height: 40,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      border: Border.all(color: color, width: 2),
      color: color.withOpacity(0.08)),
    child: Center(child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text('$score', style: TextStyle(color: color,
            fontSize: 12, fontWeight: FontWeight.w800)),
        Text('/100', style: TextStyle(color: color, fontSize: 6)),
      ])));

  Widget _secLabel(String lbl, SL sl) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(children: [
      Container(width: 3, height: 13, color: AppColors.accent,
          margin: const EdgeInsets.only(right: 7)),
      Text(lbl.toUpperCase(), style: TextStyle(color: sl.text4,
          fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
    ]));

  Widget _infoBox(String text, SL sl, Color bg) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(11),
    decoration: BoxDecoration(
      color: sl.isDark ? const Color(0xFF2A2D42) : const Color(0xFFF0F1F5),
      borderRadius: BorderRadius.circular(9),
      border: Border.all(color: sl.border.withOpacity(0.4))),
    child: Text(text, style: TextStyle(color: sl.text2,
        fontSize: 12, height: 1.5)));
}
