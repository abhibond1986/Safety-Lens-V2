import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'local_db.dart';

/// SAIL Safety Lens — Google Sheets Sync Service
///
/// HONEST DISCLOSURE:
/// This is NOT real-time sync. It's a periodic push/pull to a Google Sheet via
/// Google Apps Script Web App. Pros: completely free, admin can open the sheet
/// in browser to see all data. Cons: ~60 req/min rate limit, eventual consistency,
/// not for high-concurrency production.
///
/// SETUP STEPS (for the admin):
/// 1. Create a Google Sheet
/// 2. Extensions → Apps Script → paste backend/google_apps_script.gs
/// 3. Deploy → New deployment → Web app → Anyone access → Deploy
/// 4. Copy the Web App URL
/// 5. Paste it into _backendUrl below (or set via app settings)
class SyncService {
  // ============================================================
  // PASTE YOUR GOOGLE APPS SCRIPT WEB APP URL HERE:
  // It looks like: https://script.google.com/macros/s/AKfycby.../exec
  // ============================================================
  static const String _defaultBackendUrl = 'YOUR_APPS_SCRIPT_URL_HERE';

  static const String _kBackendUrl = 'sync_backend_url';
  static const String _kPendingQueue = 'sync_pending_queue';
  static const String _kLastSyncTime = 'sync_last_time';

  static SharedPreferences? _prefs;

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  static Future<String> getBackendUrl() async {
    _prefs ??= await SharedPreferences.getInstance();
    final saved = _prefs!.getString(_kBackendUrl);
    if (saved != null && saved.isNotEmpty) return saved;
    return _defaultBackendUrl;
  }

  static Future<void> setBackendUrl(String url) async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setString(_kBackendUrl, url.trim());
  }

  static Future<bool> get isConfigured async {
    final url = await getBackendUrl();
    return url.isNotEmpty && url != 'YOUR_APPS_SCRIPT_URL_HERE' && url.startsWith('https://');
  }

  // ============================================================
  // HEALTH CHECK
  // ============================================================
  static Future<Map<String, dynamic>> ping() async {
    final url = await getBackendUrl();
    if (!await isConfigured) {
      return {'ok': false, 'error': 'Backend URL not configured'};
    }
    try {
      final response = await http.get(
        Uri.parse('$url?action=health'),
      ).timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      return {'ok': false, 'error': 'HTTP ${response.statusCode}'};
    } catch (e) {
      return {'ok': false, 'error': e.toString()};
    }
  }

  // ============================================================
  // INCIDENT SYNC
  // ============================================================
  /// Push a single incident to the backend.
  /// If offline/failed, adds to pending queue for later retry.
  static Future<bool> pushIncident(Map<String, dynamic> incident) async {
    if (!await isConfigured) {
      await _addToPendingQueue('addIncident', incident);
      return false;
    }

    try {
      final url = await getBackendUrl();
      final params = {
        'action': 'addIncident',
        ...incident,
      };
      // Convert all values to strings for URL safety
      final body = <String, dynamic>{};
      params.forEach((k, v) {
        if (v == null) {
          body[k] = '';
        } else {
          body[k] = v.toString();
        }
      });

      final response = await http.post(
        Uri.parse(url),
        body: jsonEncode(body),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['ok'] == true) {
          await _markSyncTime();
          return true;
        }
      }
      // On failure, queue for retry
      await _addToPendingQueue('addIncident', incident);
      return false;
    } catch (e) {
      await _addToPendingQueue('addIncident', incident);
      return false;
    }
  }

  /// Fetch all incidents from backend (admin/sync use case)
  static Future<List<Map<String, dynamic>>> fetchIncidents() async {
    if (!await isConfigured) return [];
    try {
      final url = await getBackendUrl();
      final response = await http.get(
        Uri.parse('$url?action=listIncidents'),
      ).timeout(const Duration(seconds: 30));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        if (data['ok'] == true && data['items'] is List) {
          return (data['items'] as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
        }
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  // ============================================================
  // KNOWLEDGE BASE SYNC (admin uploads PDF docs that all users can search)
  // ============================================================
  static Future<bool> pushKnowledgeDoc(Map<String, dynamic> doc) async {
    if (!await isConfigured) return false;
    try {
      final url = await getBackendUrl();
      final body = <String, dynamic>{'action': 'addKnowledge'};
      doc.forEach((k, v) => body[k] = (v ?? '').toString());

      final response = await http.post(
        Uri.parse(url),
        body: jsonEncode(body),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 30));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }


  static Future<void> syncKnowledgeFromCloud() async {
    final docs = await fetchKnowledgeDocs();
    if (docs.isEmpty) return;
    for (final doc in docs) {
      await LocalDB.addKnowledgeDoc(
        title: doc['title']?.toString() ?? 'Untitled',
        content: doc['content']?.toString() ?? '',
        source: doc['source']?.toString() ?? 'cloud',
      );
    }
  }

  static Future<List<Map<String, dynamic>>> fetchKnowledgeDocs() async {
    if (!await isConfigured) return [];
    try {
      final url = await getBackendUrl();
      final response = await http.get(
        Uri.parse('$url?action=listKnowledge'),
      ).timeout(const Duration(seconds: 30));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        if (data['ok'] == true && data['items'] is List) {
          return (data['items'] as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
        }
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  // ============================================================
  // PENDING QUEUE (for offline writes)
  // ============================================================
  static Future<void> _addToPendingQueue(String action, Map<String, dynamic> payload) async {
    _prefs ??= await SharedPreferences.getInstance();
    final raw = _prefs!.getString(_kPendingQueue);
    final queue = raw != null ? (jsonDecode(raw) as List) : [];
    queue.add({'action': action, 'payload': payload, 'queuedAt': DateTime.now().toIso8601String()});
    await _prefs!.setString(_kPendingQueue, jsonEncode(queue));
  }

  /// Try to drain the queue. Returns number of items synced.
  static Future<int> drainPendingQueue() async {
    _prefs ??= await SharedPreferences.getInstance();
    final raw = _prefs!.getString(_kPendingQueue);
    if (raw == null) return 0;
    final queue = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    if (queue.isEmpty) return 0;
    if (!await isConfigured) return 0;

    final remaining = <Map<String, dynamic>>[];
    int synced = 0;
    for (final item in queue) {
      final action = item['action']?.toString();
      final payload = Map<String, dynamic>.from(item['payload'] ?? {});
      bool ok = false;
      if (action == 'addIncident') {
        ok = await pushIncident(payload);
      }
      if (ok) {
        synced++;
      } else {
        remaining.add(item);
      }
    }
    await _prefs!.setString(_kPendingQueue, jsonEncode(remaining));
    return synced;
  }

  static Future<int> pendingQueueSize() async {
    _prefs ??= await SharedPreferences.getInstance();
    final raw = _prefs!.getString(_kPendingQueue);
    if (raw == null) return 0;
    return (jsonDecode(raw) as List).length;
  }

  // ============================================================
  // STATUS
  // ============================================================
  static Future<DateTime?> getLastSyncTime() async {
    _prefs ??= await SharedPreferences.getInstance();
    final raw = _prefs!.getString(_kLastSyncTime);
    if (raw == null) return null;
    return DateTime.tryParse(raw);
  }

  static Future<void> _markSyncTime() async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setString(_kLastSyncTime, DateTime.now().toIso8601String());
  }

  // ============================================================
  // FULL SYNC (push pending + pull latest)
  // ============================================================
  static Future<Map<String, dynamic>> fullSync() async {
    if (!await isConfigured) {
      return {'ok': false, 'error': 'Backend URL not configured. Open Settings to add Apps Script URL.'};
    }
    final pushed = await drainPendingQueue();
    final pulled = await fetchIncidents();
    // Merge fetched incidents into local DB (preserve local-only ones)
    if (pulled.isNotEmpty) {
      final local = await LocalDB.getIncidents();
      final localIds = local.map((i) => i['id']?.toString()).toSet();
      for (final remote in pulled) {
        if (!localIds.contains(remote['id']?.toString())) {
          // Add remote-only items to local
          await LocalDB.saveIncident(remote);
        }
      }
    }
    await _markSyncTime();
    return {
      'ok': true,
      'pushed': pushed,
      'pulled': pulled.length,
      'syncTime': DateTime.now().toIso8601String(),
    };
  }
}
