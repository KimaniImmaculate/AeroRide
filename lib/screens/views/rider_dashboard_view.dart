import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart' as geo;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import '../../utils/fare_calculator.dart';

import '../../controllers/ride_controller.dart';
import '../../models/ride_request_model.dart';
import '../../models/ride_type_model.dart';
import '../../models/user_model.dart';
import '../../services/firestore_service.dart';
import '../../services/drivers_service.dart';
import '../../services/mock_route_service.dart';
import '../../services/mpesa_service.dart';
import '../../theme/aeroride_theme.dart';
import '../../utils/currency.dart';
import '../../utils/browser_geolocation.dart';
import '../../widgets/aeroride_components.dart';
import 'support_view.dart';
import 'directions_route_provider.dart';
import 'wallet_view.dart';
import '../role_selection_screen.dart';

enum RideState {
  idle,
  searchingAddresses,
  driverSelection,
  requesting,
  driverEnRoute,
  driverArrived,
  inTransit,
  arrivedAtDestination,
  payment
}

enum TravelPhase { driverToRider, riderToDestination }

class RiderDashboardView extends StatefulWidget {
  final dynamic user;
  const RiderDashboardView({super.key, required this.user});

  @override
  State<RiderDashboardView> createState() => _RiderDashboardViewState();
}

class _RiderDashboardViewState extends State<RiderDashboardView> {
  static const String googleMapsApiKey =
      'AIzaSyANuwPwm1dRFvh_ySIIiW22-dWnUsMrp0k';

  late RideController _rideController;
  GoogleMapController? _mapController;
  VoidCallback? _rideControllerListener;

  // Real-time Core Lifecycle States
  RideState _currentRideState = RideState.idle;
  LatLng? _riderLocation;
  LatLng? _destinationLocation;
  LatLng? _driverLocation;

  // Map Pick Toggles
  bool _isPickingFromMap = false;
  String _mapPinTarget = 'destination'; // 'pickup' or 'destination'

  // Input Controller layers
  final TextEditingController _pickupTextController = TextEditingController();
  final TextEditingController _destinationTextController =
      TextEditingController();
  final TextEditingController _mpesaPhoneController = TextEditingController();

  String _pickupAddressString = "Not Selected";
  String _destinationAddressString = "Not Selected";
  bool _isSearchingGeocode = false;

  double _movingProgress = 0.0;
  Timer? _simulationTimer;
  Timer? _inTransitTimer;
  List<LatLng> _actualRoadPoints = [];
  int _currentWaypointIndex = 0;
  double _liveTraveledDistanceKm = 0.0;
  double _liveRunningFareKsh = 100.0;
  double _liveDriverEarningsKsh = 0.0;
  int _etaMinutes = 5;
  double _calculatedFareKsh = 0.0;
  String? _currentRideDocumentId;
  bool _isPaymentProcessing = false;
  String _paymentStatusMessage = '';

  Map<String, dynamic>? _selectedDriver;
  List<Map<String, dynamic>> _availableDriversPool = [];
  final FirestoreService _firestoreService = FirestoreService();
  final DriversService _driversService = DriversService();
  final Set<Polyline> _mapPolylines = {};
  final Set<Marker> _mapMarkers = {};

  @override
  void initState() {
    super.initState();
    _rideController = Provider.of<RideController>(context, listen: false);
    _rideControllerListener = () {
      if (mounted) {
        setState(() {});
      }
    };
    _rideController.addListener(_rideControllerListener!);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_rideController.startRiderLocationTracking());
    });
    _rideController.loadRideTypes();

    final dynamic currentUser = widget.user;
    final initialPhone = currentUser?.phoneNumber?.toString() ?? '';
    if (initialPhone.isNotEmpty) {
      _mpesaPhoneController.text = initialPhone;
    }

    _rideController.onDriverArrived = (driverName, vehicleInfo) {
      if (!mounted) return;
      final snackBarColor = context.aeroTokens.primaryDarkBlue;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('🎉 $driverName has arrived ($vehicleInfo)'),
          backgroundColor: snackBarColor,
          behavior: SnackBarBehavior.floating,
        ),
      );
      setState(() {
        _currentRideState = RideState.driverArrived;
        _etaMinutes = 0;
      });
    };
  }

  @override
  void dispose() {
    _simulationTimer?.cancel();
    _inTransitTimer?.cancel();
    if (_rideControllerListener != null) {
      _rideController.removeListener(_rideControllerListener!);
    }
    if (!kIsWeb) {
      _mapController?.dispose();
    }
    _pickupTextController.dispose();
    _destinationTextController.dispose();
    _mpesaPhoneController.dispose();
    super.dispose();
  }

  // Load nearby drivers from Firestore via DriversService
  Future<void> _loadNearbyDrivers(LatLng aroundPoint) async {
    try {
      await _driversService.debugProbeUsersRead();

      final drivers = await _driversService.getSelectableDrivers(
        referenceLocation: aroundPoint,
        limit: 6,
      );

      try {
        debugPrint(
            'RiderDashboardView: fetched ${drivers.length} selectable drivers');
        debugPrint('RiderDashboardView: ids=' +
            drivers.map((d) => d['id'] as String? ?? '').join(','));
      } catch (_) {}

      setState(() {
        _availableDriversPool = drivers.map((d) {
          final raw = d['raw'] as Map<String, dynamic>? ?? {};
          final loc = d['location'] as LatLng?;
          final etaValue = d['eta'] ?? raw['eta'];
          final etaMinutes = etaValue is num
              ? etaValue.toInt()
              : int.tryParse(etaValue?.toString() ?? '') ?? 5;
          final latValue = loc?.latitude ?? d['lat'] ?? aroundPoint.latitude;
          final lngValue = loc?.longitude ?? d['lng'] ?? aroundPoint.longitude;
          return {
            'id': d['driverId'] ?? raw['driverId'] ?? '',
            'name': d['name'] ?? raw['name'] ?? 'Driver',
            'vehicle':
                d['vehicle'] ?? raw['vehicle'] ?? raw['vehicleInfo'] ?? '',
            'rating': (d['rating'] ?? raw['rating'] ?? 4.8).toString(),
            'eta': etaMinutes,
            'lat': latValue is num
                ? latValue.toDouble()
                : double.tryParse(latValue.toString()) ?? aroundPoint.latitude,
            'lng': lngValue is num
                ? lngValue.toDouble()
                : double.tryParse(lngValue.toString()) ?? aroundPoint.longitude,
          };
        }).toList();
      });
    } catch (e) {
      debugPrint('Failed loading nearby drivers: $e');
    }
  }

  Widget _buildLiveTaximeterDock() {
    if (_currentRideState != RideState.driverEnRoute &&
        _currentRideState != RideState.inTransit) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'LIVE TAXIMETER FARE',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'KSh ${_liveRunningFareKsh.toStringAsFixed(0)}',
                style: const TextStyle(
                  color: Colors.amber,
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          Container(
            height: 35,
            width: 1,
            color: Colors.white24,
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'ETA / DISTANCE',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'ETA: ${_etaMinutes < 0 ? 0 : _etaMinutes} Mins',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${_liveTraveledDistanceKm.toStringAsFixed(2)} KM',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _clearExistingRoute() {
    setState(() {
      _mapPolylines.clear();
      _destinationLocation = null;
    });
  }

  Future<void> _handleMapTap(LatLng tappedCoordinate) async {
    if (!_isPickingFromMap) return;

    setState(() {
      if (_mapPinTarget == 'pickup') {
        _riderLocation = tappedCoordinate;
        _pickupAddressString =
            'Pinned Location (${tappedCoordinate.latitude.toStringAsFixed(4)}, ${tappedCoordinate.longitude.toStringAsFixed(4)})';
        _pickupTextController.text = _pickupAddressString;
      } else {
        _destinationLocation = tappedCoordinate;
        _destinationAddressString =
            'Pinned Location (${tappedCoordinate.latitude.toStringAsFixed(4)}, ${tappedCoordinate.longitude.toStringAsFixed(4)})';
        _destinationTextController.text = _destinationAddressString;
      }

      _isPickingFromMap = false;
    });

    if (_riderLocation != null && _destinationLocation != null) {
      await _calculateRouteAndPricing(_riderLocation!, _destinationLocation!);
    }
  }

  // Uses device hardware to snap current coordinates automatically
  Future<void> _useCurrentLocation() async {
    setState(() => _isSearchingGeocode = true);

    if (kIsWeb) {
      final browserCoords = await requestBrowserLocation();
      if (browserCoords != null) {
        _rideController.riderLocation = browserCoords;
      }
    }

    final fallbackCoords =
        _rideController.riderLocation ?? const LatLng(-0.2831, 36.0664);

    // Immediately pin a usable pickup point so the button always feels responsive.
    setState(() {
      _riderLocation = fallbackCoords;
      _pickupAddressString =
          "My Current Location (${fallbackCoords.latitude.toStringAsFixed(4)}, ${fallbackCoords.longitude.toStringAsFixed(4)})";
      _pickupTextController.text = _pickupAddressString;
    });
    _mapController
        ?.animateCamera(CameraUpdate.newLatLngZoom(fallbackCoords, 16.0));

    try {
      LatLng currentCoords = _rideController.riderLocation ?? fallbackCoords;

      List<geo.Placemark> placemarks = await geo
          .placemarkFromCoordinates(
              currentCoords.latitude, currentCoords.longitude)
          .timeout(const Duration(seconds: 5));

      if (placemarks.isNotEmpty && mounted) {
        final place = placemarks.first;
        setState(() {
          _riderLocation = currentCoords;
          _pickupAddressString =
              "${place.name ?? place.street ?? 'Current Location'}, ${place.locality ?? 'Kenya'}";
          _pickupTextController.text = _pickupAddressString;
        });
        _mapController
            ?.animateCamera(CameraUpdate.newLatLngZoom(currentCoords, 16.0));
      } else if (mounted) {
        setState(() {
          _riderLocation = currentCoords;
          _pickupAddressString =
              "My Current Location (${currentCoords.latitude.toStringAsFixed(4)}, ${currentCoords.longitude.toStringAsFixed(4)})";
          _pickupTextController.text = _pickupAddressString;
        });
        _mapController
            ?.animateCamera(CameraUpdate.newLatLngZoom(currentCoords, 16.0));
      }
    } catch (e) {
      setState(() {
        _riderLocation = fallbackCoords;
        _pickupAddressString = "Current Location (Pinned)";
        _pickupTextController.text = _pickupAddressString;
      });
      _mapController
          ?.animateCamera(CameraUpdate.newLatLngZoom(fallbackCoords, 15.0));
    } finally {
      if (mounted) {
        setState(() => _isSearchingGeocode = false);
      }
    }
  }

  // Geocoding Engine: Converts raw manual string input into real map coordinates
  Future<void> _geocodeAndRouteAddresses() async {
    if (_pickupTextController.text.isEmpty ||
        _destinationTextController.text.isEmpty) {
      _showToastError("Please fill out both pickup and destination fields.");
      return;
    }

    setState(() => _isSearchingGeocode = true);

    // Multi-City Coordinate Dictionary for local zero-cost simulation testing
    final Map<String, LatLng> localTestCoordinates = {
      // 1. NAKURU (Default Base City)
      "nakuru": const LatLng(-0.2831, 36.0664),
      "nakuru cbd": const LatLng(-0.2831, 36.0664),
      "milimani": const LatLng(-0.2750, 36.0700),
      "lanet": const LatLng(-0.3012, 36.1345),
      "njoro": const LatLng(-0.3341, 35.9382),

      // 2. NAIROBI
      "nairobi": const LatLng(-1.286389, 36.817223),
      "nairobi cbd": const LatLng(-1.286389, 36.817223),
      "westlands": const LatLng(-1.2644, 36.8044),
      "kilimani": const LatLng(-1.2912, 36.7846),
      "jkia": const LatLng(-1.3194, 36.9272),

      // 3. MOMBASA
      "mombasa": const LatLng(-4.0435, 39.6682),
      "mombasa cbd": const LatLng(-4.0435, 39.6682),
      "nyali": const LatLng(-4.0275, 39.7022),
      "bamburi": const LatLng(-4.0041, 39.7188),

      // 4. KISUMU
      "kisumu": const LatLng(-0.0917, 34.7680),
      "kisumu cbd": const LatLng(-0.0917, 34.7680),
      "milimani kisumu": const LatLng(-0.1015, 34.7548),
      "kondele": const LatLng(-0.0833, 34.7778),

      // 5. ELDORET
      "eldoret": const LatLng(0.5143, 35.2698),
      "eldoret cbd": const LatLng(0.5143, 35.2698),
      "kapsoya": const LatLng(0.5231, 35.3014),
      "langas": const LatLng(0.4852, 35.2612),
    };

    String inputPickup = _pickupTextController.text.trim().toLowerCase();
    String inputDest = _destinationTextController.text.trim().toLowerCase();

    try {
      // 1. Resolve Pickup Location Layer
      if (localTestCoordinates.containsKey(inputPickup)) {
        _riderLocation = localTestCoordinates[inputPickup];
      } else if (_riderLocation == null ||
          !_pickupTextController.text.startsWith("Pinned Location")) {
        try {
          List<geo.Location> locations = await geo
              .locationFromAddress("${_pickupTextController.text}, Kenya");
          if (locations.isNotEmpty) {
            _riderLocation =
                LatLng(locations.first.latitude, locations.first.longitude);
          }
        } catch (_) {
          _riderLocation =
              _rideController.riderLocation ?? const LatLng(-0.2831, 36.0664);
        }
      }
      _pickupAddressString = _pickupTextController.text;

      // 2. Resolve Destination Location Layer
      if (localTestCoordinates.containsKey(inputDest)) {
        _destinationLocation = localTestCoordinates[inputDest];
      } else if (_destinationLocation == null ||
          !_destinationTextController.text.startsWith("Pinned Location")) {
        try {
          List<geo.Location> destLocations = await geo
              .locationFromAddress("${_destinationTextController.text}, Kenya");
          if (destLocations.isNotEmpty) {
            _destinationLocation = LatLng(
                destLocations.first.latitude, destLocations.first.longitude);
          } else {
            throw Exception("Address not found");
          }
        } catch (_) {
          final double latOffset = (math.Random().nextBool() ? 1 : -1) *
              (0.015 + math.Random().nextDouble() * 0.015);
          final double lngOffset = (math.Random().nextBool() ? 1 : -1) *
              (0.015 + math.Random().nextDouble() * 0.015);

          _destinationLocation = LatLng(
            _riderLocation!.latitude + latOffset,
            _riderLocation!.longitude + lngOffset,
          );
        }
      }
      _destinationAddressString = _destinationTextController.text;

      // 3. Mathematical distance calculation (Haversine Formula)
      double distanceInKm =
          _calculateHaversineDistance(_riderLocation!, _destinationLocation!);
      final fare = computeFareAndEarnings(distanceInKm, 0.0);
      _calculatedFareKsh = fare.passengerFare;

      await _loadNearbyDrivers(_riderLocation!);

      setState(() {
        _currentRideState = RideState.driverSelection;
      });

      await _calculateRouteAndPricing(_riderLocation!, _destinationLocation!);
    } catch (e) {
      _showToastError(
          "Could not calculate route. Please try typing another location nearby.");
    } finally {
      setState(() => _isSearchingGeocode = false);
    }
  }

  double _calculateHaversineDistance(LatLng pos1, LatLng pos2) {
    var p = 0.017453292519943295;
    var a = 0.5 -
        math.cos((pos2.latitude - pos1.latitude) * p) / 2 +
        math.cos(pos1.latitude * p) *
            math.cos(pos2.latitude * p) *
            (1 - math.cos((pos2.longitude - pos1.longitude) * p)) /
            2;
    return 12742 * math.asin(math.sqrt(a));
  }

  LatLng _interpolateCoordinates(LatLng start, LatLng end, double fraction) {
    double lat = start.latitude + (end.latitude - start.latitude) * fraction;
    double lng = start.longitude + (end.longitude - start.longitude) * fraction;
    return LatLng(lat, lng);
  }

  Future<void> _calculateRouteAndPricing(
      LatLng origin, LatLng destination) async {
    try {
      const url = 'https://routes.googleapis.com/directions/v2:computeRoutes';

      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'X-Goog-Api-Key': googleMapsApiKey,
          'X-Goog-FieldMask':
              'routes.duration,routes.distanceMeters,routes.polyline.encodedPolyline',
        },
        body: jsonEncode({
          'origin': {
            'location': {
              'latLng': {
                'latitude': origin.latitude,
                'longitude': origin.longitude,
              }
            }
          },
          'destination': {
            'location': {
              'latLng': {
                'latitude': destination.latitude,
                'longitude': destination.longitude,
              }
            }
          },
          'travelMode': 'DRIVE',
          'routingPreference': 'TRAFFIC_AWARE',
        }),
      );

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final routes = data['routes'] as List<dynamic>?;

      if (response.statusCode < 200 || response.statusCode >= 300) {
        debugPrint(
            'Routes API Error: HTTP ${response.statusCode} - ${response.body}');
        return;
      }

      if (routes == null || routes.isEmpty) {
        debugPrint('Routes API Error: No routes returned - ${response.body}');
        return;
      }

      final route = routes[0] as Map<String, dynamic>;
      final distanceMeters = route['distanceMeters'] as num? ?? 0;
      final distanceKm = distanceMeters / 1000.0;

      final driverAnchor = _riderLocation ?? origin;
      await _loadNearbyDrivers(driverAnchor);

      final durationString = route['duration'] as String? ?? '0s';
      final durationSeconds =
          num.tryParse(durationString.replaceAll('s', '')) ?? 0;
      final durationMins = durationSeconds / 60.0;

      final fare = computeFareAndEarnings(distanceKm, durationMins);

      final polylineData = route['polyline'] as Map<String, dynamic>?;
      final encodedPolyline = polylineData?['encodedPolyline']?.toString();

      if (encodedPolyline == null || encodedPolyline.isEmpty) {
        debugPrint(
            'Routing aborted: Google API did not return polyline points.');
        return;
      }

      final decodedPoints = PolylinePoints.decodePolyline(encodedPolyline);
      final roadRoute = decodedPoints
          .map((point) => LatLng(point.latitude, point.longitude))
          .toList();

      if (!mounted) return;

      setState(() {
        _actualRoadPoints = roadRoute;
        _calculatedFareKsh = fare.passengerFare;
        _mapPolylines.clear();
        _mapPolylines.add(
          Polyline(
            polylineId: const PolylineId('road_route'),
            points: roadRoute,
            color: Colors.black,
            width: 5,
            consumeTapEvents: false,
          ),
        );
        _currentRideState = RideState.driverSelection;
      });

      _zoomToFitRoute(origin, destination);
    } catch (e) {
      debugPrint('Routing engine failed: $e');
    }
  }

  Widget _buildSuggestedDestinationsSection() {
    final suggestedDestinations = <Map<String, dynamic>>[
      {
        'name': 'Nakuru CBD',
        'location': const GeoPoint(-0.2831, 36.0664),
      },
      {
        'name': 'Milimani',
        'location': const GeoPoint(-0.2745, 36.0752),
      },
      {
        'name': 'London Estate',
        'location': const GeoPoint(-0.2869, 36.0618),
      },
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Popular Nakuru destinations',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
        ),
        const SizedBox(height: 10),
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: suggestedDestinations.length,
          itemBuilder: (context, index) {
            final data = suggestedDestinations[index];
            final GeoPoint geo = data['location'] as GeoPoint;
            final String destinationName = data['name'].toString();

            return ListTile(
              onTap: () async {
                final origin = _riderLocation ??
                    _rideController.riderLocation ??
                    const LatLng(-0.2831, 36.0664);
                final dest = LatLng(geo.latitude, geo.longitude);

                setState(() {
                  _destinationLocation = dest;
                  _destinationAddressString = destinationName;
                  _destinationTextController.text = destinationName;
                  _currentRideState = RideState.driverSelection;
                });

                await _loadNearbyDrivers(origin);
                await _calculateRouteAndPricing(origin, dest);
              },
              leading: const CircleAvatar(
                backgroundColor: Colors.black12,
                child: Icon(Icons.location_on, color: Colors.black87, size: 18),
              ),
              title: Text(
                destinationName,
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              trailing: const Icon(Icons.arrow_forward_ios, size: 14),
            );
          },
        ),
      ],
    );
  }

  void _zoomToFitRoute(LatLng start, LatLng end) {
    if (_mapController == null) return;
    double minLat =
        start.latitude < end.latitude ? start.latitude : end.latitude;
    double maxLat =
        start.latitude > end.latitude ? start.latitude : end.latitude;
    double minLng =
        start.longitude < end.longitude ? start.longitude : end.longitude;
    double maxLng =
        start.longitude > end.longitude ? start.longitude : end.longitude;

    _mapController!.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat - 0.04, minLng - 0.04),
          northeast: LatLng(maxLat + 0.04, maxLng + 0.04),
        ),
        70,
      ),
    );
  }

  Future<void> _confirmDriverAndBook(Map<String, dynamic> driver) async {
    final selectedDriverId = driver['id']?.toString() ?? '';
    final driverLat = (driver['lat'] as num?)?.toDouble();
    final driverLng = (driver['lng'] as num?)?.toDouble();
    final driverLocation = (driverLat != null && driverLng != null)
        ? LatLng(driverLat, driverLng)
        : _rideController.riderLocation ?? const LatLng(-0.2831, 36.0664);
    final etaValue = driver['eta'];
    final etaMinutes = etaValue is num
        ? etaValue.toInt()
        : int.tryParse(etaValue?.toString() ?? '') ?? 5;

    setState(() {
      _selectedDriver = driver;
      _currentRideState = RideState.requesting;
      _driverLocation = driverLocation;
      _etaMinutes = etaMinutes;
    });

    final fareToSave = _calculatedFareKsh > 0
        ? _calculatedFareKsh
        : computeFareAndEarnings(
            _calculateHaversineDistance(_riderLocation!, _destinationLocation!),
            0.0,
          ).passengerFare;

    final rideRequestRef =
        FirebaseFirestore.instance.collection('ride_requests').doc();
    _currentRideDocumentId = rideRequestRef.id;

    final rideData = <String, dynamic>{
      'id': rideRequestRef.id,
      'userId': widget.user.uid,
      'riderId': widget.user.uid,
      'riderName': widget.user.displayName ?? 'AeroRide User',
      'pickup': GeoPoint(_riderLocation!.latitude, _riderLocation!.longitude),
      'pickupLocation':
          GeoPoint(_riderLocation!.latitude, _riderLocation!.longitude),
      'dropoff': GeoPoint(
          _destinationLocation!.latitude, _destinationLocation!.longitude),
      'destinationLocation': GeoPoint(
          _destinationLocation!.latitude, _destinationLocation!.longitude),
      'pickupAddress': _pickupAddressString,
      'destinationName': _destinationAddressString,
      'destinationAddress': _destinationAddressString,
      'status': 'searching',
      'estimatedCost': fareToSave,
      'finalFareCharged': fareToSave,
      'candidateDrivers': selectedDriverId.isNotEmpty ? [selectedDriverId] : [],
      'preferredDriverId':
          selectedDriverId.isNotEmpty ? selectedDriverId : null,
      'createdAt': FieldValue.serverTimestamp(),
    };

    final rideSearchData = <String, dynamic>{
      ...rideData,
      'driverId': null,
    };

    final rideFinalData = <String, dynamic>{
      ...rideData,
      'driverId': null,
      'pickupGeo':
          GeoPoint(_riderLocation!.latitude, _riderLocation!.longitude),
      'dropoffGeo': GeoPoint(
          _destinationLocation!.latitude, _destinationLocation!.longitude),
      'currentVehicleLocation':
          GeoPoint(driverLocation.latitude, driverLocation.longitude),
      'driverEarnings': 0,
    };

    try {
      final batch = FirebaseFirestore.instance.batch();
      batch.set(rideRequestRef, rideSearchData);
      batch.set(
        FirebaseFirestore.instance.collection('rides').doc(rideRequestRef.id),
        rideFinalData,
      );
      await batch.commit();
    } catch (error) {
      debugPrint('RiderDashboardView: ride write failed: $error');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ride request failed: $error')),
      );
      return;
    }

    Timer(const Duration(seconds: 2), () async {
      if (!mounted) return;
      setState(() {
        _currentRideState = RideState.driverEnRoute;
      });

      await _fetchRoadRouteForPhase(_driverLocation!, _riderLocation!);
      _startProgressiveInTransitSimulation(TravelPhase.driverToRider);
    });
  }

  Future<void> _startTripTransit() async {
    if (!mounted || _riderLocation == null || _destinationLocation == null) {
      return;
    }

    await _fetchRoadRouteForPhase(_riderLocation!, _destinationLocation!);
    _startProgressiveInTransitSimulation(TravelPhase.riderToDestination);
  }

  Future<void> _completeRidePayment() async {
    if (_isPaymentProcessing) return;

    final rideDocumentId = _currentRideDocumentId;
    final driverId = _selectedDriver?['id']?.toString() ?? '';
    final rawPhone = _mpesaPhoneController.text.trim();
    final fareToSettle =
        _calculatedFareKsh > 0 ? _calculatedFareKsh : _liveRunningFareKsh;
    final normalizedPhone = _normalizeMpesaPhone(rawPhone);

    if (rideDocumentId == null || rideDocumentId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No active ride was found to settle.')),
      );
      return;
    }

    if (driverId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Driver details are missing for this trip.')),
      );
      return;
    }

    if (normalizedPhone == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid M-Pesa phone number.')),
      );
      return;
    }

    setState(() {
      _isPaymentProcessing = true;
      _paymentStatusMessage = 'Sending STK Push to $normalizedPhone...';
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
            'STK push requested for $normalizedPhone. Check your phone to approve payment.'),
      ),
    );

    // --- START OF MAIN TRY BLOCK ---
    try {
      // 1. Broadcast and wait for Safaricom's immediate response
      await MpesaService().payWithMpesa(
        phone: normalizedPhone,
        amount: fareToSettle,
        context: context,
        onSuccess: () {
          // Explicit placeholder callback wrapper if required by the service definition
          debugPrint('MpesaService internally confirmed modal dismissal.');
        },
      );

      if (!mounted) return;

      setState(() {
        _paymentStatusMessage = 'Payment verified! Updating your ride data...';
      });

      // 2. SAFE FIRESTORE UPDATE
      if (rideDocumentId.isNotEmpty) {
        try {
          await FirebaseFirestore.instance
              .collection('rides')
              .doc(rideDocumentId)
              .update({
            'paymentStatus': 'paid',
            'status': 'completed',
            'farePaid': fareToSettle,
          });
          print("Firestore updated successfully for ride: $rideDocumentId");
        } catch (firestoreError) {
          print(
              "Firestore Write Error (Ignored for local UI testing): $firestoreError");
        }
      }

      // 3. Complete UX transitions seamlessly
      setState(() {
        _isPaymentProcessing = false;
        _paymentStatusMessage = 'Payment Successful!';

        // 🌟 THE FIX: Directly switch off the visibility panels holding up the checkout screens
        // Replace these with the exact names of the UI state variables used in your layout!
        _currentRideDocumentId = null;
        _selectedDriver = null;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Payment Received! Heading back to map...'),
          backgroundColor: Colors.green,
        ),
      );

      await Future.delayed(const Duration(seconds: 2));

      // ✅ REMOVED: Navigator.of(context).pop(); has been dropped to prevent crashing to a blank template layout.
    } catch (e) {
      if (!mounted) return;
      print("M-Pesa Core Service Error: $e");

      setState(() {
        _isPaymentProcessing = false;
        _paymentStatusMessage = 'Payment request failed.';
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Payment could not be completed: $e')),
      );
    }
    // --- END OF MAIN TRY BLOCK ---
  }

  String? _normalizeMpesaPhone(String input) {
    final digits = input.replaceAll(RegExp(r'\D'), '');
    if (digits.length == 12 && digits.startsWith('254')) return digits;
    if (digits.length == 10 && digits.startsWith('0')) {
      return '254${digits.substring(1)}';
    }
    if (digits.length == 9) {
      return '254$digits';
    }
    return null;
  }

  Future<void> _fetchRoadRouteForPhase(
      LatLng origin, LatLng destination) async {
    const url = 'https://routes.googleapis.com/directions/v2:computeRoutes';

    try {
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'X-Goog-Api-Key': googleMapsApiKey,
          'X-Goog-FieldMask': 'routes.polyline.encodedPolyline',
        },
        body: jsonEncode({
          'origin': {
            'location': {
              'latLng': {
                'latitude': origin.latitude,
                'longitude': origin.longitude,
              }
            }
          },
          'destination': {
            'location': {
              'latLng': {
                'latitude': destination.latitude,
                'longitude': destination.longitude,
              }
            }
          },
          'travelMode': 'DRIVE',
          'routingPreference': 'TRAFFIC_AWARE',
        }),
      );

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final routes = data['routes'] as List<dynamic>?;

      if (routes == null || routes.isEmpty) {
        debugPrint(
            'Phase routing aborted: No routes returned. Response: ${response.body}');
        _actualRoadPoints = MockRouteService.buildRoutePoints(
          origin,
          destination,
          steps: 18,
        );
        return;
      }

      final route = routes[0] as Map<String, dynamic>;

      final polylineData = route['polyline'] as Map<String, dynamic>?;
      final encodedPolyline = polylineData?['encodedPolyline']?.toString();

      if (encodedPolyline == null || encodedPolyline.isEmpty) {
        debugPrint('Phase routing aborted: No polyline points available.');
        _actualRoadPoints = MockRouteService.buildRoutePoints(
          origin,
          destination,
          steps: 18,
        );
        return;
      }

      final decodedPoints = PolylinePoints.decodePolyline(encodedPolyline);
      final roadRoute = decodedPoints
          .map((point) => LatLng(point.latitude, point.longitude))
          .toList();

      if (!mounted) return;

      setState(() {
        _actualRoadPoints = roadRoute;
        _currentWaypointIndex = 0;

        _mapPolylines.clear();
        _mapPolylines.add(
          Polyline(
            polylineId: const PolylineId('phase_route'),
            points: roadRoute,
            color: Colors.blue,
            width: 5,
            consumeTapEvents: false,
          ),
        );
      });

      _zoomToFitRoute(origin, destination);
    } catch (e) {
      debugPrint('Phase routing failed: $e');
      _actualRoadPoints = MockRouteService.buildRoutePoints(
        origin,
        destination,
        steps: 18,
      );
    }
  }

  void _startProgressiveInTransitSimulation(TravelPhase phase) {
    if (_actualRoadPoints.isEmpty) return;

    _simulationTimer?.cancel();
    _inTransitTimer?.cancel();
    _currentWaypointIndex = 0;
    final startingEtaMinutes = _etaMinutes <= 0
        ? (phase == TravelPhase.riderToDestination ? 8 : 5)
        : _etaMinutes;

    if (phase == TravelPhase.riderToDestination) {
      _liveTraveledDistanceKm = 0.0;
      _liveRunningFareKsh = 100.0;
      _liveDriverEarningsKsh = 0.0;
      if (_etaMinutes <= 0) {
        _etaMinutes = 8;
      }
    } else if (_etaMinutes <= 0) {
      _etaMinutes = 5;
    }

    double calculateSegmentDistance(LatLng p1, LatLng p2) {
      var p = 0.017453292519943295;
      var a = 0.5 -
          math.cos((p2.latitude - p1.latitude) * p) / 2 +
          math.cos(p1.latitude * p) *
              math.cos(p2.latitude * p) *
              (1 - math.cos((p2.longitude - p1.longitude) * p)) /
              2;
      return 12742 * math.asin(math.sqrt(a));
    }

    setState(() {
      _currentRideState = phase == TravelPhase.driverToRider
          ? RideState.driverEnRoute
          : RideState.inTransit;
      _movingProgress = 0.0;
      _driverLocation = _actualRoadPoints.first;
      _mapMarkers.removeWhere(
          (marker) => marker.markerId.value == 'simulated_car_marker');
      _mapMarkers.add(
        Marker(
          markerId: const MarkerId('simulated_car_marker'),
          position: _actualRoadPoints.first,
          icon:
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueYellow),
          infoWindow: InfoWindow(
            title: 'En Route',
            snippet: 'Meter: KSh ${_liveRunningFareKsh.toStringAsFixed(0)}',
          ),
        ),
      );
    });

    _inTransitTimer = Timer.periodic(const Duration(milliseconds: 400), (
      timer,
    ) {
      if (_currentWaypointIndex >= _actualRoadPoints.length) {
        timer.cancel();

        if (phase == TravelPhase.riderToDestination) {
          final rideDocumentId = _currentRideDocumentId;
          if (rideDocumentId != null && rideDocumentId.isNotEmpty) {
            unawaited(
              FirebaseFirestore.instance
                  .collection('rides')
                  .doc(rideDocumentId)
                  .update({
                'status': 'completed',
                'finalFareCharged': _liveRunningFareKsh.round(),
                'driverEarnings': _liveDriverEarningsKsh.round(),
                'distanceKm':
                    double.parse(_liveTraveledDistanceKm.toStringAsFixed(2)),
                'currentVehicleLocation': GeoPoint(
                  _actualRoadPoints.last.latitude,
                  _actualRoadPoints.last.longitude,
                ),
                'estimatedCost': _liveRunningFareKsh,
                'completedAt': FieldValue.serverTimestamp(),
              }),
            );
          }
          _etaMinutes = 0;
        } else {
          final rideDocumentId = _currentRideDocumentId;
          if (rideDocumentId != null && rideDocumentId.isNotEmpty) {
            unawaited(
              FirebaseFirestore.instance
                  .collection('rides')
                  .doc(rideDocumentId)
                  .update({
                'status': 'driver_arrived_pickup',
                'currentVehicleLocation': GeoPoint(
                  _actualRoadPoints.last.latitude,
                  _actualRoadPoints.last.longitude,
                ),
              }),
            );
          }
        }

        if (!mounted) return;

        setState(() {
          if (_actualRoadPoints.isNotEmpty) {
            _driverLocation = _actualRoadPoints.last;
          }

          if (phase == TravelPhase.driverToRider) {
            _currentRideState = RideState.driverArrived;
            _etaMinutes = 0;
            if (_selectedDriver != null &&
                _rideController.onDriverArrived != null) {
              _rideController.onDriverArrived!(
                _selectedDriver!['name'],
                _selectedDriver!['vehicle'],
              );
            }
          } else {
            _currentRideState = RideState.arrivedAtDestination;
            _calculatedFareKsh = _liveRunningFareKsh;
          }

          _mapMarkers.removeWhere(
              (marker) => marker.markerId.value == 'simulated_car_marker');
        });
        return;
      }

      final currentVehiclePosition = _actualRoadPoints[_currentWaypointIndex];

      if (!mounted) {
        timer.cancel();
        return;
      }

      setState(() {
        if (_currentWaypointIndex > 0) {
          final previousVehiclePosition =
              _actualRoadPoints[_currentWaypointIndex - 1];
          final segmentDistance = calculateSegmentDistance(
            previousVehiclePosition,
            currentVehiclePosition,
          );

          if (phase == TravelPhase.riderToDestination) {
            _liveTraveledDistanceKm += segmentDistance;
          }
        }

        if (phase == TravelPhase.riderToDestination) {
          _liveRunningFareKsh = 100.0 + (_liveTraveledDistanceKm * 90.0);
          _liveDriverEarningsKsh = _liveTraveledDistanceKm * 75.0;
        }

        final totalSteps = _actualRoadPoints.length;
        _movingProgress = totalSteps <= 1
            ? 1.0
            : (_currentWaypointIndex / (totalSteps - 1)).clamp(0.0, 1.0);
        _etaMinutes = ((1.0 - _movingProgress) * startingEtaMinutes)
            .ceil()
            .clamp(0, startingEtaMinutes);

        _driverLocation = currentVehiclePosition;

        _mapMarkers.removeWhere(
            (marker) => marker.markerId.value == 'simulated_car_marker');
        _mapMarkers.add(
          Marker(
            markerId: const MarkerId('simulated_car_marker'),
            position: currentVehiclePosition,
            icon: BitmapDescriptor.defaultMarkerWithHue(
                BitmapDescriptor.hueYellow),
            infoWindow: InfoWindow(
              title: 'En Route',
              snippet: 'Meter: KSh ${_liveRunningFareKsh.toStringAsFixed(0)}',
            ),
          ),
        );

        final rideDocumentId = _currentRideDocumentId;
        if (rideDocumentId != null && rideDocumentId.isNotEmpty) {
          unawaited(
            FirebaseFirestore.instance
                .collection('rides')
                .doc(rideDocumentId)
                .update({
              'status': phase == TravelPhase.riderToDestination
                  ? 'inTransit'
                  : 'driver_enroute_pickup',
              'currentVehicleLocation': GeoPoint(
                currentVehiclePosition.latitude,
                currentVehiclePosition.longitude,
              ),
              'finalFareCharged': phase == TravelPhase.riderToDestination
                  ? _liveRunningFareKsh.round()
                  : 100,
              'estimatedCost': phase == TravelPhase.riderToDestination
                  ? _liveRunningFareKsh.round()
                  : 100,
              'distanceKm':
                  double.parse(_liveTraveledDistanceKm.toStringAsFixed(2)),
              'driverEarnings': _liveDriverEarningsKsh,
              'updatedAt': FieldValue.serverTimestamp(),
            }),
          );
        }

        _currentWaypointIndex++;
      });

      _mapController?.animateCamera(
        CameraUpdate.newLatLng(currentVehiclePosition),
      );
    });
  }

  void _startTripTransitLegacy() {
    if (!mounted || _destinationLocation == null) return;
    setState(() {
      _currentRideState = RideState.inTransit;
      _movingProgress = 0.0;
      _etaMinutes = 8;
    });

    _simulationTimer?.cancel();
    _simulationTimer =
        Timer.periodic(const Duration(milliseconds: 120), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _movingProgress += 0.015;
        if (_movingProgress >= 1.0) {
          timer.cancel();
          _driverLocation = _destinationLocation;
          _riderLocation = _destinationLocation!;
          _currentRideState = RideState.arrivedAtDestination;
          _etaMinutes = 0;
        } else {
          _driverLocation = _interpolateCoordinates(
              _driverLocation!, _destinationLocation!, _movingProgress);
          if (timer.tick % 20 == 0 && _etaMinutes > 1) _etaMinutes--;
        }
        _mapController!.animateCamera(CameraUpdate.newLatLng(_driverLocation!));
      });
    });
  }

  void _showToastError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.redAccent),
    );
  }

  Future<void> _showProfileSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: context.aeroTokens.primaryDarkBlue,
                      child: Text(
                        (widget.user.displayName?.isNotEmpty ?? false)
                            ? widget.user.displayName![0].toUpperCase()
                            : 'R',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.user.displayName ?? 'Rider',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                            ),
                          ),
                          Text(
                            widget.user.email ?? '',
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.logout_rounded),
                  title: const Text('Sign out'),
                  onTap: () async {
                    Navigator.of(context).pop();
                    await FirebaseAuth.instance.signOut();
                    if (!context.mounted) return;
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(
                          builder: (context) => const RoleSelectionScreen()),
                      (route) => false,
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showRiderQuickAccountSheet(BuildContext ctx) async {
    await showModalBottomSheet<void>(
      context: ctx,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    CircleAvatar(
                      radius: 26,
                      backgroundColor: Colors.grey.shade100,
                      child: Text(
                        widget.user.displayName
                                ?.substring(0, 1)
                                .toUpperCase() ??
                            'R',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.user.displayName ?? 'AeroRide Rider',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            widget.user.email ?? 'passenger@aeroride.com',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.arrow_forward_ios,
                        size: 16,
                        color: Colors.grey,
                      ),
                      onPressed: () {
                        Navigator.pop(context);
                        _showProfileSheet();
                      },
                    ),
                  ],
                ),
                const Divider(height: 32),
                _buildSheetActionRow(
                  Icons.account_balance_wallet_outlined,
                  'Wallet & Payments',
                  'KSh 1,200 personal cash',
                  () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const WalletView(
                          currentBalance: 1200.0,
                        ),
                      ),
                    );
                  },
                ),
                _buildSheetActionRow(
                  Icons.history,
                  'My Ride Logs & History',
                  'Review past trips',
                  () {
                    Navigator.pop(context);
                    _showProfileSheet();
                  },
                ),
                _buildSheetActionRow(
                  Icons.help_outline,
                  'Support & Safety Dispatch',
                  '24/7 client care lines',
                  () {
                    Navigator.pop(context);
                    Navigator.of(this.context).push(
                      MaterialPageRoute(
                        builder: (context) => const SupportView(),
                      ),
                    );
                  },
                ),
                const Divider(height: 24),
                TextButton.icon(
                  onPressed: () async {
                    // Cleanly sign out from Firebase.
                    // Your global main.dart AuthWrapper will catch this and safely take the user back.
                    await FirebaseAuth.instance.signOut();
                  },
                  icon: const Icon(Icons.logout,
                      color: Colors.redAccent, size: 18),
                  label: const Text(
                    'Sign Out of AeroRide',
                    style: TextStyle(
                      color: Colors.redAccent,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: TextButton.styleFrom(
                    alignment: Alignment.centerLeft,
                    padding: EdgeInsets.zero,
                  ),
                ),
                const SizedBox(height: 10),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSheetActionRow(
    IconData icon,
    String title,
    String subtitle,
    VoidCallback onTap,
  ) {
    return ListTile(
      onTap: onTap,
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: Colors.black87, size: 22),
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(fontSize: 12, color: Colors.grey),
      ),
      trailing:
          const Icon(Icons.arrow_forward_ios, size: 12, color: Colors.black26),
    );
  }

  Set<Marker> _buildMapMarkers() {
    Set<Marker> markers = {};

    if (_riderLocation != null) {
      markers.add(Marker(
        markerId: const MarkerId('pickup_marker'),
        position: _riderLocation!,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        consumeTapEvents: false,
      ));
    }

    if (_destinationLocation != null) {
      markers.add(Marker(
        markerId: const MarkerId('dropoff_marker'),
        position: _destinationLocation!,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        consumeTapEvents: false,
      ));
    }

    if (_driverLocation != null &&
        _currentRideState != RideState.idle &&
        _currentRideState != RideState.payment) {
      markers.add(Marker(
        markerId: const MarkerId('moving_driver_car'),
        position: _driverLocation!,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueYellow),
        infoWindow:
            InfoWindow(title: "Your Driver", snippet: "ETA: $_etaMinutes Mins"),
      ));
    }

    markers.addAll(_mapMarkers);

    return markers;
  }

  @override
  Widget build(BuildContext context) {
    final currentLocation =
        _rideController.riderLocation ?? const LatLng(-0.3031, 36.0800);

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 5,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Stack(
                  children: [
                    // Map Container Layer
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.black12, width: 1),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: GoogleMap(
                        initialCameraPosition: CameraPosition(
                          target: currentLocation,
                          zoom: 14.0,
                        ),
                        onMapCreated: (controller) =>
                            _mapController = controller,
                        markers: _buildMapMarkers(),
                        polylines: _mapPolylines,
                        myLocationButtonEnabled: false,
                        zoomControlsEnabled: true,
                        gestureRecognizers: <Factory<
                            OneSequenceGestureRecognizer>>{
                          Factory<OneSequenceGestureRecognizer>(
                            () => EagerGestureRecognizer(),
                          ),
                        },
                        onTap: _handleMapTap,
                      ),
                    ),

                    // Premium Hybrid Floating Avatar Button
                    Positioned(
                      top: 14,
                      right: 14,
                      child: GestureDetector(
                        onTap: () => _showRiderQuickAccountSheet(context),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: const [
                              BoxShadow(
                                  color: Colors.black26,
                                  blurRadius: 6,
                                  offset: Offset(0, 2)),
                            ],
                            border: Border.all(color: Colors.black12, width: 2),
                          ),
                          child: CircleAvatar(
                            radius: 22,
                            backgroundColor: Colors.black,
                            child: Text(
                              widget.user.displayName != null &&
                                      widget.user.displayName!.isNotEmpty
                                  ? widget.user.displayName!
                                      .substring(0, 1)
                                      .toUpperCase()
                                  : 'R',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              flex: 5,
              child: Container(
                margin: const EdgeInsets.only(top: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black12, blurRadius: 8, spreadRadius: 1),
                  ],
                ),
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: _buildPanelContent(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPanelContent() {
    switch (_currentRideState) {
      case RideState.idle:
      case RideState.searchingAddresses:
        if (_isPickingFromMap) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.location_on,
                  size: 40,
                  color: _mapPinTarget == 'pickup' ? Colors.blue : Colors.red),
              const SizedBox(height: 8),
              Text(
                "Click anywhere on the map to place your $_mapPinTarget pin...",
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => setState(() => _isPickingFromMap = false),
                child: const Text("Cancel Map Pinning",
                    style: TextStyle(
                        color: Colors.redAccent, fontWeight: FontWeight.bold)),
              )
            ],
          );
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Where to?',
                style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 22,
                    letterSpacing: -0.5)),
            const SizedBox(height: 16),

            // Pickup Input Layer
            TextField(
              controller: _pickupTextController,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.circle,
                    size: 12, color: Colors.blueAccent),
                hintText: 'Enter Pickup or Click Map Icon',
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.map,
                          size: 18, color: Colors.blueAccent),
                      tooltip: "Pick on Map",
                      onPressed: () {
                        _clearExistingRoute();
                        setState(() {
                          _isPickingFromMap = true;
                          _mapPinTarget = 'pickup';
                        });
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.my_location,
                          size: 18, color: Colors.grey),
                      onPressed: _useCurrentLocation,
                    ),
                  ],
                ),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
            const SizedBox(height: 10),

            // Destination Input Layer
            TextField(
              controller: _destinationTextController,
              decoration: InputDecoration(
                prefixIcon:
                    const Icon(Icons.square, size: 12, color: Colors.black),
                hintText: 'Where are we dropping off?',
                suffixIcon: IconButton(
                  icon:
                      const Icon(Icons.map, size: 18, color: Colors.redAccent),
                  tooltip: "Pick on Map",
                  onPressed: () {
                    _clearExistingRoute();
                    setState(() {
                      _isPickingFromMap = true;
                      _mapPinTarget = 'destination';
                    });
                  },
                ),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
            const SizedBox(height: 16),

            ElevatedButton(
              onPressed: _geocodeAndRouteAddresses,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Search Route & Prices',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 18),
            _buildSuggestedDestinationsSection(),
          ],
        );

      case RideState.driverSelection:
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Select Your AeroRide',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 19)),
                TextButton(
                    child: const Text('Reset'),
                    onPressed: () {
                      setState(() {
                        _currentRideState = RideState.idle;
                        _riderLocation = null;
                        _destinationLocation = null;
                        _pickupTextController.clear();
                        _destinationTextController.clear();
                        _mapPolylines.clear();
                      });
                    }),
              ],
            ),
            const SizedBox(height: 8),
            ..._availableDriversPool.map((driver) => Card(
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  child: ListTile(
                    leading: const Icon(Icons.directions_car,
                        color: Colors.black87, size: 30),
                    title: Text(driver['name'],
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle:
                        Text('⭐ ${driver['rating']} • ${driver['vehicle']}'),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          _currentWaypointIndex > 0
                              ? 'KSh ${_liveRunningFareKsh.toStringAsFixed(0)}'
                              : 'KSh ${_calculatedFareKsh.toStringAsFixed(0)} (Est.)',
                          style: const TextStyle(
                              fontWeight: FontWeight.w900, fontSize: 16),
                        ),
                        Text('${driver['eta']} min away',
                            style: const TextStyle(
                                color: Colors.green,
                                fontSize: 11,
                                fontWeight: FontWeight.bold)),
                      ],
                    ),
                    onTap: () => _confirmDriverAndBook(driver),
                  ),
                )),
          ],
        );

      case RideState.requesting:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const LinearProgressIndicator(color: Colors.black),
            const SizedBox(height: 16),
            Text('Contacting ${_selectedDriver?['name']}...',
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
            const Text(
                'Dispatching vehicle tracking requests across servers...',
                style: TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        );

      case RideState.driverEnRoute:
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildLiveTaximeterDock(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Driver Is En Route',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                            color: Colors.orange)),
                    Text(
                        '${_selectedDriver?['name']} is arriving in $_etaMinutes Mins',
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  ],
                ),
                const Icon(Icons.directions_car,
                    color: Colors.orange, size: 32),
              ],
            ),
            const Divider(height: 24),
            Text('VEHICLE DETAILS: ${_selectedDriver?['vehicle']}',
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey)),
            const SizedBox(height: 10),
            LinearProgressIndicator(
              value: _movingProgress,
              color: Colors.orange,
              backgroundColor: Colors.orange.shade50,
            ),
          ],
        );

      case RideState.driverArrived:
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('${_selectedDriver?['name']} Has Arrived!',
                style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                    color: Colors.green)),
            const SizedBox(height: 6),
            const Text(
                'Your vehicle is currently waiting at your specified pickup point.',
                style: TextStyle(fontSize: 13)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _startTripTransit,
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  padding: const EdgeInsets.symmetric(vertical: 14)),
              child: const Text('Start Trip Transit',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        );

      case RideState.inTransit:
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildLiveTaximeterDock(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Heading to Destination...',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 17,
                        color: Colors.blue)),
                Text('ETA: $_etaMinutes Mins',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(
                value: _movingProgress,
                color: Colors.blue,
                backgroundColor: Colors.blue.shade50),
          ],
        );

      case RideState.arrivedAtDestination:
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Arrived Safely at Destination 🎉',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 19)),
            const SizedBox(height: 14),
            ElevatedButton(
              onPressed: () =>
                  setState(() => _currentRideState = RideState.payment),
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 14)),
              child: const Text('Collect Receipt & Invoice',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        );

      case RideState.payment:
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Outstanding Fare Payment',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(height: 12),
            TextField(
              controller: _mpesaPhoneController,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: 'M-Pesa Phone Number',
                hintText: '07XXXXXXXX or 2547XXXXXXXX',
                filled: true,
                fillColor: Colors.grey.shade50,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(12)),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Total Amount:',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  Text('KSh ${_calculatedFareKsh.toStringAsFixed(2)}',
                      style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 20,
                          color: Colors.green)),
                ],
              ),
            ),
            const SizedBox(height: 14),
            if (_paymentStatusMessage.isNotEmpty) ...[
              Text(
                _paymentStatusMessage,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _isPaymentProcessing ? Colors.blueGrey : Colors.green,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
            ],
            ElevatedButton(
              onPressed: _isPaymentProcessing ? null : _completeRidePayment,
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  padding: const EdgeInsets.symmetric(vertical: 14)),
              child: Text(
                _isPaymentProcessing
                    ? 'Sending STK Push...'
                    : 'Pay Now via M-Pesa STK',
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        );
    }
  }
}
