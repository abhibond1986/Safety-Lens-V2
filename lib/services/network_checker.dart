// lib/services/network_checker.dart
// Network connectivity checker — FIXED for Android + Web
//
// Previous bugs:
//   ❌ Used http.head() for Apps Script — Apps Script only supports GET/POST
//   ❌ connectivity_plus v5 returns List<ConnectivityResult>, not single value
//   ❌ On web: connectivity_plus unreliable + google.com CORS blocked → always offline
//   Result: Backend always appeared "unreachable" → permanent offline mode
//
// Fixes:
//   ✅ Uses GET with lightweight ping to Google (fast, reliable)
//   ✅ Backend check uses GET with action=ping (Apps Script responds to GET)
//   ✅ connectivity_plus v5 List<ConnectivityResult> handled correctly
//   ✅ Web: always returns online (browser handles connectivity natively)

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;

class NetworkChecker {
  static final Connectivity _connectivity = Connectivity();

  /// Check if device has internet connectivity
  static Future<bool> hasInternet() async {
    try {
      final results = await _connectivity.checkConnectivity();
      // connectivity_plus v5+ returns List<ConnectivityResult>
      if (results is List) {
        final list = results as List;
        if (list.isEmpty) return false;
        return !list.every((r) => r == ConnectivityResult.none);
      }
      // Fallback for older API (single value)
      return results != ConnectivityResult.none;
    } catch (e) {
      print('NetworkChecker: Error checking connectivity: $e');
      // If connectivity_plus fails, assume we have internet and let the
      // actual HTTP call determine reachability
      return true;
    }
  }

  /// Quick internet check — ping a reliable endpoint (Google)
  static Future<bool> _canReachInternet() async {
    try {
      final response = await http.get(
        Uri.parse('https://www.google.com/generate_204'),
      ).timeout(const Duration(seconds: 5));
      return response.statusCode == 204 || response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Verify backend is reachable
  /// ✅ FIX: Uses GET (not HEAD) — Apps Script only supports GET/POST
  static Future<bool> canReachBackend({int maxRetries = 1}) async {
    const backendUrl = 'https://script.google.com/macros/s/AKfycbxLSH2Z-X6iQPw0rY2O7T0SYSDU7bzikpWq-G_ysOT_noU-IwgSHYNr3AKbwPFPZYginw/exec';

    for (int attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        print('NetworkChecker: Backend check attempt ${attempt + 1}/${maxRetries + 1}');
        // ✅ Use GET with a lightweight ping action — Apps Script handles GET
        final response = await http.get(
          Uri.parse('$backendUrl?action=ping'),
          headers: {'Accept': 'application/json'},
        ).timeout(const Duration(seconds: 12));

        // Apps Script returns 200 on success, or 302 redirect (which http follows)
        if (response.statusCode >= 200 && response.statusCode < 400) {
          print('NetworkChecker: Backend is reachable ✓ (status: ${response.statusCode})');
          return true;
        }

        if (attempt < maxRetries) {
          await Future.delayed(Duration(seconds: 2 * (attempt + 1)));
        }
      } catch (e) {
        print('NetworkChecker: Backend check failed (attempt ${attempt + 1}): $e');
        if (attempt < maxRetries) {
          await Future.delayed(Duration(seconds: 2 * (attempt + 1)));
        }
      }
    }

    print('NetworkChecker: Backend unreachable after ${maxRetries + 1} attempts');
    return false;
  }

  /// Get network status stream
  static Stream<ConnectivityResult> get connectivityStream =>
      _connectivity.onConnectivityChanged;

  /// Summary of current network state
  /// ✅ FIX: More lenient — if we have internet, assume backend is reachable
  /// and let the actual API call handle failures with retry logic.
  /// This prevents the overly-aggressive "offline fallback" on Android.
  static Future<Map<String, bool>> getNetworkStatus() async {
    // ✅ WEB FIX: On web, always report online.
    // connectivity_plus uses Navigator.onLine which is unreliable, and
    // _canReachInternet() fails due to CORS (can't fetch google.com from browser).
    // The browser handles connectivity natively — if network is truly down,
    // the actual Cloudinary/Apps Script calls will fail with their own retry logic.
    if (kIsWeb) {
      return {
        'hasInternet': true,
        'backendReachable': true,
        'isOnline': true,
      };
    }

    final hasNet = await hasInternet();

    // If connectivity_plus says no internet, do a real check
    // (connectivity_plus can be wrong on some Android devices)
    if (!hasNet) {
      final realCheck = await _canReachInternet();
      if (realCheck) {
        print('NetworkChecker: connectivity_plus said offline but internet works — proceeding online');
        return {
          'hasInternet': true,
          'backendReachable': true,
          'isOnline': true,
        };
      }
      return {
        'hasInternet': false,
        'backendReachable': false,
        'isOnline': false,
      };
    }

    // ✅ KEY FIX: Don't pre-check backend reachability with a separate request.
    // Just report that we have internet. The actual Cloudinary upload + API call
    // in GeminiVision has its own retry logic and will fallback if it actually fails.
    // This eliminates the false "backend unreachable" that caused permanent offline mode.
    return {
      'hasInternet': true,
      'backendReachable': true,
      'isOnline': true,
    };
  }
}
