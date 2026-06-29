import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/material.dart'; // Added for ChangeNotifier support

class RideService {
  final FirebaseFirestore firestore = FirebaseFirestore.instance;

  Future<String> requestRide({
    required String pickup,
    required String destination,
    required double fare,
    required String rideTier,
    String? notes,
  }) async {
    print("Entered requestRide");
    final currentUser = FirebaseAuth.instance.currentUser;

    final rideRef = await firestore.collection('rides').add({
      'pickup': pickup,
      'destination': destination,
      'status': 'searching',
      'fare': fare.round(),
      'estimatedFare': fare.round(),
      'rideTier': rideTier,
      if (notes != null && notes.isNotEmpty) 'notes': notes,
      'createdAt': Timestamp.now(),
      'riderId': currentUser?.uid,
      'riderEmail': currentUser?.email,
    });
    print("Ride document created");
    return rideRef.id;
  }

  Future<void> acceptRide({
    required String rideId,
  }) async {
    final currentDriver = FirebaseAuth.instance.currentUser;

    Position position = await Geolocator.getCurrentPosition();

    await firestore.collection('rides').doc(rideId).update({
      'status': 'accepted',
      'driverId': currentDriver?.uid,
      'driverEmail': currentDriver?.email,
      'driverLatitude': position.latitude,
      'driverLongitude': position.longitude,
    });
  }

  Future<void> startRide({
    required String rideId,
  }) async {
    await firestore.collection('rides').doc(rideId).update({
      'status': 'started',
    });
  }

  Future<void> completeRide({
    required String rideId,
  }) async {
    final rideDoc = await firestore.collection('rides').doc(rideId).get();
    final rideData = rideDoc.data();

    if (rideData != null) {
      final driverId = rideData['driverId'];
      final fare = double.tryParse(rideData['fare'].toString()) ?? 0;
      final driverEarnings = fare * 0.75;
      final platformFee = fare * 0.25;

      await firestore.collection('rides').doc(rideId).update({
        'status': 'completed',
        'paymentStatus': 'pending',
        'paymentMethod': 'M-Pesa',
        'completedAt': Timestamp.now(),
        'driverEarnings': driverEarnings,
        'platformFee': platformFee,
      });

      if (driverId != null) {
        final driverDoc = await firestore.collection('users').doc(driverId).get();
        double currentEarnings = 0;
        double currentPlatformEarnings = 0;
        int currentTotalTrips = 0;

        final driverData = driverDoc.data();
        if (driverData != null) {
          if (driverData['earnings'] != null) {
            currentEarnings =
                double.tryParse(driverData['earnings'].toString()) ?? 0;
          }
          if (driverData['platformEarnings'] != null) {
            currentPlatformEarnings =
                double.tryParse(driverData['platformEarnings'].toString()) ?? 0;
          }
          if (driverData['totalTrips'] != null) {
            currentTotalTrips =
                int.tryParse(driverData['totalTrips'].toString()) ?? 0;
          }
        }

        await firestore.collection('users').doc(driverId).update({
          'earnings': currentEarnings + driverEarnings,
          'platformEarnings': currentPlatformEarnings + platformFee,
          'totalTrips': currentTotalTrips + 1,
        });
      }
    }
  }

  Future<void> updateDriverRating({
    required String driverId,
  }) async {
    final rides = await firestore
        .collection('rides')
        .where('driverId', isEqualTo: driverId)
        .where('rating', isNull: false)
        .get();

    if (rides.docs.isEmpty) return;

    double total = 0;
    for (var ride in rides.docs) {
      total += (ride['rating'] as num).toDouble();
    }

    final average = total / rides.docs.length;

    await firestore.collection('users').doc(driverId).update({
      'averageRating': average,
      'totalRatings': rides.docs.length,
    });
  }

  Future<void> cancelRide({
    required String rideId,
    required String cancelledBy,
    required String reason,
  }) async {
    final rideDoc = await firestore.collection('rides').doc(rideId).get();
    int? cancellationFee;
    
    if (rideDoc.exists && rideDoc.data() != null) {
      final data = rideDoc.data()!;
      final tier = data['rideTier']?.toString().toLowerCase() ?? 'tulia';
      
      switch (tier) {
        case 'nuru':
          cancellationFee = 350;
          break;
        case 'pamoja':
          cancellationFee = 500;
          break;
        case 'waziri':
          cancellationFee = 700;
          break;
        case 'tulia':
        default:
          cancellationFee = 150;
      }
    }

    final updateData = <String, dynamic>{
      'status': 'cancelled',
      'cancelledBy': cancelledBy,
      'cancelReason': reason,
      'cancelledAt': Timestamp.now(),
    };
    
    if (cancellationFee != null) {
      updateData['fare'] = cancellationFee;
    }

    await firestore.collection('rides').doc(rideId).update(updateData);
  }
}

// =========================================================================
// 🎨 ADDED TO THE BOTTOM: APPNATION STATE CONTROLLER FOR RIDER SELECTIONS
// =========================================================================

/// Keeps the rider's active tier selection tracked in-app memory
class RideController extends ChangeNotifier {
  VehicleTier? _selectedTier;

  VehicleTier? get selectedTier => _selectedTier;

  void selectTier(VehicleTier tier) {
    _selectedTier = tier;
    notifyListeners();
  }

  void clearSelection() {
    _selectedTier = null;
    notifyListeners();
  }
}

/// System properties matching the dynamic card structures
class VehicleTier {
  final String id;
  final String name;
  final String description;
  final double baseFare;
  final double perKmRate;
  final int capacity;
  final List<String> benefits;
  final String iconPath;

  VehicleTier({
    required this.id,
    required this.name,
    required this.description,
    required this.baseFare,
    required this.perKmRate,
    required this.capacity,
    required this.benefits,
    required this.iconPath,
  });
}
