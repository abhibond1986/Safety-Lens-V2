// lib/services/admin_alerts.dart
// SAIL Safety Lens — Alert rules storage
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
// Note: this service only STORES the rules. Actual delivery
// requires an SMTP / SMS gateway wired in Apps Script — that comes
// later. For now, the UI surfaces "what would have fired".

import 'dart:convert';
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
}
