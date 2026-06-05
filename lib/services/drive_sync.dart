final url = await DriveSync.uploadIncidentPdf(
  pdfBytes:   bytes,         // from PdfExport.generateIncidentReportBytes()
  incidentId: incident['id'],
  fileName:   'SafetyLens_${incident['id']}.pdf',
);
// url is now the Google Drive viewable link
// It's also already written to the Sheets pdfUrl column by Apps Script
