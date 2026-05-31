import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'local_db.dart';

class SyncService {
  static const String _defaultBackendUrl = 'https://script.google.com/macros/s/AKfycbyvq6MSAWOL_DcMtBHj_txBW8dBerJGbKLsYwNeb75IYX2TAkBaBq7_ZEELcOLcJ0cdAw/exec';

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
    return url.isNotEmpty && url.startsWith('https://script.google.com/');
  }

  static Future<Map<String, dynamic>> ping() async {
    final url = await getBackendUrl();
    if (!await isConfigured) return {'ok': false, 'error': 'Backend URL not configured'};
    try {
      final response = await http.get(Uri.parse('$url?action=health')).timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) return jsonDecode(response.body) as Map<String, dynamic>;
      return {'ok': false, 'error': 'HTTP ${response.statusCode}'};
    } catch (e) {
      return {'ok': false, 'error': e.toString()};
    }
  }

  /// Push incident to Google Sheets backend.
  /// CRITICAL: Uses text/plain Content-Type to avoid CORS preflight issue.
  /// Apps Script doesn't handle OPTIONS requests, so we MUST avoid triggering preflight.
  static Future<bool> pushIncident(Map<String, dynamic> incident) async {
    if (!await isConfigured) {
      await _addToPendingQueue('addIncident', incident);
      return false;
    }

    try {
      final url = await getBackendUrl();
      final body = <String, dynamic>{'action': 'addIncident'};
      incident.forEach((k, v) {
        if (v == null) {
          body[k] = '';
        } else if (v is List || v is Map) {
          body[k] = jsonEncode(v);
        } else {
          body[k] = v.toString();
        }
      });

      // CRITICAL: text/plain bypasses CORS preflight.
      // Google Apps Script reads body from e.postData.contents regardless of type.
      final response = await http.post(
        Uri.parse(url),
        body: jsonEncode(body),
        headers: {'Content-Type': 'text/plain;charset=utf-8'},
      ).timeout(const Duration(seconds: 30));

      print('Sync response: ${response.statusCode} - ${response.body}');

      if (response.statusCode == 200) {
        try {
          final data = jsonDecode(response.body);
          if (data['ok'] == true || data['added'] == true) {
            await _markSyncTime();
            return true;
          }
        } catch (e) {
          print('JSON parse error: $e');
        }
      }
      await _addToPendingQueue('addIncident', incident);
      return false;
    } catch (e) {
      print('Sync exception: $e');
      await _addToPendingQueue('addIncident', incident);
      return false;
    }
  }

  static Future<List<Map<String, dynamic>>> fetchIncidents() async {
    if (!await isConfigured) return [];
    try {
      final url = await getBackendUrl();
      final response = await http.get(Uri.parse('$url?action=listIncidents')).timeout(const Duration(seconds: 30));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        if (data['ok'] == true && data['items'] is List) {
          return (data['items'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        }
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  static Future<void> _addToPendingQueue(String action, Map<String, dynamic> payload) async {
    _prefs ??= await SharedPreferences.getInstance();
    final raw = _prefs!.getString(_kPendingQueue);
    final queue = raw != null ? (jsonDecode(raw) as List) : [];
    queue.add({'action': action, 'payload': payload, 'queuedAt': DateTime.now().toIso8601String()});
    await _prefs!.setString(_kPendingQueue, jsonEncode(queue));
  }

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
      final payload = Map<String, dynamic>.from(item['payload'] ?? {});
      final ok = await pushIncident(payload);
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

  static Future<Map<String, dynamic>> fullSync() async {
    if (!await isConfigured) return {'ok': false, 'error': 'Backend URL not configured'};
    final pushed = await drainPendingQueue();
    final pulled = await fetchIncidents();
    if (pulled.isNotEmpty) {
      final local = await LocalDB.getIncidents();
      final localIds = local.map((i) => i['id']?.toString()).toSet();
      for (final remote in pulled) {
        if (!localIds.contains(remote['id']?.toString())) {
          await LocalDB.saveIncident(remote);
        }
      }
    }
    await _markSyncTime();
    return {'ok': true, 'pushed': pushed, 'pulled': pulled.length};
  }
}
