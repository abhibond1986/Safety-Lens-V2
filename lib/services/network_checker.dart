// lib/services/network_checker.dart
// NEW: Network connectivity checker with retry logic for mobile optimization

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;

class NetworkChecker {
  static final Connectivity _connectivity = Connectivity();

  /// Check if device has internet connectivity
  static Future<bool> hasInternet() async {
    try {
      final result = await _connectivity.checkConnectivity();
      return result != ConnectivityResult.none;
    } catch (e) {
      print('NetworkChecker: Error checking connectivity: $e');
      return false;
    }
  }

  /// Verify backend is reachable with retry
  static Future<bool> canReachBackend({int maxRetries = 2}) async {
    const backendUrl = 'https://script.google.com/macros/s/AKfycbxLSH2Z-X6iQPw0rY2O7T0SYSDU7bzikpWq-G_ysOT_noU-IwgSHYNr3AKbwPFPZYginw/exec';
    
    for (int attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        print('NetworkChecker: Backend check attempt ${attempt + 1}/${maxRetries + 1}');
        final response = await http.head(
          Uri.parse(backendUrl),
          headers: {'Accept': 'application/json'},
        ).timeout(const Duration(seconds: 10));
        
        if (response.statusCode >= 200 && response.statusCode < 400) {
          print('NetworkChecker: Backend is reachable ✓');
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
  static Future<Map<String, bool>> getNetworkStatus() async {
    final hasNet = await hasInternet();
    final canReach = hasNet ? await canReachBackend(maxRetries: 1) : false;
    
    return {
      'hasInternet': hasNet,
      'backendReachable': canReach,
      'isOnline': hasNet && canReach,
    };
  }
}
