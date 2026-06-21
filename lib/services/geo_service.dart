// lib/services/geo_service.dart
// GPS location capture and image watermarking service

import 'dart:typed_data';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:image/image.dart' as img;
import 'package:permission_handler/permission_handler.dart';

class GeoService {
  /// Captures current GPS location with high accuracy
  static Future<LocationData?> getCurrentLocation() async {
    try {
      // Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return LocationData(
          error: 'Location services are disabled. Please enable GPS.',
        );
      }

      // Check location permission
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          return LocationData(
            error: 'Location permission denied',
          );
        }
      }

      if (permission == LocationPermission.deniedForever) {
        return LocationData(
          error: 'Location permissions are permanently denied. Please enable in settings.',
        );
      }

      // Get high-accuracy position
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );

      // Get address from coordinates
      String address = '';
      try {
        List<Placemark> placemarks = await placemarkFromCoordinates(
          position.latitude,
          position.longitude,
        );
        if (placemarks.isNotEmpty) {
          Placemark place = placemarks[0];
          address = [
            place.street,
            place.subLocality,
            place.locality,
            place.administrativeArea,
            place.postalCode,
            place.country,
          ].where((e) => e != null && e.isNotEmpty).join(', ');
        }
      } catch (e) {
        // Address lookup failed, continue with coordinates only
        address = '';
      }

      return LocationData(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracy: position.accuracy,
        altitude: position.altitude,
        timestamp: position.timestamp,
        address: address,
      );
    } catch (e) {
      return LocationData(
        error: 'Failed to get location: ${e.toString()}',
      );
    }
  }

  /// Adds timestamp and location watermark to image
  static Future<Uint8List?> addWatermarkToImage(
    Uint8List imageBytes,
    LocationData location,
  ) async {
    try {
      // Decode image
      img.Image? image = img.decodeImage(imageBytes);
      if (image == null) return imageBytes;

      // Create timestamp text
      String timestamp = _formatTimestamp(location.timestamp);

      // Create location text
      String locationText = '';
      if (location.latitude != null && location.longitude != null) {
        locationText = 'GPS: ${location.latitude!.toStringAsFixed(6)}, ${location.longitude!.toStringAsFixed(6)}';
        if (location.accuracy != null) {
          locationText += ' (±${location.accuracy!.toStringAsFixed(1)}m)';
        }
      }

      // Draw semi-transparent black background bar at bottom
      final barHeight = 80;
      img.fillRect(
        image,
        x1: 0,
        y1: image.height - barHeight,
        x2: image.width,
        y2: image.height,
        color: img.ColorRgba8(0, 0, 0, 180), // Semi-transparent black
      );

      // Draw timestamp (white text)
      img.drawString(
        image,
        timestamp,
        font: img.arial48,
        x: 20,
        y: image.height - barHeight + 10,
        color: img.ColorRgba8(255, 255, 255, 255),
      );

      // Draw location (white text)
      if (locationText.isNotEmpty) {
        img.drawString(
          image,
          locationText,
          font: img.arial24,
          x: 20,
          y: image.height - barHeight + 50,
          color: img.ColorRgba8(255, 255, 255, 255),
        );
      }

      // Encode back to bytes
      return Uint8List.fromList(img.encodeJpg(image, quality: 95));
    } catch (e) {
      // If watermarking fails, return original image
      return imageBytes;
    }
  }

  /// Formats timestamp for watermark
  static String _formatTimestamp(DateTime dt) {
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
  }

  /// Gets formatted address string for display
  static String getDisplayAddress(LocationData location) {
    if (location.error != null) return location.error!;
    if (location.address != null && location.address!.isNotEmpty) {
      return location.address!;
    }
    if (location.latitude != null && location.longitude != null) {
      return '${location.latitude!.toStringAsFixed(6)}, ${location.longitude!.toStringAsFixed(6)}';
    }
    return 'Location not available';
  }

  /// Gets Google Maps URL for location
  static String getGoogleMapsUrl(double lat, double lon) {
    return 'https://www.google.com/maps?q=$lat,$lon';
  }
}

/// Location data model
class LocationData {
  final double? latitude;
  final double? longitude;
  final double? accuracy; // meters
  final double? altitude; // meters
  final DateTime timestamp;
  final String? address;
  final String? error;

  LocationData({
    this.latitude,
    this.longitude,
    this.accuracy,
    this.altitude,
    DateTime? timestamp,
    this.address,
    this.error,
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'latitude': latitude,
        'longitude': longitude,
        'accuracy': accuracy,
        'altitude': altitude,
        'timestamp': timestamp.toIso8601String(),
        'address': address,
      };

  factory LocationData.fromJson(Map<String, dynamic> json) => LocationData(
        latitude: json['latitude'] as double?,
        longitude: json['longitude'] as double?,
        accuracy: json['accuracy'] as double?,
        altitude: json['altitude'] as double?,
        timestamp: json['timestamp'] != null
            ? DateTime.parse(json['timestamp'])
            : DateTime.now(),
        address: json['address'] as String?,
      );

  bool get isValid => latitude != null && longitude != null && error == null;
}
