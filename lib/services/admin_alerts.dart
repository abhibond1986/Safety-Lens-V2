// lib/services/admin_alerts.dart
// SAIL Safety Lens — Alert rules storage & delivery (v25)
//
// Stores notification rules locally. Rules describe WHEN to notify
// (trigger condition) and WHO to notify (subscribers).
//
// Rule schema:
//   {
//     id        : 'rule_1718012345',
//     name      : 'All Critical → Safety Head',
//     trigger   : 'critical_incident' | 'threshold_daily' | 'daily_digest' | 'high_open_7d',
//     threshold : 3,                              // for threshold_daily
//     plant     : 'BSP' | '' (any),
//     recipients: ['email@sail.in','9876543210'],
//     channel   : 'email' | 'sms' | 'both',
//     enabled   : true,
//     createdAt : ISO date,
//     createdBy : username,
//   }
//
// v25: Now actually delivers alerts via Apps Script backend:
//   - Email via MailApp (free, built-in)
//   - Push notifications via FCM (free, unlimited)

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AdminAlerts {
  static const String _kKey = 'admin_alert_rules';

  static const String trigCriticalIncident = 'critical_incident';
  static const String trigThresholdDaily   = 'threshold_daily';
  static const String trigDailyDigest      = 'daily_digest';
  static const String trigHighOpen7d       = 'high_open_7d';

  static const Map<String, String> triggerLabels = {
    trigCriticalIncident: 'Every CRITICAL incident',
    trigThresholdDaily  : 'Daily count above threshold',
    trigDailyDigest     : 'Daily digest (8 AM)',
    trigHighOpen7d      : 'HIGH/CRITICAL open >7 days',
  };

  static const Map<String, String> triggerDescriptions = {
    trigCriticalIncident: 'Fires the moment a CRITICAL is logged',
    trigThresholdDaily  : 'Fires once if N+ incidents in a day',
    trigDailyDigest     : 'Morning summary every day at 8 AM',
    trigHighOpen7d      : 'Daily check for stale HIGH/CRITICAL',
  };

  // ── READ ────────────────────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> getRules() async {
    final prefs = await SharedPreferences.getInstance();
    final raw   = prefs.getString(_kKey);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } catch (_) {
      return [];
    }
  }

  // ── ADD / UPDATE ────────────────────────────────────────────────
  static Future<void> save(Map<String, dynamic> rule) async {
    final list = await getRules();
    final id = rule['id']?.toString();
    final idx = id == null ? -1
        : list.indexWhere((r) => r['id']?.toString() == id);

    if (idx >= 0) {
      list[idx] = Map<String, dynamic>.from(rule);
    } else {
      list.insert(0, {
        ...rule,
        'id'       : rule['id'] ?? 'rule_${DateTime.now().millisecondsSinceEpoch}',
        'createdAt': rule['createdAt'] ?? DateTime.now().toIso8601String(),
      });
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kKey, jsonEncode(list));
  }

  // ── DELETE ──────────────────────────────────────────────────────
  static Future<void> delete(String id) async {
    final list = await getRules();
    list.removeWhere((r) => r['id']?.toString() == id);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kKey, jsonEncode(list));
  }

  // ── TOGGLE ──────────────────────────────────────────────────────
  static Future<void> toggle(String id, bool enabled) async {
    final list = await getRules();
    final idx  = list.indexWhere((r) => r['id']?.toString() == id);
    if (idx < 0) return;
    list[idx]['enabled'] = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kKey, jsonEncode(list));
  }

  // ── CLEAR ALL (for restore) ─────────────────────────────────────
  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kKey);
  }

  // ── EVALUATE — figure out which rules WOULD fire right now ──────
  // Pure function over current state — does not actually send.
  static List<Map<String, dynamic>> evaluate(
      List<Map<String, dynamic>> rules,
      List<Map<String, dynamic>> incidents) {
    final firing = <Map<String, dynamic>>[];
    final today = DateTime.now();
    final todayKey = '${today.year}-'
        '${today.month.toString().padLeft(2, '0')}-'
        '${today.day.toString().padLeft(2, '0')}';

    for (final r in rules) {
      if (r['enabled'] != true) continue;
      final trigger = r['trigger']?.toString();
      final plant   = r['plant']?.toString() ?? '';

      bool incPlantMatch(Map<String, dynamic> i) =>
          plant.isEmpty || (i['plant']?.toString() == plant);

      switch (trigger) {
        case trigCriticalIncident:
          final criticals = incidents.where((i) =>
              (i['severity']?.toString().toUpperCase() == 'CRITICAL') &&
              incPlantMatch(i)).toList();
          if (criticals.isNotEmpty) {
            firing.add({
              ...r, 'reason': '${criticals.length} CRITICAL incident(s)',
            });
          }
          break;
        case trigThresholdDaily:
          final threshold = (r['threshold'] is int)
              ? r['threshold'] as int
              : int.tryParse('${r['threshold']}') ?? 3;
          final today = incidents.where((i) =>
              (i['date']?.toString() ?? '').startsWith(todayKey) &&
              incPlantMatch(i)).length;
          if (today >= threshold) {
            firing.add({...r, 'reason': '$today incidents today (≥ $threshold)'});
          }
          break;
        case trigHighOpen7d:
          final cutoff = today.subtract(const Duration(days: 7));
          final stale = incidents.where((i) {
            final sev = i['severity']?.toString().toUpperCase() ?? '';
            final st  = i['status']?.toString().toUpperCase() ?? '';
            if (!(sev == 'CRITICAL' || sev == 'HIGH')) return false;
            if (st == 'CLOSED') return false;
            if (!incPlantMatch(i)) return false;
            final d = DateTime.tryParse(i['date']?.toString() ?? '');
            return d != null && d.isBefore(cutoff);
          }).length;
          if (stale > 0) {
            firing.add({...r, 'reason': '$stale HIGH/CRITICAL open >7d'});
          }
          break;
        case trigDailyDigest:
          firing.add({...r, 'reason': 'Daily digest (would send at 8 AM)'});
          break;
      }
    }
    return firing;
  }

  // ── DELIVER — actually send alerts via Apps Script backend ────
  // Call this after evaluate() returns firing rules.
  // Returns a list of delivery results.
  static Future<List<Map<String, dynamic>>> deliver(
    List<Map<String, dynamic>> firingRules,
    List<Map<String, dynamic>> incidents,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final baseUrl = prefs.getString('apps_script_url') ?? '';
    if (baseUrl.isEmpty) {
      return [{'ok': false, 'error': 'Apps Script URL not configured'}];
    }

    final results = <Map<String, dynamic>>[];

    for (final rule in firingRules) {
      try {
        // Build incident summary (send only key fields, not full data)
        final matchingIncidents = incidents
            .where((i) {
              final plant = rule['plant']?.toString() ?? '';
              return plant.isEmpty || i['plant']?.toString() == plant;
            })
            .take(10)
            .map((i) => {
              return {
                'date': i['date'] ?? '',
                'title': i['title'] ?? i['desc'] ?? '',
                'severity': i['severity'] ?? '',
                'plant': i['plant'] ?? '',
                'status': i['status'] ?? '',
              };
            })
            .toList();

        final response = await http.post(
          Uri.parse(baseUrl),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'action': 'fireAlert',
            'rule': rule,
            'reason': rule['reason'] ?? '',
            'incidents': matchingIncidents,
          }),
        ).timeout(const Duration(seconds: 30));

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          results.add(data is Map<String, dynamic> ? data : {'ok': true});
        } else {
          results.add({'ok': false, 'error': 'HTTP ${response.statusCode}'});
        }
      } catch (e) {
        results.add({'ok': false, 'error': e.toString()});
      }
    }

    return results;
  }

  // ── SYNC RULES to backend (for daily digest triggers) ────────
  // Pushes rules to Apps Script so time-based triggers can evaluate them
  static Future<bool> syncToBackend() async {
    final prefs = await SharedPreferences.getInstance();
    final baseUrl = prefs.getString('apps_script_url') ?? '';
    if (baseUrl.isEmpty) return false;

    final rules = await getRules();
    // Only sync digest/scheduled rules (not instant ones which fire from app)
    final scheduledRules = rules.where((r) =>
        r['trigger'] == trigDailyDigest ||
        r['trigger'] == trigHighOpen7d ||
        r['trigger'] == trigThresholdDaily).toList();

    try {
      final response = await http.post(
        Uri.parse(baseUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'action': 'syncAlertRules',
          'rules': scheduledRules,
        }),
      ).timeout(const Duration(seconds: 15));

      return response.statusCode == 200;
    } catch (e) {
      print('[AdminAlerts] Sync failed: $e');
      return false;
    }
  }
}
