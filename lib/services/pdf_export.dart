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
  // SAIL Brand Colors
  static final PdfColor _sailBlue = PdfColor.fromHex('#0D47A1');
  static final PdfColor _sailLightBlue = PdfColor.fromHex('#1565C0');
  static final PdfColor _sailAccent = PdfColor.fromHex('#E3F2FD');
  static final PdfColor _criticalColor = PdfColor.fromHex('#C62828');
  static final PdfColor _criticalBg = PdfColor.fromHex('#FFEBEE');
  static final PdfColor _highColor = PdfColor.fromHex('#E65100');
  static final PdfColor _highBg = PdfColor.fromHex('#FFF3E0');
  static final PdfColor _mediumColor = PdfColor.fromHex('#00838F');
  static final PdfColor _mediumBg = PdfColor.fromHex('#E0F7FA');
  static final PdfColor _lowColor = PdfColor.fromHex('#2E7D32');
  static final PdfColor _lowBg = PdfColor.fromHex('#E8F5E9');
  static final PdfColor _headerBg = PdfColor.fromHex('#F5F5F5');
  static final PdfColor _divider = PdfColor.fromHex('#BDBDBD');
  static final PdfColor _textDark = PdfColor.fromHex('#212121');
  static final PdfColor _textMed = PdfColor.fromHex('#616161');
  static final PdfColor _textLight = PdfColor.fromHex('#9E9E9E');

  static Future<Uint8List> generateIncidentReportBytes({
    required Map<String, dynamic> incident,
    String reporterName = 'SAIL Safety Officer',
    String reporterPno = '',
    Uint8List? imageBytes,
  }) async {
    final pdf = pw.Document();
    final dateStr = DateFormat('dd MMM yyyy, HH:mm').format(
      DateTime.parse(incident['date'] ?? DateTime.now().toIso8601String()),
    );

    Uint8List? embedBytes = imageBytes;
    if (embedBytes == null && incident['imageBase64'] != null) {
      try { embedBytes = base64Decode(incident['imageBase64'].toString()); } catch (_) {}
    }

    // Parse hazards list
    List<Map<String, dynamic>> hazards = [];
    final rawHazards = incident['hazards'];
    if (rawHazards is List) {
      hazards = rawHazards.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } else if (rawHazards is String && rawHazards.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawHazards);
        if (decoded is List) hazards = decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      } catch (_) {}
    }

    final severity = incident['severity']?.toString() ?? 'MEDIUM';
    final isAiScan = incident['type']?.toString() == 'AI_SCAN';

    pdf.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(28, 28, 28, 28),
      header: (ctx) => _pageHeader(ctx.pageNumber > 1),
      footer: (ctx) => _pageFooter(ctx.pageNumber, ctx.pagesCount, reporterName, dateStr),
      build: (context) {
        final widgets = <pw.Widget>[];

        // === SECTION 1: Report header banner ===
        widgets.add(_reportBanner(incident, severity, isAiScan));
        widgets.add(pw.SizedBox(height: 12));

        // === SECTION 2: Incident details table ===
        widgets.add(_sectionTitle('INCIDENT DETAILS'));
        widgets.add(pw.SizedBox(height: 6));
        widgets.add(_incidentDetailsTable(incident, dateStr, reporterName, reporterPno));
        widgets.add(pw.SizedBox(height: 14));

        // === SECTION 3: Evidence photo ===
        if (embedBytes != null) {
          widgets.add(_sectionTitle('EVIDENCE PHOTOGRAPH'));
          widgets.add(pw.SizedBox(height: 6));
          widgets.add(_photoSection(embedBytes, hazards));
          widgets.add(pw.SizedBox(height: 14));
        }

        // === SECTION 4: Hazards table (AI scan) ===
        if (hazards.isNotEmpty) {
          widgets.add(_sectionTitle('HAZARDS IDENTIFIED (${hazards.length} TOTAL)'));
          widgets.add(pw.SizedBox(height: 6));
          widgets.add(_hazardsTable(hazards));
          widgets.add(pw.SizedBox(height: 14));
        }

        // === SECTION 5: Summary & Description ===
        widgets.add(_sectionTitle('INCIDENT SUMMARY & DESCRIPTION'));
        widgets.add(pw.SizedBox(height: 6));
        widgets.add(_summarySection(incident));
        widgets.add(pw.SizedBox(height: 14));

        // === SECTION 6: Root cause & Actions ===
        widgets.add(_twoColumnSection(incident));
        widgets.add(pw.SizedBox(height: 14));

        // === SECTION 7: Sign-off box ===
        widgets.add(_signOffBox(reporterName, reporterPno));

        return widgets;
      },
    ));

    return pdf.save();
  }

  // ─── PAGE HEADER ─────────────────────────────────────────────────────────
  static pw.Widget _pageHeader(bool isSubsequentPage) {
    if (!isSubsequentPage) return pw.SizedBox();
    return pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 8),
      decoration: pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: _sailBlue, width: 1.5)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Row(children: [
            pw.Container(width: 20, height: 20, color: _sailBlue,
              alignment: pw.Alignment.center,
              child: pw.Text('SAIL', style: pw.TextStyle(color: PdfColors.white, fontSize: 6, fontWeight: pw.FontWeight.bold))),
            pw.SizedBox(width: 6),
            pw.Text('SAFETY LENS', style: pw.TextStyle(color: _sailBlue, fontSize: 9, fontWeight: pw.FontWeight.bold)),
          ]),
          pw.Text('CONFIDENTIAL · INTERNAL USE', style: pw.TextStyle(fontSize: 7, color: _textLight, fontStyle: pw.FontStyle.italic)),
        ],
      ),
    );
  }

  // ─── PAGE FOOTER ─────────────────────────────────────────────────────────
  static pw.Widget _pageFooter(int pageNo, int total, String reporter, String dateStr) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(top: 6),
      decoration: pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide(color: _divider, width: 0.5)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text('Generated by: $reporter  |  Date: $dateStr', style: pw.TextStyle(fontSize: 7, color: _textLight)),
          pw.Text('Page $pageNo of $total', style: pw.TextStyle(fontSize: 7, color: _textLight)),
          pw.Text('Compliant with IS 14489:1998 | Factories Act 1948', style: pw.TextStyle(fontSize: 7, color: _textLight)),
        ],
      ),
    );
  }

  // ─── REPORT BANNER ───────────────────────────────────────────────────────
  static pw.Widget _reportBanner(Map<String, dynamic> incident, String severity, bool isAiScan) {
    final sevColor = _getSevColor(severity);
    final sevBg = _getSevBg(severity);
    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border(left: pw.BorderSide(color: sevColor, width: 5)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          // Top blue header bar
          pw.Container(
            padding: const pw.EdgeInsets.fromLTRB(14, 10, 14, 10),
            color: _sailBlue,
            child: pw.Row(
              children: [
                // SAIL Logo placeholder
                pw.Container(
                  width: 44, height: 44,
                  color: PdfColors.white,
                  alignment: pw.Alignment.center,
                  child: pw.Column(
                    mainAxisAlignment: pw.MainAxisAlignment.center,
                    children: [
                      pw.Text('SAIL', style: pw.TextStyle(color: _sailBlue, fontSize: 10, fontWeight: pw.FontWeight.bold)),
                      pw.Text('सेल', style: pw.TextStyle(color: _sailLightBlue, fontSize: 6)),
                    ],
                  ),
                ),
                pw.SizedBox(width: 12),
                pw.Expanded(child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('STEEL AUTHORITY OF INDIA LIMITED',
                      style: pw.TextStyle(color: PdfColors.white, fontSize: 11, fontWeight: pw.FontWeight.bold)),
                    pw.Text('Safety Lens · Workplace Hazard Report',
                      style: pw.TextStyle(color: PdfColor.fromHex('#BBDEFB'), fontSize: 9)),
                  ],
                )),
                pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    color: sevColor,
                    child: pw.Text(severity, style: pw.TextStyle(color: PdfColors.white, fontSize: 10, fontWeight: pw.FontWeight.bold)),
                  ),
                  pw.SizedBox(height: 3),
                  pw.Text('IS 14489:1998 | Factories Act 1948',
                    style: pw.TextStyle(color: PdfColor.fromHex('#90CAF9'), fontSize: 7)),
                ]),
              ],
            ),
          ),
          // Title bar
          pw.Container(
            padding: const pw.EdgeInsets.fromLTRB(14, 8, 14, 8),
            color: sevBg,
            child: pw.Row(
              children: [
                pw.Expanded(child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      incident['title']?.toString() ?? 'Safety Incident Report',
                      style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: _textDark),
                    ),
                    pw.SizedBox(height: 2),
                    pw.Text(
                      isAiScan ? 'AI-Powered Hazard Scan · SAIL Safety Lens' : 'Near Miss / Unsafe Act/Condition Report',
                      style: pw.TextStyle(fontSize: 8, color: _textMed),
                    ),
                  ],
                )),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: sevColor, width: 1),
                  ),
                  child: pw.Text(
                    isAiScan ? 'AI HAZARD SCAN' : 'NEAR MISS REPORT',
                    style: pw.TextStyle(color: sevColor, fontSize: 8, fontWeight: pw.FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── SECTION TITLE ───────────────────────────────────────────────────────
  static pw.Widget _sectionTitle(String title) {
    return pw.Container(
      padding: const pw.EdgeInsets.fromLTRB(8, 4, 8, 4),
      color: _sailAccent,
      child: pw.Row(children: [
        pw.Container(width: 3, height: 12, color: _sailBlue),
        pw.SizedBox(width: 6),
        pw.Text(title, style: pw.TextStyle(
          fontSize: 9, fontWeight: pw.FontWeight.bold, color: _sailBlue, letterSpacing: 0.5)),
      ]),
    );
  }

  // ─── INCIDENT DETAILS TABLE ───────────────────────────────────────────────
  static pw.Widget _incidentDetailsTable(
    Map<String, dynamic> incident, String dateStr, String reporter, String pno) {
    pw.Widget cell(String label, String value, {bool highlight = false}) {
      return pw.Container(
        padding: const pw.EdgeInsets.fromLTRB(8, 6, 8, 6),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: _divider, width: 0.5),
          color: highlight ? _sailAccent : PdfColors.white,
        ),
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text(label.toUpperCase(),
            style: pw.TextStyle(fontSize: 7, color: _textLight, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 2),
          pw.Text(value.isEmpty ? '—' : value,
            style: pw.TextStyle(fontSize: 9, color: _textDark, fontWeight: pw.FontWeight.bold)),
        ]),
      );
    }

    return pw.Table(
      columnWidths: const {
        0: pw.FlexColumnWidth(1.5),
        1: pw.FlexColumnWidth(1.5),
        2: pw.FlexColumnWidth(1.2),
        3: pw.FlexColumnWidth(1.2),
      },
      children: [
        pw.TableRow(children: [
          cell('Plant / Unit', incident['plant']?.toString() ?? '', highlight: true),
          cell('Department', incident['dept']?.toString() ?? ''),
          cell('Location', incident['location']?.toString() ?? ''),
          cell('Date & Time', dateStr, highlight: true),
        ]),
        pw.TableRow(children: [
          cell('Reported By', reporter),
          cell('Personnel No.', pno),
          cell('Observation Type', incident['obsType']?.toString() ?? 'N/A'),
          cell('Status', incident['status']?.toString() ?? 'OPEN', highlight: true),
        ]),
        pw.TableRow(children: [
          cell('Report Type', incident['type'] == 'AI_SCAN' ? 'AI Image Scan' : 'Near Miss'),
          cell('WSA Category', incident['wsaCategory']?.toString() ?? ''),
          cell('Reference No.', incident['id']?.toString()?.substring(0, 8) ?? 'N/A'),
          cell('People Involved', incident['people']?.toString() ?? '0'),
        ]),
      ],
    );
  }

  // ─── PHOTO SECTION ────────────────────────────────────────────────────────
  static pw.Widget _photoSection(Uint8List imgBytes, List<Map<String, dynamic>> hazards) {
    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: _divider, width: 0.5),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            padding: const pw.EdgeInsets.all(8),
            child: pw.Stack(children: [
              pw.Image(pw.MemoryImage(imgBytes), height: 200, fit: pw.BoxFit.contain),
            ]),
          ),
          if (hazards.isNotEmpty) ...[
            pw.Container(
              padding: const pw.EdgeInsets.fromLTRB(8, 4, 8, 4),
              color: _headerBg,
              child: pw.Text(
                'Note: ${hazards.length} hazard(s) identified in this photograph. See Hazards table below for numbered details.',
                style: pw.TextStyle(fontSize: 8, color: _textMed, fontStyle: pw.FontStyle.italic),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ─── HAZARDS TABLE ────────────────────────────────────────────────────────
  static pw.Widget _hazardsTable(List<Map<String, dynamic>> hazards) {
    final headerStyle = pw.TextStyle(
      fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.white);
    final cellStyle = pw.TextStyle(fontSize: 8, color: _textDark);

    pw.Widget hdr(String t, {pw.FlexColumnWidth? w}) => pw.Container(
      padding: const pw.EdgeInsets.fromLTRB(6, 5, 6, 5),
      color: _sailBlue,
      child: pw.Text(t, style: headerStyle),
    );

    pw.Widget cell(String t, {PdfColor? bg, pw.TextStyle? style}) => pw.Container(
      padding: const pw.EdgeInsets.fromLTRB(6, 5, 6, 5),
      color: bg ?? PdfColors.white,
      child: pw.Text(t, style: style ?? cellStyle),
    );

    return pw.Table(
      border: pw.TableBorder.all(color: _divider, width: 0.4),
      columnWidths: const {
        0: pw.FixedColumnWidth(20),
        1: pw.FlexColumnWidth(2.0),
        2: pw.FlexColumnWidth(2.5),
        3: pw.FixedColumnWidth(48),
        4: pw.FlexColumnWidth(1.8),
        5: pw.FlexColumnWidth(2.5),
      },
      children: [
        // Header row
        pw.TableRow(children: [
          hdr('#'),
          hdr('HAZARD'),
          hdr('DESCRIPTION'),
          hdr('SEVERITY'),
          hdr('REGULATION'),
          hdr('CORRECTIVE ACTION'),
        ]),
        // Data rows
        ...List.generate(hazards.length, (i) {
          final h = hazards[i];
          final sev = h['severity']?.toString() ?? 'MEDIUM';
          final sevColor = _getSevColor(sev);
          final sevBg = _getSevBg(sev);
          final isOdd = i % 2 == 1;
          final rowBg = isOdd ? PdfColor.fromHex('#FAFAFA') : PdfColors.white;

          return pw.TableRow(children: [
            pw.Container(
              padding: const pw.EdgeInsets.fromLTRB(6, 5, 6, 5),
              color: _sailBlue,
              child: pw.Text('${i + 1}', style: pw.TextStyle(
                fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.white)),
            ),
            cell(h['name']?.toString() ?? '', bg: rowBg,
              style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: _textDark)),
            cell(h['description']?.toString() ?? '', bg: rowBg),
            pw.Container(
              padding: const pw.EdgeInsets.fromLTRB(4, 5, 4, 5),
              color: sevBg,
              child: pw.Text(sev, style: pw.TextStyle(
                fontSize: 7, fontWeight: pw.FontWeight.bold, color: sevColor)),
            ),
            cell(h['regulation']?.toString() ?? '', bg: rowBg,
              style: const pw.TextStyle(fontSize: 7)),
            cell(h['correctiveAction']?.toString() ?? '', bg: rowBg,
              style: const pw.TextStyle(fontSize: 7)),
          ]);
        }),
      ],
    );
  }

  // ─── SUMMARY SECTION ─────────────────────────────────────────────────────
  static pw.Widget _summarySection(Map<String, dynamic> incident) {
    final desc = incident['desc']?.toString() ?? incident['summary']?.toString() ?? '';
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: _divider, width: 0.5),
        color: PdfColor.fromHex('#FAFAFA'),
      ),
      child: pw.Text(desc.isEmpty ? 'No description provided.' : desc,
        style: pw.TextStyle(fontSize: 9, color: _textDark, lineSpacing: 1.5)),
    );
  }

  // ─── TWO COLUMN SECTION ───────────────────────────────────────────────────
  static pw.Widget _twoColumnSection(Map<String, dynamic> incident) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _sectionTitle('ROOT CAUSE ANALYSIS (WSA 13)'),
            pw.SizedBox(height: 6),
            pw.Container(
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: _divider, width: 0.5),
                color: PdfColor.fromHex('#FFF8E1'),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('Category:', style: pw.TextStyle(fontSize: 8, color: _textLight, fontWeight: pw.FontWeight.bold)),
                  pw.SizedBox(height: 3),
                  pw.Text(
                    incident['wsaCategory']?.toString() ?? 'Not classified',
                    style: pw.TextStyle(fontSize: 9, color: _textDark, fontWeight: pw.FontWeight.bold)),
                  pw.SizedBox(height: 6),
                  pw.Text('People involved: ${incident['people']?.toString() ?? '0'}',
                    style: pw.TextStyle(fontSize: 8, color: _textMed)),
                ],
              ),
            ),
          ],
        )),
        pw.SizedBox(width: 10),
        pw.Expanded(child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _sectionTitle('IMMEDIATE CORRECTIVE ACTION'),
            pw.SizedBox(height: 6),
            pw.Container(
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: _divider, width: 0.5),
                color: PdfColor.fromHex('#E8F5E9'),
              ),
              child: pw.Text(
                incident['immediateAction']?.toString() ??
                    'Investigate and apply corrective actions per IS 14489:1998 framework.',
                style: pw.TextStyle(fontSize: 9, color: _textDark, lineSpacing: 1.4)),
            ),
          ],
        )),
      ],
    );
  }

  // ─── SIGN-OFF BOX ─────────────────────────────────────────────────────────
  static pw.Widget _signOffBox(String reporter, String pno) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: _sailBlue, width: 0.5),
        color: _sailAccent,
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text('REPORTED BY', style: pw.TextStyle(fontSize: 7, color: _textLight, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 2),
            pw.Text(reporter, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _textDark)),
            pw.Text('P.No.: $pno', style: pw.TextStyle(fontSize: 8, color: _textMed)),
          ]),
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
            pw.Text('SIGNATURE', style: pw.TextStyle(fontSize: 7, color: _textLight, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 14),
            pw.Container(width: 100, height: 0.5, color: _textDark),
          ]),
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
            pw.Text('REVIEWED BY', style: pw.TextStyle(fontSize: 7, color: _textLight, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 14),
            pw.Container(width: 100, height: 0.5, color: _textDark),
            pw.Text('Safety Officer / HOD', style: pw.TextStyle(fontSize: 7, color: _textMed)),
          ]),
        ],
      ),
    );
  }

  // ─── COLOR HELPERS ────────────────────────────────────────────────────────
  static PdfColor _getSevColor(String sev) {
    switch (sev.toUpperCase()) {
      case 'CRITICAL': return _criticalColor;
      case 'HIGH': return _highColor;
      case 'MEDIUM': return _mediumColor;
      default: return _lowColor;
    }
  }

  static PdfColor _getSevBg(String sev) {
    switch (sev.toUpperCase()) {
      case 'CRITICAL': return _criticalBg;
      case 'HIGH': return _highBg;
      case 'MEDIUM': return _mediumBg;
      default: return _lowBg;
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
      reporterPno: reporterPno, imageBytes: imageBytes,
    );
    final filename = 'SafetyLens_${incident['type'] ?? 'Report'}_${incident['id'] ?? DateTime.now().millisecondsSinceEpoch}.pdf';
    if (kIsWeb) {
      final blob = html.Blob([bytes], 'application/pdf');
      final url = html.Url.createObjectUrlFromBlob(blob);
      final anchor = html.AnchorElement(href: url)
        ..setAttribute('download', filename)..click();
      html.Url.revokeObjectUrl(url);
    } else {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$filename');
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
    final dir = await getApplicationDocumentsDirectory();
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
    final pdf = pw.Document();
    final now = DateTime.now();
    final title = reportTitle ?? 'SAIL Safety Lens — Consolidated Incident Report';

    pdf.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      header: (ctx) => _pageHeader(ctx.pageNumber > 1),
      footer: (ctx) => _pageFooter(ctx.pageNumber, ctx.pagesCount, reporterName,
          DateFormat('dd MMM yyyy').format(now)),
      build: (ctx) => [
        pw.Container(
          padding: const pw.EdgeInsets.all(14),
          color: _sailBlue,
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text('SAIL SAFETY LENS', style: pw.TextStyle(
              color: PdfColors.white, fontSize: 18, fontWeight: pw.FontWeight.bold)),
            pw.Text(title, style: pw.TextStyle(color: PdfColor.fromHex('#BBDEFB'), fontSize: 11)),
            pw.Text('Generated: ${DateFormat('dd MMM yyyy, HH:mm').format(now)}',
              style: pw.TextStyle(color: PdfColor.fromHex('#90CAF9'), fontSize: 9)),
          ]),
        ),
        pw.SizedBox(height: 16),
        pw.Text('Total Incidents: ${incidents.length}',
          style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 12),
        pw.Table(
          border: pw.TableBorder.all(color: _divider, width: 0.4),
          columnWidths: const {
            0: pw.FixedColumnWidth(24),
            1: pw.FixedColumnWidth(56),
            2: pw.FlexColumnWidth(2.0),
            3: pw.FlexColumnWidth(1.5),
            4: pw.FixedColumnWidth(50),
            5: pw.FixedColumnWidth(48),
          },
          children: [
            pw.TableRow(children: [
              for (final h in ['#', 'Date', 'Title', 'Plant', 'Severity', 'Status'])
                pw.Container(
                  padding: const pw.EdgeInsets.fromLTRB(6, 5, 6, 5),
                  color: _sailBlue,
                  child: pw.Text(h, style: pw.TextStyle(
                    color: PdfColors.white, fontSize: 8, fontWeight: pw.FontWeight.bold)),
                ),
            ]),
            ...List.generate(incidents.length, (i) {
              final inc = incidents[i];
              final sev = inc['severity']?.toString() ?? 'MEDIUM';
              final bg = i % 2 == 0 ? PdfColors.white : PdfColor.fromHex('#FAFAFA');
              return pw.TableRow(children: [
                pw.Container(padding: const pw.EdgeInsets.fromLTRB(6, 5, 6, 5), color: bg,
                  child: pw.Text('${i + 1}', style: const pw.TextStyle(fontSize: 8))),
                pw.Container(padding: const pw.EdgeInsets.fromLTRB(6, 5, 6, 5), color: bg,
                  child: pw.Text(
                    inc['date'] != null ? DateFormat('dd/MM/yy').format(DateTime.parse(inc['date'])) : '',
                    style: const pw.TextStyle(fontSize: 8))),
                pw.Container(padding: const pw.EdgeInsets.fromLTRB(6, 5, 6, 5), color: bg,
                  child: pw.Text(inc['title']?.toString() ?? '', style: const pw.TextStyle(fontSize: 8))),
                pw.Container(padding: const pw.EdgeInsets.fromLTRB(6, 5, 6, 5), color: bg,
                  child: pw.Text(inc['plant']?.toString() ?? '', style: const pw.TextStyle(fontSize: 8))),
                pw.Container(padding: const pw.EdgeInsets.fromLTRB(6, 5, 6, 5),
                  color: _getSevBg(sev),
                  child: pw.Text(sev, style: pw.TextStyle(
                    fontSize: 7, fontWeight: pw.FontWeight.bold, color: _getSevColor(sev)))),
                pw.Container(padding: const pw.EdgeInsets.fromLTRB(6, 5, 6, 5), color: bg,
                  child: pw.Text(inc['status']?.toString() ?? 'OPEN',
                    style: const pw.TextStyle(fontSize: 8))),
              ]);
            }),
          ],
        ),
      ],
    ));

    final dir = await getApplicationDocumentsDirectory();
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
