import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import '../../utils/fare_calculator.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import '../../screens/driver/driver_profile_screen.dart';
import 'support_view.dart';
import 'wallet_view.dart';
import '../../theme/aeroride_theme.dart';
import '../role_selection_screen.dart';

class MockRideRequest {
  final String id;
  final String riderName;
  final String pickupName;
  final String destinationName;
  final LatLng pickupCoords;
  final LatLng destinationCoords;
  final double estimatedFare;

  MockRideRequest({
    required this.id,
    required this.riderName,
    required this.pickupName,
    required this.destinationName,
    required this.pickupCoords,
    required this.destinationCoords,
    required this.estimatedFare,
  });
}

enum DriverRideState {
  searchingRequests,
  navigatingToPickup,
  arrivedAtPickup,
  passengerInTransit,
  tripCompleted,
}

class DriverDashboardView extends StatefulWidget {
  final dynamic user;
  const DriverDashboardView({super.key, required this.user});

  @override
  State<DriverDashboardView> createState() => _DriverDashboardViewState();
}

// ⚠️ FIXED: The variables were sitting here out in the open. They have been moved inside the class below.

class _DriverDashboardViewState extends State<DriverDashboardView> {
  GoogleMapController? _mapController;
  DriverRideState _currentDriverState = DriverRideState.searchingRequests;

  int _selectedTabIndex = 0; // 0 = Map, 1 = Profile

  bool _isAwaitingPayment = false;
  bool _paymentReceived = false;
  bool _isProcessingPaymentPush = false;

  Timer? _driverSimulationTimer;
  List<LatLng> _driverActualRoadPoints = [];
  int _driverWaypointIndex = 0;

  double _driverTraveledDistanceKm = 0.0;
  double _driverLiveEarningsKsh = 0.0;
  double _passengerLiveFareKsh = 100.0;

  List<MockRideRequest> _availableRequests = [];
  MockRideRequest? _activeRequest;
  bool _isOnline = false;
  bool _isSearchingForRides = false;
  bool _hasIncomingRequest = false;
  bool _isTripActive = false;
  double _walletBalanceKsh =
      1450.00; // Starting mock balance for the driver wallet

  LatLng _driverCurrentLocation = const LatLng(-0.2831, 36.0664);

  final LatLng _mockDriverCurrentLocation = const LatLng(-0.28496, 36.06795);
  final LatLng _mockRiderPickupLocation = const LatLng(-0.28989, 36.05451);
  final LatLng _mockRiderDestinationLocation = const LatLng(-0.26562, 36.04853);

  Map<String, dynamic>? _activeRideData;
  String? activeRideDocId;
  Timer? _simulationTimer;
  double _transitProgress = 0.0;
  int _etaMinutes = 5;

  final Set<Polyline> _mapPolylines = {};
  final Set<Marker> _mapMarkers = {};

  // Import fare calculator helpers
  // Note: uses lib/utils/fare_calculator.dart

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _driverSimulationTimer?.cancel();
    _simulationTimer?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  void _autoTriggerIncomingRideSearch() {
    setState(() {
      _isSearchingForRides = true;
      _availableRequests.clear();
      _activeRequest = null;
      _hasIncomingRequest = false;
      _isTripActive = false;

      // ✅ CRITICAL REFRESH FLUSH LINE: Clear index tracker instantly
      _driverWaypointIndex = 0;
      _driverActualRoadPoints.clear();
    });

    Timer(const Duration(seconds: 5), () {
      if (!mounted) return;
      setState(() {
        _isSearchingForRides = false;
        _availableRequests = [
          MockRideRequest(
            id: 'TRIP_001',
            riderName: 'Mary W.',
            pickupName: 'Westside Mall Nakuru',
            destinationName: 'Milimani Estate',
            pickupCoords: const LatLng(-0.2872, 36.0617),
            destinationCoords: const LatLng(-0.2743, 36.0692),
            estimatedFare: 250.0,
          ),
          MockRideRequest(
            id: 'TRIP_002',
            riderName: 'John K.',
            pickupName: 'Nakuru Main Stage',
            destinationName: 'Section 58',
            pickupCoords: const LatLng(-0.2899, 36.0712),
            destinationCoords: const LatLng(-0.2845, 36.0941),
            estimatedFare: 380.0,
          ),
          MockRideRequest(
            id: 'TRIP_003',
            riderName: 'David O.',
            pickupName: 'Nakuru Blankets Factory',
            destinationName: 'Lanet Corner',
            pickupCoords: const LatLng(-0.2985, 36.0620),
            destinationCoords: const LatLng(-0.2952, 36.1345),
            estimatedFare: 620.0,
          ),
        ];
        _hasIncomingRequest = _availableRequests.isNotEmpty;
      });
    });
  }

  // =========================================================================
  // ✅ PLACED HERE: Your Simulated Payment Handler Method
  // =========================================================================
  void _triggerSimulatedRiderPayment() {
    setState(() {
      _isProcessingPaymentPush = true;
    });

    Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          _isAwaitingPayment = false;
          _isProcessingPaymentPush = false;
          _paymentReceived = true;

          // Adds the ride's take-home pay straight into the wallet state balance!
          _walletBalanceKsh += _driverLiveEarningsKsh;
        });

        _finalizeTripToCloudDatabase();
      }
    });
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
                const SizedBox(height: 16),
                _buildSheetActionRow(
                  Icons.monetization_on_outlined,
                  'Earnings & Cashouts',
                  'Open earnings summary and payout tools',
                  () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            DriverProfileScreen(user: widget.user),
                      ),
                    );
                  },
                ),
                _buildSheetActionRow(
                  Icons.local_taxi,
                  'Vehicle & Fleet Verification',
                  'Review vehicle and fleet details',
                  () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            DriverProfileScreen(user: widget.user),
                      ),
                    );
                  },
                ),
                _buildSheetActionRow(
                  Icons.support_agent,
                  'Driver Operator Support',
                  'Open dispatch support hub',
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
                    // The AuthWrapper in main.dart will reactively handle the screen swap safely.
                    await FirebaseAuth.instance.signOut();
                  },
                  icon: const Icon(
                    Icons.power_settings_new,
                    color: Colors.redAccent,
                    size: 18,
                  ),
                  label: const Text(
                    'Go Offline & Sign Out',
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

  Future<void> _showDriverQuickAccountSheet(BuildContext ctx) async {
    await _showProfileSheet();
  }

  Future<void> _determineDriverGPSLocation() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.high),
      );

      if (!mounted) return;

      setState(() {
        _driverCurrentLocation = LatLng(position.latitude, position.longitude);
        _isOnline = true;
      });

      _rebuildMapElements();
      _mapController?.animateCamera(
        CameraUpdate.newLatLng(_driverCurrentLocation),
      );
    } catch (e) {
      debugPrint('Failed to determine driver GPS location: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to fetch GPS location right now.'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  Widget _buildDriverTaximeterDock() {
    if (!_isTripActive && _driverWaypointIndex == 0 && !_isSearchingForRides) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.92),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'DRIVER EARNINGS',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'KSh ${_driverLiveEarningsKsh.toStringAsFixed(0)}',
                style: const TextStyle(
                  color: Colors.lightGreenAccent,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          Container(height: 24, width: 1, color: Colors.white24),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'TOTAL FARE',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'KSh ${_passengerLiveFareKsh.toStringAsFixed(0)}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDriverWorkflowControls() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
            topLeft: Radius.circular(24), topRight: Radius.circular(24)),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10)],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // =========================================================================
          // ✅ NEW SYSTEM PIECE: OFFLINE LOCKOUT STATUS NOTICE CARD
          // =========================================================================
          if (!_isOnline) ...[
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 30),
                child: Column(
                  children: [
                    Icon(Icons.wifi_off_rounded,
                        size: 44, color: Colors.grey.shade400),
                    const SizedBox(height: 12),
                    const Text("You are currently Offline",
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: Colors.black87)),
                    const SizedBox(height: 6),
                    const Text(
                        "To see available ride requests in Nakuru and start earning money, please go to your Profile / Account tab and switch your status to Available.",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 12, color: Colors.black54, height: 1.4)),
                  ],
                ),
              ),
            ),
          ],

          // PHASE 1: SEARCHING ANIMATION (Only works if online)
          if (_isOnline && _isSearchingForRides) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.black)),
                SizedBox(width: 12),
                Expanded(
                    child: Text("Scanning Nakuru for match alerts...",
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 13))),
              ],
            ),
            const SizedBox(height: 4),
          ],

          // PHASE 2: MULTI-REQUEST MARKETPLACE LIST FEED (Only works if online)
          if (_isOnline &&
              _availableRequests.isNotEmpty &&
              !_isTripActive &&
              !_isAwaitingPayment &&
              !_paymentReceived) ...[
            Text("AVAILABLE RIDES NEARBY (${_availableRequests.length})",
                style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 11,
                    color: Colors.black54,
                    letterSpacing: 1)),
            const SizedBox(height: 10),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(
                  children: _availableRequests.map((request) {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.black12)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(request.riderName,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14)),
                              Text(
                                  "Est: KSh ${request.estimatedFare.toStringAsFixed(0)}",
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                      color: Colors.green,
                                      fontSize: 13)),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text("From: ${request.pickupName}",
                              style: const TextStyle(
                                  fontSize: 11, color: Colors.black54),
                              overflow: TextOverflow.ellipsis),
                          Text("To: ${request.destinationName}",
                              style: const TextStyle(
                                  fontSize: 11, color: Colors.black54),
                              overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 8),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.black,
                                foregroundColor: Colors.white,
                                minimumSize: const Size.fromHeight(36)),
                            onPressed: () =>
                                _startLocalDriverTripSimulation(request),
                            child: const Text("ACCEPT JOB",
                                style: TextStyle(
                                    fontSize: 12, fontWeight: FontWeight.bold)),
                          )
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ],

          // PHASE 3: ACTIVE TRIP HUD PROGRESS
          if (_isTripActive && _activeRequest != null) ...[
            Text("CURRENT TRIP: ${_activeRequest!.riderName}",
                style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                    color: Colors.blue)),
            const SizedBox(height: 6),
            Row(
              children: [
                const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.blue)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    "En route to ${_activeRequest!.destinationName}... Progress: ${_driverTraveledDistanceKm.toStringAsFixed(1)} KM",
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ),
              ],
            ),
          ],

          // PHASE 4: COLLECT PAYMENT GATEWAY CONTROL
          if (_isAwaitingPayment && !_isProcessingPaymentPush) ...[
            const Text("DESTINATION ARRIVED",
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                    color: Colors.redAccent)),
            const SizedBox(height: 4),
            Text(
                "Please request final trip remittance statement from ${_activeRequest?.riderName ?? 'Passenger'}.",
                style: const TextStyle(fontSize: 12, color: Colors.black54)),
            const SizedBox(height: 12),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(45)),
              onPressed: () => _triggerSimulatedRiderPayment(),
              child: Text(
                  "REQUEST PAYMENT (KSh ${_passengerLiveFareKsh.toStringAsFixed(0)})",
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],

          // SIMULATED TRANSACTION NETWORK PING LOCKER
          if (_isProcessingPaymentPush) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.green)),
                SizedBox(width: 14),
                Text("Awaiting Rider Wallet transaction auth...",
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: Colors.black87)),
              ],
            ),
            const SizedBox(height: 4),
          ],

          // PHASE 5: NOTIFICATION ALERTS DISPATCH & REBOOT SWEEP
          if (_paymentReceived) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                  color: Colors.lightGreen.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.green.shade400, width: 1.5)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: const [
                      Icon(Icons.sms, color: Colors.green, size: 20),
                      SizedBox(width: 8),
                      Text("IN-APP MESSAGE LOG",
                          style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 11,
                              color: Colors.green)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    "📩 Success! ${_activeRequest?.riderName ?? 'Passenger'} has paid KSh ${_passengerLiveFareKsh.toStringAsFixed(0)} via AeroRide Pay. Your balance earned (KSh ${_driverLiveEarningsKsh.toStringAsFixed(0)}) has been successfully added to your account ledger wallet.",
                    style: const TextStyle(
                        fontSize: 12,
                        height: 1.4,
                        color: Colors.black87,
                        fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(42)),
              onPressed: () {
                setState(() {
                  _paymentReceived = false;
                  _isOnline = true;
                });
                _autoTriggerIncomingRideSearch();
              },
              child: const Text("GO BACK ONLINE / REFRESH JOB MARKET",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            )
          ]
        ],
      ),
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
                onPressed: () => _showDriverQuickAccountSheet(context),
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
      activeRideDocId = selectedRide['id']?.toString();
      _currentDriverState = DriverRideState.navigatingToPickup;

      double distanceMeters = Geolocator.distanceBetween(
        _driverCurrentLocation.latitude,
        _driverCurrentLocation.longitude,
        selectedRide['pickupLatLng'].latitude,
        selectedRide['pickupLatLng'].longitude,
      );
      _etaMinutes = ((distanceMeters / 1000) * 2).round().clamp(2, 25);
    });

    final rideDocId = activeRideDocId;
    if (rideDocId != null && rideDocId.isNotEmpty) {
      unawaited(
        FirebaseFirestore.instance.collection('rides').doc(rideDocId).set({
          'id': rideDocId,
          'driverId': widget.user.uid,
          'driverName': widget.user.displayName ?? 'Driver',
          'status': 'accepted',
          'pickupGeo': GeoPoint(
            selectedRide['pickupLatLng'].latitude,
            selectedRide['pickupLatLng'].longitude,
          ),
          'dropoffGeo': GeoPoint(
            selectedRide['destinationLatLng'].latitude,
            selectedRide['destinationLatLng'].longitude,
          ),
          'currentVehicleLocation': GeoPoint(
            _driverCurrentLocation.latitude,
            _driverCurrentLocation.longitude,
          ),
          'finalFareCharged': selectedRide['estimatedFare'],
          'estimatedCost': selectedRide['estimatedFare'],
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true)),
      );
    }

    _rebuildMapElements();
    _zoomToFitPoints(_driverCurrentLocation, selectedRide['pickupLatLng']);
    _startNavigationSimulation(toPickup: true);
  }

  void _startNavigationSimulation({required bool toPickup}) {
    _simulationTimer?.cancel();
    _transitProgress = 0.0;
    final startingEtaMinutes = _etaMinutes <= 0 ? 5 : _etaMinutes;

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
          _etaMinutes = ((1.0 - _transitProgress) * startingEtaMinutes)
              .ceil()
              .clamp(0, startingEtaMinutes);
        }

        _rebuildMapElements();
        _mapController
            ?.animateCamera(CameraUpdate.newLatLng(_driverCurrentLocation));
      });
    });
  }

  void _startPassengerTransitTrip() {
    final selectedRequest = _activeRequest ??
        (_availableRequests.isNotEmpty ? _availableRequests.first : null);
    if (selectedRequest == null) return;

    unawaited(_startLocalDriverTripSimulation(selectedRequest));
  }

  Future<void> _startLocalDriverTripSimulation(
      MockRideRequest selectedRequest) async {
    setState(() {
      _activeRequest = selectedRequest;
      _activeRideData = {
        'id': selectedRequest.id,
        'riderName': selectedRequest.riderName,
        'pickupName': selectedRequest.pickupName,
        'destinationName': selectedRequest.destinationName,
        'pickupLatLng': selectedRequest.pickupCoords,
        'destinationLatLng': selectedRequest.destinationCoords,
      };
      _isTripActive = true;
      _hasIncomingRequest = false;
      _availableRequests.clear();
      activeRideDocId = selectedRequest.id;
      _driverWaypointIndex = 0;
      _driverTraveledDistanceKm = 0.0;
      _driverLiveEarningsKsh = 0.0;
      _passengerLiveFareKsh = 100.0;
    });

    final pickupLatLng = selectedRequest.pickupCoords;
    final destinationLatLng = selectedRequest.destinationCoords;

    try {
      const url = 'https://routes.googleapis.com/directions/v2:computeRoutes';

      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'X-Goog-Api-Key': 'AIzaSyANuwPwm1dRFvh_ySIIiW22-dWnUsMrp0k',
          'X-Goog-FieldMask':
              'routes.duration,routes.distanceMeters,routes.polyline.encodedPolyline',
        },
        body: jsonEncode({
          'origin': {
            'location': {
              'latLng': {
                'latitude': pickupLatLng.latitude,
                'longitude': pickupLatLng.longitude,
              }
            }
          },
          'destination': {
            'location': {
              'latLng': {
                'latitude': destinationLatLng.latitude,
                'longitude': destinationLatLng.longitude,
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
            'Driver phase routing aborted: No routes returned. Response: ${response.body}');
        return;
      }

      final route = routes[0] as Map<String, dynamic>;
      final polylineData = route['polyline'] as Map<String, dynamic>?;
      final encodedPolyline = polylineData?['encodedPolyline']?.toString();

      if (encodedPolyline == null || encodedPolyline.isEmpty) {
        debugPrint(
            'Driver phase routing aborted: No polyline points available.');
        return;
      }

      final decodedPoints = PolylinePoints.decodePolyline(encodedPolyline);
      final roadPoints = decodedPoints
          .map((point) => LatLng(point.latitude, point.longitude))
          .toList();

      double calculateDistance(LatLng p1, LatLng p2) {
        const p = 0.017453292519943295;
        final a = 0.5 -
            math.cos((p2.latitude - p1.latitude) * p) / 2 +
            math.cos(p1.latitude * p) *
                math.cos(p2.latitude * p) *
                (1 - math.cos((p2.longitude - p1.longitude) * p)) /
                2;
        return 12742 * math.asin(math.sqrt(a));
      }

      if (!mounted) return;

      setState(() {
        _driverActualRoadPoints = roadPoints;
        _currentDriverState = DriverRideState.passengerInTransit;
      });

      final durationString = route['duration'] as String?;
      if (durationString != null && durationString.endsWith('s')) {
        final seconds = num.tryParse(durationString.replaceAll('s', '')) ?? 0;
        if (seconds > 0 && mounted) {
          setState(() {
            _etaMinutes = (seconds / 60).ceil();
          });
        }
      }

      _driverSimulationTimer?.cancel();
      _driverSimulationTimer = Timer.periodic(
        const Duration(milliseconds: 400),
        (timer) {
          if (_driverWaypointIndex >= _driverActualRoadPoints.length) {
            timer.cancel();
            setState(() {
              _isTripActive = false;
              _isAwaitingPayment = true;
              _paymentReceived = false;
              _isProcessingPaymentPush = false;
            });
            return;
          }

          final currentPos = _driverActualRoadPoints[_driverWaypointIndex];

          setState(() {
            if (_driverWaypointIndex > 0) {
              final previousPos =
                  _driverActualRoadPoints[_driverWaypointIndex - 1];
              final segment = calculateDistance(previousPos, currentPos);
              // Ignore very small noisy movements
              if (segment >= kSegmentThresholdKm) {
                _driverTraveledDistanceKm += segment;
              }
            }

            // Compute fares using centralized helper (MVP constants)
            final fareResult =
                computeFareAndEarnings(_driverTraveledDistanceKm, 0.0);
            _passengerLiveFareKsh = fareResult.passengerFare;
            _driverLiveEarningsKsh = fareResult.driverEarnings;
            _driverWaypointIndex++;
          });

          _mapController?.animateCamera(
            CameraUpdate.newLatLng(
              _driverActualRoadPoints[_driverWaypointIndex - 1],
            ),
          );
        },
      );
    } catch (e) {
      debugPrint('Driver phase routing failed: $e');
    }
  }

  Future<void> _finalizeTripToCloudDatabase() async {
    setState(() {
      _isTripActive = false;
      _currentDriverState = DriverRideState.tripCompleted;
    });

    try {
      final rideDocId = activeRideDocId;
      if (rideDocId != null && rideDocId.isNotEmpty) {
        await FirebaseFirestore.instance.collection('rides').doc(rideDocId).set(
          {
            'driverId': widget.user.uid,
            'driverName': widget.user.displayName ?? 'AeroRide Partner',
            'status': 'completed',
            'distanceKm':
                double.parse(_driverTraveledDistanceKm.toStringAsFixed(2)),
            'finalFareCharged': _passengerLiveFareKsh.round(),
            'estimatedCost': _passengerLiveFareKsh.round(),
            'driverEarningsLog': _driverLiveEarningsKsh.round(),
            'driverEarnings': _driverLiveEarningsKsh.round(),
            'completedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      }

      debugPrint('Trip logged to cloud history ledger.');
    } catch (e) {
      debugPrint('Failed logging history record: $e');
    }
  }

  void _resetDriverDashboard() {
    setState(() {
      _currentDriverState = DriverRideState.searchingRequests;
      _activeRideData = null;
      activeRideDocId = null;
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

  Widget _buildRealtimeRideMapLayer() {
    if (activeRideDocId == null) {
      return const Center(
        child: Text('Waiting for incoming ride matching requests...'),
      );
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('rides')
          .doc(activeRideDocId)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || !(snapshot.data?.exists ?? false)) {
          return const Center(child: CircularProgressIndicator());
        }

        final rideData = snapshot.data!.data()!;
        final vehicleGeoPoint = rideData['currentVehicleLocation'] as GeoPoint?;

        final currentCarLatLng = vehicleGeoPoint != null
            ? LatLng(vehicleGeoPoint.latitude, vehicleGeoPoint.longitude)
            : _driverCurrentLocation;

        final Set<Marker> driverScreenMarkers = {
          Marker(
            markerId: const MarkerId('driver_self_marker'),
            position: currentCarLatLng,
            icon: BitmapDescriptor.defaultMarkerWithHue(
                BitmapDescriptor.hueYellow),
            infoWindow: const InfoWindow(title: 'My Vehicle Location'),
          ),
        };

        final pickupGeo =
            (rideData['pickupGeo'] ?? rideData['pickup']) as GeoPoint?;
        if (pickupGeo != null) {
          driverScreenMarkers.add(
            Marker(
              markerId: const MarkerId('pickup_target'),
              position: LatLng(pickupGeo.latitude, pickupGeo.longitude),
              icon: BitmapDescriptor.defaultMarkerWithHue(
                  BitmapDescriptor.hueAzure),
              infoWindow: const InfoWindow(title: 'Passenger Pickup'),
            ),
          );
        }

        final dropoffGeo =
            (rideData['dropoffGeo'] ?? rideData['dropoff']) as GeoPoint?;
        if (dropoffGeo != null) {
          driverScreenMarkers.add(
            Marker(
              markerId: const MarkerId('dropoff_target'),
              position: LatLng(dropoffGeo.latitude, dropoffGeo.longitude),
              icon: BitmapDescriptor.defaultMarkerWithHue(
                  BitmapDescriptor.hueRed),
              infoWindow: const InfoWindow(title: 'Destination'),
            ),
          );
        }

        return GoogleMap(
          initialCameraPosition:
              CameraPosition(target: currentCarLatLng, zoom: 14),
          onMapCreated: (controller) => _mapController = controller,
          markers: driverScreenMarkers,
          myLocationButtonEnabled: false,
          zoomControlsEnabled: true,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // 1. MARKER GENERATION GRID (Stays identical)
    Set<Marker> driverScreenMarkers = {};
    if (!_isTripActive && _driverWaypointIndex == 0 && _isOnline) {
      driverScreenMarkers.add(
        Marker(
          markerId: const MarkerId("driver_initial_car"),
          position: _mockDriverCurrentLocation,
          icon:
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueYellow),
          infoWindow: const InfoWindow(title: "My Vehicle (Online)"),
        ),
      );
    } else if (_isTripActive &&
        _activeRequest != null &&
        _driverActualRoadPoints.isNotEmpty) {
      if (_driverWaypointIndex < _driverActualRoadPoints.length) {
        driverScreenMarkers.addAll([
          Marker(
            markerId: const MarkerId("moving_driver_car"),
            position: _driverActualRoadPoints[_driverWaypointIndex],
            icon: BitmapDescriptor.defaultMarkerWithHue(
                BitmapDescriptor.hueYellow),
          ),
          Marker(
            markerId: const MarkerId("passenger_pickup_node"),
            position: _activeRequest!.pickupCoords,
            icon: BitmapDescriptor.defaultMarkerWithHue(
                BitmapDescriptor.hueAzure),
          ),
          Marker(
            markerId: const MarkerId("passenger_dropoff_node"),
            position: _activeRequest!.destinationCoords,
            icon:
                BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          ),
        ]);
      }
    }

    // 2. RENDERING THE CHOSEN TAB CONTROLLER
    return Scaffold(
      backgroundColor: Colors.white,

      // THE CORE BODY CONTAINER
      body: IndexedStack(
        index: _selectedTabIndex,
        children: [
          // ==========================================
          // TAB INDEX 0: THE WORKSPACE MAP DASHBOARD
          // ==========================================
          Column(
            children: [
              Expanded(
                flex: 5,
                child: Stack(
                  children: [
                    GoogleMap(
                      initialCameraPosition: CameraPosition(
                          target: _mockDriverCurrentLocation, zoom: 13.5),
                      onMapCreated: (GoogleMapController controller) =>
                          _mapController = controller,
                      markers: driverScreenMarkers,
                      polylines: _driverActualRoadPoints.isNotEmpty
                          ? {
                              Polyline(
                                polylineId: const PolylineId(
                                    "driver_local_road_polyline"),
                                points: _driverActualRoadPoints,
                                color: Colors.blueAccent,
                                width: 5,
                              )
                            }
                          : {},
                    ),
                  ],
                ),
              ),
              Expanded(
                flex: 5,
                child: Container(
                  color: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildDriverTaximeterDock(),
                        _buildDriverWorkflowControls(),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),

          // ==========================================
          // TAB INDEX 1: THE DEDICATED PROFILE ACCOUNT SHEET
          // ==========================================
          SafeArea(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("My Profile",
                      style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          color: Colors.black)),
                  const SizedBox(height: 20),

                  // THE WORKSPACE TOGGLE SWITCH CARD
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color:
                          _isOnline ? Colors.grey.shade100 : Colors.red.shade50,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                          color: _isOnline
                              ? Colors.transparent
                              : Colors.red.shade100),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 24,
                          backgroundColor: Colors.black87,
                          child: Text(
                            (widget.user.displayName ?? "A")
                                .substring(0, 1)
                                .toUpperCase(),
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                  widget.user.displayName ?? "AeroRide Partner",
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15)),
                              const SizedBox(height: 2),
                              Text(
                                  _isOnline
                                      ? "Duty Status: Available"
                                      : "Duty Status: Offline",
                                  style: TextStyle(
                                      fontSize: 11,
                                      color:
                                          _isOnline ? Colors.green : Colors.red,
                                      fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                        Switch.adaptive(
                          value: _isOnline,
                          activeColor: Colors.green,
                          onChanged: (bool value) {
                            setState(() {
                              _isOnline = value;
                              if (!_isOnline) {
                                _isSearchingForRides = false;
                                _availableRequests.clear();
                                _driverSimulationTimer?.cancel();
                              } else {
                                _autoTriggerIncomingRideSearch();
                              }
                            });
                          },
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),
                  const Text("VEHICLE & METRICS",
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.black45,
                          letterSpacing: 1)),
                  const SizedBox(height: 8),

// 1. Vehicle info remains informational (no tap needed)
                  _buildStaticAccountTile(Icons.local_taxi_rounded,
                      "Vehicle Information", "Toyota Fielder - KCU 123X"),

// 2. UPDATED: Detailed Financial Statements link -> goes to WalletView!
                  _buildStaticAccountTile(
                    Icons.analytics_rounded,
                    "Detailed Financial Statements",
                    "View history, processing fees, and earnings logs",
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => WalletView(
                            currentBalance: _walletBalanceKsh,
                            isDriver: true,
                          ),
                        ),
                      );
                    },
                  ),

// 3. UPDATED: Help Desk channel link -> goes to SupportView!
                  _buildStaticAccountTile(
                    Icons.support_agent_rounded,
                    "AeroRide Partner Help Desk",
                    "Open active support channels or report an issue",
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              const SupportView(isDriver: true),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 30),

                  // SIGN OUT SYSTEM TRIGGER
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.shade600,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(46),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    icon: const Icon(Icons.logout_rounded, size: 18),
                    label: const Text("LOG OUT",
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.bold)),
                    onPressed: () async {
                      _driverSimulationTimer?.cancel();

                      // ✅ Explicit page route instead of named route string
                      Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute(
                            builder: (context) => const RoleSelectionScreen()),
                        (route) =>
                            false, // This wipes the history stack so they can't click "back" to get into the dashboard
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),

      // FOOTER PERSISTENT TABS NAVIGATION MENU BAR
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedTabIndex,
        onTap: (index) {
          setState(() {
            _selectedTabIndex = index;
          });
        },
        selectedItemColor: Colors.black,
        unselectedItemColor: Colors.grey,
        selectedLabelStyle:
            const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
        unselectedLabelStyle: const TextStyle(fontSize: 11),
        items: const [
          BottomNavigationBarItem(
              icon: Icon(Icons.map_rounded), label: "Map Dashboard"),
          BottomNavigationBarItem(
              icon: Icon(Icons.person_rounded), label: "Profile / Account"),
        ],
      ),
    );
  }

// QUICK HELPER COMPONENT FOR ACCOUNT DETAILS ROWS
  Widget _buildStaticAccountTile(IconData icon, String label, String value,
      {VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        child: Row(
          children: [
            Icon(icon, color: Colors.black54, size: 20),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style:
                          const TextStyle(fontSize: 11, color: Colors.black45)),
                  const SizedBox(height: 1),
                  Text(value,
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87)),
                ],
              ),
            ),
            if (onTap != null)
              const Icon(Icons.chevron_right_rounded,
                  color: Colors.black38, size: 18),
          ],
        ),
      ),
    );
  }
}
