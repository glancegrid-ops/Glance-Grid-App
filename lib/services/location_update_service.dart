import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'location_service.dart';
import 'device_id_service.dart';

/// Service to manage location updates to Firestore.
/// Handles periodic location fetching and database updates with distance checking.
class LocationUpdateService {
  static final LocationUpdateService _instance =
      LocationUpdateService._internal();

  LocationUpdateService._internal();

  factory LocationUpdateService() {
    return _instance;
  }

  static LocationUpdateService get instance => _instance;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final LocationService _locationService = LocationService.instance;

  Timer? _locationUpdateTimer;
  bool _isRunning = false;
  static const int _updateIntervalSeconds = 10;
  static const double _distanceThresholdMeters = 500;

  /// Start periodic location updates (every 10 seconds).
  /// Also fetches location immediately on startup.
  Future<void> startLocationTracking() async {
    if (_isRunning) {
      // debugPrint('⚠️ Location tracking already running.');
      return;
    }

    _isRunning = true;
    //  debugPrint('📍 Starting location tracking...');

    // Request permissions
    final hasPermission = await _locationService.requestLocationPermissions();
    if (!hasPermission) {
      // debugPrint(
      //   '❌ Location permissions not granted. Stopping location tracking.',
      // );
      _isRunning = false;
      return;
    }

    // Fetch and update location immediately on startup
    await _updateLocationInDatabase();

    // Start periodic updates every 10 seconds
    _locationUpdateTimer = Timer.periodic(
      const Duration(seconds: _updateIntervalSeconds),
      (_) async {
        await _updateLocationInDatabase();
      },
    );

    // debugPrint('✓ Location tracking started (10s interval)');
  }

  /// Stop periodic location updates.
  Future<void> stopLocationTracking() async {
    _locationUpdateTimer?.cancel();
    _locationUpdateTimer = null;
    _isRunning = false;
    // debugPrint('📍 Location tracking stopped');
  }

  /// Fetch current location and update in Firestore if distance > 500m.
  Future<void> _updateLocationInDatabase() async {
    try {
      final currentLocation = await _locationService.getCurrentLocation();
      if (currentLocation == null) {
        //debugPrint('⚠️ Could not fetch current location.');
        return;
      }

      final deviceId = await DeviceIdService.instance.getDeviceId();

      if (deviceId.isEmpty) {
        //   debugPrint('⚠️ DeviceId empty. Skipping location update.');
        return;
      }

      final userDocRef = _firestore.collection('users').doc(deviceId);
      final userSnap = await userDocRef.get();
      if (!userSnap.exists) {
        debugPrint(
          '⚠️ User document not found for deviceId=$deviceId. Skipping location update.',
        );
        return;
      }

      final userData = userSnap.data();
      final locations = (userData?['locations'] as List<dynamic>?) ?? [];

      // Check if distance is greater than 500 meters
      bool shouldUpdate = true;
      if (locations.isNotEmpty) {
        final lastLocationMap = locations.last as Map<String, dynamic>;
        // Support both 'lat'/'lng' and legacy 'latitude'/'longitude' keys
        final lastLat =
            ((lastLocationMap['lat'] ?? lastLocationMap['latitude']) as num?)
                ?.toDouble() ??
            0;
        final lastLng =
            ((lastLocationMap['lng'] ?? lastLocationMap['longitude']) as num?)
                ?.toDouble() ??
            0;

        final distance = _locationService.calculateDistance(
          lastLat,
          lastLng,
          currentLocation.latitude,
          currentLocation.longitude,
        );

        // debugPrint(
        //   '📍 Distance from last location: ${distance.toStringAsFixed(2)}m (threshold: $_distanceThresholdMeters m)',
        // );

        if (distance < _distanceThresholdMeters) {
          //  debugPrint('✓ Distance < 500m. Skipping update.');
          shouldUpdate = false;
        }
      }

      if (shouldUpdate) {
        // Add current location to locations array
        final updatedLocations = [...locations, currentLocation.toJson()];

        await userDocRef.update({'locations': updatedLocations});

        debugPrint(
          '✓ Location updated: lat=${currentLocation.latitude}, lng=${currentLocation.longitude}',
        );
      }
    } catch (e) {
      // debugPrint('❌ Error updating location in database: $e');
    }
  }

  /// Get tracking status.
  bool get isTracking => _isRunning;
}
