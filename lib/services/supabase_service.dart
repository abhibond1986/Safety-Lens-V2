// lib/services/supabase_service.dart
// Phase 1 of the Supabase migration (see SUPABASE_MIGRATION_GUIDE.md).
//
// Provides the incidents data path (fetch / upsert / delete) and image upload
// to Supabase Storage. Mirrors the shape of SyncService's incident methods so
// callers can switch backends via SupabaseConfig.enabled with no other change.
//
// Offline-first is preserved: these methods are the REMOTE layer only. The
// local SharedPreferences cache (LocalDB) is untouched — callers still read
// local first and sync through here when online.

import 'dart:convert';
import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_config.dart';

class SupabaseService {
  static bool _initialized = false;

  /// Initialize Supabase once at app startup. No-op if disabled/unconfigured.
  static Future<void> init() async {
    if (!SupabaseConfig.enabled || _initialized) return;
    await Supabase.initialize(
      url: SupabaseConfig.url,
      anonKey: SupabaseConfig.anonKey,
    );
    _initialized = true;
  }

  static bool get isReady => SupabaseConfig.enabled && _initialized;

  static SupabaseClient get _db => Supabase.instance.client;

  // ══════════════════════════════════════════════════════════════════════════
  //  FIELD MAPPING — app (camelCase) ↔ DB (snake_case)
  // ══════════════════════════════════════════════════════════════════════════
  // Only the keys we persist are mapped; unknown keys are dropped on write.
  static const Map<String, String> _appToDb = {
    'id': 'id',
    'title': 'title',
    'type': 'type',
    'plant': 'plant',
    'dept': 'dept',
    'location': 'location',
    'detectedSection': 'detected_section',
    'severity': 'severity',
    'status': 'status',
    'wsaCategory': 'wsa_category',
    'obsType': 'obs_type',
    'summary': 'summary',
    'desc': 'description',
    'immediateAction': 'immediate_action',
    'rootCause': 'root_cause',
    'correctiveAction': 'corrective_action',
    'hazards': 'hazards',
    'riskScore': 'risk_score',
    'confidence': 'confidence',
    'people': 'people',
    'reportedBy': 'reported_by',
    'reportedByPno': 'reported_by_pno',
    'imageUrl': 'image_url',
    'imageHash': 'image_hash',
    'latitude': 'latitude',
    'longitude': 'longitude',
    'locationAccuracy': 'location_accuracy',
    'locationAddress': 'location_address',
    'locationTimestamp': 'location_timestamp',
    'auditStatus': 'audit_status',
    'auditScore': 'audit_score',
    'date': 'date',
  };
  static final Map<String, String> _dbToApp = {
    for (final e in _appToDb.entries) e.value: e.key,
  };

  /// Convert an app incident map to a DB row (snake_case, JSON-encoded lists).
  static Map<String, dynamic> _toRow(Map<String, dynamic> inc) {
    final row = <String, dynamic>{};
    _appToDb.forEach((appKey, dbCol) {
      if (!inc.containsKey(appKey)) return;
      var v = inc[appKey];
      if (appKey == 'hazards') {
        // Store as jsonb — pass a List/Map through; parse if it's a JSON string.
        if (v is String) { try { v = jsonDecode(v); } catch (_) {} }
      }
      if (appKey == 'people' || appKey == 'riskScore' ||
          appKey == 'confidence' || appKey == 'auditScore') {
        v = v == null ? null : int.tryParse(v.toString());
      }
      row[dbCol] = v;
    });
    return row;
  }

  /// Convert a DB row back to the app's incident map (camelCase).
  static Map<String, dynamic> _fromRow(Map<String, dynamic> row) {
    final inc = <String, dynamic>{};
    row.forEach((dbCol, v) {
      final appKey = _dbToApp[dbCol];
      if (appKey == null) return;
      inc[appKey] = v;
    });
    // hazards comes back as a List/Map (jsonb) — leave as-is; callers handle both.
    return inc;
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  INCIDENTS
  // ══════════════════════════════════════════════════════════════════════════

  /// Fetch all incidents (newest first). Returns [] on any error.
  static Future<List<Map<String, dynamic>>> fetchIncidents() async {
    if (!isReady) return [];
    try {
      final rows = await _db
          .from('incidents')
          .select()
          .order('date', ascending: false);
      return (rows as List)
          .map((r) => _fromRow(Map<String, dynamic>.from(r as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Insert or update one incident (keyed by id). Returns true on success.
  static Future<bool> upsertIncident(Map<String, dynamic> incident) async {
    if (!isReady) return false;
    try {
      final row = _toRow(incident);
      if ((row['id']?.toString() ?? '').isEmpty) return false;
      await _db.from('incidents').upsert(row, onConflict: 'id');
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Hard-delete an incident by id. Returns true on success.
  static Future<bool> deleteIncident(String id) async {
    if (!isReady || id.isEmpty) return false;
    try {
      await _db.from('incidents').delete().eq('id', id);
      return true;
    } catch (_) {
      return false;
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  IMAGE STORAGE — upload once, reference by public URL everywhere
  // ══════════════════════════════════════════════════════════════════════════

  /// Upload incident evidence bytes to the Storage bucket and return the public
  /// URL (to store in incident['imageUrl']). Returns null on failure.
  static Future<String?> uploadIncidentImage(
      String incidentId, Uint8List bytes) async {
    if (!isReady || incidentId.isEmpty || bytes.isEmpty) return null;
    try {
      final path = 'img_$incidentId.jpg';
      await _db.storage.from(SupabaseConfig.imageBucket).uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(
              contentType: 'image/jpeg',
              upsert: true, // overwrite if the same incident is re-saved
            ),
          );
      return _db.storage.from(SupabaseConfig.imageBucket).getPublicUrl(path);
    } catch (_) {
      return null;
    }
  }

  /// Download image bytes for an incident that has an imageUrl. Returns null
  /// if there's no URL or the fetch fails. (Works on web AND mobile.)
  static Future<Uint8List?> downloadIncidentImage(String incidentId) async {
    if (!isReady || incidentId.isEmpty) return null;
    try {
      final path = 'img_$incidentId.jpg';
      return await _db.storage
          .from(SupabaseConfig.imageBucket)
          .download(path);
    } catch (_) {
      return null;
    }
  }
}
