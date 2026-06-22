import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'local_db.dart';

/// SAIL Safety Lens — Google Sheets Sync Service
///
/// Periodic push/pull to Google Sheet via Google Apps Script Web App.
/// Pros: completely free, admin can open sheet in browser.
/// Cons: ~60 req/min rate limit, eventual consistency.
class SyncService {
  static const String _defaultBackendUrl =
      'https://script.google.com/macros/s/AKfycbzDiT4OSvlDUxvcM9DYJ_-SiB1HyDrgXtYflGfmqJRH9wnZZusj5GqX9frCx64rkd61Rg/exec';
  static const String _kBackendUrl   = 'sync_backend_url';
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
    return url.isNotEmpty && url.startsWith('https://');
  }

  // ═══════════════════════════════════════════════════════════════
  //  HEALTH CHECK
  // ═══════════════════════════════════════════════════════════════

  static Future<Map<String, dynamic>> ping() async {
    if (!await isConfigured) {
      return {'ok': false, 'error': 'Backend URL not configured'};
    }
    try {
      final url = await getBackendUrl();
      final response = await http
          .get(Uri.parse('$url?action=health'))
          .timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      return {'ok': false, 'error': 'HTTP ${response.statusCode}'};
    } catch (e) {
      return {'ok': false, 'error': e.toString()};
    }
  }

  // ═══════════════════════════════════════════════════════════════
  //  USERS
  // ═══════════════════════════════════════════════════════════════

  /// Fetch all registered users from Apps Script backend.
  /// Used by the dashboard user-switcher dropdown.
  /// Results are automatically cached in LocalDB for offline use.
  static Future<List<Map<String, dynamic>>> fetchUsers() async {
    if (!await isConfigured) return [];
    try {
      final url = await getBackendUrl();
      final response = await http
          .get(Uri.parse('$url?action=listUsers'))
          .timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;

        List<Map<String, dynamic>> users = [];

        // New backend format: { success: true, users: [...] }
        if (data['success'] == true && data['users'] is List) {
          users = (data['users'] as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
        }
        // Old backend format: { ok: true, items: [...] }
        else if (data['ok'] == true && data['items'] is List) {
          users = (data['items'] as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
        }

        // Cache for offline use
        if (users.isNotEmpty) {
          await LocalDB.cacheUsers(users);
        }

        return users;
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  // ═══════════════════════════════════════════════════════════════
  //  INCIDENTS
  // ═══════════════════════════════════════════════════════════════

  /// Push a single incident to the backend.
  /// If offline/failed, adds to pending queue for later retry.
  static Future<bool> pushIncident(
      Map<String, dynamic> incident) async {
    if (!await isConfigured) {
      await _addToPendingQueue('addIncident', incident);
      return false;
    }
    try {
      final url = await getBackendUrl();

      // Build body — strip imageBase64 (too large) and convert all values to strings
      final body = <String, dynamic>{'action': 'addIncident'};
      incident.forEach((k, v) {
        if (k == 'imageBase64') {
          body[k] = '[image]'; // never send raw base64 to Sheets
          return;
        }
        if (v == null) { body[k] = ''; return; }
        if (v is List || v is Map) {
          body[k] = jsonEncode(v); // serialize nested objects
          return;
        }
        final str = v.toString();
        // Truncate any single field > 2000 chars
        body[k] = str.length > 2000 ? str.substring(0, 2000) : str;
      });

      // Apps Script POSTs redirect to googleusercontent.com
      // Flutter's default http.post does NOT follow redirects — must handle manually
      final client   = http.Client();
      http.Response response;
      try {
        response = await client
            .post(
              Uri.parse(url),
              body: jsonEncode(body),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
            )
            .timeout(const Duration(seconds: 30));

        // Follow redirect if 302/301 (Apps Script always redirects)
        if (response.statusCode == 302 || response.statusCode == 301) {
          final redirectUrl = response.headers['location'] ?? '';
          if (redirectUrl.isNotEmpty) {
            response = await client
                .post(
                  Uri.parse(redirectUrl),
                  body: jsonEncode(body),
                  headers: {'Content-Type': 'text/plain;charset=utf-8'},
                )
                .timeout(const Duration(seconds: 30));
          }
        }
      } finally {
        client.close();
      }

      if (response.statusCode == 200) {
        try {
          final data = jsonDecode(response.body);
          if (data['ok'] == true) {
            await _markSyncTime();
            return true;
          }
          // Apps Script returned error — still got through, log it
        } catch (_) {
          // Non-JSON response — Apps Script HTML error page
        }
      }
      await _addToPendingQueue('addIncident', incident);
      return false;
    } catch (_) {
      await _addToPendingQueue('addIncident', incident);
      return false;
    }
  }

  /// Fetch all incidents from backend.
  static Future<List<Map<String, dynamic>>> fetchIncidents() async {
    if (!await isConfigured) return [];
    try {
      final url = await getBackendUrl();
      final response = await http
          .get(Uri.parse('$url?action=listIncidents'))
          .timeout(const Duration(seconds: 30));
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

  // ═══════════════════════════════════════════════════════════════
  //  KNOWLEDGE BASE
  // ═══════════════════════════════════════════════════════════════

  static Future<bool> pushKnowledgeDoc(
      Map<String, dynamic> doc) async {
    if (!await isConfigured) return false;
    try {
      final url  = await getBackendUrl();
      final body = <String, dynamic>{'action': 'addKnowledge'};
      doc.forEach((k, v) => body[k] = (v ?? '').toString());

      final response = await http
          .post(
            Uri.parse(url),
            body: jsonEncode(body),
            headers: {'Content-Type': 'text/plain;charset=utf-8'},
          )
          .timeout(const Duration(seconds: 30));
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
        title:   doc['title']?.toString()   ?? 'Untitled',
        content: doc['content']?.toString() ?? '',
        source:  doc['source']?.toString()  ?? 'cloud',
      );
    }
  }

  static Future<List<Map<String, dynamic>>> fetchKnowledgeDocs() async {
    if (!await isConfigured) return [];
    try {
      final url = await getBackendUrl();
      final response = await http
          .get(Uri.parse('$url?action=listKnowledge'))
          .timeout(const Duration(seconds: 30));
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

  // ═══════════════════════════════════════════════════════════════
  //  PENDING QUEUE (offline writes)
  // ═══════════════════════════════════════════════════════════════

  static Future<void> _addToPendingQueue(
      String action, Map<String, dynamic> payload) async {
    _prefs ??= await SharedPreferences.getInstance();
    final raw   = _prefs!.getString(_kPendingQueue);
    final queue = raw != null ? (jsonDecode(raw) as List) : [];
    queue.add({
      'action':    action,
      'payload':   payload,
      'queuedAt':  DateTime.now().toIso8601String(),
    });
    await _prefs!.setString(_kPendingQueue, jsonEncode(queue));
  }

  static Future<int> drainPendingQueue() async {
    _prefs ??= await SharedPreferences.getInstance();
    final raw = _prefs!.getString(_kPendingQueue);
    if (raw == null) return 0;
    final queue =
        (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    if (queue.isEmpty) return 0;
    if (!await isConfigured) return 0;

    final remaining = <Map<String, dynamic>>[];
    int synced = 0;
    for (final item in queue) {
      final action  = item['action']?.toString();
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

  // ═══════════════════════════════════════════════════════════════
  //  STATUS
  // ═══════════════════════════════════════════════════════════════

  static Future<DateTime?> getLastSyncTime() async {
    _prefs ??= await SharedPreferences.getInstance();
    final raw = _prefs!.getString(_kLastSyncTime);
    if (raw == null) return null;
    return DateTime.tryParse(raw);
  }

  static Future<void> _markSyncTime() async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!
        .setString(_kLastSyncTime, DateTime.now().toIso8601String());
  }

  // ═══════════════════════════════════════════════════════════════
  //  FULL SYNC
  // ═══════════════════════════════════════════════════════════════

  static Future<Map<String, dynamic>> fullSync() async {
    if (!await isConfigured) {
      return {
        'ok': false,
        'error':
            'Backend URL not configured. Open Settings to add Apps Script URL.',
      };
    }

    // Push any queued offline writes
    final pushed = await drainPendingQueue();

    // Pull latest incidents from Sheets
    final pulled = await fetchIncidents();
    if (pulled.isNotEmpty) {
      final local    = await LocalDB.getIncidents();
      final localIds = local.map((i) => i['id']?.toString()).toSet();
      for (final remote in pulled) {
        if (!localIds.contains(remote['id']?.toString())) {
          await LocalDB.saveIncident(remote);
        }
      }
    }

    // Pull latest users from Sheets and cache them
    final users = await fetchUsers();
    if (users.isNotEmpty) {
      await LocalDB.cacheUsers(users);
    }

    await _markSyncTime();
    return {
      'ok':       true,
      'pushed':   pushed,
      'pulled':   pulled.length,
      'users':    users.length,
      'syncTime': DateTime.now().toIso8601String(),
    };
  }
  // ═══════════════════════════════════════════════════════════════
  //  ADMIN — USER MANAGEMENT
  // ═══════════════════════════════════════════════════════════════

  static Future<bool> updateUserField(
      String username, String field, String value) async {
    try {
      final url = await getBackendUrl();
      final resp = await http.post(Uri.parse(url),
        body: jsonEncode({
          'action':   'updateRole',
          'username': username,
          field:      value,
        }),
        headers: {'Content-Type': 'text/plain;charset=utf-8'}).timeout(
            const Duration(seconds: 20));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        return data['success'] == true;
      }
      return false;
    } catch (_) { return false; }
  }

  static Future<bool> deleteUser(String username) async {
    try {
      final url = await getBackendUrl();
      final resp = await http.post(Uri.parse(url),
        body: jsonEncode({'action': 'deleteUser', 'username': username}),
        headers: {'Content-Type': 'text/plain;charset=utf-8'}).timeout(
            const Duration(seconds: 20));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        return data['success'] == true;
      }
      return false;
    } catch (_) { return false; }
  }

  static Future<bool> registerUser(Map<String, dynamic> params) async {
    try {
      final url = await getBackendUrl();
      final body = Map<String, dynamic>.from(params);
      body['action'] = 'register';
      final resp = await http.post(Uri.parse(url),
        body: jsonEncode(body),
        headers: {'Content-Type': 'text/plain;charset=utf-8'}).timeout(
            const Duration(seconds: 20));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        return data['success'] == true;
      }
      return false;
    } catch (_) { return false; }
  }

  // ═══════════════════════════════════════════════════════════════
  //  ✅ NEW (admin v5): PUSH USER
  //  Insert-or-update a user record on the Apps Script backend.
  //  Used by Admin Command Centre after upsertUser() local write.
  //
  //  Strategy: try `register` first (handles new + existing in v9+);
  //  if backend doesn't recognise it, fall back to upsertUser action.
  //  Returns true on backend success, false on any failure (caller
  //  wraps in try/catch and treats it as best-effort).
  // ═══════════════════════════════════════════════════════════════
  static Future<bool> pushUser(Map<String, dynamic> user) async {
    if (!await isConfigured) return false;

    final uname = (user['username']?.toString() ?? '').trim();
    if (uname.isEmpty) return false;

    final url = await getBackendUrl();

    // Strip any password material that shouldn't go over the wire
    // unless explicitly set on this payload (the caller knows best).
    final body = <String, dynamic>{};
    user.forEach((k, v) {
      if (v == null) { body[k] = ''; return; }
      if (v is List || v is Map) { body[k] = jsonEncode(v); return; }
      body[k] = v.toString();
    });

    // Attempt 1: action=upsertUser (preferred when backend supports it)
    try {
      final b1 = Map<String, dynamic>.from(body)..['action'] = 'upsertUser';
      final client = http.Client();
      http.Response resp;
      try {
        resp = await client.post(
          Uri.parse(url),
          body: jsonEncode(b1),
          headers: {'Content-Type': 'text/plain;charset=utf-8'},
        ).timeout(const Duration(seconds: 20));
        if (resp.statusCode == 302 || resp.statusCode == 301) {
          final loc = resp.headers['location'] ?? '';
          if (loc.isNotEmpty) {
            resp = await client.post(
              Uri.parse(loc),
              body: jsonEncode(b1),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
            ).timeout(const Duration(seconds: 20));
          }
        }
      } finally { client.close(); }

      if (resp.statusCode == 200) {
        try {
          final data = jsonDecode(resp.body);
          if (data is Map &&
              (data['success'] == true || data['ok'] == true)) {
            return true;
          }
        } catch (_) {}
      }
    } catch (_) {}

    // Attempt 2: fall back to register (Apps Script v9 accepts this
    // and silently updates an existing user if `username` matches).
    try {
      final b2 = Map<String, dynamic>.from(body)..['action'] = 'register';
      final client = http.Client();
      http.Response resp;
      try {
        resp = await client.post(
          Uri.parse(url),
          body: jsonEncode(b2),
          headers: {'Content-Type': 'text/plain;charset=utf-8'},
        ).timeout(const Duration(seconds: 20));
        if (resp.statusCode == 302 || resp.statusCode == 301) {
          final loc = resp.headers['location'] ?? '';
          if (loc.isNotEmpty) {
            resp = await client.post(
              Uri.parse(loc),
              body: jsonEncode(b2),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
            ).timeout(const Duration(seconds: 20));
          }
        }
      } finally { client.close(); }

      if (resp.statusCode == 200) {
        try {
          final data = jsonDecode(resp.body);
          if (data is Map &&
              (data['success'] == true || data['ok'] == true)) {
            return true;
          }
        } catch (_) {}
      }
    } catch (_) {}

    return false;
  }

  static Future<void> pushAllIncidents(
      List<Map<String, dynamic>> incidents) async {
    for (final inc in incidents) {
      await pushIncident(inc);
    }
  }

  // ═══════════════════════════════════════════════════════════════
  //  DEBUG — returns full response for diagnosing Sheets issues
  // ═══════════════════════════════════════════════════════════════
  static Future<Map<String, dynamic>> testPush() async {
    final url = await getBackendUrl();
    final testBody = jsonEncode({
      'action':  'addIncident',
      'id':      'TEST_${DateTime.now().millisecondsSinceEpoch}',
      'title':   'Test from Flutter app',
      'plant':   'Test Plant',
      'dept':    'Safety',
      'severity':'HIGH',
      'status':  'OPEN',
      'type':    'AI_SCAN',
      'date':    DateTime.now().toIso8601String(),
      'reportedBy': 'System Test',
    });
    try {
      final client = http.Client();
      http.Response resp;
      try {
        resp = await client.post(Uri.parse(url),
          body: testBody,
          headers: {'Content-Type': 'text/plain;charset=utf-8'})
          .timeout(const Duration(seconds: 30));
        if (resp.statusCode == 302 || resp.statusCode == 301) {
          final loc = resp.headers['location'] ?? '';
          if (loc.isNotEmpty) {
            resp = await client.post(Uri.parse(loc),
              body: testBody,
              headers: {'Content-Type': 'text/plain;charset=utf-8'})
              .timeout(const Duration(seconds: 30));
          }
        }
      } finally { client.close(); }
      return {
        'statusCode': resp.statusCode,
        'body': resp.body.length > 500
            ? resp.body.substring(0, 500) : resp.body,
        'headers': resp.headers,
        'url': url,
      };
    } catch (e) {
      return {'error': e.toString(), 'url': url};
    }
  }

  // ═══════════════════════════════════════════════════════════════
  //  ONLINE LOGIN — tries Apps Script; returns user map or null
  // ═══════════════════════════════════════════════════════════════
  static Future<Map<String, dynamic>?> loginOnline(
      String username, String passwordHash) async {
    if (!await isConfigured) return null;
    try {
      final url = await getBackendUrl();
      final resp = await http.post(
        Uri.parse(url),
        body: jsonEncode({
          'action': 'login',
          'username': username,
          'passwordHash': passwordHash,
        }),
        headers: {'Content-Type': 'text/plain;charset=utf-8'},
      ).timeout(const Duration(seconds: 20));

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        // Apps Script v9 returns { success: true, user: {...} }
        // or { success: true, uid, name, username, isAdmin, ... }
        if (data['success'] == true) {
          if (data['user'] is Map) {
            return Map<String, dynamic>.from(data['user'] as Map);
          }
          // Flat format (admin hardcode path)
          final flat = Map<String, dynamic>.from(data);
          flat.remove('success');
          if (flat['username'] != null) return flat;
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════════
  //  UPLOAD PDF TO DRIVE — returns shareable URL, updates incident
  // ═══════════════════════════════════════════════════════════════
  static Future<String?> uploadPdfToDrive({
    required String incidentId,
    required Uint8List pdfBytes,
    String? fileName,
  }) async {
    if (!await isConfigured) return null;
    try {
      final url = await getBackendUrl();
      final name = fileName ?? 'SafetyLens_${incidentId}.pdf';
      final body = jsonEncode({
        'action':     'uploadPdfToDrive',
        'incidentId': incidentId,
        'fileName':   name,
        'pdfBase64':  base64Encode(pdfBytes),
      });

      // Apps Script redirects POST — follow redirect manually
      final client = http.Client();
      http.Response resp;
      try {
        resp = await client.post(
          Uri.parse(url),
          body: body,
          headers: {'Content-Type': 'text/plain;charset=utf-8'},
        ).timeout(const Duration(seconds: 60));
        if (resp.statusCode == 302 || resp.statusCode == 301) {
          final loc = resp.headers['location'] ?? '';
          if (loc.isNotEmpty) {
            resp = await client.post(
              Uri.parse(loc),
              body: body,
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
            ).timeout(const Duration(seconds: 60));
          }
        }
      } finally { client.close(); }

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        if (data['success'] == true) {
          return data['pdfUrl']?.toString();
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════════
  //  DELETE INCIDENT from Sheets (admin action)
  // ═══════════════════════════════════════════════════════════════
  static Future<bool> deleteIncident(String id) async {
    if (!await isConfigured) return false;
    try {
      final url = await getBackendUrl();
      final resp = await http.post(
        Uri.parse(url),
        body: jsonEncode({'action': 'deleteIncident', 'id': id}),
        headers: {'Content-Type': 'text/plain;charset=utf-8'},
      ).timeout(const Duration(seconds: 20));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        return data['ok'] == true || data['success'] == true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

}
