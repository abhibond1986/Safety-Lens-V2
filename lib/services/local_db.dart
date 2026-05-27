import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class LocalDB {
  static late SharedPreferences _prefs;
  static const _kUsers = 'users';
  static const _kIncidents = 'incidents';
  static const _kCurrentUser = 'current_user';
  static const _kKbTopics = 'kb_topics';

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
          'pno': 'SAIL-SSO-001', 'mobile': '9999999999', 'email': 'abhishek@sail.in',
          'isAdmin': true,
        },
        {
          'username': 'demo', 'password': 'demo',
          'name': 'R.K. Sharma', 'designation': 'Sr. Safety Officer',
          'plant': 'BSP Bhilai',
          'pno': 'BSP-2024-001', 'mobile': '9876543210', 'email': 'rks@sail.in',
          'isAdmin': false,
        },
      ];
      await _prefs.setString(_kUsers, jsonEncode(seed));
    }
    if (_prefs.getString(_kIncidents) == null) {
      final now = DateTime.now();
      final seedIncidents = [
        {
          'id': '1', 'title': 'No Fall Arrest at Formwork', 'plant': 'BSP Bhilai',
          'dept': 'Civil Construction', 'location': 'BF-2 Cast House',
          'severity': 'CRITICAL', 'wsaCategory': 'Fall from Height',
          'date': now.subtract(const Duration(days: 6)).toIso8601String(),
          'status': 'OPEN', 'reportedBy': 'R.K. Sharma', 'type': 'AI_SCAN',
          'desc': 'Worker observed at height without harness',
        },
        {
          'id': '2', 'title': 'Crane Near Miss', 'plant': 'BSP Bhilai',
          'dept': 'Rolling Mill', 'location': 'Bay 4',
          'severity': 'CRITICAL', 'wsaCategory': 'Hit / Caught / Pressed',
          'date': now.subtract(const Duration(days: 4)).toIso8601String(),
          'status': 'INVESTIGATING', 'reportedBy': 'Priya Singh', 'type': 'NEAR_MISS',
          'desc': 'Crane load swung close to worker',
        },
        {
          'id': '3', 'title': 'Slip Hazard on Walkway', 'plant': 'DSP Durgapur',
          'dept': 'Coke Oven', 'location': 'Pusher side',
          'severity': 'MEDIUM', 'wsaCategory': 'Slip / Fall',
          'date': now.subtract(const Duration(days: 3)).toIso8601String(),
          'status': 'CLOSED', 'reportedBy': 'Rajesh Kumar', 'type': 'NEAR_MISS',
          'desc': 'Oil spillage on walkway',
        },
        {
          'id': '4', 'title': 'Hot Metal Splash Risk', 'plant': 'RSP Rourkela',
          'dept': 'SMS', 'location': 'Caster 2',
          'severity': 'HIGH', 'wsaCategory': 'Hot Metal / Slag / Sub',
          'date': now.subtract(const Duration(days: 2)).toIso8601String(),
          'status': 'CLOSED', 'reportedBy': 'Priya Singh', 'type': 'AI_SCAN',
          'desc': 'Splash guard missing on caster',
        },
        {
          'id': '5', 'title': 'PPE Gap — Helmet Missing', 'plant': 'BSL Bokaro',
          'dept': 'Blast Furnace', 'location': 'BF-3 Stock house',
          'severity': 'HIGH', 'wsaCategory': 'Other',
          'date': now.subtract(const Duration(days: 2)).toIso8601String(),
          'status': 'OPEN', 'reportedBy': 'Rajesh Kumar', 'type': 'AI_SCAN',
          'desc': 'Worker without helmet near furnace',
        },
        {
          'id': '6', 'title': 'Electrical Panel Open', 'plant': 'ISP Burnpur',
          'dept': 'Electrical', 'location': 'Sub-station 4',
          'severity': 'HIGH', 'wsaCategory': 'Electrical',
          'date': now.subtract(const Duration(days: 1)).toIso8601String(),
          'status': 'OPEN', 'reportedBy': 'Abhishek Kumar', 'type': 'NEAR_MISS',
          'desc': 'Live panel open without barrier',
        },
        {
          'id': '7', 'title': 'Hose Trip Hazard', 'plant': 'BSP Bhilai',
          'dept': 'Maintenance', 'location': 'Workshop',
          'severity': 'LOW', 'wsaCategory': 'Slip / Fall',
          'date': now.subtract(const Duration(days: 1)).toIso8601String(),
          'status': 'OPEN', 'reportedBy': 'Priya Singh', 'type': 'NEAR_MISS',
          'desc': 'Compressed air hose across walkway',
        },
        {
          'id': '8', 'title': 'Loose Cable Trip Risk', 'plant': 'ISP Burnpur',
          'dept': 'Rolling Mill', 'location': 'Bay 2',
          'severity': 'MEDIUM', 'wsaCategory': 'Electrical',
          'date': now.toIso8601String(),
          'status': 'OPEN', 'reportedBy': 'Abhishek Kumar', 'type': 'NEAR_MISS',
          'desc': 'Loose electrical cable across walkway',
        },
      ];
      await _prefs.setString(_kIncidents, jsonEncode(seedIncidents));
    }
  }

  // ===== Auth =====
  static Future<Map<String, dynamic>?> signIn(String username, String password) async {
    final users = await getUsers();
    for (final u in users) {
      if ((u['username'] == username || u['email'] == username) && u['password'] == password) {
        await _prefs.setString(_kCurrentUser, jsonEncode(u));
        return u;
      }
    }
    return null;
  }

  static Future<Map<String, dynamic>?> register(Map<String, dynamic> userData) async {
    final users = await getUsers();
    // Check duplicate
    if (users.any((u) => u['username'] == userData['username'])) {
      return null;
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

  // ===== Users =====
  static Future<List<Map<String, dynamic>>> getUsers() async {
    final raw = _prefs.getString(_kUsers);
    if (raw == null) return [];
    return (jsonDecode(raw) as List).map((e) => Map<String, dynamic>.from(e)).toList();
  }

  // ===== Incidents =====
  static Future<List<Map<String, dynamic>>> getIncidents() async {
    final raw = _prefs.getString(_kIncidents);
    if (raw == null) return [];
    final list = (jsonDecode(raw) as List).map((e) => Map<String, dynamic>.from(e)).toList();
    list.sort((a, b) => (b['date'] ?? '').toString().compareTo((a['date'] ?? '').toString()));
    return list;
  }

  static Future<void> saveIncident(Map<String, dynamic> incident) async {
    final all = await getIncidents();
    final user = await getCurrentUser();
    incident['id'] = DateTime.now().millisecondsSinceEpoch.toString();
    incident['date'] = DateTime.now().toIso8601String();
    incident['reportedBy'] = user?['name'] ?? 'Unknown';
    incident['reporterPno'] = user?['pno'] ?? '';
    incident['status'] ??= 'OPEN';
    all.add(incident);
    await _prefs.setString(_kIncidents, jsonEncode(all));
  }

  // ===== Plant stats =====
  static Future<Map<String, Map<String, int>>> getPlantStats() async {
    final inc = await getIncidents();
    final result = <String, Map<String, int>>{};
    final plants = ['BSP Bhilai', 'DSP Durgapur', 'RSP Rourkela', 'BSL Bokaro', 'ISP Burnpur'];
    for (final p in plants) {
      final pInc = inc.where((i) => i['plant'] == p).toList();
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
}
