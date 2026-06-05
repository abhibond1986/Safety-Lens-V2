// ════════════════════════════════════════════════════════════════
//  ADD THIS METHOD to lib/services/sync_service.dart
//  Place it after the fetchIncidents() method (around line 115)
// ════════════════════════════════════════════════════════════════

  /// Fetch all registered users from the backend (for user switcher)
  static Future<List<Map<String, dynamic>>> fetchUsers() async {
    if (!await isConfigured) return [];
    try {
      final url = await getBackendUrl();
      final response = await http.get(
        Uri.parse('$url?action=listUsers'),
      ).timeout(const Duration(seconds: 20));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        // backend returns { success: true, users: [...] }
        if (data['success'] == true && data['users'] is List) {
          return (data['users'] as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
        }
        // backward compat — old backend returns { ok: true, items: [...] }
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


// ════════════════════════════════════════════════════════════════
//  ADD THIS METHOD to lib/services/local_db.dart
//  Returns all locally stored users
// ════════════════════════════════════════════════════════════════

  // In LocalDB class — add this static method:
  static Future<List<Map<String, dynamic>>> getAllUsers() async {
    // If you store users locally (e.g. after fetching from Sheets), return them.
    // If not stored yet, return empty list — dashboard will fetch from Sheets.
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('cached_users');
      if (raw == null || raw.isEmpty) return [];
      final list = jsonDecode(raw) as List;
      return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      return [];
    }
  }

  // Also add this to cache users after fetching:
  static Future<void> cacheUsers(List<Map<String, dynamic>> users) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('cached_users', jsonEncode(users));
  }
