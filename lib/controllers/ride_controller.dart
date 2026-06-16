import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:aeroride/models/ride_request_model.dart';
import 'package:aeroride/utils/location_extensions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:aeroride/services/firestore_service.dart';
import 'package:aeroride/services/drivers_service.dart';
import 'package:aeroride/services/simulation_service.dart';
import 'package:aeroride/models/user_model.dart';
import 'package:aeroride/models/vehicle_tier_model.dart';
import 'package:aeroride/models/ride_type_model.dart';
import 'package:aeroride/services/notification_service.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:aeroride/utils/fare_calculator.dart';
import 'package:aeroride/utils/location_utils.dart';
import 'package:aeroride/utils/exceptions.dart'; // Import the new exceptions

typedef ArrivalCallback = void Function(String driverName, String vehicleInfo);
typedef RideCompletionCallback = void Function(
    String driverId, String driverName);

class RideController extends ChangeNotifier {
  final FirestoreService _firestoreService = FirestoreService();
  final DriversService _driversService = DriversService();

  StreamSubscription<RideRequest>? _rideSubscription;
  StreamSubscription<DocumentSnapshot>? _driverSubscription;
  StreamSubscription<Position>? _riderPositionSubscription;

  Set<Marker> markers = {};
  Set<Polyline> polylines = {};
  GoogleMapController? mapController;

  String currentRideStatus = "IDLE";
  String? activeRideId;

  void Function(String driverName, String vehicleInfo)? onDriverArrived;
  RideCompletionCallback? onRideCompleted;

  // Active locations and assigned profile
  LatLng? driverLocation;
  LatLng? riderLocation;
  UserModel? assignedDriverProfile;
  LatLng? pickupLocation;
  LatLng? destinationLocation;
  double? estimatedCost;
  String? driverVehicle;
  String? driverRating;
  String? rideVerificationOtp = '----';

  // Real-time tracking data
  int driverEtaMinutes = 0;
  double driverDistanceKm = 0.0;

  // Ride type selection
  List<RideTypeModel> availableRideTypes = [];
  RideTypeModel? selectedRideType;
  String? selectedRideTypeId;

  // Vehicle Tier logic
  List<VehicleTier> vehicleTiers = [];
  VehicleTier? _selectedTier;

  VehicleTier? get selectedTier => _selectedTier;

  set selectedTier(VehicleTier? tier) {
    if (_selectedTier != tier) {
      _selectedTier = tier;
      notifyListeners();
    }
  }

  // Nearby driver previews shown while waiting for assignment.
  List<Map<String, dynamic>> nearbyDriverPreviews = [];

  BitmapDescriptor? _driverMarkerIcon;
  BitmapDescriptor? _nearbyDriverMarkerIcon;
  BitmapDescriptor? _kipronoIcon;
  BitmapDescriptor? _cheptooIcon;
  BitmapDescriptor? _cheronoIcon;
  bool _markerIconsLoading = false;

  String get driverEtaLabel {
    if (currentRideStatus == 'ARRIVED') return 'Arrived';
    if (driverEtaMinutes <= 0) return '1 min';
    return driverEtaMinutes == 1 ? '1 min' : '$driverEtaMinutes min';
  }

  // Core Flow: Triggers a new ride down to Firestore and maps it
  Future<void> requestNewRide({
    required String userId,
    required String riderName,
    required LatLng pickup,
    required LatLng destination,
    required String pickupText,
    required String dropoffText,
    List<String>? candidateDriverIds,
    bool autoAssignDriver = false,
    String rideType = 'standard',
  }) async {
    var stage = 'initializing';
    final simulationMode = kDebugMode;

    try {
      currentRideStatus = "CONTACTING DRIVER...";
      notifyListeners();

      stage = 'loading ride types';
      // Ensure tiers are loaded if the background task hasn't finished
      if (vehicleTiers.isEmpty) {
        await loadRideTypes();
      }

      // TIER RESOLUTION: Honor explicit rideType if provided, otherwise ensure we have a valid selection.
      if (vehicleTiers.isNotEmpty) {
        if (rideType != 'standard') {
          selectedTier = vehicleTiers.firstWhere(
            (t) => t.id.toLowerCase() == rideType.toLowerCase(),
            orElse: () => selectedTier ?? vehicleTiers.first,
          );
        }
        selectedTier ??= vehicleTiers.first;
      }

      stage = 'resolving user identity';
      // 👤 AUTH SYNC: Ensure we use the absolute latest UID from the Auth instance
      // to prevent "permission-denied" errors during transition from guest to real account.
      final freshUser = FirebaseAuth.instance.currentUser;
      final resolvedUserId = freshUser?.uid ?? userId;

      final resolvedRiderName = (freshUser?.displayName?.isNotEmpty == true)
          ? freshUser!.displayName!
          : (riderName.trim().isEmpty ? "AeroRide User" : riderName);

      stage = 'calculating trip metrics';
      // Use the selected tier to calculate the precise fare
      final distance = LocationUtils.calculateDistanceKm(pickup, destination);
      final rideFare = FareCalculator.calculateFare(selectedTier?.id, distance);

      final List<String> resolvedCandidateDrivers =
          List<String>.from(candidateDriverIds ?? []);

      stage = 'identifying simulation candidates';
      // Use dynamically registered drivers for simulation if none were provided
      if (simulationMode && resolvedCandidateDrivers.isEmpty) {
        final nearby = await _driversService
            .getSelectableDrivers(referenceLocation: pickup, limit: 3)
            .timeout(const Duration(seconds: 5), onTimeout: () => []);

        resolvedCandidateDrivers.addAll(
          nearby
              .map((d) => (d['driverId'] ?? d['id'] ?? '').toString())
              .where((id) => id.isNotEmpty)
              .toList(),
        );
      }

      stage = 'preparing simulation environment';
      // Ensure mock drivers are active in simulation mode to prevent matching stalls
      if (simulationMode && resolvedCandidateDrivers.isNotEmpty) {
        await SimulationService.prepareDriversForSimulation(
          resolvedCandidateDrivers,
          pickup,
        );

        // Re-read the assigned driver to populate local state instantly
        final driverSnap = await FirebaseFirestore.instance
            .collection('users')
            .doc(resolvedCandidateDrivers.first)
            .get();
        if (driverSnap.exists) {
          final data = driverSnap.data()!;
          final gp = (data['currentLocation'] ?? data['current_location'])
              as GeoPoint?;
          if (gp != null) driverLocation = gp.toLatLng();
        }
      }

      stage = 'preparing request data';
      final newRide = RideRequest(
        userId: resolvedUserId,
        riderName: resolvedRiderName,
        pickupLocation: pickup.toGeoPoint(),
        destinationLocation: destination.toGeoPoint(),
        pickupAddress: pickupText,
        destinationAddress: dropoffText,
        status: 'searching',
        estimatedCost: rideFare,
        candidateDrivers: resolvedCandidateDrivers,
        rideTier: selectedTier?.id?.toLowerCase() ?? 'tulia',
      );

      stage = 'creating ride request';
      String rideId =
          await _firestoreService.createRideRequestWithWalletReservation(
        rideRequest: newRide,
        riderId: resolvedUserId,
        fare: rideFare,
      );
      activeRideId = rideId;
      final shouldAutoAssign = autoAssignDriver || simulationMode;

      // Keep the request visible to drivers unless the caller explicitly wants
      // to auto-assign a candidate driver for simulation flows.
      if (shouldAutoAssign &&
          newRide.candidateDrivers != null &&
          newRide.candidateDrivers!.isNotEmpty) {
        _autoAssignDriver(rideId, newRide.candidateDrivers!);
      }

      // Instantly stream updates
      listenToLiveRide(rideId);
    } catch (e, st) {
      currentRideStatus = "ERROR: ${e.toString()}";
      notifyListeners();
      debugPrint('RideController: requestNewRide failed at stage: $stage');
      debugPrint('RideController: generic error: $e');
      try {
        final dynamic boxedError = e;
        final jsError = boxedError.error;
        final jsStack = boxedError.stack;
        debugPrint('RideController: boxed JS error: $jsError');
        debugPrint('RideController: boxed JS stack: $jsStack');
      } catch (_) {
        // Not a boxed JS error; ignore.
      }
      debugPrintStack(stackTrace: st, label: 'RideController.requestNewRide');
    }
  }

  Future<void> _populateNearbyDriversForRide({
    required String rideId,
    required LatLng pickup,
    required int limit,
  }) async {
    if (FirebaseAuth.instance.currentUser == null) {
      return;
    }

    try {
      final nearby = await _driversService
          .getSelectableDrivers(referenceLocation: pickup, limit: limit)
          .timeout(const Duration(seconds: 4), onTimeout: () => []);

      nearbyDriverPreviews = nearby;
      _updateMarkersAndPolylines();
      notifyListeners();

      final driverIds = nearby
          .take(limit)
          .map((driver) => driver['driverId'] as String)
          .toList();
      if (driverIds.isEmpty) {
        return;
      }

      // FIXED: Using activeRideId to ensure the variable is defined in this scope
      if (activeRideId != null) {
        await _firestoreService.updateRideCandidateDrivers(
            activeRideId!, driverIds);
      } else {
        debugPrint(
            'RideController: Cannot update candidate drivers because activeRideId is null.');
      }
    } catch (error) {
      debugPrint('RideController: nearby driver refresh skipped: $error');
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

    _rideSubscription = _firestoreService.streamRideStatus(rideId).listen(
      (RideRequest liveRide) async {
        final prevStatus = currentRideStatus;
        currentRideStatus = liveRide.status.toUpperCase();
        pickupLocation = liveRide.pickupLocation.toLatLng();
        destinationLocation = liveRide.destinationLocation.toLatLng();
        estimatedCost = liveRide.estimatedCost;

        // Sync the verification PIN from the typed RideRequest model
        if (liveRide.otp != null && liveRide.otp!.isNotEmpty) {
          rideVerificationOtp = liveRide.otp;
        }

        // Status Milestones: Trigger highly stylized context-specific notifications
        if (prevStatus != currentRideStatus) {
          String notificationTitle = "AeroRide Update";
          String notificationBody = "";
          switch (currentRideStatus) {
            case 'SEARCHING':
              notificationBody =
                  "Assembling your premium environment options...";
              break;
            case 'ACCEPTED':
              notificationBody =
                  "Your dedicated chauffeur has accepted the trajectory. Preparing cabin workspace...";
              break;
            case 'ARRIVED':
              notificationBody =
                  "The fleet vehicle has touched down at your terminal location. Ready when you are...";
              break;
            case 'STARTED':
              notificationBody =
                  "Trajectory engaged. Transitioning to optimal atmospheric equilibrium...";
              break;
          }
          if (notificationBody.isNotEmpty)
            NotificationService().showLocalNotification(
                title: notificationTitle, body: notificationBody);
        }

        final rideVehicleLocation = liveRide.currentVehicleLocation;
        if (rideVehicleLocation != null) {
          driverLocation = rideVehicleLocation.toLatLng();
        }

        // Set up driver subscription if accepted or in progress
        final driverId = liveRide.driverId;
        if (driverId != null &&
            (currentRideStatus == 'ACCEPTED' ||
                currentRideStatus == 'ARRIVED' ||
                currentRideStatus == 'STARTED' ||
                currentRideStatus == 'COMPLETED')) {
          _setupDriverSubscription(driverId);
          _setupDriverProfile(driverId);

          // In simulation mode, treat any assigned driver as a simulation candidate
          final isSimulated = kDebugMode;

          if (isSimulated &&
              (currentRideStatus == 'ACCEPTED' ||
                  currentRideStatus == 'STARTED')) {
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

        // Notify UI when driver arrives
        if (prevStatus != 'ARRIVED' && currentRideStatus == 'ARRIVED') {
          // Only generate a new OTP if one doesn't exist yet to prevent overwrites
          if (rideVerificationOtp == '----') {
            final driverName = assignedDriverProfile?.name ?? 'Driver';
            final vehicle = driverVehicle ?? '';

            // 1. Generate a random 4-digit PIN string right when the status shifts to ARRIVED
            final String randomPin = (1000 + Random().nextInt(9000)).toString();

            // Update locally for instant display before the snapshot round-trip
            rideVerificationOtp = randomPin;
            notifyListeners();

            // 2. Update the current active Firestore ride document immediately under the 'otp' field
            await FirebaseFirestore.instance
                .collection('rides')
                .doc(rideId)
                .update({
              'otp': randomPin,
            });

            await _sendArrivalNotification(liveRide);
            if (onDriverArrived != null) {
              onDriverArrived!.call(driverName, vehicle);
            }
            try {
              NotificationService().showLocalNotification(
                title: 'Driver Arrived',
                body: '$driverName has arrived in $vehicle',
              );
            } catch (_) {}
          }
        }

        // Notify UI when trip is completed so rider can rate the driver
        if (prevStatus != 'COMPLETED' && currentRideStatus == 'COMPLETED') {
          if (onRideCompleted != null && liveRide.driverId != null) {
            onRideCompleted!(
                liveRide.driverId!, assignedDriverProfile?.name ?? 'Driver');
          }
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
        .collection('users')
        .doc(driverId)
        .snapshots()
        .listen((snapshot) {
      if (snapshot.exists && snapshot.data() != null) {
        final data = snapshot.data()!;
        // FIXED: Fallback safety to check both camelCase and snake_case properties
        final gp =
            (data['currentLocation'] ?? data['current_location']) as GeoPoint?;
        if (gp != null) {
          driverLocation = gp.toLatLng();
          // compute ETA and distance
          try {
            if (pickupLocation != null) {
              driverDistanceKm = LocationUtils.calculateDistanceKm(
                  driverLocation!, pickupLocation!);
              driverEtaMinutes = LocationUtils.calculateETA(driverDistanceKm);
            }
            if (destinationLocation != null && currentRideStatus == 'STARTED') {
              driverDistanceKm = LocationUtils.calculateDistanceKm(
                  driverLocation!, destinationLocation!);
              driverEtaMinutes = LocationUtils.calculateETA(driverDistanceKm);
            }
          } catch (_) {}

          // persist ETA to Firestore for server-side visibility
          try {
            if (activeRideId != null) {
              _firestoreService.updateDriverEta(
                rideId: activeRideId!,
                etaMinutes: driverEtaMinutes,
                distanceKm: driverDistanceKm,
                driverStatus: currentRideStatus.toLowerCase(),
              );
            }
          } catch (_) {}

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
        // Fetch real data from the user collection
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(driverId)
            .get();
        if (doc.exists) {
          final data = doc.data()!;
          assignedDriverProfile = UserModel(
            uid: driverId,
            name: data['name'] ?? 'Driver',
            email: data['email'] ?? '',
            role: "driver",
          );

          final model = data['vehicleModel'] ?? 'Vehicle';
          final color = data['vehicleColor'] ?? '';
          final plate = data['plateNumber'] ?? '';

          driverVehicle = "$color $model • $plate".trim();
          driverRating = (data['rating'] ?? "5.0").toString();
        }
        notifyListeners();
      } catch (e) {
        debugPrint('RideController: Failed to fetch driver profile: $e');
      }
    }
  }

  void _updateMarkersAndPolylines() {
    // Trigger marker icon loading if any required premium vector is missing
    if (!_markerIconsLoading &&
        (_driverMarkerIcon == null ||
            _nearbyDriverMarkerIcon == null ||
            _kipronoIcon == null ||
            _cheptooIcon == null ||
            _cheronoIcon == null)) {
      unawaited(_loadMarkerIcons());
    }

    markers.clear();

    if (riderLocation != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('rider'),
          position: riderLocation!,
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueAzure,
          ),
          infoWindow: const InfoWindow(title: 'Your location'),
        ),
      );
    }

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
      final String driverId = assignedDriverProfile?.uid ?? 'driver';
      final String? name = assignedDriverProfile?.name;

      markers.add(
        Marker(
          markerId: MarkerId(driverId),
          position: driverLocation!,
          icon: _getDriverIcon(
            name,
            _driverMarkerIcon ??
                BitmapDescriptor.defaultMarkerWithHue(
                    BitmapDescriptor.hueYellow),
          ),
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

    if ((currentRideStatus == 'REQUESTING...' ||
            currentRideStatus == 'SEARCHING') &&
        nearbyDriverPreviews.isNotEmpty) {
      for (var index = 0; index < nearbyDriverPreviews.length; index++) {
        final preview = nearbyDriverPreviews[index];
        final location = preview['location'] as LatLng?;
        if (location == null) continue;
        markers.add(
          Marker(
            markerId: MarkerId('candidate_driver_$index'),
            position: location,
            icon: _nearbyDriverMarkerIcon ??
                BitmapDescriptor.defaultMarkerWithHue(
                  BitmapDescriptor.hueOrange,
                ),
            infoWindow: const InfoWindow(title: 'Nearby driver'),
          ),
        );
      }
    }

    polylines.clear();
  }

  /// Logic to swap generic pins for specific Lucide vector icons based on driver identity
  BitmapDescriptor _getDriverIcon(String? name, BitmapDescriptor fallback) {
    if (name == null) return fallback;
    final lowerName = name.toLowerCase();
    if (lowerName.contains('kiprono')) return _kipronoIcon ?? fallback;
    if (lowerName.contains('cheptoo')) return _cheptooIcon ?? fallback;
    if (lowerName.contains('cherono')) return _cheronoIcon ?? fallback;
    return fallback;
  }

  Future<void> _loadMarkerIcons() async {
    _markerIconsLoading = true;
    try {
      // Standard application markers using Lucide vectors
      _driverMarkerIcon = await getMarkerIconFromIconData(
        LucideIcons.car,
        color: Colors.blueAccent,
      );
      _nearbyDriverMarkerIcon = await getMarkerIconFromIconData(
        LucideIcons.car,
        color: const Color(0xFFFF8A00),
      );

      // Specific named driver markers (Kiprono: Blue, Cheptoo: Amber, Cherono: Green)
      _kipronoIcon =
          await getMarkerIconFromIconData(LucideIcons.car, color: Colors.blue);
      _cheptooIcon = await getMarkerIconFromIconData(LucideIcons.carFront,
          color: Colors.amber.shade600);
      _cheronoIcon = await getMarkerIconFromIconData(LucideIcons.carTaxiFront,
          color: Colors.green);

      _updateMarkersAndPolylines();
      notifyListeners();
    } catch (e) {
      debugPrint('RideController: Failed to build vehicle markers: $e');
    } finally {
      _markerIconsLoading = false;
    }
  }

  /// Dynamically transforms any vector IconData into a crisp Google Maps BitmapDescriptor
  Future<BitmapDescriptor> getMarkerIconFromIconData(
    IconData iconData, {
    required Color color,
    double size = 70.0,
  }) async {
    final pictureRecorder = ui.PictureRecorder();
    final canvas = ui.Canvas(pictureRecorder);
    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    textPainter.text = TextSpan(
      text: String.fromCharCode(iconData.codePoint),
      style: TextStyle(
        fontSize: size,
        fontFamily: iconData.fontFamily,
        package: iconData.fontPackage,
        color: color,
      ),
    );

    textPainter.layout();
    textPainter.paint(canvas, const Offset(0, 0));

    final picture = pictureRecorder.endRecording();
    final image = await picture.toImage(size.toInt(), size.toInt());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);

    return BitmapDescriptor.fromBytes(bytes!.buffer.asUint8List());
  }

  Future<BitmapDescriptor> _buildVehicleMarkerIcon({
    required Color background,
    required IconData icon,
  }) async {
    const size = 144.0;
    // CanvasKit on web can lose context and cause late-init errors when creating
    // pictures/images. Avoid building custom bitmap markers on web and fall
    // back to a default marker to keep the app stable.
    if (kIsWeb) {
      // Choose a reasonable hue fallback based on the provided background
      final hue = BitmapDescriptor.hueOrange;
      return BitmapDescriptor.defaultMarkerWithHue(hue);
    }

    try {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final center = const Offset(size / 2, size / 2);
      final radius = size / 2;

      final shadowPaint = Paint()
        ..color = Colors.black.withValues(alpha: 0.22) // Already correct
        ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 10);
      canvas.drawCircle(center.translate(0, 5), radius * 0.74, shadowPaint);

      final circlePaint = Paint()..color = background;
      canvas.drawCircle(center, radius * 0.72, circlePaint);

      final iconSpan = TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          fontSize: 70,
          color: Colors.white,
        ),
      );
      final painter = TextPainter(
        text: iconSpan,
        textDirection: ui.TextDirection.ltr,
      )..layout();
      painter.paint(
        canvas,
        Offset(center.dx - painter.width / 2, center.dy - painter.height / 2),
      );

      final picture = recorder.endRecording();
      final image = await picture.toImage(size.toInt(), size.toInt());
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) {
        throw Exception('Failed to convert marker image to bytes');
      }
      // fromBytes is deprecated in some SDK versions; suppress the lint here.
      // ignore: deprecated_member_use
      return BitmapDescriptor.fromBytes(data.buffer.asUint8List());
    } catch (e, st) {
      debugPrint('RideController: Failed to build vehicle marker icon: $e');
      debugPrintStack(stackTrace: st);
      // Safe fallback
      return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange);
    }
  }

  Future<void> startRiderLocationTracking() async {
    if (_riderPositionSubscription != null) return;

    try {
      if (kIsWeb) {
        riderLocation = const LatLng(-0.3031, 36.0800);
        _updateMarkersAndPolylines();
        _fitCameraToRoute();
        notifyListeners();
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      // If permission is denied, use Nakuru as our fallback instead of killing the process!
      if (permission == LocationPermission.deniedForever ||
          permission == LocationPermission.denied) {
        debugPrint(
            'RideController: rider location permission denied. Falling back to Nakuru.');

        // 🇰🇪 Setting active fallback coordinates to Nakuru
        riderLocation = const LatLng(-0.3031, 36.0800);

        _updateMarkersAndPolylines();
        _fitCameraToRoute(); // 🎥 Centers your map window onto the simulation
        notifyListeners(); // 🔔 Wakes up the progress bar & ETA calculations
        return;
      }

      final current = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
        ),
      );
      riderLocation = LatLng(current.latitude, current.longitude);
      _updateMarkersAndPolylines();
      _fitCameraToRoute();
      notifyListeners();

      _riderPositionSubscription = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          distanceFilter: 10,
        ),
      ).listen((Position position) {
        riderLocation = LatLng(position.latitude, position.longitude);
        _updateMarkersAndPolylines();
        notifyListeners();
      });
    } catch (e) {
      debugPrint('RideController: Failed to start rider tracking: $e');

      // Secondary fallback safety if the GPS hardware fails entirely
      riderLocation = const LatLng(-0.3031, 36.0800);
      _updateMarkersAndPolylines();
      notifyListeners();
    }
  }

  Future<void> stopRiderLocationTracking() async {
    await _riderPositionSubscription?.cancel();
    _riderPositionSubscription = null;
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
        final docRef =
            FirebaseFirestore.instance.collection('rides').doc(rideId);
        final snapshot = await tx.get(docRef);
        if (!snapshot.exists) return;
        final data = snapshot.data();
        final status = data?['status'];
        if (status != 'searching') return;

        String? chosen;
        for (final id in candidateDriverIds) {
          final driverDoc = await tx.get(
            FirebaseFirestore.instance.collection('users').doc(id),
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
    if (ride.driverId == null || ride.id == null) return;

    try {
      final driverDoc = await FirebaseFirestore.instance
          .collection('users')
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
        rideId: ride.id!,
      );
    } catch (e) {
      debugPrint('RideController: Failed to send arrival notification: $e');
    }
  }

  void setOnDriverArrived(ArrivalCallback callback) {
    onDriverArrived = callback;
  }

  void setOnRideCompleted(RideCompletionCallback callback) {
    onRideCompleted = callback;
  }

  Future<void> loadRideTypes() async {
    // If already loaded, don't re-seed
    if (vehicleTiers.isNotEmpty) return;

    try {
      // Seed standard tiers (In production, load these from Firestore)
      vehicleTiers = [
        VehicleTier(
          id: 'tulia',
          name: 'Tulia',
          description: 'Sustainable, low-profile urban transit.',
          baseFare: FareCalculator.getRates('tulia')['base']!,
          perKmRate: FareCalculator.getRates('tulia')['km']!,
          capacity: 4,
          benefits: [
            'Eco-Conscious Carbon Footprint',
            'Silent Interior Environment',
            'Agile City Maneuvering'
          ],
          iconPath: 'assets/vitz.png',
        ),
        VehicleTier(
          id: 'nuru',
          name: 'Nuru',
          description: 'Elevated workspace travel designed for your comfort.',
          baseFare: FareCalculator.getRates('nuru')['base']!,
          perKmRate: FareCalculator.getRates('nuru')['km']!,
          capacity: 4,
          benefits: [
            'Curated Premium Audio & Mood Profiles',
            'Climate Controlled Sanctuary',
            'Top-Rated Five-Star Operators'
          ],
          iconPath: 'assets/premio.png',
        ),
        VehicleTier(
          id: 'pamoja',
          name: 'Pamoja',
          description: 'Expansive space for your whole collective.',
          baseFare: FareCalculator.getRates('pamoja')['base']!,
          perKmRate: FareCalculator.getRates('pamoja')['km']!,
          capacity: 7,
          benefits: [
            'Maximized Legroom & Lounge Seating',
            'Squad-Optimized High Capacity',
            'Expansive Multi-Luggage Cargo Hull'
          ],
          iconPath: 'assets/honda freed.png',
        ),
        VehicleTier(
          id: 'waziri',
          name: 'Waziri',
          description: 'Elite flagship command. Unmarked, unbothered.',
          baseFare: FareCalculator.getRates('waziri')['base']!,
          perKmRate: FareCalculator.getRates('waziri')['km']!,
          capacity: 5,
          benefits: [
            'VIP Full-Grain Leather Lounge',
            'Absolute Discretion Privacy Shield',
            'Certified Professional Executive Chauffeur'
          ],
          iconPath: 'assets/prado.png',
        ),
      ];

      // 🛡️ Guard: Only set a default if the rider hasn't selected one yet.
      selectedTier ??= vehicleTiers.first;

      try {
        availableRideTypes = await _firestoreService.getRideTypes();
        if (availableRideTypes.isNotEmpty && selectedRideType == null) {
          selectedRideType = availableRideTypes.first;
          selectedRideTypeId = selectedRideType!.id;
        }
      } catch (e) {
        debugPrint(
            'RideController: Firestore RideTypes blocked. Using local tiers.');
        // The vehicleTiers defined above ensure the app remains usable.
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
      final user = FirebaseAuth.instance.currentUser;

      // 🔐 AUTH GUARD: Ensure user is fully authenticated (not a guest)
      // when performing critical ride modifications.
      if (user == null || user.isAnonymous) {
        debugPrint('RideController: Aborting cancel - Real account required.');
        throw NotAuthenticatedException('Please sign in to cancel a ride.');
      }

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

  /// Helper for UI buttons to verify if the current user has driver-level permissions
  /// and is fully authenticated (not a guest).
  bool verifyDriverAccess() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) {
      debugPrint(
          'RideController: Driver access denied - Guest session detected.');
      // Throwing here triggers the try/catch block in your UI to show the Login Modal
      throw FirebaseAuthException(
        code: 'auth-required',
        message: 'Please sign in to access Driver Mode.',
      );
    }
    return true;
  }

  /// Transition the ride from ARRIVED to STARTED.
  /// This is called when the rider provides the OTP and the trip officially begins.
  Future<void> startActiveRide() async {
    if (activeRideId == null) return;

    try {
      await FirebaseFirestore.instance
          .collection('rides')
          .doc(activeRideId)
          .update({
        'status': 'started',
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('RideController: Failed to start ride: $e');
      rethrow;
    }
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
    nearbyDriverPreviews = [];
    assignedDriverProfile = null;
    pickupLocation = null;
    destinationLocation = null;
    estimatedCost = null;
    driverVehicle = null;
    driverRating = null;
    rideVerificationOtp = '----';
    notifyListeners();
  }

  @override
  void dispose() {
    _rideSubscription?.cancel();
    _driverSubscription?.cancel();
    _riderPositionSubscription?.cancel();
    SimulationService.stopRideSimulation();
    super.dispose();
  }
}
