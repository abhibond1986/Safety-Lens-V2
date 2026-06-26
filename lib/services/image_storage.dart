// lib/services/image_storage.dart
// ★ v25: Separate image storage — images saved as files, not in SharedPreferences JSON.
// This prevents SharedPreferences from growing to megabytes of base64 data.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ImageStorage {
  static Directory? _imageDir;
  static const String _kImageIndex = 'image_storage_index';

  /// Initialize the image storage directory
  static Future<void> init() async {
    if (kIsWeb) return; // Web uses base64 in memory only
    final appDir = await getApplicationDocumentsDirectory();
    _imageDir = Directory('${appDir.path}/incident_images');
    if (!await _imageDir!.exists()) {
      await _imageDir!.create(recursive: true);
    }
  }

  /// Save image bytes to file storage, return the filename (not base64)
  /// Returns the filename reference to store in incident record
  static Future<String?> saveImage(String incidentId, Uint8List bytes) async {
    if (kIsWeb) return null; // Web can't save to file system
    if (_imageDir == null) await init();

    try {
      final filename = 'img_$incidentId.jpg';
      final file = File('${_imageDir!.path}/$filename');
      await file.writeAsBytes(bytes);
      return filename;
    } catch (e) {
      print('[ImageStorage] Failed to save image: $e');
      return null;
    }
  }

  /// Load image bytes from file storage
  static Future<Uint8List?> loadImage(String filename) async {
    if (kIsWeb) return null;
    if (_imageDir == null) await init();

    try {
      final file = File('${_imageDir!.path}/$filename');
      if (await file.exists()) {
        return await file.readAsBytes();
      }
      return null;
    } catch (e) {
      print('[ImageStorage] Failed to load image: $e');
      return null;
    }
  }

  /// Load image from either a filename reference or inline base64
  /// Handles both new format (filename) and legacy format (base64 string)
  static Future<Uint8List?> getImageForIncident(Map<String, dynamic> incident) async {
    final imageRef = incident['imageRef']?.toString();
    final imageBase64 = incident['imageBase64']?.toString();

    // New format: file reference
    if (imageRef != null && imageRef.isNotEmpty && imageRef != 'null') {
      return await loadImage(imageRef);
    }

    // Legacy format: inline base64
    if (imageBase64 != null && imageBase64.isNotEmpty &&
        imageBase64 != 'null' && imageBase64 != '[image]') {
      try {
        return base64Decode(imageBase64);
      } catch (_) {
        return null;
      }
    }

    return null;
  }

  /// Delete image file for an incident
  static Future<void> deleteImage(String filename) async {
    if (kIsWeb) return;
    if (_imageDir == null) await init();

    try {
      final file = File('${_imageDir!.path}/$filename');
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      print('[ImageStorage] Failed to delete image: $e');
    }
  }

  /// Migrate existing base64 images from incidents to file storage
  /// Call once during upgrade to clear out heavy SharedPreferences data
  static Future<int> migrateInlineImages() async {
    if (kIsWeb) return 0;
    if (_imageDir == null) await init();

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('incidents');
    if (raw == null) return 0;

    try {
      final incidents = (jsonDecode(raw) as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      int migrated = 0;
      for (int i = 0; i < incidents.length; i++) {
        final inc = incidents[i];
        final base64 = inc['imageBase64']?.toString();
        if (base64 != null && base64.length > 100 && base64 != '[image]') {
          try {
            final bytes = base64Decode(base64);
            final id = inc['id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString();
            final filename = await saveImage(id, bytes);
            if (filename != null) {
              incidents[i]['imageRef'] = filename;
              incidents[i]['imageBase64'] = null; // Remove heavy data
              migrated++;
            }
          } catch (_) {
            // Skip corrupted base64
          }
        }
      }

      if (migrated > 0) {
        await prefs.setString('incidents', jsonEncode(incidents));
        print('[ImageStorage] Migrated $migrated images from SharedPreferences to file storage');
      }
      return migrated;
    } catch (e) {
      print('[ImageStorage] Migration failed: $e');
      return 0;
    }
  }

  /// Get total size of stored images (for diagnostics)
  static Future<int> getTotalSize() async {
    if (kIsWeb || _imageDir == null) return 0;
    try {
      int total = 0;
      await for (final entity in _imageDir!.list()) {
        if (entity is File) {
          total += await entity.length();
        }
      }
      return total;
    } catch (_) {
      return 0;
    }
  }
}
