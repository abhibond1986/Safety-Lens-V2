import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class LocalDB {
  static late SharedPreferences _prefs;
  static const _kUsers        = 'users';
  static const _kIncidents    = 'incidents';
  static const _kCurrentUser  = 'current_user';
  static const _kKbTopics     = 'kb_topics';
  static const _kCachedUsers  = 'cached_users'; // ← NEW: users fetched from Sheets

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    await _seedIfEmpty();
  }

  static Future<void> _seedIfEmpty() async {
    if (_prefs.getString(_kUsers) == null) {
      final seed = [
        {
          'username': 'abhishek.kumar', 'password': 'demo',
          'name': 'Abhishek Kumar', 'designation': 'AGM',
          'plant': 'SAIL Safety Organisation',
          'pno': 'SAIL-SSO-001', 'mobile': '9999999999',
          'email': 'abhishek@sail.in',
          'isAdmin': true,
        },
        {
          'username': 'demo', 'password': 'demo',
          'name': 'R.K. Sharma', 'designation': 'Sr. Safety Officer',
          'plant': 'BSP Bhilai',
          'pno': 'BSP-2024-001', 'mobile': '9876543210',
          'email': 'rks@sail.in',
          'isAdmin': false,
        },
        {
          'username': 'rajesh.kumar', 'password': 'demo',
          'name': 'Rajesh Kumar', 'designation': 'Safety Officer',
          'plant': 'BSP Bhilai',
          'pno': 'BSP-2024-002', 'mobile': '9876543211',
          'email': 'rajesh@sail.in',
          'isAdmin': false,
        },
        {
          'username': 'priya.singh', 'password': 'demo',
          'name': 'Priya Singh', 'designation': 'Safety Supervisor',
          'plant': 'ISP Burnpur',
          'pno': 'ISP-2024-001', 'mobile': '9876543212',
          'email': 'priya@sail.in',
          'isAdmin': false,
        },
      ];
      await _prefs.setString(_kUsers, jsonEncode(seed));
    }

    if (_prefs.getString(_kIncidents) == null) {
      final now = DateTime.now();
      final seedIncidents = [
        {
          'id': '1', 'title': 'No Fall Arrest at Formwork',
          'plant': 'BSP Bhilai', 'dept': 'Civil Construction',
          'location': 'BF-2 Cast House', 'severity': 'CRITICAL',
          'wsaCategory': 'Fall from Height',
          'date': now.subtract(const Duration(days: 6)).toIso8601String(),
          'status': 'OPEN', 'reportedBy': 'R.K. Sharma',
          'reportedByPno': 'BSP-2024-001',
          'type': 'AI_SCAN',
          'desc': 'Worker observed at height without harness',
        },
        {
          'id': '2', 'title': 'Crane Near Miss',
          'plant': 'BSP Bhilai', 'dept': 'Rolling Mill',
          'location': 'Bay 4', 'severity': 'CRITICAL',
          'wsaCategory': 'Hit / Caught / Pressed',
          'date': now.subtract(const Duration(days: 4)).toIso8601String(),
          'status': 'INVESTIGATING', 'reportedBy': 'Priya Singh',
          'reportedByPno': 'ISP-2024-001',
          'type': 'NEAR_MISS',
          'desc': 'Crane load swung close to worker',
        },
        {
          'id': '3', 'title': 'Slip Hazard on Walkway',
          'plant': 'DSP Durgapur', 'dept': 'Coke Oven',
          'location': 'Pusher side', 'severity': 'MEDIUM',
          'wsaCategory': 'Slip / Fall',
          'date': now.subtract(const Duration(days: 3)).toIso8601String(),
          'status': 'CLOSED', 'reportedBy': 'Rajesh Kumar',
          'reportedByPno': 'BSP-2024-002',
          'type': 'NEAR_MISS',
          'desc': 'Oil spillage on walkway',
        },
        {
          'id': '4', 'title': 'Hot Metal Splash Risk',
          'plant': 'RSP Rourkela', 'dept': 'SMS',
          'location': 'Caster 2', 'severity': 'HIGH',
          'wsaCategory': 'Hot Metal / Slag / Sub',
          'date': now.subtract(const Duration(days: 2)).toIso8601String(),
          'status': 'CLOSED', 'reportedBy': 'Priya Singh',
          'reportedByPno': 'ISP-2024-001',
          'type': 'AI_SCAN',
          'desc': 'Splash guard missing on caster',
        },
        {
          'id': '5', 'title': 'PPE Gap — Helmet Missing',
          'plant': 'BSL Bokaro', 'dept': 'Blast Furnace',
          'location': 'BF-3 Stock house', 'severity': 'HIGH',
          'wsaCategory': 'Other',
          'date': now.subtract(const Duration(days: 2)).toIso8601String(),
          'status': 'OPEN', 'reportedBy': 'Rajesh Kumar',
          'reportedByPno': 'BSP-2024-002',
          'type': 'AI_SCAN',
          'desc': 'Worker without helmet near furnace',
        },
        {
          'id': '6', 'title': 'Electrical Panel Open',
          'plant': 'ISP Burnpur', 'dept': 'Electrical',
          'location': 'Sub-station 4', 'severity': 'HIGH',
          'wsaCategory': 'Electrical',
          'date': now.subtract(const Duration(days: 1)).toIso8601String(),
          'status': 'OPEN', 'reportedBy': 'Abhishek Kumar',
          'reportedByPno': 'SAIL-SSO-001',
          'type': 'NEAR_MISS',
          'desc': 'Live panel open without barrier',
        },
        {
          'id': '7', 'title': 'Hose Trip Hazard',
          'plant': 'BSP Bhilai', 'dept': 'Maintenance',
          'location': 'Workshop', 'severity': 'LOW',
          'wsaCategory': 'Slip / Fall',
          'date': now.subtract(const Duration(days: 1)).toIso8601String(),
          'status': 'OPEN', 'reportedBy': 'Priya Singh',
          'reportedByPno': 'ISP-2024-001',
          'type': 'NEAR_MISS',
          'desc': 'Compressed air hose across walkway',
        },
        {
          'id': '8', 'title': 'Loose Cable Trip Risk',
          'plant': 'ISP Burnpur', 'dept': 'Rolling Mill',
          'location': 'Bay 2', 'severity': 'MEDIUM',
          'wsaCategory': 'Electrical',
          'date': now.toIso8601String(),
          'status': 'OPEN', 'reportedBy': 'Abhishek Kumar',
          'reportedByPno': 'SAIL-SSO-001',
          'type': 'NEAR_MISS',
          'desc': 'Loose electrical cable across walkway',
        },
      ];
      await _prefs.setString(_kIncidents, jsonEncode(seedIncidents));
    }
  }

  // ═══════════════════════════════════════════════════════════════
  //  AUTH
  // ═══════════════════════════════════════════════════════════════

  // ── SIGN IN ─────────────────────────────────────────────────
  // Accepts plain password (local DB) OR passwordHash (from Sheets sync).
  // Also tries online login via SyncService if local fails.
  static Future<Map<String, dynamic>?> signIn(
      String username, String password) async {

    // 1. Always accept admin/admin as hardcoded offline fallback
    if (username == 'admin' && password == 'admin') {
      final adminUser = {
        'username': 'admin', 'password': 'admin',
        'name': 'System Admin', 'designation': 'Administrator',
        'plant': 'Corporate – Ranchi', 'department': 'Safety HQ',
        'pno': 'ADMIN001', 'isAdmin': true, 'status': 'active',
      };
      await _prefs.setString(_kCurrentUser, jsonEncode(adminUser));
      return adminUser;
    }

    // 2. Check local users (plain password field)
    final users = await getUsers();
    for (final u in users) {
      final uname   = u['username']?.toString() ?? '';
      final email   = u['email']?.toString() ?? '';
      final stored  = u['password']?.toString() ?? '';
      final storedH = u['passwordHash']?.toString() ?? '';
      if ((uname == username || email == username) &&
          (stored == password || storedH == password)) {
        await _prefs.setString(_kCurrentUser, jsonEncode(u));
        return u;
      }
    }

    // 3. Check cached users from Sheets (passwordHash field)
    final cached = await getAllUsers();
    for (final u in cached) {
      final uname   = u['username']?.toString() ?? '';
      final storedH = u['passwordHash']?.toString() ?? '';
      if (uname == username && storedH == password) {
        await _prefs.setString(_kCurrentUser, jsonEncode(u));
        return u;
      }
    }

    return null;
  }

  static Future<Map<String, dynamic>?> register(
      Map<String, dynamic> userData) async {
    final users = await getUsers();
    if (users.any((u) => u['username'] == userData['username'])) {
      return null; // duplicate
    }
    users.add(userData);
    await _prefs.setString(_kUsers, jsonEncode(users));
    await _prefs.setString(_kCurrentUser, jsonEncode(userData));
    return userData;
  }

  static Future<void> signOut() async {
    await _prefs.remove(_kCurrentUser);
  }

  static Future<Map<String, dynamic>?> getCurrentUser() async {
    final raw = _prefs.getString(_kCurrentUser);
    if (raw == null) return null;
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  // ═══════════════════════════════════════════════════════════════
  //  USERS — local seed list
  // ═══════════════════════════════════════════════════════════════

  static Future<List<Map<String, dynamic>>> getUsers() async {
    final raw = _prefs.getString(_kUsers);
    if (raw == null) return [];
    return (jsonDecode(raw) as List)
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  // ── NEW: All users for dashboard user-switcher ─────────────────
  /// Returns all users available for the dashboard switcher.
  /// Priority: Sheets-cached users (most up to date) → local seed users.
  static Future<List<Map<String, dynamic>>> getAllUsers() async {
    // 1. Try Sheets-cached users first (fetched from Apps Script)
    final cached = await getCachedUsers();
    if (cached.isNotEmpty) return cached;

    // 2. Fall back to local seed users (always available offline)
    return getUsers();
  }

  /// Save the user list fetched from Google Sheets to local cache.
  /// Called by dashboard after SyncService.fetchUsers() returns data.
  static Future<void> cacheUsers(
      List<Map<String, dynamic>> users) async {
    await _prefs.setString(_kCachedUsers, jsonEncode(users));
  }

  /// Get previously cached Sheets users.
  static Future<List<Map<String, dynamic>>> getCachedUsers() async {
    final raw = _prefs.getString(_kCachedUsers);
    if (raw == null || raw.isEmpty) return [];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Clear the Sheets user cache (call on logout or full reset).
  static Future<void> clearCachedUsers() async {
    await _prefs.remove(_kCachedUsers);
  }

  // ═══════════════════════════════════════════════════════════════
  //  INCIDENTS
  // ═══════════════════════════════════════════════════════════════

  static Future<List<Map<String, dynamic>>> getIncidents() async {
    final raw = _prefs.getString(_kIncidents);
    if (raw == null) return [];
    final list = (jsonDecode(raw) as List)
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    list.sort((a, b) => (b['date'] ?? '')
        .toString()
        .compareTo((a['date'] ?? '').toString()));
    return list;
  }

  static Future<void> saveIncident(
      Map<String, dynamic> incident) async {
    final all  = await getIncidents();
    final user = await getCurrentUser();

    incident['id']          ??= DateTime.now().millisecondsSinceEpoch.toString();
    incident['date']        ??= DateTime.now().toIso8601String();
    incident['reportedBy']  ??= user?['name'] ?? 'Unknown';
    incident['reporterPno'] ??= user?['pno']  ?? '';
    incident['status']      ??= 'OPEN';

    final existingIdx = all.indexWhere(
        (i) => i['id']?.toString() == incident['id']?.toString());
    if (existingIdx >= 0) {
      all[existingIdx] = incident;
    } else {
      all.add(incident);
    }
    await _prefs.setString(_kIncidents, jsonEncode(all));
  }

  // ═══════════════════════════════════════════════════════════════
  //  PLANT STATS
  // ═══════════════════════════════════════════════════════════════

  static Future<Map<String, Map<String, int>>> getPlantStats() async {
    final inc = await getIncidents();
    final result = <String, Map<String, int>>{};
    final plants = [
      'BSP Bhilai', 'DSP Durgapur', 'RSP Rourkela',
      'BSL Bokaro', 'ISP Burnpur',
    ];
    for (final p in plants) {
      final pInc = inc.where((i) => i['plant'] == p).toList();
      result[p] = {
        'total':    pInc.length,
        'open':     pInc.where((i) => i['status']   == 'OPEN').length,
        'critical': pInc.where((i) => i['severity'] == 'CRITICAL').length,
        'high':     pInc.where((i) => i['severity'] == 'HIGH').length,
      };
    }
    return result;
  }

  static int calcSafetyScore(
      int critical, int high, int medium, int open) {
    return (100 - critical * 15 - high * 8 - medium * 3 - open * 2)
        .clamp(0, 100);
  }

  // ═══════════════════════════════════════════════════════════════
  //  FEEDBACK & LEARNING
  // ═══════════════════════════════════════════════════════════════

  static const _kFeedback      = 'feedback_corrections';
  static const _kCustomHazards = 'custom_hazards';

  static Future<void> saveFeedback({
    required int imageSeed,
    required String type,
    required Map<String, dynamic> hazardData,
  }) async {
    final all = await getAllFeedback();
    all.add({
      'imageSeed': imageSeed,
      'type':      type,
      'hazard':    hazardData,
      'timestamp': DateTime.now().toIso8601String(),
      'user':      (await getCurrentUser())?['name'] ?? 'unknown',
    });
    await _prefs.setString(_kFeedback, jsonEncode(all));
  }

  static Future<List<Map<String, dynamic>>> getAllFeedback() async {
    final raw = _prefs.getString(_kFeedback);
    if (raw == null) return [];
    return (jsonDecode(raw) as List)
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  static Future<List<Map<String, dynamic>>> getFeedbackForSeed(
      int imageSeed) async {
    final all = await getAllFeedback();
    return all.where((f) => f['imageSeed'] == imageSeed).toList();
  }

  static Future<void> addCustomHazard(
      Map<String, dynamic> hazard) async {
    final all = await getCustomHazards();
    hazard['addedAt'] = DateTime.now().toIso8601String();
    hazard['addedBy'] = (await getCurrentUser())?['name'] ?? 'unknown';
    all.add(hazard);
    await _prefs.setString(_kCustomHazards, jsonEncode(all));
  }

  static Future<List<Map<String, dynamic>>> getCustomHazards() async {
    final raw = _prefs.getString(_kCustomHazards);
    if (raw == null) return [];
    return (jsonDecode(raw) as List)
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  static Future<void> clearFeedback() async {
    await _prefs.remove(_kFeedback);
    await _prefs.remove(_kCustomHazards);
  }

  static Future<Map<String, int>> getFeedbackStats() async {
    final all = await getAllFeedback();
    return {
      'total':    all.length,
      'added':    all.where((f) => f['type'] == 'add').length,
      'removed':  all.where((f) => f['type'] == 'remove').length,
      'reworded': all.where((f) => f['type'] == 'reword').length,
    };
  }

  // ═══════════════════════════════════════════════════════════════
  //  KNOWLEDGE BASE
  // ═══════════════════════════════════════════════════════════════

  static const _kKbDocs = 'kb_documents';

  static Future<void> addKnowledgeDoc({
    required String title,
    required String content,
    String? source,
  }) async {
    final all = await getKnowledgeDocs();
    all.add({
      'id':         DateTime.now().millisecondsSinceEpoch.toString(),
      'title':      title,
      'content':    content,
      'source':     source ?? 'uploaded',
      'uploadedAt': DateTime.now().toIso8601String(),
      'uploadedBy': (await getCurrentUser())?['name'] ?? 'admin',
    });
    await _prefs.setString(_kKbDocs, jsonEncode(all));
  }

  static Future<List<Map<String, dynamic>>> getKnowledgeDocs() async {
    final raw = _prefs.getString(_kKbDocs);
    if (raw == null) return [];
    return (jsonDecode(raw) as List)
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  static Future<void> updateKnowledgeDoc({
    required String id,
    required String title,
    required String content,
    String? source,
  }) async {
    final all = await getKnowledgeDocs();
    final idx = all.indexWhere((d) => d['id'] == id);
    if (idx >= 0) {
      all[idx]['title']   = title;
      all[idx]['content'] = content;
      if (source != null) all[idx]['source'] = source;
      await _prefs.setString(_kKbDocs, jsonEncode(all));
    }
  }

  static Future<void> deleteKnowledgeDoc(String id) async {
    final all = await getKnowledgeDocs();
    all.removeWhere((d) => d['id'] == id);
    await _prefs.setString(_kKbDocs, jsonEncode(all));
  }

  static Future<List<Map<String, dynamic>>> searchKnowledge(
      String query) async {
    final all = await getKnowledgeDocs();
    if (all.isEmpty) return [];
    final q = query
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((w) => w.length > 2)
        .toList();
    if (q.isEmpty) return [];

    final results = <Map<String, dynamic>>[];
    for (final doc in all) {
      final content      = doc['content']?.toString() ?? '';
      final contentLower = content.toLowerCase();
      int score = 0;
      for (final word in q) {
        score += word.allMatches(contentLower).length;
      }
      if (score > 0) {
        final sentences = content.split(RegExp(r'(?<=[.!?])\s+'));
        String bestSnippet      = '';
        int    bestSnippetScore = 0;
        for (final s in sentences) {
          final sl = s.toLowerCase();
          int ss = 0;
          for (final word in q) {
            if (sl.contains(word)) ss++;
          }
          if (ss > bestSnippetScore) {
            bestSnippetScore = ss;
            bestSnippet      = s.trim();
          }
        }
        results.add({
          'title':   doc['title'],
          'snippet': bestSnippet.length > 400
              ? '${bestSnippet.substring(0, 400)}...'
              : bestSnippet,
          'score': score,
        });
      }
    }
    results.sort(
        (a, b) => (b['score'] as int).compareTo(a['score'] as int));
    return results.take(3).toList();
  }

  // ── DELETE INCIDENT ───────────────────────────────────────────
  static Future<void> deleteIncident(String id) async {
    final incidents = await getIncidents();
    incidents.removeWhere((i) => i['id']?.toString() == id);
    await _prefs.setString(_kIncidents, jsonEncode(incidents));
  }
}
