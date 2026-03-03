import 'package:geolocator/geolocator.dart';
import 'package:flutter/foundation.dart';
import 'dart:math' as math;
import '../models/location_data.dart';

/// Service to handle location fetching and distance calculations.
/// Provides methods to get current location and calculate distance between two points.
class LocationService {
  static final LocationService _instance = LocationService._internal();

  LocationService._internal();

  factory LocationService() {
    return _instance;
  }

  static LocationService get instance => _instance;

  /// Request location permissions and return permission status.
  Future<bool> requestLocationPermissions() async {
    try {
      final permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        final result = await Geolocator.requestPermission();
        return result == LocationPermission.whileInUse ||
            result == LocationPermission.always;
      } else if (permission == LocationPermission.deniedForever) {
        debugPrint(
          '⚠️ Location permission denied forever. User must enable from settings.',
        );
        return false;
      }

      return permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always;
    } catch (e) {
      debugPrint('❌ Error requesting location permissions: $e');
      return false;
    }
  }

  /// Fetch current location and return LocationData.
  /// Returns null if location cannot be fetched.
  Future<LocationData?> getCurrentLocation() async {
    try {
      final permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        debugPrint('❌ Location permission not granted.');
        return null;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );

      return LocationData(
        latitude: position.latitude,
        longitude: position.longitude,
        timestamp: DateTime.now(),
      );
    } catch (e) {
      debugPrint('❌ Error fetching location: $e');
      return null;
    }
  }

  /// Calculate distance between two points in meters using Haversine formula.
  double calculateDistance(double lat1, double lng1, double lat2, double lng2) {
    const earthRadiusMeters = 6371000; // Earth radius in meters

    final dLat = _toRadians(lat2 - lat1);
    final dLng = _toRadians(lng2 - lng1);

    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRadians(lat1)) *
            math.cos(_toRadians(lat2)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);

    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));

    return earthRadiusMeters * c;
  }

  /// Convert degrees to radians.
  double _toRadians(double degrees) {
    return degrees * (math.pi / 180);
  }
}
