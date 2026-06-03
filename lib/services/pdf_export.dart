import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb, Uint8List;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';
import 'dart:html' as html if (dart.library.io) 'pdf_export_stub.dart';

class PdfExport {
  static final PdfColor _sailBlue    = PdfColor.fromHex('#0D47A1');
  static final PdfColor _sailLight   = PdfColor.fromHex('#E3F2FD');
  static final PdfColor _critCol     = PdfColor.fromHex('#C62828');
  static final PdfColor _critBg      = PdfColor.fromHex('#FFEBEE');
  static final PdfColor _highCol     = PdfColor.fromHex('#E65100');
  static final PdfColor _highBg      = PdfColor.fromHex('#FFF3E0');
  static final PdfColor _medCol      = PdfColor.fromHex('#00838F');
  static final PdfColor _medBg       = PdfColor.fromHex('#E0F7FA');
  static final PdfColor _lowCol      = PdfColor.fromHex('#2E7D32');
  static final PdfColor _lowBg       = PdfColor.fromHex('#E8F5E9');
  static final PdfColor _divider     = PdfColor.fromHex('#BDBDBD');
  static final PdfColor _textDark    = PdfColor.fromHex('#212121');
  static final PdfColor _textMed     = PdfColor.fromHex('#616161');
  static final PdfColor _textLight   = PdfColor.fromHex('#9E9E9E');
  static final PdfColor _rowAlt      = PdfColor.fromHex('#F8FAFF');
  static final PdfColor _rowNorm     = PdfColors.white;

  // ─── MAIN ENTRY ──────────────────────────────────────────────────────────
  static Future<Uint8List> generateIncidentReportBytes({
    required Map<String, dynamic> incident,
    String reporterName = 'SAIL Safety Officer',
    String reporterPno = '',
    Uint8List? imageBytes,
  }) async {
    final pdf = pw.Document();
    final dateStr = DateFormat('dd MMM yyyy, HH:mm').format(
      DateTime.parse(incident['date'] ?? DateTime.now().toIso8601String()));

    // Decode image
    Uint8List? imgBytes = imageBytes;
    if (imgBytes == null && incident['imageBase64'] != null) {
      try { imgBytes = base64Decode(incident['imageBase64'].toString()); } catch (_) {}
    }

    // Parse hazards
    List<Map<String, dynamic>> hazards = _parseHazards(incident['hazards']);

    // Extract clean summary (first sentence before === or newline block)
    String summary = _cleanSummary(incident);

    final severity  = incident['severity']?.toString() ?? 'MEDIUM';
    final isAiScan  = incident['type']?.toString() == 'AI_SCAN';
    final riskScore = incident['riskScore'] ?? 0;
    final confidence = incident['confidence'] ?? 0;

    pdf.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(28, 28, 28, 28),
      header: (ctx) => _pageHeader(ctx.pageNumber > 1),
      footer: (ctx) => _pageFooter(ctx.pageNumber, ctx.pagesCount, reporterName, dateStr),
      build: (context) {
        final w = <pw.Widget>[];

        // 1 — Banner
        w.add(_banner(incident, severity, isAiScan, riskScore, confidence));
        w.add(pw.SizedBox(height: 12));

        // 2 — Incident details grid
        w.add(_sectionTitle('INCIDENT DETAILS'));
        w.add(pw.SizedBox(height: 5));
        w.add(_detailsGrid(incident, dateStr, reporterName, reporterPno));
        w.add(pw.SizedBox(height: 14));

        // 3 — Evidence photo
        if (imgBytes != null) {
          w.add(_sectionTitle('EVIDENCE PHOTOGRAPH'));
          w.add(pw.SizedBox(height: 5));
          w.add(_photoBox(imgBytes, hazards.length));
          w.add(pw.SizedBox(height: 14));
        }

        // 4 — Hazards table (AI scan)
        if (hazards.isNotEmpty) {
          w.add(_sectionTitle('HAZARDS IDENTIFIED  —  ${hazards.length} TOTAL'));
          w.add(pw.SizedBox(height: 5));
          w.add(_hazardsTable(hazards));
          w.add(pw.SizedBox(height: 8));
          w.add(_riskScoreBar(riskScore, severity));
          w.add(pw.SizedBox(height: 14));
        }

        // 5 — Summary
        w.add(_sectionTitle('INCIDENT SUMMARY'));
        w.add(pw.SizedBox(height: 5));
        w.add(_summaryBox(summary));
        w.add(pw.SizedBox(height: 14));

        // 6 — Root cause + immediate action (2 columns)
        w.add(_twoCol(incident));
        w.add(pw.SizedBox(height: 14));

        // 7 — Sign-off
        w.add(_signOff(reporterName, reporterPno));

        return w;
      },
    ));
    return pdf.save();
  }

  // ─── PAGE CHROME ─────────────────────────────────────────────────────────
  static pw.Widget _pageHeader(bool show) {
    if (!show) return pw.SizedBox();
    return pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 7),
      decoration: pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: _sailBlue, width: 1.2))),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Row(children: [
            pw.Container(width: 18, height: 18, color: _sailBlue,
              alignment: pw.Alignment.center,
              child: pw.Text('SAIL', style: pw.TextStyle(
                color: PdfColors.white, fontSize: 5, fontWeight: pw.FontWeight.bold))),
            pw.SizedBox(width: 5),
            pw.Text('SAFETY LENS', style: pw.TextStyle(
              color: _sailBlue, fontSize: 8, fontWeight: pw.FontWeight.bold)),
          ]),
          pw.Text('CONFIDENTIAL · INTERNAL USE', style: pw.TextStyle(
            fontSize: 7, color: _textLight, fontStyle: pw.FontStyle.italic)),
        ],
      ),
    );
  }

  static pw.Widget _pageFooter(int pg, int tot, String reporter, String date) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(top: 5),
      decoration: pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide(color: _divider, width: 0.5))),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text('Generated by: $reporter  |  $date',
            style: pw.TextStyle(fontSize: 7, color: _textLight)),
          pw.Text('Page $pg of $tot',
            style: pw.TextStyle(fontSize: 7, color: _textLight)),
          pw.Text('IS 14489:1998  |  Factories Act 1948',
            style: pw.TextStyle(fontSize: 7, color: _textLight)),
        ],
      ),
    );
  }

  // ─── BANNER ──────────────────────────────────────────────────────────────
  static pw.Widget _banner(Map<String, dynamic> inc, String sev, bool isAi,
      dynamic score, dynamic conf) {
    final sc = _getSevCol(sev);
    final sb = _getSevBg(sev);
    return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      // Blue top bar
      pw.Container(
        padding: const pw.EdgeInsets.fromLTRB(12, 9, 12, 9),
        color: _sailBlue,
        child: pw.Row(children: [
          pw.Container(width: 42, height: 42, color: PdfColors.white,
            alignment: pw.Alignment.center,
            child: pw.Column(mainAxisAlignment: pw.MainAxisAlignment.center,
              children: [
                pw.Text('SAIL', style: pw.TextStyle(color: _sailBlue, fontSize: 10,
                  fontWeight: pw.FontWeight.bold)),
                pw.Text('सेल', style: pw.TextStyle(
                  color: PdfColor.fromHex('#1565C0'), fontSize: 5)),
              ])),
          pw.SizedBox(width: 10),
          pw.Expanded(child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('STEEL AUTHORITY OF INDIA LIMITED', style: pw.TextStyle(
                color: PdfColors.white, fontSize: 11, fontWeight: pw.FontWeight.bold)),
              pw.Text('Safety Lens  ·  Workplace Hazard Report', style: pw.TextStyle(
                color: PdfColor.fromHex('#BBDEFB'), fontSize: 8)),
            ])),
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              color: sc,
              child: pw.Text(sev, style: pw.TextStyle(
                color: PdfColors.white, fontSize: 11, fontWeight: pw.FontWeight.bold))),
            pw.SizedBox(height: 3),
            pw.Text('IS 14489:1998  |  Factories Act 1948',
              style: pw.TextStyle(color: PdfColor.fromHex('#90CAF9'), fontSize: 6)),
          ]),
        ]),
      ),
      // Title bar
      pw.Container(
        padding: const pw.EdgeInsets.fromLTRB(12, 7, 12, 7),
        color: sb,
        child: pw.Row(children: [
          pw.Expanded(child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(inc['title']?.toString() ?? 'Safety Incident Report',
                style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold,
                  color: _textDark)),
              pw.SizedBox(height: 2),
              pw.Text(isAi
                  ? 'AI-Powered Hazard Scan  ·  SAIL Safety Lens'
                  : 'Near Miss / Unsafe Condition Report',
                style: pw.TextStyle(fontSize: 8, color: _textMed)),
            ])),
          pw.SizedBox(width: 8),
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: sc, width: 1)),
            child: pw.Text(isAi ? 'AI HAZARD SCAN' : 'NEAR MISS REPORT',
              style: pw.TextStyle(color: sc, fontSize: 8, fontWeight: pw.FontWeight.bold))),
        ]),
      ),
    ]);
  }

  // ─── SECTION TITLE ───────────────────────────────────────────────────────
  static pw.Widget _sectionTitle(String t) => pw.Container(
    padding: const pw.EdgeInsets.fromLTRB(8, 4, 8, 4),
    color: _sailLight,
    child: pw.Row(children: [
      pw.Container(width: 3, height: 11, color: _sailBlue),
      pw.SizedBox(width: 6),
      pw.Text(t, style: pw.TextStyle(
        fontSize: 8, fontWeight: pw.FontWeight.bold,
        color: _sailBlue, letterSpacing: 0.4)),
    ]));

  // ─── DETAILS GRID ─────────────────────────────────────────────────────────
  static pw.Widget _detailsGrid(Map<String, dynamic> inc, String date,
      String reporter, String pno) {
    pw.Widget cell(String lbl, String val, {bool hi = false}) =>
      pw.Container(
        padding: const pw.EdgeInsets.fromLTRB(8, 5, 8, 5),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: _divider, width: 0.4),
          color: hi ? _sailLight : PdfColors.white),
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(lbl.toUpperCase(), style: pw.TextStyle(
              fontSize: 6.5, color: _textLight, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 2),
            pw.Text(val.isEmpty ? '—' : val, style: pw.TextStyle(
              fontSize: 9, color: _textDark, fontWeight: pw.FontWeight.bold)),
          ]));

    return pw.Table(
      columnWidths: const {
        0: pw.FlexColumnWidth(1.6),
        1: pw.FlexColumnWidth(1.4),
        2: pw.FlexColumnWidth(1.2),
        3: pw.FlexColumnWidth(1.2),
      },
      children: [
        pw.TableRow(children: [
          cell('Plant / Unit', inc['plant']?.toString() ?? '', hi: true),
          cell('Department', inc['dept']?.toString() ?? ''),
          cell('Location', inc['location']?.toString() ?? ''),
          cell('Date & Time', date, hi: true),
        ]),
        pw.TableRow(children: [
          cell('Reported By', reporter),
          cell('Personnel No.', pno),
          cell('Observation Type', inc['obsType']?.toString() ?? 'N/A'),
          cell('Status', inc['status']?.toString() ?? 'OPEN', hi: true),
        ]),
        pw.TableRow(children: [
          cell('Report Type', inc['type'] == 'AI_SCAN' ? 'AI Image Scan' : 'Near Miss'),
          cell('WSA Category', inc['wsaCategory']?.toString() ?? ''),
          cell('Reference No.', (inc['id']?.toString() ?? 'N/A').length > 8
              ? inc['id'].toString().substring(0, 8) : inc['id']?.toString() ?? 'N/A'),
          cell('People Involved', inc['people']?.toString() ?? '0'),
        ]),
      ],
    );
  }

  // ─── PHOTO ────────────────────────────────────────────────────────────────
  static pw.Widget _photoBox(Uint8List img, int count) => pw.Container(
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: _divider, width: 0.5)),
    child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Padding(padding: const pw.EdgeInsets.all(8),
          child: pw.Image(pw.MemoryImage(img), height: 190, fit: pw.BoxFit.contain)),
        if (count > 0)
          pw.Container(
            padding: const pw.EdgeInsets.fromLTRB(8, 4, 8, 4),
            color: PdfColor.fromHex('#F5F5F5'),
            child: pw.Text(
              '$count hazard(s) identified — see table below for full analysis.',
              style: pw.TextStyle(fontSize: 7.5, color: _textMed,
                fontStyle: pw.FontStyle.italic))),
      ]));

  // ─── HAZARDS TABLE ────────────────────────────────────────────────────────
  static pw.Widget _hazardsTable(List<Map<String, dynamic>> hazards) {
    pw.Widget hdrCell(String t) => pw.Container(
      padding: const pw.EdgeInsets.fromLTRB(6, 6, 6, 6),
      color: _sailBlue,
      child: pw.Text(t, style: pw.TextStyle(
        color: PdfColors.white, fontSize: 7.5, fontWeight: pw.FontWeight.bold)));

    return pw.Table(
      border: pw.TableBorder.all(color: _divider, width: 0.4),
      columnWidths: const {
        0: pw.FixedColumnWidth(18),   // #
        1: pw.FlexColumnWidth(1.8),   // Hazard
        2: pw.FixedColumnWidth(46),   // Severity
        3: pw.FlexColumnWidth(2.4),   // Description
        4: pw.FlexColumnWidth(1.6),   // Regulation
        5: pw.FlexColumnWidth(2.4),   // Action
      },
      children: [
        // Header
        pw.TableRow(children: [
          hdrCell('#'),
          hdrCell('HAZARD'),
          hdrCell('SEVERITY'),
          hdrCell('DESCRIPTION'),
          hdrCell('REGULATION'),
          hdrCell('CORRECTIVE ACTION'),
        ]),
        // Data rows
        ...List.generate(hazards.length, (i) {
          final h   = hazards[i];
          final sev = h['severity']?.toString().toUpperCase() ?? 'MEDIUM';
          final sc  = _getSevCol(sev);
          final sb  = _getSevBg(sev);
          final bg  = i % 2 == 0 ? _rowNorm : _rowAlt;

          return pw.TableRow(children: [
            // # (bold, sail-blue background)
            pw.Container(
              padding: const pw.EdgeInsets.fromLTRB(5, 6, 5, 6),
              color: PdfColor.fromHex('#E3F2FD'),
              child: pw.Text('${i + 1}', style: pw.TextStyle(
                fontSize: 8, fontWeight: pw.FontWeight.bold, color: _sailBlue),
                textAlign: pw.TextAlign.center)),
            // Hazard name
            pw.Container(
              padding: const pw.EdgeInsets.fromLTRB(6, 6, 6, 6),
              color: bg,
              child: pw.Text(h['name']?.toString() ?? '', style: pw.TextStyle(
                fontSize: 8, fontWeight: pw.FontWeight.bold, color: _textDark))),
            // Severity pill
            pw.Container(
              padding: const pw.EdgeInsets.fromLTRB(4, 6, 4, 6),
              color: sb,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                mainAxisAlignment: pw.MainAxisAlignment.center,
                children: [
                  pw.Text(sev, style: pw.TextStyle(
                    fontSize: 7, fontWeight: pw.FontWeight.bold, color: sc),
                    textAlign: pw.TextAlign.center),
                  pw.SizedBox(height: 2),
                  // Small colored bar under severity text
                  pw.Container(height: 2, width: 30, color: sc),
                ])),
            // Description
            pw.Container(
              padding: const pw.EdgeInsets.fromLTRB(6, 6, 6, 6),
              color: bg,
              child: pw.Text(h['description']?.toString() ?? '',
                style: pw.TextStyle(fontSize: 7.5, color: _textDark,
                  lineSpacing: 1.2))),
            // Regulation
            pw.Container(
              padding: const pw.EdgeInsets.fromLTRB(6, 6, 6, 6),
              color: bg,
              child: pw.Text(h['regulation']?.toString() ?? '',
                style: pw.TextStyle(fontSize: 7, color: _textMed,
                  lineSpacing: 1.2))),
            // Action
            pw.Container(
              padding: const pw.EdgeInsets.fromLTRB(6, 6, 6, 6),
              color: bg,
              child: pw.Text(h['correctiveAction']?.toString() ?? '',
                style: pw.TextStyle(fontSize: 7.5, color: _textDark,
                  lineSpacing: 1.2))),
          ]);
        }),
      ],
    );
  }

  // ─── RISK SCORE BAR ───────────────────────────────────────────────────────
  static pw.Widget _riskScoreBar(dynamic rawScore, String severity) {
    final score = (rawScore is int ? rawScore : int.tryParse('$rawScore') ?? 0).clamp(0, 100);
    final sc    = _getSevCol(severity);
    final sb    = _getSevBg(severity);
    final crit  = hazards_countBySev([], 'CRITICAL'); // placeholder

    return pw.Container(
      padding: const pw.EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: pw.BoxDecoration(
        color: sb,
        border: pw.Border.all(color: sc, width: 0.8)),
      child: pw.Row(children: [
        pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text('TOTAL RISK SCORE', style: pw.TextStyle(
            fontSize: 7, color: _textLight, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 2),
          pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.baseline,
            textBaseline: pw.TextBaseline.alphabetic,
            children: [
              pw.Text('$score', style: pw.TextStyle(
                fontSize: 28, fontWeight: pw.FontWeight.bold, color: sc)),
              pw.Text(' / 100', style: pw.TextStyle(fontSize: 10, color: _textMed)),
            ]),
        ]),
        pw.SizedBox(width: 16),
        pw.Expanded(child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('OVERALL RISK: $severity', style: pw.TextStyle(
              fontSize: 9, fontWeight: pw.FontWeight.bold, color: sc)),
            pw.SizedBox(height: 6),
            // Score bar
            pw.Stack(children: [
              pw.Container(
                height: 8,
                decoration: pw.BoxDecoration(
                  color: PdfColors.white,
                  border: pw.Border.all(color: _divider, width: 0.5))),
              pw.Container(
                height: 8,
                width: (score / 100) * 300,
                color: sc),
            ]),
            pw.SizedBox(height: 4),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('0 — LOW', style: pw.TextStyle(fontSize: 6.5, color: _lowCol)),
                pw.Text('50 — MEDIUM', style: pw.TextStyle(fontSize: 6.5, color: _medCol)),
                pw.Text('75 — HIGH', style: pw.TextStyle(fontSize: 6.5, color: _highCol)),
                pw.Text('90+ CRITICAL', style: pw.TextStyle(fontSize: 6.5, color: _critCol)),
              ]),
          ])),
      ]),
    );
  }

  // dummy helper used only inside _riskScoreBar for syntax — remove
  static int hazards_countBySev(List l, String s) => 0;

  // ─── SUMMARY BOX ──────────────────────────────────────────────────────────
  static pw.Widget _summaryBox(String summary) => pw.Container(
    padding: const pw.EdgeInsets.all(10),
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: _divider, width: 0.5),
      color: PdfColor.fromHex('#FAFAFA')),
    child: pw.Text(summary.isEmpty ? 'No summary provided.' : summary,
      style: pw.TextStyle(fontSize: 9, color: _textDark, lineSpacing: 1.6)));

  // ─── TWO COLUMN ───────────────────────────────────────────────────────────
  static pw.Widget _twoCol(Map<String, dynamic> inc) => pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Expanded(child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _sectionTitle('ROOT CAUSE ANALYSIS (WSA 13)'),
          pw.SizedBox(height: 5),
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: _divider, width: 0.5),
              color: PdfColor.fromHex('#FFF8E1')),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('Category:', style: pw.TextStyle(
                  fontSize: 7.5, color: _textLight, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 3),
                pw.Text(inc['wsaCategory']?.toString() ?? 'Not classified',
                  style: pw.TextStyle(fontSize: 9, color: _textDark,
                    fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 6),
                pw.Text('People involved: ${inc['people']?.toString() ?? '0'}',
                  style: pw.TextStyle(fontSize: 8, color: _textMed)),
              ])),
        ])),
      pw.SizedBox(width: 10),
      pw.Expanded(child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _sectionTitle('IMMEDIATE CORRECTIVE ACTION'),
          pw.SizedBox(height: 5),
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: _divider, width: 0.5),
              color: PdfColor.fromHex('#E8F5E9')),
            child: pw.Text(
              inc['immediateAction']?.toString().isNotEmpty == true
                  ? inc['immediateAction'].toString()
                  : 'Investigate and apply corrective actions per IS 14489:1998.',
              style: pw.TextStyle(fontSize: 9, color: _textDark, lineSpacing: 1.4))),
        ])),
    ]);

  // ─── SIGN-OFF ─────────────────────────────────────────────────────────────
  static pw.Widget _signOff(String reporter, String pno) => pw.Container(
    padding: const pw.EdgeInsets.all(10),
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: _sailBlue, width: 0.5),
      color: _sailLight),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text('REPORTED BY', style: pw.TextStyle(
            fontSize: 7, color: _textLight, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 2),
          pw.Text(reporter, style: pw.TextStyle(
            fontSize: 10, fontWeight: pw.FontWeight.bold, color: _textDark)),
          pw.Text('P.No.: $pno',
            style: pw.TextStyle(fontSize: 8, color: _textMed)),
        ]),
        pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
          pw.Text('SIGNATURE', style: pw.TextStyle(
            fontSize: 7, color: _textLight, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 18),
          pw.Container(width: 100, height: 0.5, color: _textDark),
        ]),
        pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
          pw.Text('REVIEWED BY', style: pw.TextStyle(
            fontSize: 7, color: _textLight, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 18),
          pw.Container(width: 100, height: 0.5, color: _textDark),
          pw.Text('Safety Officer / HOD',
            style: pw.TextStyle(fontSize: 7, color: _textMed)),
        ]),
      ]));

  // ─── HELPERS ──────────────────────────────────────────────────────────────
  static List<Map<String, dynamic>> _parseHazards(dynamic raw) {
    if (raw == null) return [];
    if (raw is List) {
      return raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    }
    if (raw is String && raw.isNotEmpty) {
      try {
        final d = jsonDecode(raw);
        if (d is List) return d.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      } catch (_) {}
    }
    return [];
  }

  /// Extract only the clean AI summary — strip the === HAZARDS === text block
  static String _cleanSummary(Map<String, dynamic> inc) {
    // Prefer top-level summary key (AI result stores it here)
    final s = inc['summary']?.toString() ?? '';
    if (s.isNotEmpty && !s.contains('===')) return s;

    // Fall back to desc, but strip the === blocks
    final d = inc['desc']?.toString() ?? '';
    if (d.isEmpty) return '';
    // Take only lines before the first === separator
    final lines = d.split('\n');
    final clean = <String>[];
    for (final line in lines) {
      if (line.startsWith('===')) break;
      clean.add(line);
    }
    return clean.join(' ').replaceAll('Summary: ', '').trim();
  }

  static PdfColor _getSevCol(String s) {
    switch (s.toUpperCase()) {
      case 'CRITICAL': return _critCol;
      case 'HIGH':     return _highCol;
      case 'MEDIUM':   return _medCol;
      default:         return _lowCol;
    }
  }

  static PdfColor _getSevBg(String s) {
    switch (s.toUpperCase()) {
      case 'CRITICAL': return _critBg;
      case 'HIGH':     return _highBg;
      case 'MEDIUM':   return _medBg;
      default:         return _lowBg;
    }
  }

  // ─── PUBLIC API ───────────────────────────────────────────────────────────
  static Future<void> downloadOrShareIncident({
    required Map<String, dynamic> incident,
    String reporterName = 'SAIL Safety Officer',
    String reporterPno = '',
    Uint8List? imageBytes,
  }) async {
    final bytes = await generateIncidentReportBytes(
      incident: incident, reporterName: reporterName,
      reporterPno: reporterPno, imageBytes: imageBytes);
    final fn = 'SafetyLens_${incident['type'] ?? 'Report'}_${incident['id'] ?? DateTime.now().millisecondsSinceEpoch}.pdf';
    if (kIsWeb) {
      final blob   = html.Blob([bytes], 'application/pdf');
      final url    = html.Url.createObjectUrlFromBlob(blob);
      final anchor = html.AnchorElement(href: url)
        ..setAttribute('download', fn)..click();
      html.Url.revokeObjectUrl(url);
    } else {
      final dir  = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$fn');
      await file.writeAsBytes(bytes);
      await Share.shareXFiles([XFile(file.path)],
          text: 'SAIL Safety Lens Report', subject: 'Incident Report');
    }
  }

  static Future<File> generateIncidentReport({
    required Map<String, dynamic> incident,
    String reporterName = 'SAIL Safety Officer',
    String reporterPno = '',
  }) async {
    final bytes = await generateIncidentReportBytes(
      incident: incident, reporterName: reporterName, reporterPno: reporterPno);
    final dir  = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/SafetyLens_${incident['id']}.pdf');
    await file.writeAsBytes(bytes);
    return file;
  }

  static Future<File> generateConsolidatedReport({
    required List<Map<String, dynamic>> incidents,
    String reporterName = 'SAIL Safety Officer',
    String? reportTitle,
    String? plant,
    DateTime? fromDate,
    DateTime? toDate,
  }) async {
    final pdf   = pw.Document();
    final now   = DateTime.now();
    final title = reportTitle ?? 'SAIL Safety Lens — Consolidated Incident Report';

    pdf.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      header: (ctx) => _pageHeader(ctx.pageNumber > 1),
      footer: (ctx) => _pageFooter(ctx.pageNumber, ctx.pagesCount,
          reporterName, DateFormat('dd MMM yyyy').format(now)),
      build: (ctx) => [
        pw.Container(
          padding: const pw.EdgeInsets.all(14),
          color: _sailBlue,
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('SAIL SAFETY LENS', style: pw.TextStyle(
                color: PdfColors.white, fontSize: 18, fontWeight: pw.FontWeight.bold)),
              pw.Text(title, style: pw.TextStyle(
                color: PdfColor.fromHex('#BBDEFB'), fontSize: 11)),
              pw.Text('Generated: ${DateFormat('dd MMM yyyy, HH:mm').format(now)}',
                style: pw.TextStyle(color: PdfColor.fromHex('#90CAF9'), fontSize: 9)),
            ])),
        pw.SizedBox(height: 16),
        pw.Text('Total Incidents: ${incidents.length}',
          style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 12),
        pw.Table(
          border: pw.TableBorder.all(color: _divider, width: 0.4),
          columnWidths: const {
            0: pw.FixedColumnWidth(22), 1: pw.FixedColumnWidth(54),
            2: pw.FlexColumnWidth(2.0), 3: pw.FlexColumnWidth(1.5),
            4: pw.FixedColumnWidth(50), 5: pw.FixedColumnWidth(46),
          },
          children: [
            pw.TableRow(children: [
              for (final h in ['#','Date','Title','Plant','Severity','Status'])
                pw.Container(
                  padding: const pw.EdgeInsets.fromLTRB(6,5,6,5),
                  color: _sailBlue,
                  child: pw.Text(h, style: pw.TextStyle(
                    color: PdfColors.white, fontSize: 7.5,
                    fontWeight: pw.FontWeight.bold))),
            ]),
            ...List.generate(incidents.length, (i) {
              final inc = incidents[i];
              final sev = inc['severity']?.toString() ?? 'MEDIUM';
              final bg  = i % 2 == 0 ? _rowNorm : _rowAlt;
              pw.Widget c(String t) => pw.Container(
                padding: const pw.EdgeInsets.fromLTRB(6,5,6,5), color: bg,
                child: pw.Text(t, style: const pw.TextStyle(fontSize: 8)));
              return pw.TableRow(children: [
                c('${i+1}'),
                c(inc['date'] != null
                    ? DateFormat('dd/MM/yy').format(DateTime.parse(inc['date'])) : ''),
                c(inc['title']?.toString() ?? ''),
                c(inc['plant']?.toString() ?? ''),
                pw.Container(
                  padding: const pw.EdgeInsets.fromLTRB(6,5,6,5),
                  color: _getSevBg(sev),
                  child: pw.Text(sev, style: pw.TextStyle(
                    fontSize: 7, fontWeight: pw.FontWeight.bold,
                    color: _getSevCol(sev)))),
                c(inc['status']?.toString() ?? 'OPEN'),
              ]);
            }),
          ]),
      ]));

    final dir  = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/SafetyLens_Consolidated_${DateFormat('yyyyMMdd').format(now)}.pdf');
    await file.writeAsBytes(await pdf.save());
    return file;
  }

  static Future<void> sharePdf(File file, {String? subject}) async {
    await Share.shareXFiles([XFile(file.path)],
        subject: subject ?? 'Safety Lens Report',
        text: 'Safety report generated by SAIL Safety Lens');
  }
}
