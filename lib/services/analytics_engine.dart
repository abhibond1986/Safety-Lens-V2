import 'dart:math' as math;
import 'package:flutter/material.dart';

class AnalyticsEngine {
  // ═══════════════════════════════════════════════════════════════
  //  TIME BUCKETING
  // ═══════════════════════════════════════════════════════════════

  static List<Map<String, dynamic>> getIncidentsByTimeBucket(
      List<Map<String, dynamic>> incidents, String bucketSize) {
    final buckets = <String, int>{};
    for (final i in incidents) {
      final date = DateTime.tryParse(i['date']?.toString() ?? '');
      if (date == null) continue;
      final key = _bucketKey(date, bucketSize);
      buckets[key] = (buckets[key] ?? 0) + 1;
    }
    final sorted = buckets.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return sorted.map((e) => {'bucket': e.key, 'count': e.value}).toList();
  }

  static Map<String, List<Map<String, dynamic>>> getSeverityTrend(
      List<Map<String, dynamic>> incidents, String bucketSize) {
    final result = <String, List<Map<String, dynamic>>>{};
    final severities = ['CRITICAL', 'HIGH', 'MEDIUM', 'LOW'];
    for (final sev in severities) {
      final filtered = incidents.where(
          (i) => (i['severity']?.toString().toUpperCase() ?? '') == sev).toList();
      result[sev] = getIncidentsByTimeBucket(filtered, bucketSize);
    }
    return result;
  }

  static Map<String, List<Map<String, dynamic>>> getCategoryTrend(
      List<Map<String, dynamic>> incidents, String bucketSize) {
    final categories = <String>{};
    for (final i in incidents) {
      final cat = i['wsaCategory']?.toString() ?? 'Other';
      categories.add(cat);
    }
    final result = <String, List<Map<String, dynamic>>>{};
    for (final cat in categories) {
      final filtered = incidents.where(
          (i) => (i['wsaCategory']?.toString() ?? 'Other') == cat).toList();
      result[cat] = getIncidentsByTimeBucket(filtered, bucketSize);
    }
    return result;
  }

  static String _bucketKey(DateTime date, String bucketSize) {
    switch (bucketSize) {
      case 'day':
        return '${date.year}-${_pad(date.month)}-${_pad(date.day)}';
      case 'week':
        final weekStart = date.subtract(Duration(days: date.weekday - 1));
        return '${weekStart.year}-W${_pad(_weekNumber(weekStart))}';
      case 'month':
        return '${date.year}-${_pad(date.month)}';
      default:
        return '${date.year}-${_pad(date.month)}';
    }
  }

  static int _weekNumber(DateTime date) {
    final firstDay = DateTime(date.year, 1, 1);
    return ((date.difference(firstDay).inDays + firstDay.weekday - 1) / 7)
            .ceil() +
        1;
  }

  static String _pad(int n) => n.toString().padLeft(2, '0');

  // ═══════════════════════════════════════════════════════════════
  //  PREDICTIVE ANALYTICS
  // ═══════════════════════════════════════════════════════════════

  static Map<String, double> computePlantRiskScores(
      List<Map<String, dynamic>> incidents) {
    final scores = <String, double>{};
    final now = DateTime.now();
    final plants = <String>{};
    for (final i in incidents) {
      plants.add(i['plant']?.toString() ?? 'Unknown');
    }
    for (final plant in plants) {
      final plantIncidents =
          incidents.where((i) => i['plant']?.toString() == plant).toList();
      double score = 0;
      for (final i in plantIncidents) {
        final sev = i['severity']?.toString().toUpperCase() ?? 'MEDIUM';
        final weight = _severityWeight(sev);
        final date = DateTime.tryParse(i['date']?.toString() ?? '');
        final recency = date != null
            ? (now.difference(date).inDays <= 30 ? 3.0 : 1.0)
            : 1.0;
        score += weight * recency;
      }
      scores[plant] = score;
    }
    return scores;
  }

  static double _severityWeight(String severity) {
    switch (severity) {
      case 'CRITICAL':
        return 4.0;
      case 'HIGH':
        return 3.0;
      case 'MEDIUM':
        return 2.0;
      case 'LOW':
        return 1.0;
      default:
        return 2.0;
    }
  }

  static List<Map<String, dynamic>> detectRisingCategories(
      List<Map<String, dynamic>> incidents) {
    final now = DateTime.now();
    final last30 = incidents.where((i) {
      final d = DateTime.tryParse(i['date']?.toString() ?? '');
      return d != null && now.difference(d).inDays <= 30;
    }).toList();
    final prior60 = incidents.where((i) {
      final d = DateTime.tryParse(i['date']?.toString() ?? '');
      return d != null &&
          now.difference(d).inDays > 30 &&
          now.difference(d).inDays <= 90;
    }).toList();

    final categories = <String>{};
    for (final i in incidents) {
      categories.add(i['wsaCategory']?.toString() ?? 'Other');
    }

    final rising = <Map<String, dynamic>>[];
    for (final cat in categories) {
      final recent = last30.where(
          (i) => (i['wsaCategory']?.toString() ?? 'Other') == cat).length;
      final prior = prior60.where(
          (i) => (i['wsaCategory']?.toString() ?? 'Other') == cat).length;
      final priorNorm = prior / 2.0; // normalize 60d → 30d equivalent
      if (recent > priorNorm && recent > 0) {
        final change = priorNorm > 0
            ? ((recent - priorNorm) / priorNorm * 100).round()
            : 100;
        rising.add({
          'category': cat,
          'recentCount': recent,
          'priorCount': prior,
          'changePercent': change,
        });
      }
    }
    rising.sort((a, b) =>
        (b['changePercent'] as int).compareTo(a['changePercent'] as int));
    return rising;
  }

  static List<Map<String, dynamic>> predictHotSpots(
      List<Map<String, dynamic>> incidents) {
    final now = DateTime.now();
    final plants = <String>{};
    for (final i in incidents) {
      plants.add(i['plant']?.toString() ?? 'Unknown');
    }

    final hotSpots = <Map<String, dynamic>>[];
    for (final plant in plants) {
      final plantInc =
          incidents.where((i) => i['plant']?.toString() == plant).toList();
      final last30 = plantInc.where((i) {
        final d = DateTime.tryParse(i['date']?.toString() ?? '');
        return d != null && now.difference(d).inDays <= 30;
      }).length;
      final prior30 = plantInc.where((i) {
        final d = DateTime.tryParse(i['date']?.toString() ?? '');
        return d != null &&
            now.difference(d).inDays > 30 &&
            now.difference(d).inDays <= 60;
      }).length;

      if (last30 > prior30 && last30 > 0) {
        final acceleration =
            prior30 > 0 ? ((last30 - prior30) / prior30 * 100).round() : 100;
        hotSpots.add({
          'plant': plant,
          'recentCount': last30,
          'priorCount': prior30,
          'acceleration': acceleration,
        });
      }
    }
    hotSpots.sort(
        (a, b) => (b['acceleration'] as int).compareTo(a['acceleration'] as int));
    return hotSpots;
  }

  // ═══════════════════════════════════════════════════════════════
  //  HEAT MAP
  // ═══════════════════════════════════════════════════════════════

  static Map<String, Map<String, int>> buildHeatMapMatrix(
      List<Map<String, dynamic>> incidents) {
    final matrix = <String, Map<String, int>>{};
    for (final i in incidents) {
      final plant = i['plant']?.toString() ?? 'Unknown';
      final cat = i['wsaCategory']?.toString() ?? 'Other';
      matrix.putIfAbsent(plant, () => <String, int>{});
      matrix[plant]![cat] = (matrix[plant]![cat] ?? 0) + 1;
    }
    return matrix;
  }

  static Map<String, Map<String, int>> buildSeverityHeatMap(
      List<Map<String, dynamic>> incidents) {
    final matrix = <String, Map<String, int>>{};
    for (final i in incidents) {
      final plant = i['plant']?.toString() ?? 'Unknown';
      final sev = i['severity']?.toString().toUpperCase() ?? 'MEDIUM';
      matrix.putIfAbsent(plant, () => <String, int>{});
      matrix[plant]![sev] = (matrix[plant]![sev] ?? 0) + 1;
    }
    return matrix;
  }

  static Color heatColor(int count, int maxCount) {
    if (maxCount == 0 || count == 0) return const Color(0x00000000);
    final t = math.min(count / maxCount, 1.0);
    // white → yellow → orange → red
    if (t < 0.33) {
      return Color.lerp(
          const Color(0xFFFFF9C4), const Color(0xFFFFD54F), t / 0.33)!;
    } else if (t < 0.66) {
      return Color.lerp(const Color(0xFFFFD54F), const Color(0xFFFF8A65),
          (t - 0.33) / 0.33)!;
    } else {
      return Color.lerp(const Color(0xFFFF8A65), const Color(0xFFE53935),
          (t - 0.66) / 0.34)!;
    }
  }

  // ═══════════════════════════════════════════════════════════════
  //  FILTERING & GROUPING (Report Builder)
  // ═══════════════════════════════════════════════════════════════

  static List<Map<String, dynamic>> filterIncidents(
      List<Map<String, dynamic>> incidents, {
    DateTime? startDate,
    DateTime? endDate,
    List<String>? plants,
    List<String>? severities,
    List<String>? categories,
    List<String>? types,
    List<String>? statuses,
  }) {
    return incidents.where((i) {
      if (startDate != null || endDate != null) {
        final d = DateTime.tryParse(i['date']?.toString() ?? '');
        if (d == null) return false;
        if (startDate != null && d.isBefore(startDate)) return false;
        if (endDate != null && d.isAfter(endDate)) return false;
      }
      if (plants != null && plants.isNotEmpty) {
        if (!plants.contains(i['plant']?.toString())) return false;
      }
      if (severities != null && severities.isNotEmpty) {
        if (!severities.contains(i['severity']?.toString().toUpperCase()))
          return false;
      }
      if (categories != null && categories.isNotEmpty) {
        if (!categories.contains(i['wsaCategory']?.toString())) return false;
      }
      if (types != null && types.isNotEmpty) {
        if (!types.contains(i['type']?.toString().toUpperCase())) return false;
      }
      if (statuses != null && statuses.isNotEmpty) {
        if (!statuses.contains(i['status']?.toString().toUpperCase()))
          return false;
      }
      return true;
    }).toList();
  }

  static Map<String, List<Map<String, dynamic>>> groupIncidents(
      List<Map<String, dynamic>> incidents, String dimension) {
    final result = <String, List<Map<String, dynamic>>>{};
    for (final i in incidents) {
      String key;
      switch (dimension) {
        case 'plant':
          key = i['plant']?.toString() ?? 'Unknown';
          break;
        case 'category':
          key = i['wsaCategory']?.toString() ?? 'Other';
          break;
        case 'severity':
          key = i['severity']?.toString().toUpperCase() ?? 'MEDIUM';
          break;
        case 'month':
          final d = DateTime.tryParse(i['date']?.toString() ?? '');
          key = d != null ? '${d.year}-${_pad(d.month)}' : 'Unknown';
          break;
        case 'status':
          key = i['status']?.toString().toUpperCase() ?? 'OPEN';
          break;
        default:
          key = 'All';
      }
      result.putIfAbsent(key, () => []);
      result[key]!.add(i);
    }
    return result;
  }

  // ═══════════════════════════════════════════════════════════════
  //  DATE RANGE HELPERS
  // ═══════════════════════════════════════════════════════════════

  static List<Map<String, dynamic>> filterByDateRange(
      List<Map<String, dynamic>> incidents, String range) {
    final now = DateTime.now();
    DateTime? start;
    switch (range) {
      case '7d':
        start = now.subtract(const Duration(days: 7));
        break;
      case '30d':
        start = now.subtract(const Duration(days: 30));
        break;
      case '90d':
        start = now.subtract(const Duration(days: 90));
        break;
      case '1yr':
        start = now.subtract(const Duration(days: 365));
        break;
      case 'all':
      default:
        start = null;
    }
    if (start == null) return incidents;
    return incidents.where((i) {
      final d = DateTime.tryParse(i['date']?.toString() ?? '');
      return d != null && d.isAfter(start!);
    }).toList();
  }

  static String bestBucketSize(String range) {
    switch (range) {
      case '7d':
        return 'day';
      case '30d':
        return 'day';
      case '90d':
        return 'week';
      case '1yr':
        return 'month';
      case 'all':
      default:
        return 'month';
    }
  }
}

