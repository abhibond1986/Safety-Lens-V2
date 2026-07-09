// lib/services/fine_tuning_collector.dart
// ★ Fine-Tuning Data Collector for SAIL Safety Lens
//
// PURPOSE: Collects "approved" AI scan results as training examples
// for fine-tuning Gemini Flash via Google AI Studio.
//
// HOW IT WORKS:
//   1. After an AI scan, admin can tap "Approve for Training" button
//   2. This saves the image (base64) + approved JSON output as a training pair
//   3. Admin can also EDIT the output before approving (to fix wrong results)
//   4. When enough examples collected (50-100), export as JSONL for fine-tuning
//
// USAGE:
//   await FineTuningCollector.saveTrainingExample(imageBytes, approvedResult);
//   final jsonl = await FineTuningCollector.exportAsJsonl();
//   final count = await FineTuningCollector.getExampleCount();

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class FineTuningCollector {
  static const String _kExamplesKey = 'fine_tuning_examples';
  static const String _kCountKey = 'fine_tuning_count';
  static const int maxExamples = 500; // Cap to prevent storage bloat

  /// Save an approved scan result as a training example
  /// [imageBase64] — the image that was scanned (base64 encoded JPEG)
  /// [approvedResult] — the JSON result (either AI-generated or admin-corrected)
  /// [metadata] — optional: section, location, inspector name
  static Future<bool> saveTrainingExample({
    required String imageBase64,
    required Map<String, dynamic> approvedResult,
    Map<String, String>? metadata,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final count = prefs.getInt(_kCountKey) ?? 0;

      if (count >= maxExamples) {
        print('FineTuningCollector: Max examples ($maxExamples) reached. Export and clear first.');
        return false;
      }

      // Build the training example in Gemini fine-tuning format
      final example = {
        'timestamp': DateTime.now().toIso8601String(),
        'imageBase64': imageBase64,
        'approvedOutput': approvedResult,
        'metadata': metadata ?? {},
        'version': 1,
      };

      // Store as individual keyed entries (avoid loading entire list into memory)
      final key = '${_kExamplesKey}_$count';
      await prefs.setString(key, jsonEncode(example));
      await prefs.setInt(_kCountKey, count + 1);

      print('FineTuningCollector: ✓ Saved example #${count + 1}');
      return true;
    } catch (e) {
      print('FineTuningCollector: Error saving example: $e');
      return false;
    }
  }

  /// Get current count of collected training examples
  static Future<int> getExampleCount() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_kCountKey) ?? 0;
  }

  /// Export all collected examples as JSONL (JSON Lines) format
  /// This is the format required by Google AI Studio for fine-tuning
  ///
  /// Each line is a complete training example in Gemini's tuning format:
  /// {"contents": [{"role": "user", "parts": [{"text": "..."}, {"inline_data": {...}}]},
  ///               {"role": "model", "parts": [{"text": "..."}]}]}
  static Future<String> exportAsJsonl() async {
    final prefs = await SharedPreferences.getInstance();
    final count = prefs.getInt(_kCountKey) ?? 0;

    if (count == 0) return '';

    final buffer = StringBuffer();

    for (int i = 0; i < count; i++) {
      final key = '${_kExamplesKey}_$i';
      final raw = prefs.getString(key);
      if (raw == null) continue;

      try {
        final example = jsonDecode(raw) as Map<String, dynamic>;
        final imageBase64 = example['imageBase64'] as String;
        final approvedOutput = example['approvedOutput'] as Map<String, dynamic>;

        // Format for Gemini fine-tuning (supervised tuning format)
        final tuningExample = {
          'contents': [
            {
              'role': 'user',
              'parts': [
                {
                  'text': _getFineTuningPrompt(),
                },
                {
                  'inline_data': {
                    'mime_type': 'image/jpeg',
                    'data': imageBase64,
                  }
                }
              ]
            },
            {
              'role': 'model',
              'parts': [
                {
                  'text': jsonEncode(approvedOutput),
                }
              ]
            }
          ]
        };

        buffer.writeln(jsonEncode(tuningExample));
      } catch (e) {
        print('FineTuningCollector: Error processing example $i: $e');
      }
    }

    return buffer.toString();
  }

  /// Export as simplified format (for review/editing before fine-tuning)
  static Future<List<Map<String, dynamic>>> exportForReview() async {
    final prefs = await SharedPreferences.getInstance();
    final count = prefs.getInt(_kCountKey) ?? 0;
    final results = <Map<String, dynamic>>[];

    for (int i = 0; i < count; i++) {
      final key = '${_kExamplesKey}_$i';
      final raw = prefs.getString(key);
      if (raw == null) continue;

      try {
        final example = jsonDecode(raw) as Map<String, dynamic>;
        results.add({
          'index': i,
          'timestamp': example['timestamp'],
          'hazardCount': (example['approvedOutput']?['hazards'] as List?)?.length ?? 0,
          'overallRisk': example['approvedOutput']?['overallRisk'] ?? 'UNKNOWN',
          'section': example['approvedOutput']?['detectedSection'] ?? 'GENERAL',
          'metadata': example['metadata'],
        });
      } catch (_) {}
    }

    return results;
  }

  /// Delete a specific training example by index
  static Future<void> deleteExample(int index) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '${_kExamplesKey}_$index';
    await prefs.remove(key);
    print('FineTuningCollector: Deleted example #$index');
  }

  /// Clear all collected training data
  static Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    final count = prefs.getInt(_kCountKey) ?? 0;

    for (int i = 0; i < count; i++) {
      await prefs.remove('${_kExamplesKey}_$i');
    }
    await prefs.setInt(_kCountKey, 0);
    print('FineTuningCollector: Cleared all $count examples');
  }

  /// The simplified prompt used for fine-tuning examples
  /// (shorter than the full prompt — fine-tuned model learns the behavior)
  static String _getFineTuningPrompt() {
    return '''Analyze this industrial safety image from a SAIL steel plant. Identify all visible hazards with:
- Specific visual evidence for each hazard
- Correct statutory regulation (FA 1948, SMPV Rules, CEA Regulations, IS standards)
- Severity rating (CRITICAL/HIGH/MEDIUM/LOW)
- Specific corrective actions
- Plant section identification

Return structured JSON with overallRisk, riskScore, confidence, people count, detectedSection, summary, and hazards array. Each hazard must have: name, description (starting with "Visible:"), visualEvidence, severity, regulation, correctiveAction, type, bbox.''';
  }

  /// Get statistics about collected data
  static Future<Map<String, dynamic>> getStats() async {
    final prefs = await SharedPreferences.getInstance();
    final count = prefs.getInt(_kCountKey) ?? 0;

    int criticalCount = 0, highCount = 0, mediumCount = 0, lowCount = 0;
    Map<String, int> sectionCounts = {};

    for (int i = 0; i < count; i++) {
      final key = '${_kExamplesKey}_$i';
      final raw = prefs.getString(key);
      if (raw == null) continue;

      try {
        final example = jsonDecode(raw) as Map<String, dynamic>;
        final risk = example['approvedOutput']?['overallRisk']?.toString() ?? '';
        final section = example['approvedOutput']?['detectedSection']?.toString() ?? 'GENERAL';

        switch (risk) {
          case 'CRITICAL': criticalCount++; break;
          case 'HIGH': highCount++; break;
          case 'MEDIUM': mediumCount++; break;
          case 'LOW': lowCount++; break;
        }
        sectionCounts[section] = (sectionCounts[section] ?? 0) + 1;
      } catch (_) {}
    }

    return {
      'totalExamples': count,
      'maxExamples': maxExamples,
      'readyForFineTuning': count >= 50,
      'riskDistribution': {
        'CRITICAL': criticalCount,
        'HIGH': highCount,
        'MEDIUM': mediumCount,
        'LOW': lowCount,
      },
      'sectionDistribution': sectionCounts,
      'recommendation': count < 50
          ? 'Need ${50 - count} more examples. Aim for diverse sections and risk levels.'
          : count < 100
              ? 'Good! ${count} examples collected. Can start fine-tuning, but 100+ is ideal.'
              : 'Excellent! ${count} examples ready. Export JSONL and fine-tune via AI Studio.',
    };
  }
}
