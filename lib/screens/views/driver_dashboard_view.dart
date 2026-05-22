import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';

import '../../screens/driver/driver_profile_screen.dart';
import '../../theme/aeroride_theme.dart';

enum DriverRideState {
  searchingRequests,
  navigatingToPickup,
  arrivedAtPickup,
  passengerInTransit,
  tripCompleted
}

class DriverDashboardView extends StatefulWidget {
  final User user;
  const DriverDashboardView({super.key, required this.user});

  @override
  State<DriverDashboardView> createState() => _DriverDashboardViewState();
}

class _DriverDashboardViewState extends State<DriverDashboardView> {
  GoogleMapController? _mapController;
  DriverRideState _currentDriverState = DriverRideState.searchingRequests;

  bool _isOnline = false;
  LatLng _driverCurrentLocation =
      const LatLng(-0.2831, 36.0664); // Defaults to Nakuru

  Map<String, dynamic>? _activeRideData;
  Timer? _simulationTimer;
  double _transitProgress = 0.0;
  int _etaMinutes = 5;

  final Set<Polyline> _mapPolylines = {};
  final Set<Marker> _mapMarkers = {};

  final List<Map<String, dynamic>> _mockIncomingRidesPool = [
    {
      "id": "req_001",
      "riderName": "Grace Otieno",
      "pickupName": "Nakuru CBD - Westside Mall",
      "destinationName": "Milimani Estate",
      "pickupLatLng": const LatLng(-0.2831, 36.0664),
      "destinationLatLng": const LatLng(-0.2750, 36.0700),
      "fareKsh": 350.00,
      "distanceKm": 2.4
    },
    {
      "id": "req_002",
      "riderName": "Kelvin Mwangi",
      "pickupName": "Nairobi - Westlands (Sarit Centre)",
      "destinationName": "Kilimani Area",
      "pickupLatLng": const LatLng(-1.2644, 36.8044),
      "destinationLatLng": const LatLng(-1.2912, 36.7846),
      "fareKsh": 580.00,
      "distanceKm": 4.1
    },
    {
      "id": "req_003",
      "riderName": "Aminah Hussein",
      "pickupName": "Mombasa - Nyali Centre",
      "destinationName": "Bamburi Beach Resort",
      "pickupLatLng": const LatLng(-4.0275, 39.7022),
      "destinationLatLng": const LatLng(-4.0041, 39.7188),
      "fareKsh": 720.00,
      "distanceKm": 5.8
    }
  ];

  @override
  void dispose() {
    _simulationTimer?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _determineDriverGPSLocation() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(color: Colors.white),
      ),
    );

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) Navigator.pop(context);
        _showErrorSnackbar('Location services are disabled on your device.');
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) Navigator.pop(context);
          _showErrorSnackbar('Location permissions were denied.');
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (mounted) Navigator.pop(context);
        _showErrorSnackbar('Location permissions are permanently blocked.');
        return;
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      if (mounted) {
        Navigator.pop(context);
        setState(() {
          _driverCurrentLocation =
              LatLng(position.latitude, position.longitude);
          _isOnline = true;
          _rebuildMapElements();
        });

        _mapController?.animateCamera(
          CameraUpdate.newLatLngZoom(_driverCurrentLocation, 14.5),
        );
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      _showErrorSnackbar('Failed to acquire location coordinates: $e');
    }
  }

  void _showErrorSnackbar(String message) {
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
                      backgroundColor: Colors.black,
                      child: Text(
                        (widget.user.displayName?.isNotEmpty ?? false)
                            ? widget.user.displayName![0].toUpperCase()
                            : 'D',
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
                            widget.user.displayName ?? 'Driver',
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
                _AccountActionTile(
                  icon: Icons.account_circle_outlined,
                  title: 'View full profile',
                  subtitle: 'Edit driver details and preferences',
                  onTap: () {
                    Navigator.of(context).pop();
                    Navigator.of(this.context).push(
                      MaterialPageRoute(
                        builder: (context) =>
                            DriverProfileScreen(user: widget.user),
                      ),
                    );
                  },
                ),
                _AccountActionTile(
                  icon: Icons.receipt_long_outlined,
                  title: 'Trips',
                  subtitle: 'Review completed rides and earnings',
                  onTap: () {
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(this.context).showSnackBar(
                      const SnackBar(
                          content: Text(
                              'Trips view opens from your profile screen.')),
                    );
                  },
                ),
                _AccountActionTile(
                  icon: Icons.account_balance_wallet_outlined,
                  title: 'Wallet',
                  subtitle: 'Check payouts and earnings balance',
                  onTap: () {
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(this.context).showSnackBar(
                      const SnackBar(
                          content:
                              Text('Wallet is coming from the profile flow.')),
                    );
                  },
                ),
                _AccountActionTile(
                  icon: Icons.support_agent_outlined,
                  title: 'Support',
                  subtitle: 'Get help or report an issue',
                  onTap: () {
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(this.context).showSnackBar(
                      const SnackBar(
                          content: Text('Support entry is not wired yet.')),
                    );
                  },
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

  Widget _buildTopStatusBanner() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      child: Card(
        color: Colors.black,
        elevation: 1,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.circle,
                    size: 11,
                    color: !_isOnline
                        ? Colors.redAccent
                        : (_currentDriverState ==
                                DriverRideState.searchingRequests
                            ? Colors.greenAccent
                            : Colors.orangeAccent),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    !_isOnline
                        ? 'STATUS: OFFLINE'
                        : (_currentDriverState ==
                                DriverRideState.searchingRequests
                            ? 'STATUS: ONLINE'
                            : 'JOB IN PROGRESS'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.badge, color: Colors.white, size: 24),
                tooltip: 'Driver Account Desk',
                onPressed: _showProfileSheet,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _acceptRideRequest(Map<String, dynamic> selectedRide) {
    setState(() {
      _activeRideData = selectedRide;
      _currentDriverState = DriverRideState.navigatingToPickup;

      double distanceMeters = Geolocator.distanceBetween(
        _driverCurrentLocation.latitude,
        _driverCurrentLocation.longitude,
        selectedRide['pickupLatLng'].latitude,
        selectedRide['pickupLatLng'].longitude,
      );
      _etaMinutes = ((distanceMeters / 1000) * 2).round().clamp(2, 25);
    });

    _rebuildMapElements();
    _zoomToFitPoints(_driverCurrentLocation, selectedRide['pickupLatLng']);
    _startNavigationSimulation(toPickup: true);
  }

  void _startNavigationSimulation({required bool toPickup}) {
    _simulationTimer?.cancel();
    _transitProgress = 0.0;

    LatLng startPosition = _driverCurrentLocation;
    LatLng targetPosition = toPickup
        ? _activeRideData!['pickupLatLng']
        : _activeRideData!['destinationLatLng'];

    _simulationTimer =
        Timer.periodic(const Duration(milliseconds: 150), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      setState(() {
        _transitProgress += 0.025;
        if (_transitProgress >= 1.0) {
          timer.cancel();
          _driverCurrentLocation = targetPosition;

          if (toPickup) {
            _currentDriverState = DriverRideState.arrivedAtPickup;
            _etaMinutes = 0;
          } else {
            _currentDriverState = DriverRideState.tripCompleted;
            _etaMinutes = 0;
          }
        } else {
          _driverCurrentLocation = _interpolatePoints(
              startPosition, targetPosition, _transitProgress);
          if (timer.tick % 12 == 0 && _etaMinutes > 1) _etaMinutes--;
        }

        _rebuildMapElements();
        _mapController
            ?.animateCamera(CameraUpdate.newLatLng(_driverCurrentLocation));
      });
    });
  }

  void _startPassengerTransitTrip() {
    if (_activeRideData == null) return;
    setState(() {
      _currentDriverState = DriverRideState.passengerInTransit;
      _etaMinutes = (_activeRideData!['distanceKm'] * 2).round().clamp(3, 20);
    });

    _zoomToFitPoints(_activeRideData!['pickupLatLng'],
        _activeRideData!['destinationLatLng']);
    _startNavigationSimulation(toPickup: false);
  }

  void _resetDriverDashboard() {
    setState(() {
      _currentDriverState = DriverRideState.searchingRequests;
      _activeRideData = null;
      _mapPolylines.clear();
      _mapMarkers.clear();
    });
    _determineDriverGPSLocation();
  }

  LatLng _interpolatePoints(LatLng start, LatLng end, double fraction) {
    double lat = start.latitude + (end.latitude - start.latitude) * fraction;
    double lng = start.longitude + (end.longitude - start.longitude) * fraction;
    return LatLng(lat, lng);
  }

  void _rebuildMapElements() {
    _mapMarkers.clear();
    _mapPolylines.clear();

    _mapMarkers.add(Marker(
      markerId: const MarkerId('driver_vehicle_marker'),
      position: _driverCurrentLocation,
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
      infoWindow: const InfoWindow(title: "Your Vehicle (Live GPS)"),
    ));

    if (_activeRideData != null) {
      LatLng pickup = _activeRideData!['pickupLatLng'];
      LatLng destination = _activeRideData!['destinationLatLng'];

      _mapMarkers.add(Marker(
        markerId: const MarkerId('rider_pickup_marker'),
        position: pickup,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
        infoWindow:
            InfoWindow(title: "Pickup: ${_activeRideData!['pickupName']}"),
      ));

      _mapMarkers.add(Marker(
        markerId: const MarkerId('rider_destination_marker'),
        position: destination,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        infoWindow: InfoWindow(
            title: "Dropoff: ${_activeRideData!['destinationName']}"),
      ));

      List<LatLng> points =
          (_currentDriverState == DriverRideState.navigatingToPickup)
              ? [_driverCurrentLocation, pickup]
              : [pickup, destination];

      _mapPolylines.add(Polyline(
        polylineId: const PolylineId('driver_route_line'),
        points: points,
        color: Colors.blue.shade900,
        width: 6,
        jointType: JointType.round,
      ));
    }
  }

  void _zoomToFitPoints(LatLng start, LatLng end) {
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
          southwest: LatLng(minLat - 0.02, minLng - 0.02),
          northeast: LatLng(maxLat + 0.02, maxLng + 0.02),
        ),
        60,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Fixed Top Duty Pill Status Banner
            _buildTopStatusBanner(),

            // TOP 50% HALF: Framed Map Box
            Expanded(
              flex: 5,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Stack(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border:
                            Border.all(color: Colors.grey.shade200, width: 1),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: GoogleMap(
                        initialCameraPosition: CameraPosition(
                            target: _driverCurrentLocation, zoom: 12.0),
                        onMapCreated: (controller) =>
                            _mapController = controller,
                        markers: _mapMarkers,
                        polylines: _mapPolylines,
                        myLocationButtonEnabled: false,
                        zoomControlsEnabled: true,
                      ),
                    ),
                    Positioned(
                      top: 12,
                      right: 12,
                      child: FloatingActionButton.small(
                        heroTag: 'driver_profile_btn',
                        backgroundColor: Colors.black,
                        foregroundColor: Colors.white,
                        elevation: 4,
                        shape: const CircleBorder(),
                        onPressed: _showProfileSheet,
                        child: const Icon(Icons.badge, size: 20),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // BOTTOM 50% HALF: Clean Workflow Action Board Panel
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
                        color: Colors.black12, blurRadius: 8, spreadRadius: 1)
                  ],
                ),
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: !_isOnline
                      ? _buildOfflinePanel()
                      : _buildDriverWorkflowPanel(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOfflinePanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        const Text(
          'You are currently Offline',
          style: TextStyle(
              fontWeight: FontWeight.w900, fontSize: 20, letterSpacing: -0.5),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        const Text(
          'Declare yourself online to share your live device GPS location in the frame above and begin accepting active trip assignments.',
          style: TextStyle(fontSize: 13, color: Colors.grey, height: 1.4),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: _determineDriverGPSLocation,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green.shade700,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            elevation: 1,
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.location_on, color: Colors.white),
              SizedBox(width: 8),
              Text('GO ONLINE / SHARE GPS LOCATION',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDriverWorkflowPanel() {
    switch (_currentDriverState) {
      case DriverRideState.searchingRequests:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Live Request Board',
                  style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 19,
                      letterSpacing: -0.5),
                ),
                TextButton.icon(
                  onPressed: () => setState(() => _isOnline = false),
                  icon: const Icon(Icons.power_settings_new,
                      size: 16, color: Colors.red),
                  label: const Text('GO OFFLINE',
                      style: TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.bold,
                          fontSize: 12)),
                )
              ],
            ),
            const Text(
              'Select an offer below to begin simulation sequence.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _mockIncomingRidesPool.length,
              itemBuilder: (context, index) {
                final ride = _mockIncomingRidesPool[index];
                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  elevation: 1,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: Colors.grey.shade200)),
                  child: InkWell(
                    onTap: () => _acceptRideRequest(ride),
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          const CircleAvatar(
                            backgroundColor: Colors.black12,
                            child: Icon(Icons.person, color: Colors.black87),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  ride['riderName'],
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15),
                                ),
                                const SizedBox(height: 4),
                                Text('🟢 From: ${ride['pickupName']}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 12)),
                                Text('🔴 To: ${ride['destinationName']}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 12)),
                                Text('📏 Distance: ${ride['distanceKm']} KM',
                                    style: const TextStyle(
                                        fontSize: 11, color: Colors.grey)),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'KSh ${ride['fareKsh'].toStringAsFixed(0)}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 16,
                                    color: Colors.green),
                              ),
                              const SizedBox(height: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                    color: Colors.black,
                                    borderRadius: BorderRadius.circular(6)),
                                child: const Text('ACCEPT',
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold)),
                              )
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        );

      case DriverRideState.navigatingToPickup:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Navigating to Passenger...',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                            color: Colors.blue)),
                    Text('Arriving at pickup point in $_etaMinutes Mins',
                        style: const TextStyle(fontWeight: FontWeight.w500)),
                  ],
                ),
                const Icon(Icons.directions_run, color: Colors.blue, size: 32),
              ],
            ),
            const Divider(height: 24),
            Text('PICKUP TARGET: ${_activeRideData?['pickupName']}',
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey)),
            const SizedBox(height: 12),
            LinearProgressIndicator(
                value: _transitProgress, color: Colors.blue, minHeight: 5),
          ],
        );

      case DriverRideState.arrivedAtPickup:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 12),
            const Text('Arrived at Pickup Spot! 👋',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 19,
                    color: Colors.green)),
            const SizedBox(height: 6),
            Text(
                'Passenger: ${_activeRideData?['riderName']} is getting into your vehicle.',
                style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _startPassengerTransitTrip,
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 14)),
              child: const Text('Start Passenger Trip Transit',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        );

      case DriverRideState.passengerInTransit:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Trip In Progress...',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 17,
                        color: Colors.orange)),
                Text('Dest ETA: $_etaMinutes Mins',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 8),
            Text('Dropping off at: ${_activeRideData?['destinationName']}',
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 14),
            LinearProgressIndicator(
                value: _transitProgress, color: Colors.orange, minHeight: 5),
          ],
        );

      case DriverRideState.tripCompleted:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 12),
            const Text('Trip Completed Successfully! 🏁',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 19)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(12)),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Earnings Collected:',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  Text('KSh ${_activeRideData?['fareKsh'].toStringAsFixed(2)}',
                      style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 20,
                          color: Colors.green)),
                ],
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _resetDriverDashboard,
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 14)),
              child: const Text('Return to Request Board',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        );
    }
  }
}

class _AccountActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _AccountActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }
}
