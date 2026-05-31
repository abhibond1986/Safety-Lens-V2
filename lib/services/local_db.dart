import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class LocalDB {
  static late SharedPreferences _prefs;

  static const _kUsers = 'users';
  static const _kCurrent = 'current_user';
  static const _kIncidents = 'incidents';
  static const _kFeedback = 'feedback_corrections';
  static const _kCustomHazards = 'custom_hazards';
  static const _kKbDocs = 'kb_documents';

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    await _seedDefaultUser();
  }

  static Future<void> _seedDefaultUser() async {
    final users = await getUsers();
    if (users.isEmpty) {
      users.add({
        'uid': '1',
        'username': 'abhishek.kumar',
        'password': 'demo',
        'name': 'Abhishek Kumar',
        'designation': 'AGM',
        'plant': 'SAIL Safety Organisation',
        'department': 'Safety',
        'pno': 'EMP001',
        'mobile': '+91-9876543210',
        'email': 'abhishek.kumar@sail.in',
        'isAdmin': true,
        'createdAt': DateTime.now().toIso8601String(),
      });
      await _prefs.setString(_kUsers, jsonEncode(users));
    }
  }

  // ===== USERS =====
  static Future<List<Map<String, dynamic>>> getUsers() async {
    final raw = _prefs.getString(_kUsers);
    if (raw == null) return [];
    return (jsonDecode(raw) as List).map((e) => Map<String, dynamic>.from(e)).toList();
  }

  static Future<Map<String, dynamic>?> login(String username, String password) async {
    final users = await getUsers();
    final user = users.firstWhere(
      (u) => u['username'] == username && u['password'] == password,
      orElse: () => {},
    );
    if (user.isEmpty) return null;
    await _prefs.setString(_kCurrent, jsonEncode(user));
    return user;
  }

  static Future<Map<String, dynamic>?> register(Map<String, dynamic> userData) async {
    final users = await getUsers();
    if (users.any((u) => u['username'] == userData['username'])) {
      return null;
    }
    userData['uid'] = DateTime.now().millisecondsSinceEpoch.toString();
    userData['createdAt'] = DateTime.now().toIso8601String();
    userData['isAdmin'] ??= false;
    users.add(userData);
    await _prefs.setString(_kUsers, jsonEncode(users));
    await _prefs.setString(_kCurrent, jsonEncode(userData));
    return userData;
  }

  static Future<Map<String, dynamic>?> getCurrentUser() async {
    final raw = _prefs.getString(_kCurrent);
    if (raw == null) return null;
    return Map<String, dynamic>.from(jsonDecode(raw));
  }

  static Future<void> signOut() async {
    await _prefs.remove(_kCurrent);
  }

  // ===== INCIDENTS =====
  static Future<List<Map<String, dynamic>>> getIncidents() async {
    final raw = _prefs.getString(_kIncidents);
    if (raw == null) return [];
    return (jsonDecode(raw) as List).map((e) => Map<String, dynamic>.from(e)).toList();
  }

  static Future<void> saveIncident(Map<String, dynamic> incident) async {
    final all = await getIncidents();
    final user = await getCurrentUser();
    incident['id'] ??= DateTime.now().millisecondsSinceEpoch.toString();
    incident['date'] ??= DateTime.now().toIso8601String();
    incident['reportedBy'] ??= user?['name'] ?? 'Unknown';
    incident['reporterPno'] ??= user?['pno'] ?? '';
    incident['status'] ??= 'OPEN';

    // De-duplicate: if same id already exists, replace; else add
    final existingIdx = all.indexWhere((i) => i['id']?.toString() == incident['id']?.toString());
    if (existingIdx >= 0) {
      all[existingIdx] = incident;
    } else {
      all.add(incident);
    }
    await _prefs.setString(_kIncidents, jsonEncode(all));
  }

  // ===== STATS =====
  static Future<Map<String, Map<String, int>>> getPlantStats() async {
    final incidents = await getIncidents();
    final result = <String, Map<String, int>>{};
    final plants = ['BSP Bhilai', 'DSP Durgapur', 'RSP Rourkela', 'BSL Bokaro', 'ISP Burnpur'];
    for (final p in plants) {
      final pInc = incidents.where((i) => i['plant'] == p).toList();
      result[p] = {
        'total': pInc.length,
        'open': pInc.where((i) => i['status'] == 'OPEN').length,
        'critical': pInc.where((i) => i['severity'] == 'CRITICAL').length,
        'high': pInc.where((i) => i['severity'] == 'HIGH').length,
      };
    }
    return result;
  }

  static int calcSafetyScore(int critical, int high, int medium, int open) {
    return (100 - critical * 15 - high * 8 - medium * 3 - open * 2).clamp(0, 100);
  }

  // ===== FEEDBACK & LEARNING =====
  static Future<void> saveFeedback({
    required int imageSeed,
    required String type,
    required Map<String, dynamic> hazardData,
  }) async {
    final all = await getAllFeedback();
    all.add({
      'imageSeed': imageSeed,
      'type': type,
      'hazard': hazardData,
      'timestamp': DateTime.now().toIso8601String(),
      'user': (await getCurrentUser())?['name'] ?? 'unknown',
    });
    await _prefs.setString(_kFeedback, jsonEncode(all));
  }

  static Future<List<Map<String, dynamic>>> getAllFeedback() async {
    final raw = _prefs.getString(_kFeedback);
    if (raw == null) return [];
    return (jsonDecode(raw) as List).map((e) => Map<String, dynamic>.from(e)).toList();
  }

  static Future<List<Map<String, dynamic>>> getFeedbackForSeed(int imageSeed) async {
    final all = await getAllFeedback();
    return all.where((f) => f['imageSeed'] == imageSeed).toList();
  }

  static Future<void> addCustomHazard(Map<String, dynamic> hazard) async {
    final all = await getCustomHazards();
    hazard['addedAt'] = DateTime.now().toIso8601String();
    hazard['addedBy'] = (await getCurrentUser())?['name'] ?? 'unknown';
    all.add(hazard);
    await _prefs.setString(_kCustomHazards, jsonEncode(all));
  }

  static Future<List<Map<String, dynamic>>> getCustomHazards() async {
    final raw = _prefs.getString(_kCustomHazards);
    if (raw == null) return [];
    return (jsonDecode(raw) as List).map((e) => Map<String, dynamic>.from(e)).toList();
  }

  static Future<void> clearFeedback() async {
    await _prefs.remove(_kFeedback);
    await _prefs.remove(_kCustomHazards);
  }

  static Future<Map<String, int>> getFeedbackStats() async {
    final all = await getAllFeedback();
    return {
      'total': all.length,
      'added': all.where((f) => f['type'] == 'add').length,
      'removed': all.where((f) => f['type'] == 'remove').length,
      'reworded': all.where((f) => f['type'] == 'reword').length,
    };
  }

  // ===== KNOWLEDGE BASE =====
  static Future<void> addKnowledgeDoc({
    required String title,
    required String content,
    String? source,
  }) async {
    final all = await getKnowledgeDocs();
    all.add({
      'id': DateTime.now().millisecondsSinceEpoch.toString(),
      'title': title,
      'content': content,
      'source': source ?? 'uploaded',
      'uploadedAt': DateTime.now().toIso8601String(),
      'uploadedBy': (await getCurrentUser())?['name'] ?? 'admin',
    });
    await _prefs.setString(_kKbDocs, jsonEncode(all));
  }

  static Future<List<Map<String, dynamic>>> getKnowledgeDocs() async {
    final raw = _prefs.getString(_kKbDocs);
    if (raw == null) return [];
    return (jsonDecode(raw) as List).map((e) => Map<String, dynamic>.from(e)).toList();
  }

  static Future<void> deleteKnowledgeDoc(String id) async {
    final all = await getKnowledgeDocs();
    all.removeWhere((d) => d['id'] == id);
    await _prefs.setString(_kKbDocs, jsonEncode(all));
  }

  static Future<List<Map<String, dynamic>>> searchKnowledge(String query) async {
    final all = await getKnowledgeDocs();
    if (all.isEmpty) return [];
    final q = query.toLowerCase().split(RegExp(r'\s+')).where((w) => w.length > 2).toList();
    if (q.isEmpty) return [];

    final results = <Map<String, dynamic>>[];
    for (final doc in all) {
      final content = doc['content']?.toString() ?? '';
      final contentLower = content.toLowerCase();
      int score = 0;
      for (final word in q) {
        score += word.allMatches(contentLower).length;
      }
      if (score > 0) {
        final sentences = content.split(RegExp(r'(?<=[.!?])\s+'));
        String bestSnippet = '';
        int bestSnippetScore = 0;
        for (final s in sentences) {
          final sl = s.toLowerCase();
          int ss = 0;
          for (final word in q) {
            if (sl.contains(word)) ss++;
          }
          if (ss > bestSnippetScore) {
            bestSnippetScore = ss;
            bestSnippet = s.trim();
          }
        }
        results.add({
          'title': doc['title'],
          'snippet': bestSnippet.length > 400 ? '${bestSnippet.substring(0, 400)}...' : bestSnippet,
          'score': score,
        });
      }
    }
    results.sort((a, b) => (b['score'] as int).compareTo(a['score'] as int));
    return results.take(3).toList();
  }
}
