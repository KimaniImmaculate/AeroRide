import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:math';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class DriversService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
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
          await _db.collection('users').doc(uid).set({
            'current_location': GeoPoint(pos.latitude, pos.longitude),
            'isOnline': true,
            'updatedAt': FieldValue.serverTimestamp(),
            'role': 'driver',
          }, SetOptions(merge: true));
        } catch (e) {
          // swallow — UI can show problems if needed
          debugPrint('Error writing driver location: $e');
        }
      },
    );
  }

  Future<void> stopLocationUpdates(String uid) async {
    await _db.collection('users').doc(uid).set({
      'isOnline': false,
      'updatedAt': FieldValue.serverTimestamp(),
      'role': 'driver',
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
    if (_auth.currentUser == null) {
      debugPrint(
          'DriversService.getNearbyDrivers: no auth user, returning empty');
      return <Map<String, dynamic>>[];
    }
    debugPrint(
        'DriversService.getNearbyDrivers: auth uid=${_auth.currentUser?.uid}');

    final cutoff = DateTime.now().subtract(const Duration(minutes: 5));
    final List<Map<String, dynamic>> results = [];
    QuerySnapshot<Map<String, dynamic>> querySnapshot;
    try {
      querySnapshot = await _db
          .collection('users')
          .where('isOnline', isEqualTo: true)
          .get()
          .timeout(const Duration(seconds: 4));
      try {
        debugPrint(
            'DriversService.getNearbyDrivers: query returned ${querySnapshot.docs.length} docs');
        for (final d in querySnapshot.docs.take(6)) {
          final dd = d.data();
          debugPrint(
              'Nearby doc ${d.id}: isOnline=${dd['isOnline']}, hasLocation=${dd['current_location'] != null || dd['currentLocation'] != null}, role=${dd['role']}');
        }
      } catch (_) {}
    } on FirebaseException catch (error) {
      debugPrint(
          'DriversService.getNearbyDrivers: FirebaseException code=${error.code} message=${error.message}');
      if (error.code == 'permission-denied') {
        return <Map<String, dynamic>>[];
      }
      rethrow;
    }

    for (final doc in querySnapshot.docs) {
      // Skip simulation/mock driver docs
      final id = doc.id.toString().toLowerCase();
      final ddata = doc.data();
      final name = (ddata['name'] ?? ddata['displayName'] ?? '').toString();
      final role = (ddata['role'] ?? '').toString().toLowerCase();
      final locationData =
          ddata['current_location'] ?? ddata['currentLocation'];
      final hasLocation = locationData is GeoPoint;
      final isDriverLike = hasLocation || role == 'driver' || role == 'drivers';
      if (id.startsWith('mock-') ||
          id.contains('mock-driver') ||
          name.toLowerCase().contains('mock driver') ||
          (ddata['isMock'] == true) ||
          !isDriverLike) {
        continue;
      }
      final data = doc.data();
      final updatedAt = data['updatedAt'];
      if (updatedAt is Timestamp && updatedAt.toDate().isBefore(cutoff)) {
        continue;
      }
      if (locationData == null) continue;
      final GeoPoint gp = locationData as GeoPoint;
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
      final allResults = await getSelectableDrivers(
        referenceLocation: LatLng(lat, lng),
        limit: limit,
      );
      return allResults.take(limit).toList();
    } catch (error) {
      debugPrint('DriversService: nearby lookup skipped: $error');
      return <Map<String, dynamic>>[];
    }
  }

  Future<List<Map<String, dynamic>>> getSelectableDrivers({
    LatLng? referenceLocation,
    int limit = 6,
  }) async {
    final results = <Map<String, dynamic>>[];
    if (_auth.currentUser == null) {
      debugPrint('DriversService.getSelectableDrivers: no auth user');
    } else {
      debugPrint(
          'DriversService.getSelectableDrivers: auth uid=${_auth.currentUser?.uid}');
    }

    QuerySnapshot<Map<String, dynamic>> querySnapshot;
    try {
      querySnapshot = await _db
          .collection('users')
          .where('role', whereIn: ['driver', 'drivers'])
          .get()
          .timeout(const Duration(seconds: 4));
      if (querySnapshot.docs.isEmpty) {
        // MVP fallback: if role tagging is inconsistent, scan users and filter in code.
        querySnapshot = await _db
            .collection('users')
            .limit(200)
            .get()
            .timeout(const Duration(seconds: 4));
      }
      try {
        debugPrint(
            'DriversService.getSelectableDrivers: raw docs=${querySnapshot.docs.length}');
        for (final d in querySnapshot.docs.take(6)) {
          final dd = d.data();
          debugPrint(
              'Selectable doc ${d.id}: role=${dd['role']}, hasLocation=${dd['current_location'] != null || dd['currentLocation'] != null}, isOnline=${dd['isOnline']}');
        }
      } catch (_) {}
    } on FirebaseException catch (error) {
      debugPrint(
          'DriversService.getSelectableDrivers: FirebaseException code=${error.code} message=${error.message}');
      if (error.code == 'permission-denied') {
        return <Map<String, dynamic>>[];
      }
      rethrow;
    }

    for (final doc in querySnapshot.docs) {
      // Filter out simulation/mock drivers so the rider UI shows only real users
      final id = doc.id.toString().toLowerCase();
      final data = doc.data();
      final name = (data['name'] ?? data['displayName'] ?? '').toString();
      final role = (data['role'] ?? '').toString().toLowerCase();
      final locationData = data['current_location'] ?? data['currentLocation'];
      final hasLocation = locationData is GeoPoint;
      final isDriverLike = hasLocation || role == 'driver' || role == 'drivers';
      if (id.startsWith('mock-') ||
          id.contains('mock-driver') ||
          name.toLowerCase().contains('mock driver') ||
          (data['isMock'] == true) ||
          !isDriverLike) {
        continue;
      }
      final GeoPoint? geoPoint = locationData is GeoPoint ? locationData : null;
      final LatLng? location = geoPoint == null
          ? null
          : LatLng(geoPoint.latitude, geoPoint.longitude);
      final double? distanceKm = referenceLocation != null && geoPoint != null
          ? _distanceKm(
              referenceLocation.latitude,
              referenceLocation.longitude,
              geoPoint.latitude,
              geoPoint.longitude,
            )
          : null;

      results.add({
        'driverId': doc.id,
        'id': doc.id,
        'name': data['name'] ?? data['displayName'] ?? 'Driver',
        'vehicle': data['vehicle'] ??
            data['vehicleInfo'] ??
            data['vehicleModel'] ??
            '',
        'rating': (data['rating'] ?? 4.8).toString(),
        'eta': distanceKm == null ? 5 : (distanceKm * 2).round().clamp(1, 99),
        'lat': location?.latitude,
        'lng': location?.longitude,
        'distanceKm': distanceKm,
        'location': location,
        'raw': data,
      });
    }

    results.sort((a, b) {
      final aDistance = a['distanceKm'] as double?;
      final bDistance = b['distanceKm'] as double?;
      if (aDistance == null && bDistance == null) {
        return (a['name'] as String).compareTo(b['name'] as String);
      }
      if (aDistance == null) return 1;
      if (bDistance == null) return -1;
      return aDistance.compareTo(bDistance);
    });

    return results.take(limit).toList();
  }

  /// Probe: attempt a minimal users read to see whether rules allow collection reads.
  Future<void> debugProbeUsersRead() async {
    try {
      debugPrint(
          'DriversService.debugProbeUsersRead: attempting users.limit(1)');
      final snapshot = await _db.collection('users').limit(1).get();
      debugPrint(
          'DriversService.debugProbeUsersRead: success docs=${snapshot.docs.length}');
      for (final d in snapshot.docs) {
        debugPrint('probe doc ${d.id}: fields=${d.data().keys.toList()}');
      }
    } on FirebaseException catch (e) {
      debugPrint(
          'DriversService.debugProbeUsersRead: FirebaseException code=${e.code} message=${e.message}');
    } catch (e) {
      debugPrint('DriversService.debugProbeUsersRead: error $e');
    }
  }

  double _distanceKm(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371; // Earth's radius km
    final dLat = _deg2rad(lat2 - lat1);
    final dLon = _deg2rad(lon2 - lon1);
    final a = (sin(dLat / 2) * sin(dLat / 2)) +
        cos(_deg2rad(lat1)) *
            cos(_deg2rad(lat2)) *
            (sin(dLon / 2) * sin(dLon / 2));
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return R * c;
  }

  double _deg2rad(double deg) => deg * (pi / 180);
}
