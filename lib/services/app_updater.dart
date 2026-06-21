// lib/services/app_updater.dart
// Auto-update service — checks for new APK every 2 days and prompts user to install

import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/material.dart';

class AppUpdater {
  // ── Config ─────────────────────────────────────────────────────────────────
  /// GitHub owner/repo — change if repo moves
  static const String _owner = 'abhibond1986';
  static const String _repo = 'Safety-Lens-V2';

  /// Current app version — auto-set during build via --build-name flag
  /// If you build locally, update this manually to match pubspec.yaml
  static const String currentVersion = '1.0.0';

  /// Fallback: read version from package_info if available
  /// (currentVersion is the compile-time constant used for comparison)

  /// How often to check for updates (in hours)
  static const int _checkIntervalHours = 48; // every 2 days

  static const String _lastCheckKey = 'app_updater_last_check';
  static const String _skippedVersionKey = 'app_updater_skipped_version';

  /// Initialize and check for updates silently in background
  /// Call this from main.dart after app startup
  static Future<void> init() async {
    // Skip on web platform
    if (kIsWeb) return;
    // Only run on Android
    if (!Platform.isAndroid) return;

    // Check if enough time has passed since last check
    final prefs = await SharedPreferences.getInstance();
    final lastCheck = prefs.getInt(_lastCheckKey) ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    final hoursSinceLastCheck = (now - lastCheck) / (1000 * 60 * 60);

    if (hoursSinceLastCheck < _checkIntervalHours) {
      debugPrint('[AppUpdater] Skipping check — last check was ${hoursSinceLastCheck.toStringAsFixed(1)}h ago');
      return;
    }

    // Save check timestamp
    await prefs.setInt(_lastCheckKey, now);

    // Check for update in background
    try {
      final updateInfo = await _checkForUpdate();
      if (updateInfo != null) {
        _pendingUpdate = updateInfo;
        debugPrint('[AppUpdater] Update available: ${updateInfo.version}');
      } else {
        debugPrint('[AppUpdater] App is up to date');
      }
    } catch (e) {
      debugPrint('[AppUpdater] Check failed (will retry later): $e');
    }
  }

  /// Pending update info (set after background check)
  static UpdateInfo? _pendingUpdate;

  /// Returns true if an update is available
  static bool get hasUpdate => _pendingUpdate != null;

  /// Gets the pending update info
  static UpdateInfo? get pendingUpdate => _pendingUpdate;

  /// Show update dialog if update is available
  /// Call this from your home screen's initState or after build
  static Future<void> showUpdateDialogIfAvailable(BuildContext context) async {
    if (_pendingUpdate == null) return;
    if (!context.mounted) return;

    // Check if user previously skipped this version
    final prefs = await SharedPreferences.getInstance();
    final skippedVersion = prefs.getString(_skippedVersionKey);
    if (skippedVersion == _pendingUpdate!.version) return;

    // Show non-intrusive update dialog
    if (!context.mounted) return;
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => _UpdateDialog(
        updateInfo: _pendingUpdate!,
        onUpdate: () {
          Navigator.pop(ctx);
          _downloadAndInstall(_pendingUpdate!);
        },
        onSkip: () async {
          await prefs.setString(_skippedVersionKey, _pendingUpdate!.version);
          if (ctx.mounted) Navigator.pop(ctx);
        },
        onLater: () => Navigator.pop(ctx),
      ),
    );
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

    // Extract version number from tag (e.g., "v1.2.0" → "1.2.0")
    final remoteVersion = tagName.replaceAll(RegExp(r'^v'), '');

    // Compare versions
    if (!_isNewerVersion(remoteVersion, currentVersion)) {
      return null;
    }

    // Find APK asset in release
    String? apkUrl;
    final assets = (data['assets'] as List?) ?? [];
    for (final asset in assets) {
      final name = (asset['name'] ?? '') as String;
      if (name.toLowerCase().endsWith('.apk')) {
        apkUrl = asset['browser_download_url'] as String?;
        break;
      }
    }

    // If no APK asset found, use the release page URL
    apkUrl ??= data['html_url'] as String? ??
        'https://github.com/$_owner/$_repo/releases/latest';

    return UpdateInfo(
      version: remoteVersion,
      releaseName: releaseName,
      releaseNotes: body,
      downloadUrl: apkUrl,
      publishedAt: data['published_at'] as String? ?? '',
    );
  }

  /// Compare semantic versions: returns true if remote > current
  static bool _isNewerVersion(String remote, String current) {
    try {
      final remoteParts = remote.split('.').map(int.parse).toList();
      final currentParts = current.split('.').map(int.parse).toList();

      // Pad to same length
      while (remoteParts.length < 3) remoteParts.add(0);
      while (currentParts.length < 3) currentParts.add(0);

      for (int i = 0; i < 3; i++) {
        if (remoteParts[i] > currentParts[i]) return true;
        if (remoteParts[i] < currentParts[i]) return false;
      }
      return false; // equal
    } catch (_) {
      return false;
    }
  }

  /// Download APK and trigger install
  static Future<void> _downloadAndInstall(UpdateInfo info) async {
    try {
      final uri = Uri.parse(info.downloadUrl);
      if (await canLaunchUrl(uri)) {
        // Open in browser — Android will handle APK download & install
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('[AppUpdater] Download failed: $e');
    }
  }

  /// Force check now (e.g., from settings screen)
  static Future<UpdateInfo?> checkNow() async {
    try {
      final info = await _checkForUpdate();
      _pendingUpdate = info;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_lastCheckKey, DateTime.now().millisecondsSinceEpoch);
      return info;
    } catch (e) {
      debugPrint('[AppUpdater] Manual check failed: $e');
      return null;
    }
  }
}

/// Update information model
class UpdateInfo {
  final String version;
  final String releaseName;
  final String releaseNotes;
  final String downloadUrl;
  final String publishedAt;

  UpdateInfo({
    required this.version,
    required this.releaseName,
    required this.releaseNotes,
    required this.downloadUrl,
    required this.publishedAt,
  });
}

/// Update dialog widget
class _UpdateDialog extends StatelessWidget {
  final UpdateInfo updateInfo;
  final VoidCallback onUpdate;
  final VoidCallback onSkip;
  final VoidCallback onLater;

  const _UpdateDialog({
    required this.updateInfo,
    required this.onUpdate,
    required this.onSkip,
    required this.onLater,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(children: [
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            color: const Color(0xFF7C4DFF).withOpacity(0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.system_update_rounded,
              color: Color(0xFF7C4DFF), size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Update Available',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            Text('v${updateInfo.version}',
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        )),
      ]),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (updateInfo.releaseNotes.isNotEmpty) ...[
            const Text("What's new:",
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 120),
              child: SingleChildScrollView(
                child: Text(
                  updateInfo.releaseNotes.length > 300
                      ? '${updateInfo.releaseNotes.substring(0, 300)}...'
                      : updateInfo.releaseNotes,
                  style: const TextStyle(fontSize: 12, height: 1.5),
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF00E676).withOpacity(0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF00E676).withOpacity(0.3)),
            ),
            child: const Row(children: [
              Icon(Icons.info_outline, size: 14, color: Color(0xFF00E676)),
              SizedBox(width: 8),
              Expanded(child: Text(
                'Update ensures you have the latest safety features and bug fixes.',
                style: TextStyle(fontSize: 10, height: 1.4),
              )),
            ]),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: onSkip,
          child: const Text('Skip this version',
              style: TextStyle(color: Colors.grey, fontSize: 12)),
        ),
        TextButton(
          onPressed: onLater,
          child: const Text('Later',
              style: TextStyle(fontSize: 12)),
        ),
        ElevatedButton(
          onPressed: onUpdate,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF7C4DFF),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8)),
          ),
          child: const Text('Update Now',
              style: TextStyle(color: Colors.white,
                  fontWeight: FontWeight.w700, fontSize: 12)),
        ),
      ],
    );
  }
}
