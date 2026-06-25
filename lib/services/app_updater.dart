// lib/services/app_updater.dart
// Silent auto-update service — downloads APK in background and installs
// with minimal/no user interaction via Android PackageInstaller API.

import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/material.dart';

class AppUpdater {
  // ── Config ─────────────────────────────────────────────────────────────────
  static const String _owner = 'abhibond1986';
  static const String _repo = 'Safety-Lens-V2';

  /// Current app version — update this to match pubspec.yaml on each release
  static const String currentVersion = '1.0.0';

  /// How often to check for updates (in hours)
  static const int _checkIntervalHours = 6; // check every 6 hours

  static const String _lastCheckKey = 'app_updater_last_check';
  static const String _lastAutoInstallKey = 'app_updater_last_auto_install';

  /// Method channel for native install
  static const MethodChannel _channel =
      MethodChannel('com.sail.safety/app_updater');

  /// Initialize — check for updates and silently install if available.
  /// Call this from main.dart after app startup.
  static Future<void> init() async {
    if (kIsWeb) return;
    if (!Platform.isAndroid) return;

    final prefs = await SharedPreferences.getInstance();
    final lastCheck = prefs.getInt(_lastCheckKey) ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    final hoursSinceLastCheck = (now - lastCheck) / (1000 * 60 * 60);

    if (hoursSinceLastCheck < _checkIntervalHours) {
      debugPrint('[AppUpdater] Skipping — last check ${hoursSinceLastCheck.toStringAsFixed(1)}h ago');
      return;
    }

    await prefs.setInt(_lastCheckKey, now);

    try {
      final updateInfo = await _checkForUpdate();
      if (updateInfo != null) {
        debugPrint('[AppUpdater] Update available: v${updateInfo.version}');
        await _silentDownloadAndInstall(updateInfo);
      } else {
        debugPrint('[AppUpdater] App is up to date');
      }
    } catch (e) {
      debugPrint('[AppUpdater] Check failed: $e');
    }
  }

  /// Check GitHub Releases API for a newer version
  static Future<UpdateInfo?> _checkForUpdate() async {
    final url = Uri.parse(
        'https://api.github.com/repos/$_owner/$_repo/releases/latest');

    final response = await http.get(url, headers: {
      'Accept': 'application/vnd.github.v3+json',
    }).timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw Exception('GitHub API returned ${response.statusCode}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final tagName = (data['tag_name'] ?? '') as String;
    final releaseName = (data['name'] ?? '') as String;
    final body = (data['body'] ?? '') as String;

    final remoteVersion = tagName.replaceAll(RegExp(r'^v'), '');

    if (!_isNewerVersion(remoteVersion, currentVersion)) {
      return null;
    }

    // Find APK asset in release
    String? apkUrl;
    int? apkSize;
    final assets = (data['assets'] as List?) ?? [];
    for (final asset in assets) {
      final name = (asset['name'] ?? '') as String;
      if (name.toLowerCase().endsWith('.apk')) {
        apkUrl = asset['browser_download_url'] as String?;
        apkSize = asset['size'] as int?;
        break;
      }
    }

    if (apkUrl == null) return null; // No APK attached to release

    return UpdateInfo(
      version: remoteVersion,
      releaseName: releaseName,
      releaseNotes: body,
      downloadUrl: apkUrl,
      apkSize: apkSize ?? 0,
      publishedAt: data['published_at'] as String? ?? '',
    );
  }

  /// Compare semantic versions: returns true if remote > current
  static bool _isNewerVersion(String remote, String current) {
    try {
      final remoteParts = remote.split('.').map(int.parse).toList();
      final currentParts = current.split('.').map(int.parse).toList();

      while (remoteParts.length < 3) remoteParts.add(0);
      while (currentParts.length < 3) currentParts.add(0);

      for (int i = 0; i < 3; i++) {
        if (remoteParts[i] > currentParts[i]) return true;
        if (remoteParts[i] < currentParts[i]) return false;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Download APK silently to internal storage, then trigger native install
  static Future<void> _silentDownloadAndInstall(UpdateInfo info) async {
    try {
      debugPrint('[AppUpdater] Downloading APK from ${info.downloadUrl}');

      // Download to app's internal cache directory (no permissions needed)
      final cacheDir = await getTemporaryDirectory();
      final apkFile = File('${cacheDir.path}/safety_lens_update.apk');

      // Clean up old APK if present
      if (await apkFile.exists()) {
        await apkFile.delete();
      }

      // Stream-download the APK
      final request = http.Request('GET', Uri.parse(info.downloadUrl));
      final streamedResponse = await request.send().timeout(
        const Duration(minutes: 10),
      );

      if (streamedResponse.statusCode != 200) {
        // Handle GitHub redirect (302 → actual download URL)
        if (streamedResponse.statusCode == 302) {
          final redirectUrl = streamedResponse.headers['location'];
          if (redirectUrl != null) {
            final redirectResponse = await http.get(Uri.parse(redirectUrl))
                .timeout(const Duration(minutes: 10));
            await apkFile.writeAsBytes(redirectResponse.bodyBytes);
          } else {
            throw Exception('Redirect with no location header');
          }
        } else {
          throw Exception('Download failed: HTTP ${streamedResponse.statusCode}');
        }
      } else {
        final bytes = await streamedResponse.stream.toBytes();
        await apkFile.writeAsBytes(bytes);
      }

      debugPrint('[AppUpdater] APK downloaded: ${apkFile.lengthSync()} bytes');

      // Verify file is reasonable size (at least 1MB — not a 404 page)
      if (apkFile.lengthSync() < 1024 * 1024) {
        debugPrint('[AppUpdater] Downloaded file too small — likely not a valid APK');
        await apkFile.delete();
        return;
      }

      // Trigger silent install via native Android code
      final result = await _channel.invokeMethod('installApk', {
        'apkPath': apkFile.path,
      });

      debugPrint('[AppUpdater] Install triggered: $result');

      // Record that we triggered an install for this version
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_lastAutoInstallKey, info.version);
    } catch (e) {
      debugPrint('[AppUpdater] Silent install failed: $e');
    }
  }

  /// Force check now (e.g., from settings screen)
  static Future<String> checkNow() async {
    try {
      final info = await _checkForUpdate();
      if (info != null) {
        await _silentDownloadAndInstall(info);
        return 'Update v${info.version} downloading and installing...';
      }
      return 'App is up to date (v$currentVersion)';
    } catch (e) {
      return 'Check failed: $e';
    }
  }
}

/// Update information model
class UpdateInfo {
  final String version;
  final String releaseName;
  final String releaseNotes;
  final String downloadUrl;
  final int apkSize;
  final String publishedAt;

  UpdateInfo({
    required this.version,
    required this.releaseName,
    required this.releaseNotes,
    required this.downloadUrl,
    required this.apkSize,
    required this.publishedAt,
  });
}
