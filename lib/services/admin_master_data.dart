// lib/services/admin_master_data.dart
// SAIL Safety Lens — Master data + Custom list editor storage
//
// Constants for SAIL plants, default WSA causes, default departments.
// Plus storage hooks for user-edited custom lists.

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'sync_service.dart';

class AdminMasterData {
  // ── SAIL PLANTS (14 units + Others) ──────────────────────────────
  static const List<Map<String, String>> sailPlants = [
    {'code': 'BSP',        'name': 'Bhilai Steel Plant',          'state': 'Chhattisgarh', 'kind': 'Plant'},
    {'code': 'DSP',        'name': 'Durgapur Steel Plant',        'state': 'West Bengal',  'kind': 'Plant'},
    {'code': 'RSP',        'name': 'Rourkela Steel Plant',        'state': 'Odisha',       'kind': 'Plant'},
    {'code': 'BSL',        'name': 'Bokaro Steel Plant',          'state': 'Jharkhand',    'kind': 'Plant'},
    {'code': 'ISP',        'name': 'IISCO Steel Plant Burnpur',   'state': 'West Bengal',  'kind': 'Plant'},
    {'code': 'ASP',        'name': 'Alloy Steels Plant',          'state': 'West Bengal',  'kind': 'Plant'},
    {'code': 'SSP',        'name': 'Salem Steel Plant',           'state': 'Tamil Nadu',   'kind': 'Plant'},
    {'code': 'CFP',        'name': 'Chandrapur Ferro Alloys',     'state': 'Maharashtra',  'kind': 'Plant'},
    {'code': 'CMO',        'name': 'Central Marketing Org',       'state': 'Delhi',        'kind': 'Marketing'},
    {'code': 'JGOM',       'name': 'Jharkhand Group of Mines',    'state': 'Jharkhand',    'kind': 'Mines'},
    {'code': 'OGOM',       'name': 'Odisha Group of Mines',       'state': 'Odisha',       'kind': 'Mines'},
    {'code': 'BSP_MINES',  'name': 'BSP Mines',                   'state': 'Chhattisgarh', 'kind': 'Mines'},
    {'code': 'COLLIERIES', 'name': 'Collieries Division',         'state': 'Jharkhand/WB', 'kind': 'Mines'},
    {'code': 'SRU',        'name': 'SRU Kulti',                   'state': 'West Bengal',  'kind': 'Refractory'},
    {'code': 'CORP',       'name': 'Corporate — Ranchi',          'state': 'Jharkhand',    'kind': 'HQ'},
    {'code': 'OTHER',      'name': 'Others',                      'state': '—',            'kind': 'Other'},
  ];

  static String stateForPlant(String plantNameOrCode) {
    final q = plantNameOrCode.trim().toUpperCase();
    for (final p in sailPlants) {
      if (q == p['code']!.toUpperCase() ||
          q == p['name']!.toUpperCase() ||
          p['name']!.toUpperCase().contains(q)) {
        return p['state']!;
      }
    }
    return '—';
  }

  // ── DEFAULT WSA 13 CAUSES ────────────────────────────────────────
  static const List<String> defaultWsaCauses = [
    '1. Failure to follow procedure',
    '2. Lack of hazard awareness',
    '3. Improper PPE use',
    '4. Unsafe body positioning',
    '5. Equipment failure',
    '6. Communication failure',
    '7. Human error',
    '8. Poor housekeeping',
    '9. Lack of supervision',
    '10. Fatigue / time pressure',
    '11. Unauthorized operation',
    '12. Inadequate isolation (LOTO/PTW)',
    '13. Environmental conditions',
  ];

  // ── DEFAULT DEPARTMENTS ──────────────────────────────────────────
  static const List<String> defaultDepartments = [
    'Blast Furnace', 'Steel Melting Shop', 'Coke Ovens',
    'Sinter Plant', 'Rolling Mill', 'Hot Strip Mill',
    'Cold Rolling Mill', 'Plate Mill', 'Bar & Rod Mill',
    'Wire Rod Mill', 'Power Plant', 'Oxygen Plant',
    'Refractory', 'Mechanical Maintenance',
    'Electrical Maintenance', 'Instrumentation',
    'Civil', 'Stores', 'Transport', 'Mines',
    'Quality Assurance', 'Safety', 'Fire Brigade',
    'Medical', 'Security', 'Personnel', 'Finance',
    'IT', 'Training', 'Environment',
  ];

  // ── DEFAULT SEVERITIES ───────────────────────────────────────────
  static const List<String> defaultSeverities = ['LOW', 'MEDIUM', 'HIGH', 'CRITICAL'];

  // ── DEFAULT STATUSES ─────────────────────────────────────────────
  static const List<String> defaultStatuses = [
    'OPEN', 'INVESTIGATING', 'ACTION TAKEN', 'VERIFIED', 'CLOSED',
  ];

  // ── DEFAULT OBSERVATION TYPES ────────────────────────────────────
  static const List<String> defaultObservationTypes = [
    'Unsafe Act', 'Unsafe Condition', 'Near Miss', 'First Aid Case',
  ];

  // ── STORAGE KEYS for custom (user-edited) lists ──────────────────
  static const String _kPlants     = 'admin_master_plants';
  static const String _kDepts      = 'admin_master_departments';
  static const String _kWsa        = 'admin_master_wsa_causes';
  static const String _kSeverities = 'admin_master_severities';
  static const String _kStatuses   = 'admin_master_statuses';
  static const String _kObsTypes   = 'admin_master_obs_types';

  // ── READ helpers — fall back to defaults if not customised ───────
  static Future<List<Map<String, String>>> getPlants() async {
    final prefs = await SharedPreferences.getInstance();
    final raw   = prefs.getString(_kPlants);
    if (raw == null) {
      return sailPlants.map((p) => Map<String, String>.from(p)).toList();
    }
    try {
      final l = (jsonDecode(raw) as List)
          .map((e) => Map<String, String>.from(
              (e as Map).map((k, v) => MapEntry(k.toString(), v.toString()))))
          .toList();
      return l;
    } catch (_) {
      return sailPlants.map((p) => Map<String, String>.from(p)).toList();
    }
  }

  static Future<List<String>> _getList(String key, List<String> def) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null) return List<String>.from(def);
    try {
      final l = (jsonDecode(raw) as List).map((e) => e.toString()).toList();
      return l;
    } catch (_) {
      return List<String>.from(def);
    }
  }

  static Future<List<String>> getDepartments() => _getList(_kDepts, defaultDepartments);
  static Future<List<String>> getWsaCauses()   => _getList(_kWsa, defaultWsaCauses);
  static Future<List<String>> getSeverities()  => _getList(_kSeverities, defaultSeverities);
  static Future<List<String>> getStatuses()    => _getList(_kStatuses, defaultStatuses);
  static Future<List<String>> getObsTypes()    => _getList(_kObsTypes, defaultObservationTypes);

  // ── SAVE helpers (local + push to backend) ──────────────────────
  static Future<void> savePlants(List<Map<String, String>> v, {bool syncToBackend = true}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPlants, jsonEncode(v));
    if (syncToBackend) {
      // Fire-and-forget push to backend
      SyncService.pushMasterData(plants: v).catchError((_) => false);
    }
  }

  static Future<void> _saveList(String key, List<String> v, {bool syncToBackend = true}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, jsonEncode(v));
    if (syncToBackend) {
      // Push the specific list to backend
      switch (key) {
        case _kDepts:      SyncService.pushMasterData(departments: v).catchError((_) => false); break;
        case _kWsa:        SyncService.pushMasterData(wsaCauses: v).catchError((_) => false); break;
        case _kSeverities: SyncService.pushMasterData(severities: v).catchError((_) => false); break;
        case _kStatuses:   SyncService.pushMasterData(statuses: v).catchError((_) => false); break;
        case _kObsTypes:   SyncService.pushMasterData(obsTypes: v).catchError((_) => false); break;
      }
    }
  }

  static Future<void> saveDepartments(List<String> v, {bool syncToBackend = true}) =>
      _saveList(_kDepts, v, syncToBackend: syncToBackend);
  static Future<void> saveWsaCauses(List<String> v, {bool syncToBackend = true}) =>
      _saveList(_kWsa, v, syncToBackend: syncToBackend);
  static Future<void> saveSeverities(List<String> v, {bool syncToBackend = true}) =>
      _saveList(_kSeverities, v, syncToBackend: syncToBackend);
  static Future<void> saveStatuses(List<String> v, {bool syncToBackend = true}) =>
      _saveList(_kStatuses, v, syncToBackend: syncToBackend);
  static Future<void> saveObsTypes(List<String> v, {bool syncToBackend = true}) =>
      _saveList(_kObsTypes, v, syncToBackend: syncToBackend);

  // ── PULL from backend & update local storage ───────────────────
  /// Call on app startup to fetch latest master data from server.
  /// Returns true if data was updated from server.
  static Future<bool> syncFromBackend() async {
    try {
      final remote = await SyncService.pullMasterData();
      if (remote == null || remote.isEmpty) return false;

      bool updated = false;

      if (remote['plants'] is List && (remote['plants'] as List).isNotEmpty) {
        final plants = (remote['plants'] as List)
            .map((e) => Map<String, String>.from(
                (e as Map).map((k, v) => MapEntry(k.toString(), v.toString()))))
            .toList();
        await savePlants(plants, syncToBackend: false);
        updated = true;
      }
      if (remote['departments'] is List && (remote['departments'] as List).isNotEmpty) {
        final depts = (remote['departments'] as List).map((e) => e.toString()).toList();
        await saveDepartments(depts, syncToBackend: false);
        updated = true;
      }
      if (remote['wsaCauses'] is List && (remote['wsaCauses'] as List).isNotEmpty) {
        final wsa = (remote['wsaCauses'] as List).map((e) => e.toString()).toList();
        await saveWsaCauses(wsa, syncToBackend: false);
        updated = true;
      }
      if (remote['severities'] is List && (remote['severities'] as List).isNotEmpty) {
        final sev = (remote['severities'] as List).map((e) => e.toString()).toList();
        await saveSeverities(sev, syncToBackend: false);
        updated = true;
      }
      if (remote['statuses'] is List && (remote['statuses'] as List).isNotEmpty) {
        final st = (remote['statuses'] as List).map((e) => e.toString()).toList();
        await saveStatuses(st, syncToBackend: false);
        updated = true;
      }
      if (remote['obsTypes'] is List && (remote['obsTypes'] as List).isNotEmpty) {
        final obs = (remote['obsTypes'] as List).map((e) => e.toString()).toList();
        await saveObsTypes(obs, syncToBackend: false);
        updated = true;
      }

      // ★ v25: Sync API keys from backend — ensures all devices have keys
      if (remote['geminiApiKey'] is String && (remote['geminiApiKey'] as String).length > 10) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('gemini_vision_api_key', remote['geminiApiKey'] as String);
        updated = true;
      }
      if (remote['groqApiKey'] is String && (remote['groqApiKey'] as String).length > 10) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('groq_api_key', remote['groqApiKey'] as String);
        updated = true;
      }
      if (remote['geminiModel'] is String && (remote['geminiModel'] as String).isNotEmpty) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('gemini_vision_model', remote['geminiModel'] as String);
        updated = true;
      }

      return updated;
    } catch (_) {
      return false;
    }
  }

  // ── SEVERITY SCORING (admin-configurable) ─────────────────────────
  static const String _kSeverityScores = 'admin_severity_scores';

  static const Map<String, int> defaultSeverityScores = {
    'CRITICAL': 25,
    'HIGH': 15,
    'MEDIUM': 10,
    'LOW': 5,
  };

  static Future<Map<String, int>> getSeverityScores() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kSeverityScores);
    if (raw == null) return Map<String, int>.from(defaultSeverityScores);
    try {
      final map = (jsonDecode(raw) as Map)
          .map((k, v) => MapEntry(k.toString(), (v is int) ? v : int.tryParse(v.toString()) ?? 0));
      return map;
    } catch (_) {
      return Map<String, int>.from(defaultSeverityScores);
    }
  }

  static Future<void> saveSeverityScores(Map<String, int> scores) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kSeverityScores, jsonEncode(scores));
  }

  // ── RESET to defaults ────────────────────────────────────────────
  static Future<void> resetAllToDefaults() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kPlants);
    await prefs.remove(_kDepts);
    await prefs.remove(_kWsa);
    await prefs.remove(_kSeverities);
    await prefs.remove(_kStatuses);
    await prefs.remove(_kObsTypes);
    await prefs.remove(_kSeverityScores);
  }
}
