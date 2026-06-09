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
import 'package:aeroride/models/ride_type_model.dart';
import 'package:aeroride/services/notification_service.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

typedef ArrivalCallback = void Function(String driverName, String vehicleInfo);

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

  // Arrival callback for UI to show notifications
  void Function(String driverName, String vehicleInfo)? onDriverArrived;

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
    var stage = 'starting request';
    final simulationMode = kDebugMode;

    try {
      currentRideStatus = "CONTACTING DRIVER...";
      notifyListeners();

      // 👤 LAZY-AUTH FALLBACK: If the user hasn't registered a real name yet, enforce a guest placeholder
      final freshUser = FirebaseAuth.instance.currentUser;
      final resolvedRiderName = (freshUser?.displayName?.isNotEmpty ?? false)
          ? freshUser!.displayName!
          : (riderName.trim().isEmpty ? "Guest Rider" : riderName);

      final rideFare = _estimateBaseFare(rideType);

      final List<String> resolvedCandidateDrivers =
          candidateDriverIds == null || candidateDriverIds.isEmpty
              ? <String>[]
              : List<String>.from(candidateDriverIds);

      // Use dynamically registered drivers for simulation if none were provided
      if (simulationMode && resolvedCandidateDrivers.isEmpty) {
        final nearby = await _driversService.getSelectableDrivers(
          referenceLocation: pickup,
          limit: 3,
        );
        resolvedCandidateDrivers.addAll(
          nearby.map((d) => (d['driverId'] ?? d['id']).toString()).toList(),
        );
      }

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

      final newRide = RideRequest(
        userId: freshUser?.uid ?? userId, // Ensure we use the authenticated UID
        riderName:
            resolvedRiderName, // 👈 Uses the safe fallback placeholder name
        pickupLocation: pickup.toGeoPoint(),
        destinationLocation: destination.toGeoPoint(),
        pickupAddress: pickupText,
        destinationAddress: dropoffText,
        status: 'searching',
        estimatedCost: rideFare,
        candidateDrivers: resolvedCandidateDrivers,
        rideType: rideType,
      );

      stage = 'creating ride request';
      String rideId =
          await _firestoreService.createRideRequestWithWalletReservation(
        rideRequest: newRide,
        riderId: userId,
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

  double _estimateBaseFare(String rideType) {
    switch (rideType) {
      case 'economy':
        return 12.50;
      case 'premium':
        return 28.50;
      case 'standard':
      default:
        return 18.00;
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

          if (isSimulated && (currentRideStatus == 'ACCEPTED' || currentRideStatus == 'STARTED')) {
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
              final meters = _distanceMeters(
                driverLocation!.latitude,
                driverLocation!.longitude,
                pickupLocation!.latitude,
                pickupLocation!.longitude,
              );
              driverDistanceKm = (meters / 1000.0);
              // assume average urban speed 500 m/min (~30 km/h)
              driverEtaMinutes = (meters / 500).ceil();
            }
            if (destinationLocation != null && currentRideStatus == 'STARTED') {
              final meters = _distanceMeters(
                driverLocation!.latitude,
                driverLocation!.longitude,
                destinationLocation!.latitude,
                destinationLocation!.longitude,
              );
              driverDistanceKm = (meters / 1000.0);
              driverEtaMinutes = (meters / 500).ceil();
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

  double _distanceMeters(double lat1, double lng1, double lat2, double lng2) {
    const earthRadius = 6371000.0;
    final dLat = _degToRad(lat2 - lat1);
    final dLng = _degToRad(lng2 - lng1);
    final a = (sin(dLat / 2) * sin(dLat / 2)) +
        cos(_degToRad(lat1)) *
            cos(_degToRad(lat2)) *
            (sin(dLng / 2) * sin(dLng / 2));
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadius * c;
  }

  double _degToRad(double degrees) => degrees * (pi / 180);

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
        ..color = Colors.black.withOpacity(0.22)
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
