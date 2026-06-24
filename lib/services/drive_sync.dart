// lib/services/drive_sync.dart
//
// After saving an incident + generating PDF bytes,
// call this to upload to Google Drive and store the link in Sheets.

import 'dart:convert';
import 'package:flutter/foundation.dart' show Uint8List;
import 'package:http/http.dart' as http;

class DriveSync {
  static const String _appsScriptUrl =
      'https://script.google.com/macros/s/AKfycbzDiT4OSvlDUxvcM9DYJ_-SiB1HyDrgXtYflGfmqJRH9wnZZusj5GqX9frCx64rkd61Rg/exec';

  /// Upload a PDF to Google Drive and return the shareable view URL.
  /// Also updates the incident row in Google Sheets with the pdfUrl.
  ///
  /// Returns the Drive URL on success, or null on failure.
  static Future<String?> uploadIncidentPdf({
    required Uint8List pdfBytes,
    required String incidentId,
    required String fileName,
  }) async {
    try {
      final b64 = base64Encode(pdfBytes);
      final client = http.Client();
      http.Response response;
      try {
        response = await client.post(
          Uri.parse(_appsScriptUrl),
          headers: {'Content-Type': 'text/plain;charset=utf-8'},
          body: jsonEncode({
            'action':     'uploadPdfToDrive',
            'pdfBase64':  b64,
            'fileName':   fileName,
            'incidentId': incidentId,
          }),
        ).timeout(const Duration(seconds: 90));

        // ✅ FIX: Apps Script redirects POST → GET for the response
        if (response.statusCode == 302 || response.statusCode == 301) {
          final loc = response.headers['location'] ?? '';
          if (loc.isNotEmpty) {
            response = await client.get(
              Uri.parse(loc),
              headers: {'Accept': 'application/json'},
            ).timeout(const Duration(seconds: 30));
          }
        }
      } finally { client.close(); }

      if (response.statusCode == 200) {
        final bodyTrimmed = response.body.trim();
        if (bodyTrimmed.startsWith('<')) return null;
        final data = jsonDecode(bodyTrimmed) as Map<String, dynamic>;
        if (data['success'] == true) {
          return data['pdfUrl']?.toString();
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}
