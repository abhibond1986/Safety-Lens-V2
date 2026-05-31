import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb, Uint8List;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';
// Web-only download support (uses dart:html on web, stub on mobile)
import 'dart:html' as html if (dart.library.io) 'pdf_export_stub.dart';

/// PDF Export service for SAIL Safety Lens.
class PdfExport {
  static const String _sailBlue = '#0D47A1';
  static const String _critical = '#EF4444';
  static const String _high = '#F59E0B';
  static const String _medium = '#00BCD4';
  static const String _low = '#10B981';

  /// Get PDF as bytes (works on web AND mobile)
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
      try {
        embedBytes = base64Decode(incident['imageBase64'].toString());
      } catch (_) {}
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) {
          final widgets = <pw.Widget>[];
          widgets.add(_buildHeader());
          widgets.add(pw.SizedBox(height: 16));
          widgets.add(_buildIncidentInfo(incident, dateStr, reporterName, reporterPno));
          widgets.add(pw.SizedBox(height: 16));

          if (embedBytes != null) {
            final imgBytes = embedBytes;
            widgets.add(pw.Text('EVIDENCE PHOTO',
              style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColor.fromHex('#666666'))));
            widgets.add(pw.SizedBox(height: 4));
            widgets.add(pw.Container(
              margin: const pw.EdgeInsets.only(bottom: 12),
              decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.5)),
              child: pw.Image(pw.MemoryImage(imgBytes), height: 220, fit: pw.BoxFit.contain),
            ));
          }

          widgets.add(_buildSeverityCard(incident['severity'] ?? 'MEDIUM'));
          widgets.add(pw.SizedBox(height: 16));
          widgets.add(_buildDescriptionSection(incident));
          widgets.add(pw.SizedBox(height: 16));
          widgets.add(_buildWsaSection(incident));
          widgets.add(pw.SizedBox(height: 16));
          widgets.add(_buildCorrectiveActions(incident));
          widgets.add(pw.SizedBox(height: 24));
          widgets.add(_buildFooter());
          return widgets;
        },
      ),
    );

    return pdf.save();
  }

  /// Download PDF on web (triggers browser download) OR share on mobile
  static Future<void> downloadOrShareIncident({
    required Map<String, dynamic> incident,
    String reporterName = 'SAIL Safety Officer',
    String reporterPno = '',
    Uint8List? imageBytes,
  }) async {
    final bytes = await generateIncidentReportBytes(
      incident: incident,
      reporterName: reporterName,
      reporterPno: reporterPno,
      imageBytes: imageBytes,
    );
    final filename =
        'SafetyLens_Report_${incident['id'] ?? DateTime.now().millisecondsSinceEpoch}.pdf';

    if (kIsWeb) {
      try {
        final blob = html.Blob([bytes], 'application/pdf');
        final url = html.Url.createObjectUrlFromBlob(blob);
        final anchor = html.AnchorElement(href: url)
          ..setAttribute('download', filename)
          ..click();
        html.Url.revokeObjectUrl(url);
      } catch (e) {
        rethrow;
      }
    } else {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$filename');
      await file.writeAsBytes(bytes);
      await Share.shareXFiles([XFile(file.path)],
          text: 'SAIL Safety Lens Incident Report',
          subject: 'Incident Report ${incident['id'] ?? ''}');
    }
  }

  // Legacy: Generate file (mobile only)
  static Future<File> generateIncidentReport({
    required Map<String, dynamic> incident,
    String reporterName = 'SAIL Safety Officer',
    String reporterPno = '',
  }) async {
    final bytes = await generateIncidentReportBytes(
      incident: incident,
      reporterName: reporterName,
      reporterPno: reporterPno,
    );
    final dir = await getApplicationDocumentsDirectory();
    final filename = 'SafetyLens_Report_${incident['id'] ?? DateTime.now().millisecondsSinceEpoch}.pdf';
    final file = File('${dir.path}/$filename');
    await file.writeAsBytes(bytes);
    return file;
  }

  /// Generate consolidated report — all params optional for backward compat
  static Future<File> generateConsolidatedReport({
    required List<Map<String, dynamic>> incidents,
    String reporterName = 'SAIL Safety Officer',
    String? reportTitle,
  }) async {
    final pdf = pw.Document();
    final title = reportTitle ?? 'CONSOLIDATED INCIDENT REPORT';

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          _buildHeader(),
          pw.SizedBox(height: 16),
          pw.Text(title,
            style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 8),
          pw.Text('Generated by: $reporterName',
            style: const pw.TextStyle(fontSize: 10)),
          pw.Text('Date: ${DateFormat('dd MMM yyyy, HH:mm').format(DateTime.now())}',
            style: const pw.TextStyle(fontSize: 10)),
          pw.SizedBox(height: 16),
          pw.Text('Total Incidents: ${incidents.length}',
            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 16),
          pw.Table.fromTextArray(
            headers: ['Date', 'Title', 'Plant', 'Severity', 'Status'],
            data: incidents.map((i) => [
              i['date']?.toString().substring(0, 10) ?? '',
              i['title']?.toString() ?? '',
              i['plant']?.toString() ?? '',
              i['severity']?.toString() ?? '',
              i['status']?.toString() ?? '',
            ]).toList(),
            headerStyle: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
            headerDecoration: pw.BoxDecoration(color: PdfColor.fromHex(_sailBlue)),
            cellStyle: const pw.TextStyle(fontSize: 8),
            cellAlignment: pw.Alignment.centerLeft,
          ),
          pw.SizedBox(height: 24),
          _buildFooter(),
        ],
      ),
    );

    final dir = await getApplicationDocumentsDirectory();
    final filename = 'SafetyLens_Consolidated_${DateTime.now().millisecondsSinceEpoch}.pdf';
    final file = File('${dir.path}/$filename');
    await file.writeAsBytes(await pdf.save());
    return file;
  }

  static Future<void> sharePdf(File file, {String? subject}) async {
    await Share.shareXFiles([XFile(file.path)],
        text: subject ?? 'SAIL Safety Lens Report',
        subject: subject ?? 'Safety Report');
  }

  // ============ PDF BUILD HELPERS ============
  static pw.Widget _buildHeader() {
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: PdfColor.fromHex(_sailBlue),
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text('SAFETY LENS',
              style: pw.TextStyle(fontSize: 18, color: PdfColors.white, fontWeight: pw.FontWeight.bold)),
            pw.Text('Steel Authority of India Limited',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.white)),
          ]),
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
            pw.Text('IS 14489:1998',
              style: pw.TextStyle(fontSize: 9, color: PdfColors.white, fontWeight: pw.FontWeight.bold)),
            pw.Text('Factories Act 1948',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.white)),
          ]),
        ],
      ),
    );
  }

  static pw.Widget _buildIncidentInfo(Map<String, dynamic> incident, String dateStr, String reporterName, String reporterPno) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: PdfColor.fromHex('#F1F5F9'),
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Text(incident['title']?.toString() ?? 'Incident Report',
          style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 8),
        pw.Row(children: [
          _kv('Date', dateStr),
          pw.SizedBox(width: 30),
          _kv('Plant', incident['plant']?.toString() ?? ''),
        ]),
        pw.SizedBox(height: 4),
        pw.Row(children: [
          _kv('Department', incident['dept']?.toString() ?? ''),
          pw.SizedBox(width: 30),
          _kv('Location', incident['location']?.toString() ?? ''),
        ]),
        pw.SizedBox(height: 4),
        pw.Row(children: [
          _kv('Reported by', reporterName),
          if (reporterPno.isNotEmpty) ...[
            pw.SizedBox(width: 30),
            _kv('P. No.', reporterPno),
          ],
        ]),
        pw.SizedBox(height: 4),
        pw.Row(children: [
          _kv('Type', incident['type']?.toString() ?? 'NEAR_MISS'),
          pw.SizedBox(width: 30),
          _kv('Status', incident['status']?.toString() ?? 'OPEN'),
        ]),
      ]),
    );
  }

  static pw.Widget _kv(String k, String v) {
    return pw.Row(children: [
      pw.Text('$k: ',
        style: pw.TextStyle(fontSize: 8, color: PdfColor.fromHex('#64748B'), fontWeight: pw.FontWeight.bold)),
      pw.Text(v, style: const pw.TextStyle(fontSize: 9)),
    ]);
  }

  static pw.Widget _buildSeverityCard(String severity) {
    final color = severity == 'CRITICAL' ? _critical
        : severity == 'HIGH' ? _high
        : severity == 'MEDIUM' ? _medium
        : _low;
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: PdfColor.fromHex(color),
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Row(children: [
        pw.Text('SEVERITY: ',
          style: pw.TextStyle(fontSize: 10, color: PdfColors.white, fontWeight: pw.FontWeight.bold)),
        pw.Text(severity,
          style: pw.TextStyle(fontSize: 14, color: PdfColors.white, fontWeight: pw.FontWeight.bold)),
      ]),
    );
  }

  static pw.Widget _buildDescriptionSection(Map<String, dynamic> incident) {
    return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Text('DESCRIPTION',
        style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColor.fromHex(_sailBlue))),
      pw.SizedBox(height: 4),
      pw.Text(incident['desc']?.toString() ?? '',
        style: const pw.TextStyle(fontSize: 10, lineSpacing: 1.4)),
    ]);
  }

  static pw.Widget _buildWsaSection(Map<String, dynamic> incident) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        color: PdfColor.fromHex('#FEF3C7'),
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Text('ROOT CAUSE ANALYSIS (WSA 13)',
          style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColor.fromHex('#92400E'))),
        pw.SizedBox(height: 4),
        pw.Text(incident['wsaCategory']?.toString() ?? 'Not specified',
          style: const pw.TextStyle(fontSize: 10)),
      ]),
    );
  }

  static pw.Widget _buildCorrectiveActions(Map<String, dynamic> incident) {
    return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Text('IMMEDIATE CORRECTIVE ACTION',
        style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColor.fromHex(_sailBlue))),
      pw.SizedBox(height: 4),
      pw.Text(incident['immediateAction']?.toString() ?? 'Not specified',
        style: const pw.TextStyle(fontSize: 10, lineSpacing: 1.4)),
    ]);
  }

  static pw.Widget _buildFooter() {
    return pw.Container(
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        color: PdfColor.fromHex('#F1F5F9'),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Column(children: [
        pw.Text('This report is generated by SAIL Safety Lens',
          style: pw.TextStyle(fontSize: 8, color: PdfColor.fromHex('#64748B'), fontWeight: pw.FontWeight.bold)),
        pw.Text('Compliant with IS 14489:1998, Factories Act 1948, Ministry of Steel Guidelines',
          style: pw.TextStyle(fontSize: 7, color: PdfColor.fromHex('#94A3B8'))),
      ]),
    );
  }
}
