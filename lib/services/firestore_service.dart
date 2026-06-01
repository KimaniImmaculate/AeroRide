import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/ride_request_model.dart';
import '../models/user_model.dart';
import '../models/ride_type_model.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Save User profile info to DB
  Future<void> createUserProfile(UserModel user) async {
    await _db
        .collection('users')
        .doc(user.uid)
        .set(user.toMap())
        .timeout(const Duration(seconds: 12));
  }

  // Merge profile data for existing auth users.
  Future<void> upsertUserProfile(UserModel user) async {
    await _db
        .collection('users')
        .doc(user.uid)
        .set(user.toMap(), SetOptions(merge: true))
        .timeout(const Duration(seconds: 12));
  }

  // Fetch single User info
  Future<UserModel> getUserProfile(String uid) async {
    DocumentSnapshot doc = await _db
        .collection('users')
        .doc(uid)
        .get()
        .timeout(const Duration(seconds: 12));
    if (!doc.exists || doc.data() == null) {
      // Return a safe default profile when the Firestore document is missing.
      return UserModel(uid: uid, name: '', email: '', role: 'rider');
    }

    return UserModel.fromMap(doc.data() as Map<String, dynamic>, doc.id);
  }

  Future<List<RideRequest>> getUserRideHistory(
    String userId, {
    int limit = 12,
  }) async {
    final snapshot = await _db
        .collection('rides')
        .where('userId', isEqualTo: userId)
        .limit(limit)
        .get()
        .timeout(const Duration(seconds: 12));

    final rides = snapshot.docs
        .map((doc) => RideRequest.fromMap(doc.data(), doc.id))
        .toList();

    rides.sort((a, b) {
      final aTime = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bTime = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bTime.compareTo(aTime);
    });

    return rides.take(limit).toList();
  }

  // CREATE: Post a new ride request document to Firestore
  Future<String> createRideRequest(RideRequest rideRequest) async {
    DocumentReference docRef = await _db.collection('rides').add({
      ...rideRequest.toMap(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }).timeout(const Duration(seconds: 12));
    return docRef.id;
  }

  Future<String> createRideRequestWithWalletReservation({
    required RideRequest rideRequest,
    required String riderId,
    required double fare,
  }) async {
    final rideRef = _db.collection('rides').doc();

    try {
      return await _db.runTransaction((tx) async {
        tx.set(rideRef, {
          ...rideRequest.toMap(),
          'estimatedCost': fare,
          'finalFareCharged': fare,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          'paymentStatus': 'pending',
        });

        return rideRef.id;
      });
    } catch (e, st) {
      debugPrint('FirestoreService: transaction ride reservation failed: $e');
      try {
        final dynamic boxedError = e;
        debugPrint('FirestoreService: boxed JS error: ${boxedError.error}');
        debugPrint('FirestoreService: boxed JS stack: ${boxedError.stack}');
      } catch (_) {
        // Not a boxed JS object.
      }
      debugPrintStack(
        stackTrace: st,
        label: 'FirestoreService.createRideRequestWithWalletReservation',
      );

      await rideRef.set({
        ...rideRequest.toMap(),
        'estimatedCost': fare,
        'finalFareCharged': fare,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'paymentStatus': 'pending',
      }).timeout(const Duration(seconds: 12));

      return rideRef.id;
    }
  }

  // STREAM: Real-time tracking of a ride request document
  Stream<RideRequest> streamRideStatus(String rideId) {
    return _db.collection('rides').doc(rideId).snapshots().map((snapshot) {
      if (!snapshot.exists || snapshot.data() == null) {
        throw Exception("Ride not found");
      }
      return RideRequest.fromMap(snapshot.data()!, snapshot.id);
    });
  }

  Stream<List<RideRequest>> watchDriverRequests(String driverId) {
    return _db
        .collection('rides')
        .where('status', isEqualTo: 'searching')
        .where('candidateDrivers', arrayContains: driverId)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => RideRequest.fromMap(doc.data(), doc.id))
              .toList(),
        );
  }

  Stream<List<RideRequest>> watchOpenRideRequests({int limit = 50}) {
    final cutoff = DateTime.now().subtract(const Duration(days: 3));
    Stream<List<RideRequest>> openRidesForCollection(String collectionName) {
      return _db
          .collection(collectionName)
          .where('status', isEqualTo: 'searching')
          .limit(limit)
          .snapshots()
          .map((snapshot) {
        final rides = snapshot.docs
            .where((doc) {
              if (doc.metadata.hasPendingWrites) {
                return true;
              }
              final data = doc.data();
              final createdAt = data['createdAt'] as Timestamp?;
              final updatedAt = data['updatedAt'] as Timestamp?;
              final recordTime = createdAt ?? updatedAt;
              if (recordTime == null) {
                return false;
              }
              return recordTime.toDate().isAfter(cutoff);
            })
            .map((doc) => RideRequest.fromMap(doc.data(), doc.id))
            .toList();
        rides.sort((a, b) {
          final aTime = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final bTime = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          return bTime.compareTo(aTime);
        });
        return rides.take(limit).toList();
      });
    }

    return Stream.multi((controller) {
      final activeRides = <String, RideRequest>{};
      StreamSubscription<List<RideRequest>>? ridesSub;
      StreamSubscription<List<RideRequest>>? requestsSub;

      void emitMerged() {
        final merged = activeRides.values.toList()
          ..sort((a, b) {
            final aTime = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            final bTime = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            return bTime.compareTo(aTime);
          });
        controller.add(merged.take(limit).toList());
      }

      ridesSub = openRidesForCollection('rides').listen((rides) {
        for (final ride in rides) {
          activeRides['rides:${ride.id ?? ride.userId}'] = ride;
        }
        emitMerged();
      }, onError: controller.addError);

      requestsSub = openRidesForCollection('ride_requests').listen((rides) {
        for (final ride in rides) {
          activeRides['ride_requests:${ride.id ?? ride.userId}'] = ride;
        }
        emitMerged();
      }, onError: controller.addError);

      controller.onCancel = () async {
        await ridesSub?.cancel();
        await requestsSub?.cancel();
      };
    });
  }

  // Simple: watch a single collection for recent ride requests.
  // Useful for MVP: drivers can subscribe directly to `ride_requests`.
  Stream<List<RideRequest>> watchSimpleOpenRides({
    String collectionName = 'ride_requests',
    int limit = 50,
  }) {
    final cutoff = DateTime.now().subtract(const Duration(days: 3));

    return _db
        .collection(collectionName)
        .limit(limit)
        .snapshots()
        .map((snapshot) {
      final rides = snapshot.docs
          .where((doc) {
            if (doc.metadata.hasPendingWrites) return true;
            final data = doc.data();
            final createdAt = data['createdAt'] as Timestamp?;
            final updatedAt = data['updatedAt'] as Timestamp?;
            final recordTime = createdAt ?? updatedAt;
            if (recordTime == null) return false;
            return recordTime.toDate().isAfter(cutoff);
          })
          .map((doc) => RideRequest.fromMap(doc.data(), doc.id))
          .toList();
      rides.sort((a, b) {
        final aTime = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bTime = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bTime.compareTo(aTime);
      });
      return rides.take(limit).toList();
    });
  }

  Stream<List<RideRequest>> watchActiveDriverRides(String driverId) {
    return _db
        .collection('rides')
        .where('driverId', isEqualTo: driverId)
        .where(
          'status',
          whereIn: ['accepted', 'arrived', 'started', 'completed'],
        )
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => RideRequest.fromMap(doc.data(), doc.id))
              .toList(),
        );
  }

  Future<void> acceptRide({
    required String rideId,
    required String driverId,
  }) async {
    await _db.runTransaction((tx) async {
      final docRef = _db.collection('rides').doc(rideId);
      final snapshot = await tx.get(docRef);
      if (!snapshot.exists) {
        throw Exception('Ride not found');
      }

      final data = snapshot.data();
      if (data == null) {
        throw Exception('Ride data missing');
      }

      final status = data['status'];
      if (status != 'searching') {
        throw Exception('Ride no longer available');
      }

      tx.update(docRef, {
        'status': 'accepted',
        'driverId': driverId,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> updateRideStatus(String rideId, String status) async {
    await _db.collection('rides').doc(rideId).update({
      'status': status,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> completeRideAndSettlePayment({
    required String rideId,
    required String riderId,
    required String driverId,
    required double fare,
  }) async {
    await _db.runTransaction((tx) async {
      final rideRef = _db.collection('rides').doc(rideId);
      final riderWalletRef = _db.collection('wallets').doc(riderId);
      final driverWalletRef = _db.collection('wallets').doc(driverId);

      final rideSnapshot = await tx.get(rideRef);
      if (!rideSnapshot.exists) {
        throw Exception('Ride not found');
      }

      final rideData = rideSnapshot.data();
      if (rideData == null) {
        throw Exception('Ride data missing');
      }

      final rideOwnerId = rideData['userId'] as String?;
      final rideDriverId = rideData['driverId'] as String?;
      if (rideOwnerId != riderId) {
        throw Exception('Ride owner mismatch');
      }
      if (rideDriverId != null && rideDriverId != driverId) {
        throw Exception('Ride driver mismatch');
      }

      final amount =
          ((rideData['finalFareCharged'] ?? rideData['estimatedCost']) as num?)
                  ?.toDouble() ??
              fare;
      final riderWalletSnapshot = await tx.get(riderWalletRef);
      final riderWalletData = riderWalletSnapshot.data();
      final riderBalance =
          (riderWalletData?['balance'] as num?)?.toDouble() ?? 0.0;

      final driverWalletSnapshot = await tx.get(driverWalletRef);
      final driverWalletData = driverWalletSnapshot.data();
      final driverBalance =
          (driverWalletData?['balance'] as num?)?.toDouble() ?? 0.0;

      final newRiderBalance = riderBalance - amount;

      tx.update(rideRef, {
        'status': 'completed',
        'paymentStatus': 'settled',
        'updatedAt': FieldValue.serverTimestamp(),
      });

      tx.set(
          riderWalletRef,
          {
            'balance': newRiderBalance,
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true));

      tx.set(
          driverWalletRef,
          {
            'balance': driverBalance + amount,
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true));
    });
  }

  Future<void> cancelRideAndReleaseFunds({
    required String rideId,
    required String riderId,
  }) async {
    await _db.runTransaction((tx) async {
      final rideRef = _db.collection('rides').doc(rideId);
      final riderWalletRef = _db.collection('wallets').doc(riderId);

      final rideSnapshot = await tx.get(rideRef);
      if (!rideSnapshot.exists) {
        throw Exception('Ride not found');
      }

      final rideData = rideSnapshot.data();
      if (rideData == null) {
        throw Exception('Ride data missing');
      }

      final amount =
          ((rideData['finalFareCharged'] ?? rideData['estimatedCost']) as num?)
                  ?.toDouble() ??
              0.0;
      final walletSnapshot = await tx.get(riderWalletRef);
      final walletData = walletSnapshot.data();
      final balance = (walletData?['balance'] as num?)?.toDouble() ?? 0.0;
      final reservedBalance =
          (walletData?['reservedBalance'] as num?)?.toDouble() ?? 0.0;

      tx.update(rideRef, {
        'status': 'cancelled',
        'paymentStatus': 'refunded',
        'updatedAt': FieldValue.serverTimestamp(),
      });

      tx.set(
          riderWalletRef,
          {
            'balance': balance + amount,
            'reservedBalance':
                reservedBalance >= amount ? reservedBalance - amount : 0.0,
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true));
    });
  }

  // ==========================================
  //          METRICS & CONFIGURATIONS
  // ==========================================

  // Ride Types
  Stream<List<RideTypeModel>> streamRideTypes() {
    return _db
        .collection('rideTypes')
        .where('isActive', isEqualTo: true)
        .orderBy('sortOrder')
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => RideTypeModel.fromMap(doc.data(), doc.id))
              .toList(),
        );
  }

  Future<List<RideTypeModel>> getRideTypes() async {
    final snapshot = await _db
        .collection('rideTypes')
        .where('isActive', isEqualTo: true)
        .orderBy('sortOrder')
        .get();
    return snapshot.docs
        .map((doc) => RideTypeModel.fromMap(doc.data(), doc.id))
        .toList();
  }

  // Notifications
  Future<void> sendArrivalNotification({
    required String riderId,
    required String driverName,
    required String vehicleInfo,
    required String rideId,
  }) async {
    final notification = {
      'userId': riderId,
      'title': 'Driver Arrived!',
      'body': '$driverName has arrived in $vehicleInfo',
      'type': 'driver_arrived',
      'rideId': rideId,
      'read': false,
      'createdAt': FieldValue.serverTimestamp(),
    };

    await _db.collection('notifications').add(notification);
  }

  Stream<List<Map<String, dynamic>>> streamUserNotifications(String userId) {
    return _db
        .collection('notifications')
        .where('userId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => {'id': doc.id, ...doc.data()})
              .toList(),
        );
  }

  Future<void> markNotificationRead(String notificationId) async {
    await _db.collection('notifications').doc(notificationId).update({
      'read': true,
    });
  }

  // Driver ETA tracking
  Future<void> updateDriverEta({
    required String rideId,
    required int etaMinutes,
    required double distanceKm,
    required String driverStatus,
  }) async {
    await _db.collection('rides').doc(rideId).update({
      'driverEtaMinutes': etaMinutes,
      'driverDistanceKm': distanceKm,
      'driverStatus': driverStatus,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // ==========================================
  //    MVP INTERFACES & MOCK SIMULATIONS
  // ==========================================

  /// Updates candidate drivers assigned to a live request.
  Future<void> updateRideCandidateDrivers(
    String rideId,
    List<String> driverIds,
  ) async {
    await _db.collection('rides').doc(rideId).update({
      'candidateDrivers': driverIds,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Forces a mock status update sequence for simulator dashboard controllers.
  Future<void> updateMockTripStatus(String rideId, String status) async {
    await _db.collection('rides').doc(rideId).update({
      'status': status,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Creates a mock trip targeting dummy endpoints.
  Future<String> createMockTrip({
    required String riderId,
    required GeoPoint pickup,
    required GeoPoint destination,
    required String pickupAddress,
    required String destinationAddress,
    required double cost,
  }) async {
    final docRef = await _db.collection('rides').add({
      'userId': riderId,
      'pickupLocation': pickup,
      'destinationLocation': destination,
      'pickupAddress': pickupAddress,
      'destinationAddress': destinationAddress,
      'status': 'searching',
      'estimatedCost': cost,
      'createdAt': FieldValue.serverTimestamp(),
      'candidateDrivers': [],
      'driverId': null,
    });
    return docRef.id;
  }

  /// Spawns dummy tracking points directly into the drivers workspace loop.
  Future<int> seedMockDrivers(int count, GeoPoint centerPoint) async {
    final batch = _db.batch();
    for (int i = 0; i < count; i++) {
      final docRef = _db.collection('drivers').doc('mock-driver-$i');
      batch.set(docRef, {
        'driverId': 'mock-driver-$i',
        'name': 'Mock Driver #${i + 1}',
        'currentLocation': centerPoint,
        'isAvailable': true,
        'status': 'online',
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
    return count;
  }

  /// Streams available mock drivers.
  Future<List<Map<String, dynamic>>> getAvailableMockDrivers() async {
    final snapshot = await _db
        .collection('drivers')
        .where('isAvailable', isEqualTo: true)
        .where('status', isEqualTo: 'online')
        .get();

    return snapshot.docs
        .map((doc) => {
              'driverId': doc.id,
              ...doc.data(),
            })
        .toList();
  }

  /// Atomically pairs an unassigned simulation driver to a ride document request.
  Future<void> assignDriverAndAcceptTrip(String rideId, String driverId) async {
    await _db.runTransaction((transaction) async {
      final rideRef = _db.collection('rides').doc(rideId);
      final driverRef = _db.collection('drivers').doc(driverId);

      transaction.update(rideRef, {
        'driverId': driverId,
        'status': 'accepted',
        'updatedAt': FieldValue.serverTimestamp(),
      });

      transaction.update(driverRef, {
        'isAvailable': false,
        'currentRideId': rideId,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }
}
