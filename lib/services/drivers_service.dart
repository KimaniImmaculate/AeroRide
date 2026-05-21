import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:math';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class DriversService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  StreamSubscription<Position>? _positionSub;

  Future<void> startLocationUpdates(String uid) async {
    // Request permissions first
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever ||
        permission == LocationPermission.denied) {
      throw Exception('Location permission not granted');
    }

    // Start listening to position updates
    final LocationSettings locationSettings =
        defaultTargetPlatform == TargetPlatform.android
        ? AndroidSettings(
            accuracy: LocationAccuracy.bestForNavigation,
            distanceFilter: 10,
            forceLocationManager: false,
            intervalDuration: const Duration(seconds: 3),
          )
        : AppleSettings(
            accuracy: LocationAccuracy.bestForNavigation,
            distanceFilter: 10,
            activityType: ActivityType.otherNavigation,
            pauseLocationUpdatesAutomatically: false,
            showBackgroundLocationIndicator: true,
          );

    _positionSub =
        Geolocator.getPositionStream(locationSettings: locationSettings).listen(
          (Position pos) async {
            try {
              await _db.collection('drivers').doc(uid).set({
                'current_location': GeoPoint(pos.latitude, pos.longitude),
                'isOnline': true,
                'updatedAt': FieldValue.serverTimestamp(),
              }, SetOptions(merge: true));
            } catch (e) {
              // swallow — UI can show problems if needed
              debugPrint('Error writing driver location: $e');
            }
          },
        );
  }

  Future<void> stopLocationUpdates(String uid) async {
    await _db.collection('drivers').doc(uid).set({
      'isOnline': false,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await _positionSub?.cancel();
    _positionSub = null;
  }

  // Query online drivers, compute distance client-side, and return those within radiusKm sorted by distance
  Future<List<Map<String, dynamic>>> getNearbyDrivers(
    double lat,
    double lng, {
    double radiusKm = 5.0,
  }) async {
    final cutoff = DateTime.now().subtract(const Duration(minutes: 5));

    final querySnapshot = await _db
        .collection('drivers')
        .where('isOnline', isEqualTo: true)
        .get();

    final List<Map<String, dynamic>> results = [];
    for (final doc in querySnapshot.docs) {
      final data = doc.data();
      final updatedAt = data['updatedAt'];
      if (updatedAt is Timestamp && updatedAt.toDate().isBefore(cutoff)) {
        continue;
      }
      if (data['current_location'] == null) continue;
      final GeoPoint gp = data['current_location'];
      final double d = _distanceKm(lat, lng, gp.latitude, gp.longitude);
      if (d <= radiusKm) {
        results.add({
          'driverId': doc.id,
          'distanceKm': d,
          'location': LatLng(gp.latitude, gp.longitude),
          'raw': data,
        });
      }
    }

    results.sort(
      (a, b) =>
          (a['distanceKm'] as double).compareTo(b['distanceKm'] as double),
    );
    return results;
  }

  Future<List<Map<String, dynamic>>> getTopNearbyDrivers(
    double lat,
    double lng, {
    double initialRadiusKm = 5.0,
    double maxRadiusKm = 15.0,
    int limit = 5,
  }) async {
    try {
      final seenDriverIds = <String>{};
      final allResults = <Map<String, dynamic>>[];

      for (
        double radius = initialRadiusKm;
        radius <= maxRadiusKm;
        radius += initialRadiusKm
      ) {
        final results = await getNearbyDrivers(lat, lng, radiusKm: radius);
        for (final driver in results) {
          final driverId = driver['driverId'] as String;
          if (seenDriverIds.add(driverId)) {
            allResults.add(driver);
          }
        }

        allResults.sort(
          (a, b) =>
              (a['distanceKm'] as double).compareTo(b['distanceKm'] as double),
        );

        if (allResults.length >= limit) {
          break;
        }
      }

      return allResults.take(limit).toList();
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  double _distanceKm(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371; // Earth's radius km
    final dLat = _deg2rad(lat2 - lat1);
    final dLon = _deg2rad(lon2 - lon1);
    final a =
        (sin(dLat / 2) * sin(dLat / 2)) +
        cos(_deg2rad(lat1)) *
            cos(_deg2rad(lat2)) *
            (sin(dLon / 2) * sin(dLon / 2));
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return R * c;
  }

  double _deg2rad(double deg) => deg * (pi / 180);
}
