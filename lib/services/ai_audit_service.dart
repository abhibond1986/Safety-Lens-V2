// lib/services/ai_audit_service.dart
// ★ v35: Background AI Audit Service
//
// PURPOSE: After every AI scan is saved, re-analyze the image with a DIFFERENT
// AI model in the background. Compare hazard results. If match < 95%, flag
// the incident with discrepancy notes for human review.
//
// FLOW:
//   1. User saves scan → _triggerAudit() called silently
//   2. Pick a model different from the one that produced the original result
//   3. Run analysis → compare hazards (name similarity + severity match)
//   4. Score match percentage
//   5. If < 95%, update incident with auditStatus = 'NEEDS_REVIEW' + notes
//   6. Show badge in Reports log

import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'local_db.dart';

class AiAuditService {
  static bool _isAuditing = false;

  /// Trigger background audit for a saved AI scan incident.
  /// Call this AFTER saving — it runs silently, no user-facing delay.
  static Future<void> auditIncident({
    required Map<String, dynamic> incident,
    required Uint8List imageBytes,
    required String primarySource, // which model produced the original result
  }) async {
    // Don't audit if already auditing or if no image
    if (_isAuditing || imageBytes.isEmpty) return;

    // Only audit AI_SCAN type
    if (incident['type']?.toString() != 'AI_SCAN') return;

    _isAuditing = true;
    try {
      print('AiAudit: Starting background audit (primary was: $primarySource)');

      // Pick a different model for cross-verification
      final auditResult = await _runAuditAnalysis(imageBytes, primarySource);
      if (auditResult == null) {
        print('AiAudit: Audit model failed — skipping');
        return;
      }

      // Compare original hazards with audit hazards
      final originalHazards = _extractHazardNames(incident);
      final auditHazards = _extractHazardNamesFromResult(auditResult);

      if (originalHazards.isEmpty || auditHazards.isEmpty) {
        print('AiAudit: No hazards to compare — skipping');
        return;
      }

      final matchScore = _calculateMatchScore(originalHazards, auditHazards);
      print('AiAudit: Match score = ${matchScore.toStringAsFixed(1)}%');

      // Store audit result — full detail for admin comparison panel
      final auditData = <String, dynamic>{
        'auditScore': matchScore.round(),
        'auditModel': 'OpenRouter Nemotron 30B',
        'auditHazardCount': auditHazards.length,
        'originalHazardCount': originalHazards.length,
        'auditTimestamp': DateTime.now().toIso8601String(),
        'auditHazards': jsonEncode(auditResult['hazards'] ?? []),
        'originalHazardNames': jsonEncode(originalHazards),
        'auditHazardNames': jsonEncode(auditHazards),
      };

      if (matchScore < 95) {
        // Flag for review
        auditData['auditStatus'] = 'NEEDS_REVIEW';
        auditData['auditNotes'] = _generateDiscrepancyNotes(
            originalHazards, auditHazards, auditResult);
        print('AiAudit: ⚠ DISCREPANCY FOUND — flagging for review');
        print('AiAudit: Original: ${originalHazards.join(", ")}');
        print('AiAudit: Audit:    ${auditHazards.join(", ")}');
      } else {
        auditData['auditStatus'] = 'VERIFIED';
        auditData['auditNotes'] = 'Cross-verified: hazards match across models';
        print('AiAudit: ✓ Verified — hazards consistent across models');
      }

      // Update incident in LocalDB with audit data
      final incidentId = incident['id']?.toString() ?? '';
      if (incidentId.isNotEmpty) {
        await LocalDB.updateIncidentAudit(incidentId, auditData);
      }
    } catch (e) {
      print('AiAudit: Exception: $e');
    } finally {
      _isAuditing = false;
    }
  }

  /// Run audit analysis — ALWAYS uses OpenRouter Nemotron 30B
  /// This gives a consistent second opinion from a single audit model.
  static Future<Map<String, dynamic>?> _runAuditAnalysis(
      Uint8List bytes, String primarySource) async {
    final prefs = await SharedPreferences.getInstance();
    final orKey = prefs.getString('openrouter_api_key') ?? '';

    if (orKey.isNotEmpty && orKey.startsWith('sk-or-')) {
      return await _callOpenRouterAudit(bytes, orKey);
    }

    // Fallback: if OpenRouter key not configured, skip audit
    print('AiAudit: OpenRouter key not configured — cannot run audit');
    return null;
  }

  /// Simplified prompt for audit — just asks for hazard identification
  static String _getAuditPrompt() {
    return '''Analyze this industrial/workplace image for safety hazards.

List ALL hazards you can identify. For each hazard provide:
- name: short hazard name
- severity: CRITICAL, HIGH, MEDIUM, or LOW
- description: what you observe

Respond in JSON format:
{
  "hazards": [
    {"name": "...", "severity": "...", "description": "..."}
  ]
}

Respond ONLY with JSON.''';
  }

  // ═══════════════════════════════════════════════════════════════
  //  AUDIT PROVIDERS
  // ═══════════════════════════════════════════════════════════════

  static Future<Map<String, dynamic>?> _callOpenRouterAudit(
      Uint8List bytes, String apiKey) async {
    try {
      final base64Image = base64Encode(bytes);
      final dataUrl = 'data:image/jpeg;base64,$base64Image';
      const model = 'nvidia/nemotron-3-nano-omni-30b-a3b-reasoning:free';

      final response = await http.post(
        Uri.parse('https://openrouter.ai/api/v1/chat/completions'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        },
        body: jsonEncode({
          'model': model,
          'messages': [{
            'role': 'user',
            'content': [
              {'type': 'text', 'text': _getAuditPrompt()},
              {'type': 'image_url', 'image_url': {'url': dataUrl}},
            ]
          }],
          'max_tokens': 4096,
          'temperature': 0.1,
        }),
      ).timeout(const Duration(seconds: 45));

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        final content = data['choices']?[0]?['message']?['content']?.toString() ?? '';
        final parsed = _parseJsonResponse(content);
        if (parsed != null) {
          parsed['_source'] = 'openrouter_audit';
          return parsed;
        }
      }
    } catch (e) {
      print('AiAudit: OpenRouter error: $e');
    }
    return null;
  }


  // ═══════════════════════════════════════════════════════════════
  //  COMPARISON LOGIC
  // ═══════════════════════════════════════════════════════════════

  /// Extract hazard names from saved incident data
  static List<String> _extractHazardNames(Map<String, dynamic> incident) {
    final hazards = <String>[];
    // The incident stores hazards in different formats depending on source
    if (incident['hazards'] is List) {
      for (final h in incident['hazards'] as List) {
        if (h is Map) {
          final name = h['name']?.toString() ?? '';
          if (name.isNotEmpty) hazards.add(name.toLowerCase().trim());
        }
      }
    }
    // Also check the title as primary hazard
    final title = incident['title']?.toString() ?? '';
    if (title.isNotEmpty && hazards.isEmpty) {
      hazards.add(title.toLowerCase().trim());
    }
    return hazards;
  }

  /// Extract hazard names from audit result
  static List<String> _extractHazardNamesFromResult(Map<String, dynamic> result) {
    final hazards = <String>[];
    if (result['hazards'] is List) {
      for (final h in result['hazards'] as List) {
        if (h is Map) {
          final name = h['name']?.toString() ?? '';
          if (name.isNotEmpty) hazards.add(name.toLowerCase().trim());
        }
      }
    }
    return hazards;
  }

  /// Calculate match score between two hazard lists
  /// Uses keyword overlap — not exact string match
  static double _calculateMatchScore(
      List<String> original, List<String> audit) {
    if (original.isEmpty && audit.isEmpty) return 100.0;
    if (original.isEmpty || audit.isEmpty) return 0.0;

    int matched = 0;
    final totalToCheck = original.length;

    for (final origHazard in original) {
      final origKeywords = _extractKeywords(origHazard);
      bool found = false;

      for (final auditHazard in audit) {
        final auditKeywords = _extractKeywords(auditHazard);
        // Calculate keyword overlap
        final overlap = origKeywords.intersection(auditKeywords).length;
        final minLen = [origKeywords.length, auditKeywords.length]
            .reduce((a, b) => a < b ? a : b);
        // If >50% keyword overlap, consider it a match
        if (minLen > 0 && overlap / minLen >= 0.5) {
          found = true;
          break;
        }
      }
      if (found) matched++;
    }

    // Also penalize if audit found significantly more hazards
    final extraHazards = (audit.length - original.length).clamp(0, 999);
    final penalty = extraHazards * 5.0; // 5% penalty per extra hazard found

    final baseScore = (matched / totalToCheck) * 100.0;
    return (baseScore - penalty).clamp(0.0, 100.0);
  }

  /// Extract meaningful keywords from a hazard name
  static Set<String> _extractKeywords(String text) {
    final stopWords = {'a', 'an', 'the', 'is', 'are', 'of', 'in', 'on', 'at',
        'to', 'for', 'and', 'or', 'not', 'no', 'with', 'from', 'by', 'this',
        'that', 'it', 'its', 'be', 'has', 'have', 'was', 'were', 'visible'};
    return text
        .replaceAll(RegExp(r'[^\w\s]'), '')
        .split(RegExp(r'\s+'))
        .map((w) => w.toLowerCase().trim())
        .where((w) => w.length > 2 && !stopWords.contains(w))
        .toSet();
  }

  /// Generate human-readable discrepancy notes
  static String _generateDiscrepancyNotes(
      List<String> original, List<String> audit, Map<String, dynamic> auditResult) {
    final buf = StringBuffer();
    buf.writeln('Cross-model verification found differences:');
    buf.writeln('');
    buf.writeln('Original model found ${original.length} hazard(s):');
    for (int i = 0; i < original.length; i++) {
      buf.writeln('  ${i+1}. ${original[i]}');
    }
    buf.writeln('');
    buf.writeln('Audit model found ${audit.length} hazard(s):');
    for (int i = 0; i < audit.length; i++) {
      buf.writeln('  ${i+1}. ${audit[i]}');
    }

    // Identify what was missed
    final missed = <String>[];
    for (final auditHazard in audit) {
      final auditKeywords = _extractKeywords(auditHazard);
      bool found = false;
      for (final origHazard in original) {
        final origKeywords = _extractKeywords(origHazard);
        final overlap = origKeywords.intersection(auditKeywords).length;
        final minLen = [origKeywords.length, auditKeywords.length]
            .reduce((a, b) => a < b ? a : b);
        if (minLen > 0 && overlap / minLen >= 0.5) {
          found = true;
          break;
        }
      }
      if (!found) missed.add(auditHazard);
    }

    if (missed.isNotEmpty) {
      buf.writeln('');
      buf.writeln('Potentially missed by primary model:');
      for (final m in missed) {
        buf.writeln('  ⚠ $m');
      }
    }

    return buf.toString();
  }

  /// Parse JSON from AI response (handles markdown fences)
  static Map<String, dynamic>? _parseJsonResponse(String content) {
    if (content.isEmpty) return null;
    try {
      String jsonStr = content.trim();
      // Remove markdown fences
      if (jsonStr.contains('```')) {
        final match = RegExp(r'\{[\s\S]*\}').firstMatch(jsonStr);
        if (match != null) jsonStr = match.group(0)!;
      }
      final parsed = jsonDecode(jsonStr);
      if (parsed is Map<String, dynamic>) return parsed;
    } catch (_) {
      // Try regex extraction
      try {
        final match = RegExp(r'\{[\s\S]*\}').firstMatch(content);
        if (match != null) {
          return jsonDecode(match.group(0)!) as Map<String, dynamic>;
        }
      } catch (_) {}
    }
    return null;
  }
}
