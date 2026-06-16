import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:aeroride/services/mock_route_service.dart';
import 'package:aeroride/utils/fare_calculator.dart';
import 'package:aeroride/utils/location_utils.dart';

class SimulationService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static final Map<String, Timer> _movementTimers = {};
  static const String _simulatedDriversCollection = 'simulatedDrivers';

  /// Prepares specified drivers for simulation by setting active status and location.
  static Future<void> prepareDriversForSimulation(
    List<String> ids,
    LatLng location,
  ) async {
    final rnd = Random();
    for (final id in ids) {
      // Offset position slightly so driver doesn't spawn exactly on the rider
      final latOffset = (rnd.nextDouble() - 0.5) * 0.005;
      final lonOffset = (rnd.nextDouble() - 0.5) * 0.005;
      final geo = GeoPoint(
          location.latitude + latOffset, location.longitude + lonOffset);

      final update = {
        'isOnline': true,
        'hasLocation': true,
        'status': 'available',
        'current_location': geo,
        'currentLocation': geo, // Camel case for mobile consistency
        'location': geo, // Legacy field support
        'updatedAt': Timestamp.now(),
      };

      // Update simulation registry
      await _db
          .collection(_simulatedDriversCollection)
          .doc(id)
          .set(update, SetOptions(merge: true));

      // Synchronize to the primary users collection for matcher visibility
      await _db
          .collection('users')
          .doc(id)
          .set(update, SetOptions(merge: true));
    }
  }

  // Create simple simulated drivers around `center` and start moving them slowly.
  // Returns the created driver ids.
  static Future<List<String>> seedMockDrivers(
    LatLng center, {
    int count = 5,
    double spreadMeters = 800,
  }) async {
    final user = FirebaseAuth.instance.currentUser;

    // 🔐 STRICT AUTH GUARD: Drivers cannot use simulation or journey features
    // while browsing as an anonymous guest.
    if (user == null || user.isAnonymous) {
      debugPrint(
          'SimulationService: Aborting seedMockDrivers - Real account required.');
      // Throwing this allows the UI to catch it and call authService.showLogin()
      throw FirebaseAuthException(
          code: 'auth-required',
          message: 'Please sign in to start your journey.');
    }

    debugPrint('SimulationService: seeding $count drivers around $center');
    final rnd = Random();
    final created = <String>[];

    for (var i = 0; i < count; i++) {
      final id = 'sim-driver-${DateTime.now().millisecondsSinceEpoch}-$i';
      final angle = rnd.nextDouble() * pi * 2;
      final dist = rnd.nextDouble() * spreadMeters; // meters

      // rough meter to degree conversion
      final latOffset = (dist / 111000) * cos(angle);
      final lonOffset =
          (dist / (111000 * cos(center.latitude * pi / 180))) * sin(angle);

      final lat = center.latitude + latOffset;
      final lng = center.longitude + lonOffset;

      await _db.collection(_simulatedDriversCollection).doc(id).set({
        'name': 'Sim Driver ${i + 1}',
        'phone': '+254700000${i + 1}',
        // Cycles through all 4 local asset tiers including pamoja
        'vehicleTier': ['tulia', 'nuru', 'pamoja', 'waziri'][i % 4],
        'vehicleModel': [
          'Toyota Vitz',
          'Toyota Premio',
          'Honda Freed',
          'Toyota Prado'
        ][i % 4],
        'vehicleColor': ['Blue', 'White', 'Silver', 'Black'][i % 4],
        'rating': 4.7 + (i % 3) * 0.1,
        'current_location': GeoPoint(lat, lng),
        'location': GeoPoint(lat, lng),
        'isOnline': true,
        'hasLocation': true,
        'status': 'available',
        'updatedAt': Timestamp.now(),
      });

      // start simple movement timer for this driver
      _startMovingDriver(id, LatLng(lat, lng));
      debugPrint('SimulationService: created driver $id at $lat,$lng');
      created.add(id);
    }

    return created;
  }

  /// NEW: Seeds mock ride requests from existing riders to be picked up by drivers.
  /// This is what the "Grid Telemetry" is looking for.
  static Future<void> seedMockRequestsForNearbyDrivers({
    required LatLng area,
    int count = 3,
  }) async {
    final rnd = Random();
    final List<String> tiers = ['tulia', 'nuru', 'pamoja', 'waziri'];

    // Find some existing riders to "act" as the requesters
    final ridersQuery = await _db
        .collection('users')
        .where('role', isEqualTo: 'rider')
        .limit(10)
        .get();

    for (var i = 0; i < count; i++) {
      final riderDoc = ridersQuery.docs.isNotEmpty
          ? ridersQuery.docs[i % ridersQuery.docs.length]
          : null;

      final riderId = riderDoc?.id ?? 'sim-rider-$i';
      final riderName = riderDoc?.data()['name'] ?? 'AeroRide Rider';

      final pickup = LatLng(
        area.latitude + (rnd.nextDouble() - 0.5) * 0.01,
        area.longitude + (rnd.nextDouble() - 0.5) * 0.01,
      );
      final destination = LatLng(
        area.latitude + (rnd.nextDouble() - 0.5) * 0.03,
        area.longitude + (rnd.nextDouble() - 0.5) * 0.03,
      );

      final tierId = tiers[rnd.nextInt(tiers.length)];
      final distance = LocationUtils.calculateDistanceKm(pickup, destination);
      final fare = FareCalculator.calculateFare(tierId, distance);

      await _db.collection('ride_requests').add({
        'userId': riderId,
        'riderName': riderName,
        'status': 'searching',
        'pickupLocation': GeoPoint(pickup.latitude, pickup.longitude),
        'destinationLocation':
            GeoPoint(destination.latitude, destination.longitude),
        'pickupAddress': 'Simulated Pickup Point',
        'destinationAddress': 'Simulated Drop-off Point',
        'rideTier': tierId,
        'estimatedCost': fare,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
  }

  static void _startMovingDriver(String id, LatLng start) {
    final rnd = Random();
    var pos = start;
    _movementTimers[id]?.cancel();
    _movementTimers[id] = Timer.periodic(const Duration(seconds: 2), (_) async {
      // small random walk
      final dLat = (rnd.nextDouble() - 0.5) * 0.0002;
      final dLng = (rnd.nextDouble() - 0.5) * 0.0002;
      pos = LatLng(pos.latitude + dLat, pos.longitude + dLng);
      try {
        await _db.collection(_simulatedDriversCollection).doc(id).set({
          'current_location': GeoPoint(pos.latitude, pos.longitude),
          'isOnline': true,
          'hasLocation': true,
          'status': 'available',
          'updatedAt': Timestamp.now(),
        }, SetOptions(merge: true));
        // Mirror to users collection so driver app subscriptions receive updates
        try {
          await _db.collection('users').doc(id).set({
            'currentLocation': GeoPoint(pos.latitude, pos.longitude),
            'current_location': GeoPoint(pos.latitude, pos.longitude),
            'isOnline': true,
            'hasLocation': true,
            'status': 'available',
            'updatedAt': Timestamp.now(),
          }, SetOptions(merge: true));
        } catch (_) {}
      } catch (_) {}
    });
  }

  static Future<void> stopAllSimulatedDrivers() async {
    for (final t in _movementTimers.values) {
      t.cancel();
    }
    _movementTimers.clear();
  }

  // Create a few mock rides that include the provided driver id in candidateDrivers
  static Future<void> createMockRidesForDriver(
    String driverUid, {
    LatLng? center,
    int count = 3,
  }) async {
    final rnd = Random();
    final base = center ?? const LatLng(-1.2833, 36.8167);

    for (var i = 0; i < count; i++) {
      final pickup = LatLng(
        base.latitude + (rnd.nextDouble() - 0.5) * 0.02,
        base.longitude + (rnd.nextDouble() - 0.5) * 0.02,
      );
      final dest = LatLng(
        base.latitude + (rnd.nextDouble() - 0.5) * 0.02,
        base.longitude + (rnd.nextDouble() - 0.5) * 0.02,
      );

      final tierId = ['tulia', 'nuru', 'pamoja', 'waziri'][i % 4];
      final distance = LocationUtils.calculateDistanceKm(pickup, dest);
      final estimatedCost = FareCalculator.calculateFare(tierId, distance);

      try {
        await _db.collection('rides').add({
          'userId': 'sim-user-$i',
          'driverId': null,
          'candidateDrivers': [driverUid],
          'rideTier': tierId,
          'pickupLocation': GeoPoint(pickup.latitude, pickup.longitude),
          'destinationLocation': GeoPoint(dest.latitude, dest.longitude),
          'pickupAddress': 'Sim Pickup $i',
          'destinationAddress': 'Sim Drop $i',
          'status': 'searching',
          'estimatedCost': estimatedCost,
          'finalFareCharged': estimatedCost,
        });
      } catch (e) {
        debugPrint(
            'SimulationService: Ignored write when creating mock ride: $e');
      }
    }
  }

  static Timer? _rideSimulationTimer;
  static String? _currentSimulatedRideId;

  // Run database-driven simulation for the ride lifecycle.
  static Future<void> simulateRideLifecycle({
    required String rideId,
    required String driverId,
    required LatLng pickup,
    required LatLng destination,
  }) async {
    if (_currentSimulatedRideId == rideId) return;
    _currentSimulatedRideId = rideId;
    _rideSimulationTimer?.cancel();

    debugPrint('SimulationService: Starting ride simulation for ride $rideId');

    // 1. Get driver starting location or default to offset
    LatLng driverStart = LatLng(
      pickup.latitude + 0.005,
      pickup.longitude + 0.005,
    );
    try {
      final doc =
          await _db.collection(_simulatedDriversCollection).doc(driverId).get();
      if (doc.exists && doc.data()?['current_location'] != null) {
        final gp = doc.data()!['current_location'] as GeoPoint;
        driverStart = LatLng(gp.latitude, gp.longitude);
      }
    } catch (e) {
      debugPrint(
        'SimulationService: Could not read driver location, using default offset: $e',
      );
    }

    // 2. Build coordinates for both legs
    // Leg 1: Driver to pickup (approx. 10 steps)
    final toPickupPoints = MockRouteService.buildRoutePoints(
      driverStart,
      pickup,
      steps: 10,
    );
    // Leg 2: Pickup to destination (approx. 15 steps)
    final toDestPoints = MockRouteService.buildRoutePoints(
      pickup,
      destination,
      steps: 15,
    );

    final rideSnap = await _db.collection('rides').doc(rideId).get();
    final rideData = rideSnap.data() ?? {};
    final status = rideData['status'] ?? '';
    final tierId = (rideData['rideTier'] ?? 'tulia').toString().toLowerCase();
    int step = 0;
    // 1: moving to pickup, 3: moving to destination (2: waiting is now handled by UI)
    int leg = (status == 'started' || status == 'inTransit') ? 3 : 1;
    int waitingCounter = 0;

    _rideSimulationTimer = Timer.periodic(const Duration(seconds: 1), (
      timer,
    ) async {
      try {
        if (leg == 1) {
          // Leg 1: Moving to pickup
          if (step < toPickupPoints.length) {
            final pos = toPickupPoints[step];
            final update = {
              'current_location': GeoPoint(pos.latitude, pos.longitude),
              'updatedAt': Timestamp.now(),
            };
            await _db.collection(_simulatedDriversCollection).doc(driverId).set(
                  update,
                  SetOptions(merge: true),
                );
            // Mirror to users document for driver subscriptions
            try {
              await _db.collection('users').doc(driverId).set({
                'currentLocation': GeoPoint(pos.latitude, pos.longitude),
                'current_location': GeoPoint(pos.latitude, pos.longitude),
                'updatedAt': Timestamp.now(),
              }, SetOptions(merge: true));
            } catch (_) {}
            await _db.collection('rides').doc(rideId).set(
              {
                'currentVehicleLocation': GeoPoint(
                  pos.latitude,
                  pos.longitude,
                ),
                'updatedAt': Timestamp.now(),
              },
              SetOptions(merge: true),
            );
            step++;
          } else {
            // Arrived at pickup
            await _db.collection('rides').doc(rideId).update({
              'status': 'arrived',
              'currentVehicleLocation': GeoPoint(
                pickup.latitude,
                pickup.longitude,
              ),
            });
            // Mirror pickup location to users doc
            try {
              await _db.collection('users').doc(driverId).set({
                'currentLocation': GeoPoint(pickup.latitude, pickup.longitude),
                'current_location': GeoPoint(pickup.latitude, pickup.longitude),
                'updatedAt': Timestamp.now(),
              }, SetOptions(merge: true));
            } catch (_) {}
            leg = 2;
            waitingCounter = 0;
            debugPrint('SimulationService: Driver arrived at pickup.');
            _currentSimulatedRideId =
                null; // Clear lock to allow restart for the destination leg

            // CRITICAL FIX: Stop the simulation here.
            // The trip only resumes when the rider validates OTP in the UI.
            timer.cancel();
            _rideSimulationTimer = null;
          }
        } else if (leg == 3) {
          // Leg 3: Moving to destination
          if (step < toDestPoints.length) {
            final pos = toDestPoints[step];

            // Calculate live fare based on simulated progress
            final totalDist =
                LocationUtils.calculateDistanceKm(pickup, destination);
            final progress = (step + 1) / toDestPoints.length;
            final currentDistKm = totalDist * progress;
            final liveFare =
                FareCalculator.calculateFare(tierId, currentDistKm);

            await _db
                .collection(_simulatedDriversCollection)
                .doc(driverId)
                .set({
              'current_location': GeoPoint(pos.latitude, pos.longitude),
              'updatedAt': Timestamp.now(),
            }, SetOptions(merge: true));
            // Mirror to users collection so driver app subscriptions receive updates
            try {
              await _db.collection('users').doc(driverId).set({
                'currentLocation': GeoPoint(pos.latitude, pos.longitude),
                'current_location': GeoPoint(pos.latitude, pos.longitude),
                'updatedAt': Timestamp.now(),
              }, SetOptions(merge: true));
            } catch (_) {}
            await _db.collection('rides').doc(rideId).set(
              {
                'currentVehicleLocation': GeoPoint(
                  pos.latitude,
                  pos.longitude,
                ),
                'estimatedCost': liveFare,
                'updatedAt': Timestamp.now(),
              },
              SetOptions(merge: true),
            );
            step++;
          } else {
            // Arrived at destination
            await _db
                .collection(_simulatedDriversCollection)
                .doc(driverId)
                .set({
              'current_location': GeoPoint(
                destination.latitude,
                destination.longitude,
              ),
              'updatedAt': Timestamp.now(),
            }, SetOptions(merge: true));
            // Mirror final destination to users doc
            try {
              await _db.collection('users').doc(driverId).set({
                'currentLocation':
                    GeoPoint(destination.latitude, destination.longitude),
                'current_location':
                    GeoPoint(destination.latitude, destination.longitude),
                'updatedAt': Timestamp.now(),
              }, SetOptions(merge: true));
            } catch (_) {}
            await _db.collection('rides').doc(rideId).set(
              {
                'currentVehicleLocation': GeoPoint(
                  destination.latitude,
                  destination.longitude,
                ),
                'updatedAt': Timestamp.now(),
              },
              SetOptions(merge: true),
            );
            leg = 4;
            timer.cancel();
            _rideSimulationTimer = null;
            debugPrint('SimulationService: Trip awaiting rider confirmation.');
          }
        }
      } catch (e) {
        debugPrint('SimulationService: Error in ride simulation loop: $e');
        timer.cancel();
        _rideSimulationTimer = null;
      }
    });
  }

  static void stopRideSimulation() {
    _rideSimulationTimer?.cancel();
    _rideSimulationTimer = null;
    _currentSimulatedRideId = null;
    debugPrint('SimulationService: Stopped ride simulation.');
  }
}
