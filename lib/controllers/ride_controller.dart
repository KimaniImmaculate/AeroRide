import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:aeroride/models/ride_request_model.dart';
import 'package:aeroride/utils/location_extensions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:aeroride/services/firestore_service.dart';
import 'package:aeroride/services/drivers_service.dart';
import 'package:aeroride/services/surge_pricing_service.dart';
import 'package:aeroride/services/simulation_service.dart';
import 'package:aeroride/models/user_model.dart';
import 'package:aeroride/models/ride_type_model.dart';

// Callback type for arrival notifications
typedef ArrivalCallback = void Function(String driverName, String vehicleInfo);

class RideController extends ChangeNotifier {
  final FirestoreService _firestoreService = FirestoreService();
  final DriversService _driversService = DriversService();
  final SurgePricingService _surgePricingService = SurgePricingService();

  StreamSubscription<RideRequest>? _rideSubscription;
  StreamSubscription<DocumentSnapshot>? _driverSubscription;

  Set<Marker> markers = {};
  Set<Polyline> polylines = {};
  GoogleMapController? mapController;

  String currentRideStatus = "IDLE";
  String? activeRideId;

  // Active locations and assigned profile
  LatLng? driverLocation;
  UserModel? assignedDriverProfile;
  LatLng? pickupLocation;
  LatLng? destinationLocation;
  double? estimatedCost;
  String? driverVehicle;
  String? driverRating;

  // Real-time tracking data
  int driverEtaMinutes = 0;
  double driverDistanceKm = 0.0;
  ArrivalCallback? onDriverArrived;

  // Ride type selection
  List<RideTypeModel> availableRideTypes = [];
  RideTypeModel? selectedRideType;
  String? selectedRideTypeId;

  // Core Flow: Triggers a new ride down to Firestore and maps it
  Future<void> requestNewRide({
    required String userId,
    required LatLng pickup,
    required LatLng destination,
    required String pickupText,
    required String dropoffText,
    List<String>? candidateDriverIds,
    bool autoAssignDriver = false,
  }) async {
    // 1. Fetch nearby drivers if not supplied
    if (candidateDriverIds == null || candidateDriverIds.isEmpty) {
      try {
        final nearby = await _driversService.getTopNearbyDrivers(
          pickup.latitude,
          pickup.longitude,
          limit: 5,
        );
        candidateDriverIds = nearby
            .take(5)
            .map((d) => d['driverId'] as String)
            .toList();
      } catch (_) {
        candidateDriverIds = null;
      }
    }

    final surgeQuote = await _surgePricingService.quoteForPickup(
      baseFare: 12.0,
      pickup: pickup,
    );

    RideRequest newRide = RideRequest(
      userId: userId,
      pickupLocation: pickup.toGeoPoint(),
      destinationLocation: destination.toGeoPoint(),
      pickupAddress: pickupText,
      destinationAddress: dropoffText,
      status: 'searching',
      estimatedCost: surgeQuote.finalFare,
      candidateDrivers: candidateDriverIds,
    );

    currentRideStatus = "REQUESTING...";
    notifyListeners();

    try {
      String rideId = await _firestoreService
          .createRideRequestWithWalletReservation(
            rideRequest: newRide,
            riderId: userId,
            fare: surgeQuote.finalFare,
          );
      activeRideId = rideId;

      // Keep the request visible to drivers unless the caller explicitly wants
      // to auto-assign a candidate driver for simulation flows.
      if (autoAssignDriver &&
          newRide.candidateDrivers != null &&
          newRide.candidateDrivers!.isNotEmpty) {
        _autoAssignDriver(rideId, newRide.candidateDrivers!);
      }

      // Instantly stream updates
      listenToLiveRide(rideId);
    } catch (e) {
      currentRideStatus = "ERROR: $e";
      notifyListeners();
      debugPrint("RideController: Error creating ride: $e");
    }
  }

  void listenToLiveRide(String rideId) {
    _rideSubscription?.cancel();
    _driverSubscription?.cancel();
    _driverSubscription = null;
    SimulationService.stopRideSimulation();

    activeRideId = rideId;
    driverLocation = null;
    assignedDriverProfile = null;

    _rideSubscription = _firestoreService
        .streamRideStatus(rideId)
        .listen(
          (RideRequest liveRide) async {
            currentRideStatus = liveRide.status.toUpperCase();
            pickupLocation = liveRide.pickupLocation.toLatLng();
            destinationLocation = liveRide.destinationLocation.toLatLng();
            estimatedCost = liveRide.estimatedCost;

            // Set up driver subscription if accepted or in progress
            final driverId = liveRide.driverId;
            if (driverId != null &&
                (currentRideStatus == 'ACCEPTED' ||
                    currentRideStatus == 'ARRIVED' ||
                    currentRideStatus == 'STARTED' ||
                    currentRideStatus == 'COMPLETED')) {
              _setupDriverSubscription(driverId);
              _setupDriverProfile(driverId);

              // If it's a simulated driver and status is accepted, trigger the simulation runner
              if (driverId.startsWith('sim-driver-') &&
                  currentRideStatus == 'ACCEPTED') {
                SimulationService.simulateRideLifecycle(
                  rideId: rideId,
                  driverId: driverId,
                  pickup: pickupLocation!,
                  destination: destinationLocation!,
                );
              }
            }

            if (currentRideStatus == 'COMPLETED' ||
                currentRideStatus == 'CANCELLED') {
              _driverSubscription?.cancel();
              _driverSubscription = null;
              SimulationService.stopRideSimulation();
            }

            _updateMarkersAndPolylines();
            _fitCameraToRoute();
            notifyListeners();
          },
          onError: (error) {
            currentRideStatus = "STREAM ERROR: $error";
            notifyListeners();
            debugPrint("RideController: Stream error: $error");
          },
        );
  }

  void _setupDriverSubscription(String driverId) {
    if (_driverSubscription != null) return;

    _driverSubscription = FirebaseFirestore.instance
        .collection('drivers')
        .doc(driverId)
        .snapshots()
        .listen((snapshot) {
          if (snapshot.exists && snapshot.data() != null) {
            final gp = snapshot.data()!['current_location'] as GeoPoint?;
            if (gp != null) {
              driverLocation = gp.toLatLng();
              _updateMarkersAndPolylines();
              notifyListeners();
            }
          }
        });
  }

  Future<void> _setupDriverProfile(String driverId) async {
    if (assignedDriverProfile != null &&
        assignedDriverProfile!.uid == driverId) {
      return;
    }

    if (driverId.startsWith('sim-driver-')) {
      final indexStr = driverId.split('-').last;
      final int index = int.tryParse(indexStr) ?? 0;

      final names = [
        "James K.",
        "Sarah M.",
        "David O.",
        "Emily W.",
        "Michael T.",
      ];
      final cars = [
        "Silver Nissan Leaf • KDD 555Y",
        "White Toyota Prius • KCA 123Z",
        "Blue Honda Fit • KCB 987X",
        "Red Mazda 3 • KCD 456W",
        "Black Tesla Model 3 • KCE 789V",
      ];
      final ratings = ["4.9", "4.8", "4.7", "4.9", "4.8"];

      assignedDriverProfile = UserModel(
        uid: driverId,
        name: names[index % names.length],
        email: 'driver$index@aeroride-sim.com',
        role: "driver",
      );
      driverVehicle = cars[index % cars.length];
      driverRating = ratings[index % ratings.length];
      notifyListeners();
    } else {
      try {
        final profile = await _firestoreService.getUserProfile(driverId);
        assignedDriverProfile = profile;
        driverVehicle = "Standard Cab • KAA 001A";
        driverRating = "4.5";
        notifyListeners();
      } catch (e) {
        debugPrint('RideController: Failed to fetch driver profile: $e');
      }
    }
  }

  void _updateMarkersAndPolylines() {
    markers.clear();

    if (pickupLocation != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('pickup'),
          position: pickupLocation!,
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueGreen,
          ),
          infoWindow: const InfoWindow(title: "Pickup Location"),
        ),
      );
    }

    if (destinationLocation != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('destination'),
          position: destinationLocation!,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          infoWindow: const InfoWindow(title: "Destination"),
        ),
      );
    }

    if (driverLocation != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('driver'),
          position: driverLocation!,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
          infoWindow: InfoWindow(
            title: assignedDriverProfile?.name ?? "Driver",
            snippet: currentRideStatus == 'ACCEPTED'
                ? "On the way to pickup"
                : currentRideStatus == 'ARRIVED'
                ? "Arrived at pickup"
                : "In transit to destination",
          ),
        ),
      );
    }

    polylines.clear();
    if (pickupLocation != null && destinationLocation != null) {
      if (currentRideStatus == 'ACCEPTED' && driverLocation != null) {
        polylines.add(
          Polyline(
            polylineId: const PolylineId('driver_to_pickup'),
            points: [driverLocation!, pickupLocation!],
            color: Colors.orange,
            width: 5,
          ),
        );
      } else if (currentRideStatus == 'STARTED' && driverLocation != null) {
        polylines.add(
          Polyline(
            polylineId: const PolylineId('driver_to_destination'),
            points: [driverLocation!, destinationLocation!],
            color: Colors.blue,
            width: 5,
          ),
        );
      } else {
        polylines.add(
          Polyline(
            polylineId: const PolylineId('route'),
            points: [pickupLocation!, destinationLocation!],
            color: Colors.blue.withValues(alpha: 0.5),
            width: 4,
          ),
        );
      }
    }
  }

  void _fitCameraToRoute() {
    if (mapController == null) return;

    final points = <LatLng>[];
    if (pickupLocation != null) points.add(pickupLocation!);
    if (destinationLocation != null) points.add(destinationLocation!);
    if (driverLocation != null) points.add(driverLocation!);

    if (points.isEmpty) return;

    if (points.length == 1) {
      mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(points.first, 15),
      );
      return;
    }

    double minLat = points.first.latitude;
    double maxLat = points.first.latitude;
    double minLng = points.first.longitude;
    double maxLng = points.first.longitude;

    for (final p in points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }

    final bounds = LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );

    mapController?.animateCamera(CameraUpdate.newLatLngBounds(bounds, 80));
  }

  Future<void> _autoAssignDriver(
    String rideId,
    List<String> candidateDriverIds,
  ) async {
    try {
      await FirebaseFirestore.instance.runTransaction((tx) async {
        final docRef = FirebaseFirestore.instance
            .collection('rides')
            .doc(rideId);
        final snapshot = await tx.get(docRef);
        if (!snapshot.exists) return;
        final data = snapshot.data();
        final status = data?['status'];
        if (status != 'searching') return;

        String? chosen;
        for (final id in candidateDriverIds) {
          final driverDoc = await tx.get(
            FirebaseFirestore.instance.collection('drivers').doc(id),
          );
          final driverData = driverDoc.data();
          if (driverData != null && (driverData['isOnline'] == true)) {
            chosen = id;
            break;
          }
        }
        chosen ??= candidateDriverIds.first;

        tx.update(docRef, {
          'status': 'accepted',
          'driverId': chosen,
          'assignedAt': FieldValue.serverTimestamp(),
        });
      });
    } catch (e) {
      debugPrint('RideController: Auto-assign failed: $e');
    }
  }

  Future<void> _sendArrivalNotification(RideRequest ride) async {
    if (ride.driverId == null) return;

    try {
      final driverDoc = await _firestoreService._db
          .collection('drivers')
          .doc(ride.driverId)
          .get();
      final driverData = driverDoc.data();
      if (driverData == null) return;

      final driverName = driverData['name'] ?? 'Your driver';
      final vehicleInfo =
          '${driverData['vehicleModel'] ?? ''} ${driverData['vehicleColor'] ?? ''}'
              .trim();

      await _firestoreService.sendArrivalNotification(
        riderId: ride.userId,
        driverName: driverName,
        vehicleInfo: vehicleInfo.isEmpty ? 'the vehicle' : vehicleInfo,
        rideId: ride.id,
      );

      // Call the local callback if set
      onDriverArrived?.call(driverName, vehicleInfo);
    } catch (e) {
      debugPrint('RideController: Failed to send arrival notification: $e');
    }
  }

  void setOnDriverArrived(ArrivalCallback callback) {
    onDriverArrived = callback;
  }

  Future<void> loadRideTypes() async {
    try {
      availableRideTypes = await _firestoreService.getRideTypes();
      if (availableRideTypes.isNotEmpty && selectedRideType == null) {
        selectedRideType = availableRideTypes.first;
        selectedRideTypeId = selectedRideType!.id;
      }
      notifyListeners();
    } catch (e) {
      debugPrint('RideController: Failed to load ride types: $e');
    }
  }

  void selectRideType(RideTypeModel type) {
    selectedRideType = type;
    selectedRideTypeId = type.id;
    notifyListeners();
  }

  Future<void> cancelActiveRide() async {
    if (activeRideId != null) {
      try {
        await FirebaseFirestore.instance
            .collection('rides')
            .doc(activeRideId)
            .update({'status': 'cancelled'});
      } catch (e) {
        debugPrint(
          'RideController: Error updating cancel status in Firestore: $e',
        );
      }
    }
    cancelActiveTracking();
  }

  void cancelActiveTracking() {
    _rideSubscription?.cancel();
    _driverSubscription?.cancel();
    _driverSubscription = null;
    SimulationService.stopRideSimulation();
    markers.clear();
    polylines.clear();
    currentRideStatus = "IDLE";
    activeRideId = null;
    driverLocation = null;
    assignedDriverProfile = null;
    pickupLocation = null;
    destinationLocation = null;
    estimatedCost = null;
    driverVehicle = null;
    driverRating = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _rideSubscription?.cancel();
    _driverSubscription?.cancel();
    SimulationService.stopRideSimulation();
    super.dispose();
  }
}
