import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart' as geo;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';

import '../../controllers/ride_controller.dart';
import '../../models/ride_request_model.dart';
import '../../models/ride_type_model.dart';
import '../../models/user_model.dart';
import '../../services/firestore_service.dart';
import '../../theme/aeroride_theme.dart';
import '../../utils/currency.dart';
import '../../widgets/aeroride_components.dart';

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

class RiderDashboardView extends StatefulWidget {
  final User user;
  const RiderDashboardView({super.key, required this.user});

  @override
  State<RiderDashboardView> createState() => _RiderDashboardViewState();
}

class _RiderDashboardViewState extends State<RiderDashboardView> {
  late RideController _rideController;
  GoogleMapController? _mapController;

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

  String _pickupAddressString = "Not Selected";
  String _destinationAddressString = "Not Selected";
  bool _isSearchingGeocode = false;

  double _movingProgress = 0.0;
  Timer? _simulationTimer;
  int _etaMinutes = 5;
  double _calculatedFareKsh = 0.0;

  Map<String, dynamic>? _selectedDriver;
  List<Map<String, dynamic>> _availableDriversPool = [];
  final Set<Polyline> _mapPolylines = {};

  @override
  void initState() {
    super.initState();
    _rideController = Provider.of<RideController>(context, listen: false);
    unawaited(_rideController.startRiderLocationTracking());
    _rideController.loadRideTypes();

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
    _mapController?.dispose();
    _pickupTextController.dispose();
    _destinationTextController.dispose();
    super.dispose();
  }

  void _clearExistingRoute() {
    setState(() {
      _mapPolylines.clear();
      _destinationLocation = null;
    });
  }

  // Uses device hardware to snap current coordinates automatically
  Future<void> _useCurrentLocation() async {
    setState(() => _isSearchingGeocode = true);
    try {
      LatLng currentCoords =
          _rideController.riderLocation ?? const LatLng(-0.2831, 36.0664);

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
      final fallbackCoords =
          _rideController.riderLocation ?? const LatLng(-0.2831, 36.0664);
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
      _calculatedFareKsh = (distanceInKm * 70.0) + 150.0;
      if (_calculatedFareKsh < 200) _calculatedFareKsh = 200.00;

      // 4. Generate custom nearby vehicle pool
      _availableDriversPool = [
        {
          "name": "James Kamau",
          "vehicle": "KDD 555Y - Silver Nissan Leaf",
          "rating": "4.9",
          "eta": 3,
          "lat": _riderLocation!.latitude + 0.003,
          "lng": _riderLocation!.longitude + 0.003
        },
        {
          "name": "Sarah Mwangi",
          "vehicle": "KCA 123Z - White Toyota Prius",
          "rating": "4.8",
          "eta": 5,
          "lat": _riderLocation!.latitude - 0.002,
          "lng": _riderLocation!.longitude + 0.002
        }
      ];

      setState(() {
        _currentRideState = RideState.driverSelection;
      });

      _generateRoutePolylines(_riderLocation!, _destinationLocation!);
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

  void _generateRoutePolylines(LatLng start, LatLng end) {
    _mapPolylines.clear();
    List<LatLng> routePoints = [
      start,
      LatLng((start.latitude + end.latitude) / 2 + 0.001,
          (start.longitude + end.longitude) / 2 - 0.001),
      end
    ];

    setState(() {
      _mapPolylines.add(
        Polyline(
          polylineId: const PolylineId('ride_route'),
          points: routePoints,
          color: Colors.black,
          width: 5,
          jointType: JointType.round,
          consumeTapEvents:
              false, // Core Web Fix: Stops polyline from consuming click gestures
        ),
      );
    });
    _zoomToFitRoute(start, end);
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

  void _confirmDriverAndBook(Map<String, dynamic> driver) {
    setState(() {
      _selectedDriver = driver;
      _currentRideState = RideState.requesting;
      _driverLocation = LatLng(driver['lat'], driver['lng']);
      _etaMinutes = driver['eta'];
    });

    final rideRequestRef =
        FirebaseFirestore.instance.collection('ride_requests').doc();
    rideRequestRef.set({
      'id': rideRequestRef.id,
      'riderId': widget.user.uid,
      'riderName': widget.user.displayName ?? 'AeroRide User',
      'pickup': GeoPoint(_riderLocation!.latitude, _riderLocation!.longitude),
      'dropoff': GeoPoint(
          _destinationLocation!.latitude, _destinationLocation!.longitude),
      'pickupAddress': _pickupAddressString,
      'destinationName': _destinationAddressString,
      'status': 'searching',
      'fareKsh': _calculatedFareKsh,
      'createdAt': FieldValue.serverTimestamp(),
    });

    Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      rideRequestRef
          .update({'status': 'accepted', 'driverName': driver['name']});

      setState(() {
        _currentRideState = RideState.driverEnRoute;
      });

      _movingProgress = 0.0;
      LatLng initialDriverPos = _driverLocation!;
      _simulationTimer =
          Timer.periodic(const Duration(milliseconds: 100), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        setState(() {
          _movingProgress += 0.02;
          if (_movingProgress >= 1.0) {
            timer.cancel();
            _driverLocation = _riderLocation;
            _currentRideState = RideState.driverArrived;
            _etaMinutes = 0;

            if (_rideController.onDriverArrived != null) {
              _rideController.onDriverArrived!(
                  driver['name'], driver['vehicle']);
            }
          } else {
            _driverLocation = _interpolateCoordinates(
                initialDriverPos, _riderLocation!, _movingProgress);
            if (timer.tick % 15 == 0 && _etaMinutes > 1) _etaMinutes--;
          }
          _mapController!
              .animateCamera(CameraUpdate.newLatLng(_driverLocation!));
        });
      });
    });
  }

  void _startTripTransit() {
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
        return Padding(
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
                      widget.user.displayName?.substring(0, 1).toUpperCase() ??
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
                  _showToastError('Wallet screen is not connected yet.');
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
                  _showToastError('Support is not connected yet.');
                },
              ),
              const Divider(height: 24),
              TextButton.icon(
                onPressed: () async {
                  await FirebaseAuth.instance.signOut();
                  if (!ctx.mounted) return;
                  Navigator.popUntil(ctx, (route) => route.isFirst);
                },
                icon:
                    const Icon(Icons.logout, color: Colors.redAccent, size: 18),
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
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
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
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
        infoWindow:
            InfoWindow(title: "Your Driver", snippet: "ETA: $_etaMinutes Mins"),
      ));
    }

    return markers;
  }

  @override
  Widget build(BuildContext context) {
    final currentLocation =
        _rideController.riderLocation ?? const LatLng(-1.286389, 36.817223);

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
                        Text('KSh ${_calculatedFareKsh.toStringAsFixed(0)}',
                            style: const TextStyle(
                                fontWeight: FontWeight.w900, fontSize: 16)),
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
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _currentRideState = RideState.idle;
                  _riderLocation = null;
                  _destinationLocation = null;
                  _driverLocation = null;
                  _pickupTextController.clear();
                  _destinationTextController.clear();
                  _mapPolylines.clear();
                });
              },
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  padding: const EdgeInsets.symmetric(vertical: 14)),
              child: const Text('Pay Now via M-Pesa / Card',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        );
    }
  }
}
