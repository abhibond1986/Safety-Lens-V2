// lib/services/local_db.dart
// SAIL Safety Lens — Local storage layer (SharedPreferences)
// ✅ All existing methods preserved
// ✅ NEW: seedKnowledgeBase() — loads 38 default FA 1948 + state-rules entries
// ✅ NEW: resetAllData()      — wipes incidents (optionally KB / users)
// ✅ NEW: dataCounts()        — counts for confirmation dialogs
// ✅ NEW (admin v5): upsertUser, deleteUser, replaceAllIncidents,
//                   replaceAllUsers, replaceAllKnowledgeDocs

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'kb_seed_data.dart';
import 'crypto_utils.dart';

class LocalDB {
  static late SharedPreferences _prefs;
  static const _kUsers         = 'users';
  static const _kIncidents     = 'incidents';
  static const _kCurrentUser   = 'current_user';
  // ignore: unused_field
  static const _kKbTopics      = 'kb_topics';
  static const _kCachedUsers   = 'cached_users';
  static const _kKbDocs        = 'kb_documents';
  static const _kFeedback      = 'feedback_corrections';
  static const _kCustomHazards = 'custom_hazards';

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    await _seedIfEmpty();
  }

  static Future<void> _seedIfEmpty() async {
    if (_prefs.getString(_kUsers) == null) {
      // Seed users with hashed passwords (default password: 'demo')
      final seed = <Map<String, dynamic>>[];
      final seedData = [
        {'username': 'abhishek.kumar', 'name': 'Abhishek Kumar', 'designation': 'AGM',
         'plant': 'SAIL Safety Organisation', 'pno': 'SAIL-SSO-001',
         'mobile': '9999999999', 'email': 'abhishek@sail.in', 'isAdmin': true},
        {'username': 'demo', 'name': 'R.K. Sharma', 'designation': 'Sr. Safety Officer',
         'plant': 'BSP Bhilai', 'pno': 'BSP-2024-001',
         'mobile': '9876543210', 'email': 'rks@sail.in', 'isAdmin': false},
        {'username': 'rajesh.kumar', 'name': 'Rajesh Kumar', 'designation': 'Safety Officer',
         'plant': 'BSP Bhilai', 'pno': 'BSP-2024-002',
         'mobile': '9876543211', 'email': 'rajesh@sail.in', 'isAdmin': false},
        {'username': 'priya.singh', 'name': 'Priya Singh', 'designation': 'Safety Supervisor',
         'plant': 'ISP Burnpur', 'pno': 'ISP-2024-001',
         'mobile': '9876543212', 'email': 'priya@sail.in', 'isAdmin': false},
      ];
      for (final u in seedData) {
        final salt = CryptoUtils.generateSalt();
        u['salt'] = salt;
        u['passwordHash'] = CryptoUtils.hashPassword('demo', salt);
        u['status'] = 'active';
        seed.add(u);
      }
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

  static Future<Map<String, dynamic>?> signIn(
      String username, String password) async {
    // Check local users first
    final users = await getUsers();
    for (final u in users) {
      final uname  = u['username']?.toString() ?? '';
      final email  = u['email']?.toString() ?? '';
      if (uname != username && email != username) continue;

      // Block disabled users
      final status = (u['status']?.toString().toLowerCase() ?? 'active');
      if (status == 'disabled' || status == 'blocked') return null;

      // Try secure hash verification first
      final salt = u['salt']?.toString() ?? '';
      final storedHash = u['passwordHash']?.toString() ?? '';
      if (salt.isNotEmpty && storedHash.isNotEmpty) {
        if (CryptoUtils.verifyPassword(password, salt, storedHash)) {
          final safeUser = Map<String, dynamic>.from(u)
            ..remove('password')..remove('passwordHash')..remove('salt');
          await _prefs.setString(_kCurrentUser, jsonEncode(safeUser));
          return safeUser;
        }
      }

      // Legacy fallback: plaintext password (migrate on successful login)
      final stored = u['password']?.toString() ?? '';
      if (stored.isNotEmpty && stored == password) {
        // Migrate to hashed password
        await _migratePassword(u, password);
        final safeUser = Map<String, dynamic>.from(u)
          ..remove('password')..remove('passwordHash')..remove('salt');
        await _prefs.setString(_kCurrentUser, jsonEncode(safeUser));
        return safeUser;
      }

      // Legacy fallback: old simpleHash (from backend)
      if (storedHash.isNotEmpty && salt.isEmpty && storedHash == password) {
        await _migratePassword(u, password);
        final safeUser = Map<String, dynamic>.from(u)
          ..remove('password')..remove('passwordHash')..remove('salt');
        await _prefs.setString(_kCurrentUser, jsonEncode(safeUser));
        return safeUser;
      }
    }

    // Check cached users from backend
    final cached = await getAllUsers();
    for (final u in cached) {
      final uname = u['username']?.toString() ?? '';
      if (uname != username) continue;

      final status = (u['status']?.toString().toLowerCase() ?? 'active');
      if (status == 'disabled' || status == 'blocked') return null;

      final salt = u['salt']?.toString() ?? '';
      final storedHash = u['passwordHash']?.toString() ?? '';
      if (salt.isNotEmpty && storedHash.isNotEmpty) {
        if (CryptoUtils.verifyPassword(password, salt, storedHash)) {
          final safeUser = Map<String, dynamic>.from(u)
            ..remove('password')..remove('passwordHash')..remove('salt');
          await _prefs.setString(_kCurrentUser, jsonEncode(safeUser));
          return safeUser;
        }
      }
    }

    return null;
  }

  /// Migrate a legacy plaintext password to SHA-256 + salt
  static Future<void> _migratePassword(Map<String, dynamic> user, String password) async {
    final salt = CryptoUtils.generateSalt();
    final hash = CryptoUtils.hashPassword(password, salt);
    user['salt'] = salt;
    user['passwordHash'] = hash;
    user.remove('password'); // Remove plaintext

    // Update in users list
    final users = await getUsers();
    for (int i = 0; i < users.length; i++) {
      if (users[i]['username'] == user['username']) {
        users[i] = user;
        break;
      }
    }
    await _prefs.setString(_kUsers, jsonEncode(users));
  }

  static Future<Map<String, dynamic>?> register(
      Map<String, dynamic> userData) async {
    final users = await getUsers();
    if (users.any((u) => u['username'] == userData['username'])) {
      return null;
    }

    // Hash the password before storing
    final rawPassword = userData['password']?.toString() ?? '';
    if (rawPassword.isNotEmpty) {
      final salt = CryptoUtils.generateSalt();
      userData['salt'] = salt;
      userData['passwordHash'] = CryptoUtils.hashPassword(rawPassword, salt);
      userData.remove('password'); // Never store plaintext
    }

    users.add(userData);
    await _prefs.setString(_kUsers, jsonEncode(users));

    // Store safe user (no credentials) in current session
    final safeUser = Map<String, dynamic>.from(userData)
      ..remove('password')..remove('passwordHash')..remove('salt');
    await _prefs.setString(_kCurrentUser, jsonEncode(safeUser));
    return safeUser;
  }

  static Future<bool> resetPassword(String username, {String newPassword = 'sail@123'}) async {
    final users = await getUsers();
    bool found = false;
    for (int i = 0; i < users.length; i++) {
      if (users[i]['username']?.toString() == username ||
          users[i]['email']?.toString() == username) {
        final salt = CryptoUtils.generateSalt();
        users[i]['salt'] = salt;
        users[i]['passwordHash'] = CryptoUtils.hashPassword(newPassword, salt);
        users[i].remove('password'); // Remove any legacy plaintext
        found = true;
        break;
      }
    }
    if (found) {
      await _prefs.setString(_kUsers, jsonEncode(users));
    }
    return found;
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
  //  USERS
  // ═══════════════════════════════════════════════════════════════

  static Future<List<Map<String, dynamic>>> getUsers() async {
    final raw = _prefs.getString(_kUsers);
    if (raw == null) return [];
    return (jsonDecode(raw) as List)
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  static Future<List<Map<String, dynamic>>> getAllUsers() async {
    final cached = await getCachedUsers();
    if (cached.isNotEmpty) return cached;
    return getUsers();
  }

  static Future<void> cacheUsers(
      List<Map<String, dynamic>> users) async {
    await _prefs.setString(_kCachedUsers, jsonEncode(users));
  }

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

  static Future<void> clearCachedUsers() async {
    await _prefs.remove(_kCachedUsers);
  }

  // ═══════════════════════════════════════════════════════════════
  //  ✅ NEW (admin v5): UPSERT USER
  //  Insert or update a user record by `username`.
  //  Writes to the same `_kUsers` bucket that getUsers() reads.
  // ═══════════════════════════════════════════════════════════════
  static Future<void> upsertUser(Map<String, dynamic> user) async {
    final uname = (user['username']?.toString() ?? '').trim();
    if (uname.isEmpty) return;

    final users = await getUsers();
    final idx = users.indexWhere(
        (u) => (u['username']?.toString() ?? '').trim() == uname);

    if (idx >= 0) {
      // Merge: incoming non-empty values overwrite, others preserved
      final merged = Map<String, dynamic>.from(users[idx]);
      user.forEach((k, v) {
        if (v != null && v.toString().isNotEmpty) merged[k] = v;
      });
      users[idx] = merged;
    } else {
      users.add(Map<String, dynamic>.from(user));
    }
    await _prefs.setString(_kUsers, jsonEncode(users));

    // Also refresh cached_users so the dashboard switcher sees the change
    try {
      final cached = await getCachedUsers();
      if (cached.isNotEmpty) {
        final cIdx = cached.indexWhere(
            (u) => (u['username']?.toString() ?? '').trim() == uname);
        if (cIdx >= 0) {
          final merged = Map<String, dynamic>.from(cached[cIdx]);
          user.forEach((k, v) {
            if (v != null && v.toString().isNotEmpty) merged[k] = v;
          });
          cached[cIdx] = merged;
        } else {
          cached.add(Map<String, dynamic>.from(user));
        }
        await _prefs.setString(_kCachedUsers, jsonEncode(cached));
      }
    } catch (_) {}
  }

  // ═══════════════════════════════════════════════════════════════
  //  ✅ NEW (admin v5): DELETE USER
  //  Removes a user (and cached copy) by username.
  // ═══════════════════════════════════════════════════════════════
  static Future<void> deleteUser(String username) async {
    final uname = username.trim();
    if (uname.isEmpty) return;

    final users = await getUsers();
    users.removeWhere(
        (u) => (u['username']?.toString() ?? '').trim() == uname);
    await _prefs.setString(_kUsers, jsonEncode(users));

    try {
      final cached = await getCachedUsers();
      if (cached.isNotEmpty) {
        cached.removeWhere(
            (u) => (u['username']?.toString() ?? '').trim() == uname);
        await _prefs.setString(_kCachedUsers, jsonEncode(cached));
      }
    } catch (_) {}
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

    // ✅ GPS Location fields (optional - may be null if GPS unavailable)
    // incident['latitude']        - GPS latitude
    // incident['longitude']       - GPS longitude
    // incident['locationAccuracy'] - GPS accuracy in meters
    // incident['locationAddress']  - Human-readable address
    // incident['locationTimestamp'] - When GPS was captured

    // ✅ FIX: Strip imageBase64 before local storage to prevent
    // QuotaExceededError. Images are already uploaded to Cloudinary
    // and sent to Google Sheets separately — no need to store locally.
    final toStore = Map<String, dynamic>.from(incident);
    toStore.remove('imageBase64');

    // Also strip imageBase64 from any existing entries (in case purge hasn't run yet)
    for (final existing in all) {
      existing.remove('imageBase64');
    }

    final existingIdx = all.indexWhere(
        (i) => i['id']?.toString() == toStore['id']?.toString());
    if (existingIdx >= 0) {
      all[existingIdx] = toStore;
    } else {
      all.add(toStore);
    }

    try {
      await _prefs.setString(_kIncidents, jsonEncode(all));
    } catch (e) {
      // If still over quota (unlikely after stripping images), try removing
      // oldest incidents to make room
      if (e.toString().contains('QuotaExceeded')) {
        // Keep only last 50 incidents
        all.sort((a, b) => (b['date'] ?? '').toString()
            .compareTo((a['date'] ?? '').toString()));
        final trimmed = all.take(50).toList();
        await _prefs.setString(_kIncidents, jsonEncode(trimmed));
      } else {
        rethrow;
      }
    }
  }

  static Future<void> deleteIncident(String id) async {
    final incidents = await getIncidents();
    incidents.removeWhere((i) => i['id']?.toString() == id);
    await _prefs.setString(_kIncidents, jsonEncode(incidents));
  }

  // ═══════════════════════════════════════════════════════════════
  //  ✅ NEW (admin v5): BULK REPLACE — used by Backup & Restore
  //  Wipes the bucket and writes the supplied list verbatim.
  // ═══════════════════════════════════════════════════════════════
  static Future<void> replaceAllIncidents(
      List<Map<String, dynamic>> incidents) async {
    // Strip imageBase64 to prevent storage quota overflow
    final cleaned = incidents.map((inc) {
      final copy = Map<String, dynamic>.from(inc);
      copy.remove('imageBase64');
      return copy;
    }).toList();
    await _prefs.setString(_kIncidents, jsonEncode(cleaned));
  }

  /// ✅ FIX: Purge bloated imageBase64 fields from existing stored incidents.
  /// Call this once on app startup to reclaim storage quota.
  /// Returns number of incidents cleaned.
  static Future<int> purgeStoredImages() async {
    final raw = _prefs.getString(_kIncidents);
    if (raw == null) return 0;

    try {
      final list = (jsonDecode(raw) as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      int cleaned = 0;
      for (final inc in list) {
        if (inc.containsKey('imageBase64') &&
            inc['imageBase64'] != null &&
            inc['imageBase64'].toString().length > 10) {
          inc.remove('imageBase64');
          cleaned++;
        }
      }
      if (cleaned > 0) {
        await _prefs.setString(_kIncidents, jsonEncode(list));
      }
      return cleaned;
    } catch (_) {
      return 0;
    }
  }

  static Future<void> replaceAllUsers(
      List<Map<String, dynamic>> users) async {
    await _prefs.setString(_kUsers, jsonEncode(users));
  }

  static Future<void> replaceAllKnowledgeDocs(
      List<Map<String, dynamic>> docs) async {
    await _prefs.setString(_kKbDocs, jsonEncode(docs));
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

  static Future<void> addKnowledgeDoc({
    required String title,
    required String content,
    String? source,
  }) async {
    final all = await getKnowledgeDocs();
    all.add({
      'id':         '${DateTime.now().millisecondsSinceEpoch}-${all.length}',
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

  // ═══════════════════════════════════════════════════════════════
  //  ✅ NEW: SEED KNOWLEDGE BASE
  //  Wipes existing KB (if replace=true), loads 38 default entries
  //  covering Factories Act 1948 + Chhattisgarh/Odisha/TN/Bihar rules.
  //  Returns count of entries added.
  // ═══════════════════════════════════════════════════════════════
  static Future<int> seedKnowledgeBase({bool replace = true}) async {
    if (replace) {
      await _prefs.remove(_kKbDocs);
    }

    final all      = <Map<String, dynamic>>[];
    final userName = (await getCurrentUser())?['name'] ?? 'system-seed';
    int added = 0;

    for (final entry in KbSeedData.entries) {
      try {
        all.add({
          'id':         'seed-${DateTime.now().millisecondsSinceEpoch}-$added',
          'title':      entry['title']  ?? 'Untitled',
          'content':    entry['content'] ?? '',
          'source':     entry['source']  ?? 'Default seed',
          'uploadedAt': DateTime.now().toIso8601String(),
          'uploadedBy': userName,
        });
        added++;
      } catch (_) {
        // Skip the one bad entry, continue
      }
    }

    // If not replacing, merge with existing KB first
    if (!replace) {
      final existing = await getKnowledgeDocs();
      all.insertAll(0, existing);
    }

    await _prefs.setString(_kKbDocs, jsonEncode(all));
    return added;
  }

  // ═══════════════════════════════════════════════════════════════
  //  ✅ NEW: RESET ALL DATA
  //  Clears incidents + feedback + sync caches.
  //  Optionally clears KB / users / login.
  // ═══════════════════════════════════════════════════════════════
  static Future<void> resetAllData({
    bool keepUsers = true,
    bool keepKb    = true,
    bool keepLogin = true,
  }) async {
    // 1. Always clear incidents
    await _prefs.remove(_kIncidents);

    // 2. Always clear feedback/learning data linked to past scans
    await _prefs.remove(_kFeedback);
    await _prefs.remove(_kCustomHazards);

    // 3. Clear best-effort caches if they exist (no-op if absent)
    await _prefs.remove('image_hashes');
    await _prefs.remove('sync_queue');
    await _prefs.remove('pending_pdfs');
    await _prefs.remove('chat_history');

    // 4. Optional clears
    if (!keepKb)    await _prefs.remove(_kKbDocs);
    if (!keepUsers) {
      await _prefs.remove(_kUsers);
      await _prefs.remove(_kCachedUsers);
    }
    if (!keepLogin) await _prefs.remove(_kCurrentUser);
  }

  // ═══════════════════════════════════════════════════════════════
  //  ✅ NEW: DATA COUNTS — for confirmation dialogs
  // ═══════════════════════════════════════════════════════════════
  static Future<Map<String, int>> dataCounts() async {
    int incidents = 0, kb = 0, users = 0;
    try {
      final raw = _prefs.getString(_kIncidents);
      if (raw != null) {
        final list = jsonDecode(raw);
        if (list is List) incidents = list.length;
      }
    } catch (_) {}
    try {
      final raw = _prefs.getString(_kKbDocs);
      if (raw != null) {
        final list = jsonDecode(raw);
        if (list is List) kb = list.length;
      }
    } catch (_) {}
    try {
      final raw = _prefs.getString(_kUsers);
      if (raw != null) {
        final list = jsonDecode(raw);
        if (list is List) users = list.length;
      }
    } catch (_) {}
    return {'incidents': incidents, 'kb': kb, 'users': users};
  }
}
