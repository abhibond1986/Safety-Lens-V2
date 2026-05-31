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
    required String reporterName,
    required String reporterPno,
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
    required String reporterName,
    required String reporterPno,
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
    required Map<S
