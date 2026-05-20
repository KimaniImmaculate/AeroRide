import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:aeroride/models/ride_request_model.dart'; // Absolute Import
import 'package:aeroride/utils/location_extensions.dart';
import 'package:aeroride/services/firestore_service.dart';
import 'package:aeroride/services/drivers_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class RideController extends ChangeNotifier {
  final FirestoreService _firestoreService = FirestoreService();
  final DriversService _driversService = DriversService();
  StreamSubscription<RideRequest>? _rideSubscription;
  StreamSubscription<DocumentSnapshot>? _driverLocationSub;

  Set<Marker> markers = {};
  Set<Polyline> polylines = {};
  GoogleMapController? mapController;

  String currentRideStatus = "IDLE";
  String? activeRideId;

  // Core Flow: Triggers a new ride down to Firestore and maps it
  Future<void> requestNewRide({
    required String userId,
    required LatLng pickup,
    required LatLng destination,
    required String pickupText,
    required String dropoffText,
    List<String>? candidateDriverIds,
  }) async {
    // 1. Build data payload mapping directly to GeoPoints
    // If caller supplied candidate drivers use them, otherwise pick nearest 3
    if (candidateDriverIds == null) {
      try {
        final nearby = await _driversService.getNearbyDrivers(
          pickup.latitude,
          pickup.longitude,
          radiusKm: 5.0,
        );
        candidateDriverIds = nearby
            .take(3)
            .map((d) => d['driverId'] as String)
            .toList();
      } catch (_) {
        candidateDriverIds = null;
      }
    }

    RideRequest newRide = RideRequest(
      userId: userId,
      pickupLocation: pickup.toGeoPoint(),
      destinationLocation: destination.toGeoPoint(),
      pickupAddress: pickupText,
      destinationAddress: dropoffText,
      status: 'searching',
      estimatedCost: 18.75,
      candidateDrivers: candidateDriverIds,
    );

    // 2. Upload to database
    currentRideStatus = "REQUESTING...";
    notifyListeners();

    try {
      String rideId = await _firestoreService.createRideRequest(newRide);
      activeRideId = rideId;

      // 3. Instantly bind our UI map directly to the newly spawned document stream
      listenToLiveRide(rideId);
    } catch (e) {
      currentRideStatus = "ERROR: $e";
      notifyListeners();
      debugPrint("Error creating ride: $e");
    }
  }

  void listenToLiveRide(String rideId) {
    _rideSubscription?.cancel();

    _rideSubscription = _firestoreService
        .streamRideStatus(rideId)
        .listen(
          (RideRequest liveRide) {
            currentRideStatus = liveRide.status.toUpperCase();

            final pickupLatLng = liveRide.pickupLocation.toLatLng();
            final destinationLatLng = liveRide.destinationLocation.toLatLng();

            markers.clear();
            markers.add(
              Marker(
                markerId: const MarkerId('pickup'),
                position: pickupLatLng,
                icon: BitmapDescriptor.defaultMarkerWithHue(
                  BitmapDescriptor.hueGreen,
                ),
              ),
            );
            markers.add(
              Marker(
                markerId: const MarkerId('destination'),
                position: destinationLatLng,
                icon: BitmapDescriptor.defaultMarkerWithHue(
                  BitmapDescriptor.hueRed,
                ),
              ),
            );

            polylines.clear();
            polylines.add(
              Polyline(
                polylineId: const PolylineId('route'),
                points: [pickupLatLng, destinationLatLng],
                color: Colors.blue,
                width: 5,
              ),
            );

            notifyListeners();

            // If driver assigned, listen for driver's location updates and animate marker
            _driverLocationSub?.cancel();
            if (liveRide.driverId != null) {
              _driverLocationSub = FirebaseFirestore.instance
                  .collection('drivers')
                  .doc(liveRide.driverId)
                  .snapshots()
                  .listen((doc) {
                    if (!doc.exists || doc.data() == null) return;
                    final data = doc.data() as Map<String, dynamic>;
                    if (data['current_location'] != null) {
                      final gp = data['current_location'] as GeoPoint;
                      final driverLatLng = LatLng(gp.latitude, gp.longitude);

                      // update driver marker
                      markers.removeWhere((m) => m.markerId.value == 'driver');
                      markers.add(
                        Marker(
                          markerId: const MarkerId('driver'),
                          position: driverLatLng,
                          icon: BitmapDescriptor.defaultMarkerWithHue(
                            BitmapDescriptor.hueBlue,
                          ),
                          infoWindow: const InfoWindow(title: 'Driver'),
                        ),
                      );
                      notifyListeners();

                      // optionally pan camera to show driver and pickup
                      mapController?.animateCamera(
                        CameraUpdate.newLatLng(driverLatLng),
                      );
                    }
                  });
            }

            // Pan camera to the pickup spot
            mapController?.animateCamera(
              CameraUpdate.newLatLngZoom(pickupLatLng, 14.0),
            );
          },
          onError: (error) {
            currentRideStatus = "STREAM ERROR: $error";
            notifyListeners();
            debugPrint("Stream error: $error");
          },
        );
  }

  void cancelActiveTracking() {
    _rideSubscription?.cancel();
    markers.clear();
    polylines.clear();
    currentRideStatus = "IDLE";
    activeRideId = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _rideSubscription?.cancel();
    super.dispose();
  }
}
