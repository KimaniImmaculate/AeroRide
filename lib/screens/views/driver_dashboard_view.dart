import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
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
import 'package:aeroride/screens/views/gateway_portal.dart';
import '../../services/firestore_service.dart';
import '../../services/mock_route_service.dart';
import '../../models/ride_request_model.dart';
import '../../utils/location_extensions.dart';

class MockRideRequest {
  final String id;
  final String riderName;
  final DateTime? createdAt;
  final String pickupName;
  final String destinationName;
  final LatLng pickupCoords;
  final LatLng destinationCoords;
  final double estimatedFare;

  MockRideRequest({
    required this.id,
    required this.riderName,
    required this.createdAt,
    required this.pickupName,
    required this.destinationName,
    required this.pickupCoords,
    required this.destinationCoords,
    required this.estimatedFare,
  });
}

enum DriverTerminalState {
  offline,
  searching,
  accepted,
  arrived,
  inTransit,
  completing,
}

class DriverDashboardView extends StatefulWidget {
  final User? user;
  const DriverDashboardView({super.key, required this.user});

  @override
  State<DriverDashboardView> createState() => _DriverDashboardViewState();
}

class _DriverDashboardViewState extends State<DriverDashboardView> {
  static const double kSegmentThresholdKm = 0.0001;
  static const Color signatureTurquoise = Color(0xFF16A085);
  static const Color midnightSlate = Color(0xFF1A1C23);
  static const Color charcoalBg = Color(0xFF0F1013);

  GoogleMapController? _mapController;
  DriverTerminalState _currentState = DriverTerminalState.offline;

  int _selectedTabIndex = 0;
  bool _isProcessingPaymentPush = false;

  Timer? _driverSimulationTimer;
  List<LatLng> _driverActualRoadPoints = [];
  int _driverWaypointIndex = 0;

  double _driverTraveledDistanceKm = 0.0;
  double _driverLiveEarningsKsh = 0.0;
  double _passengerLiveFareKsh = 100.0;

  bool _paymentReceived = false;
  List<RideRequest> _availableRequests = [];
  RideRequest? _activeRequest;
  bool _isOnline = false;
  bool _isSearchingForRides = false;
  bool _hasIncomingRequest = false;
  bool _isTripActive = false;
  double _walletBalanceKsh =
      1450.00; // Starting mock balance for the driver wallet

  final FirestoreService _firestoreService = FirestoreService();
  StreamSubscription<List<RideRequest>>? _driverRequestsSub;

  LatLng _driverCurrentLocation = const LatLng(-0.2831, 36.0664);

  final LatLng _mockDriverCurrentLocation = const LatLng(-0.28496, 36.06795);
  final TextEditingController _pinController = TextEditingController();
  final LatLng _mockRiderPickupLocation = const LatLng(-0.28989, 36.05451);
  final LatLng _mockRiderDestinationLocation = const LatLng(-0.26562, 36.04853);

  Map<String, dynamic>? _activeRideData;
  String? activeRideDocId;
  Timer? _simulationTimer;
  double _transitProgress = 0.0;
  int _etaMinutes = 5;

  final Set<Polyline> _mapPolylines = {};
  final Set<Marker> _mapMarkers = {};

  @override
  void initState() {
    super.initState();
    _isOnline = false;
    _currentState = DriverTerminalState.offline;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(_determineDriverGPSLocation());
      }
    });
  }

  @override
  void dispose() {
    _driverSimulationTimer?.cancel();
    _pinController.dispose();
    _simulationTimer?.cancel();
    _mapController = null;
    super.dispose();
  }

  void _autoTriggerIncomingRideSearch() {
    _driverRequestsSub?.cancel();
    setState(() {
      _currentState = DriverTerminalState.searching;
      _isSearchingForRides = true;
      _availableRequests.clear();
      _activeRequest = null;

      // Clear the local trip simulation state before listening for live rides.
      _driverWaypointIndex = 0;
      _driverActualRoadPoints.clear();
    });

    _driverRequestsSub = _firestoreService
        .watchSimpleOpenRides(collectionName: 'ride_requests')
        .listen((rideList) {
      if (!mounted) return;
      setState(() {
        _availableRequests = rideList;
        _hasIncomingRequest = _availableRequests.isNotEmpty;
        _isSearchingForRides = false;
      });
    }, onError: (e) {
      debugPrint('Driver requests stream error: $e');
      if (!mounted) return;
      setState(() {
        _isSearchingForRides = false;
      });
    });
  }

  String _formatRequestTime(DateTime? time) {
    if (time == null) return 'Time unknown';
    final local = time.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    return '$day/$month ${hour}:$minute';
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
                        // Added null check for widget.user.displayName
                        (widget.user?.displayName?.isNotEmpty ?? false)
                            ? widget.user!.displayName![0].toUpperCase()
                            : 'D', // Fallback to 'D' if displayName is null or empty
                        style: GoogleFonts.urbanist(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.user?.displayName ??
                                'Driver', // Fallback for displayName
                            style: GoogleFonts.urbanist(
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            widget.user?.email ?? '',
                            style: TextStyle(
                                color:
                                    Colors.grey.shade600), // Fallback for email
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
                            DriverProfileScreen(user: widget.user!),
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
                            DriverProfileScreen(user: widget.user!),
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
                  label: Text(
                    'Go Offline & Sign Out',
                    style: GoogleFonts.urbanist(
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
        _isOnline = false; // Start offline by default for luxury flow
        _currentState = DriverTerminalState.offline;
      });

      _rebuildMapElements();
      _mapController?.animateCamera(
        CameraUpdate.newLatLng(_driverCurrentLocation),
      );

      _autoTriggerIncomingRideSearch();
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
    if (_currentState != DriverTerminalState.inTransit) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: midnightSlate,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.08), width: 1.5),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'DRIVER EARNINGS',
                style: GoogleFonts.urbanist(
                  color: Colors.grey[400],
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'KSh ${_driverLiveEarningsKsh.toStringAsFixed(0)}',
                style: GoogleFonts.urbanist(
                  color: signatureTurquoise,
                  fontSize: 36,
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
              Text(
                'TOTAL FARE',
                style: GoogleFonts.urbanist(
                  color: Colors.grey[400],
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'KSh ${_passengerLiveFareKsh.toStringAsFixed(0)}',
                style: GoogleFonts.urbanist(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
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
      decoration: BoxDecoration(
        color: midnightSlate,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(color: Colors.white.withOpacity(0.08), width: 1.5),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_currentState == DriverTerminalState.offline) ...[
            Text("PARTNER COCKPIT",
                style: GoogleFonts.urbanist(
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                    color: Colors.grey[400],
                    letterSpacing: 1.5)),
            const SizedBox(height: 20),
            // Clean Scorecard Grid
            GridView.count(
              shrinkWrap: true,
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.4,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _buildScorecardItem(
                    "Today's Earnings", "KSh 1,450", signatureTurquoise),
                _buildScorecardItem("Total Trips", "12 Jobs", Colors.white),
                _buildScorecardItem(
                    "Driver Rating", "4.98 ★", Colors.amberAccent),
                _buildScorecardItem("Reliability", "98%", Colors.blueAccent),
              ],
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: signatureTurquoise,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  elevation: 0,
                ),
                onPressed: () {
                  setState(() {
                    _isOnline = true;
                    _currentState = DriverTerminalState.searching;
                  });
                  _autoTriggerIncomingRideSearch();
                },
                child: Text("ENTER LIVE GRID",
                    style: GoogleFonts.urbanist(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                        letterSpacing: 1,
                        color: Colors.white)),
              ),
            ),
            const SizedBox(height: 10),
          ],
          if (_currentState == DriverTerminalState.searching) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 3, color: signatureTurquoise)),
                const SizedBox(width: 12),
                Expanded(
                    child: Text("SCANNING GRID TELEMETRY...",
                        style: GoogleFonts.urbanist(
                            fontWeight: FontWeight.w900,
                            fontSize: 12,
                            color: Colors.white70))),
              ],
            ),
            const SizedBox(height: 12),
          ],
          if (_currentState == DriverTerminalState.searching &&
              _availableRequests.isNotEmpty) ...[
            Text("AVAILABLE DISPATCHES (${_availableRequests.length})",
                style: GoogleFonts.urbanist(
                    fontWeight: FontWeight.w900,
                    fontSize: 10,
                    color: Colors.amberAccent,
                    letterSpacing: 1.2)),
            const SizedBox(height: 14),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 260),
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(
                  children: _availableRequests.map((request) {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.03),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                              color: Colors.white.withOpacity(0.05))),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                  request.riderName?.toUpperCase() ??
                                      "NEW RIDER",
                                  style: GoogleFonts.urbanist(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 14,
                                      color: Colors.white)),
                              Text(
                                  "KSh ${request.estimatedCost.toStringAsFixed(0)}",
                                  style: GoogleFonts.urbanist(
                                      fontWeight: FontWeight.w900,
                                      color: signatureTurquoise,
                                      fontSize: 15)),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              const Icon(Icons.radio_button_checked,
                                  size: 14, color: Colors.blueAccent),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(request.pickupAddress,
                                    style: GoogleFonts.urbanist(
                                        fontSize: 12, color: Colors.grey[300]),
                                    overflow: TextOverflow.ellipsis),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              const Icon(Icons.location_on,
                                  size: 14, color: Colors.redAccent),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(request.destinationAddress,
                                    style: GoogleFonts.urbanist(
                                        fontSize: 12, color: Colors.grey[300]),
                                    overflow: TextOverflow.ellipsis),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: signatureTurquoise,
                              foregroundColor: Colors.white,
                              minimumSize: const Size.fromHeight(40),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: () {
                              _acceptRideRequest(request.toMap());
                            },
                            child: Text("ACCEPT TRAJECTORY",
                                style: GoogleFonts.urbanist(
                                    fontSize: 13, fontWeight: FontWeight.w900)),
                          )
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ],
          if (_currentState == DriverTerminalState.arrived) ...[
            Text("PASSENGER PIN GATE",
                style: GoogleFonts.urbanist(
                    fontWeight: FontWeight.w900,
                    fontSize: 10,
                    color: Colors.amberAccent,
                    letterSpacing: 1.5)),
            const SizedBox(height: 12),
            TextField(
              controller: _pinController,
              keyboardType: TextInputType.number,
              maxLength: 4,
              style: GoogleFonts.urbanist(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                color: charcoalBg,
                letterSpacing: 20,
              ),
              textAlign: TextAlign.center,
              decoration: InputDecoration(
                hintText: "0000",
                counterText: "",
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.white, width: 2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => _startPassengerTransitTrip(),
              style: ElevatedButton.styleFrom(
                  backgroundColor: signatureTurquoise,
                  minimumSize: const Size.fromHeight(48)),
              child: Text("VALIDATE & START TRIP",
                  style: GoogleFonts.urbanist(
                      fontWeight: FontWeight.w900, color: Colors.white)),
            ),
          ],
          if (_currentState == DriverTerminalState.inTransit &&
              _activeRequest != null) ...[
            Text("CURRENT TRIP: ${_activeRequest!.riderName}",
                style: GoogleFonts.urbanist(
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                    color: signatureTurquoise)),
            const SizedBox(height: 6),
            Row(
              children: [
                const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: signatureTurquoise)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    "En route... Progress: ${_driverTraveledDistanceKm.toStringAsFixed(1)} KM",
                    style: GoogleFonts.urbanist(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: Colors.white70),
                  ),
                ),
              ],
            ),
          ],
          if (_currentState == DriverTerminalState.completing &&
              !_isProcessingPaymentPush) ...[
            Text("DESTINATION REACHED",
                style: GoogleFonts.urbanist(
                    fontWeight: FontWeight.w900,
                    fontSize: 11,
                    color: Colors.redAccent,
                    letterSpacing: 1.2)),
            const SizedBox(height: 8),
            Text(
                "Verify final fare on the passenger terminal and request remittance.",
                style: GoogleFonts.urbanist(
                    fontSize: 13, color: Colors.grey[400])),
            const SizedBox(height: 20),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: charcoalBg,
                  minimumSize: const Size.fromHeight(50),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12))),
              onPressed: () => _triggerSimulatedRiderPayment(),
              child: Text(
                  "COMPLETE & SETTLE (KSh ${_passengerLiveFareKsh.toStringAsFixed(0)})",
                  style: GoogleFonts.urbanist(
                      fontWeight: FontWeight.w900, letterSpacing: 0.5)),
            ),
          ],
          if (_isProcessingPaymentPush) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(width: 14),
                Text("Awaiting Rider Wallet transaction auth...",
                    style: GoogleFonts.urbanist(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: Colors.white70)),
              ],
            ),
            const SizedBox(height: 4),
          ],
          if (_paymentReceived) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.02),
                  borderRadius: BorderRadius.circular(20),
                  border:
                      Border.all(color: signatureTurquoise.withOpacity(0.2))),
              child: Column(
                children: [
                  const Icon(Icons.verified,
                      color: signatureTurquoise, size: 48),
                  const SizedBox(height: 14),
                  Text(
                    "SETTLEMENT SUCCESSFUL",
                    style: GoogleFonts.urbanist(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                        color: signatureTurquoise),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: signatureTurquoise,
                  minimumSize: const Size.fromHeight(50)),
              onPressed: () {
                _resetDriverDashboard();
              },
              child: Text("RESUME LIVE OPERATIONS",
                  style: GoogleFonts.urbanist(
                      fontWeight: FontWeight.w900, color: Colors.white)),
            )
          ]
        ],
      ),
    );
  }

  Widget _buildScorecardItem(String label, String value, Color accent) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label,
              style: GoogleFonts.urbanist(
                  fontSize: 11,
                  color: Colors.grey[400],
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(value,
              style: GoogleFonts.urbanist(
                  fontSize: 20, fontWeight: FontWeight.w900, color: accent)),
        ],
      ),
    );
  }

  Widget _buildTelemetryPanel() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      decoration: const BoxDecoration(
        color: charcoalBg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("GRID TELEMETRY OVERRIDES",
              style: GoogleFonts.urbanist(
                  color: Colors.white38,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5)),
          const SizedBox(height: 16),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildHazardChip("MAANDAMANO"),
                const SizedBox(width: 8),
                _buildHazardChip("FLASH FLOOD"),
                const SizedBox(width: 8),
                _buildHazardChip("SEVERE POTHOLES"),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildHazardChip(String label) {
    return ActionChip(
      backgroundColor: Colors.white.withOpacity(0.05),
      side: const BorderSide(color: Colors.white10),
      label: Text(label,
          style: GoogleFonts.urbanist(
              color: Colors.white70,
              fontSize: 10,
              fontWeight: FontWeight.w800)),
      onPressed: () => _reportHazard(label),
    );
  }

  Future<void> _reportHazard(String type) async {
    await FirebaseFirestore.instance.collection('live_hazards').add({
      'type': type,
      'reporterId': widget.user?.uid ?? 'anonymous_driver', // Fallback for uid
      'timestamp': FieldValue.serverTimestamp(),
      'location': GeoPoint(
          _driverCurrentLocation.latitude, _driverCurrentLocation.longitude),
    });
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text("GRID ALERT: $type reported")));
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
        style: GoogleFonts.urbanist(fontWeight: FontWeight.w800, fontSize: 14),
      ),
      subtitle: Text(
        subtitle,
        style: GoogleFonts.urbanist(fontSize: 12, color: Colors.grey[600]),
      ),
      trailing:
          const Icon(Icons.arrow_forward_ios, size: 12, color: Colors.black26),
    );
  }

  Widget _buildDriverProfileHeader() {
    final String uid = widget.user?.uid ?? "";
    return StreamBuilder<DocumentSnapshot>(
      stream:
          FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data() as Map<String, dynamic>?;
        final String name = data?['name'] ?? data?['fullName'] ?? "Driver";
        final String email = data?['email'] ?? "partner@aeroride.com";

        // Initials logic
        final initials = name
            .trim()
            .split(' ')
            .map((e) => e.isNotEmpty ? e[0] : '')
            .take(2)
            .join()
            .toUpperCase();

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
          child: GestureDetector(
            onTap: () => _showDriverQuickAccountSheet(context),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: midnightSlate,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white10),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: signatureTurquoise,
                    child: Text(initials,
                        style: GoogleFonts.urbanist(
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            fontSize: 14)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name,
                            style: GoogleFonts.urbanist(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 14)),
                        Text(email,
                            style: GoogleFonts.urbanist(
                                color: Colors.white38, fontSize: 11)),
                      ],
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _currentState == DriverTerminalState.offline
                          ? Colors.red.withOpacity(0.1)
                          : Colors.green.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.circle,
                            size: 8,
                            color: _currentState == DriverTerminalState.offline
                                ? Colors.red
                                : Colors.green),
                        const SizedBox(width: 6),
                        Text(
                          _currentState == DriverTerminalState.offline
                              ? "OFFLINE"
                              : "ONLINE",
                          style: GoogleFonts.urbanist(
                            color: _currentState == DriverTerminalState.offline
                                ? Colors.red
                                : Colors.green,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _acceptRideRequest(Map<String, dynamic> selectedRide) async {
    if (_isTripActive) {
      debugPrint('Accept ignored: trip already active.');
      return;
    }

    final pickupLatLng = selectedRide['pickupLatLng'] as LatLng? ??
        selectedRide['pickupCoords'] as LatLng?;
    final destinationLatLng = selectedRide['destinationLatLng'] as LatLng? ??
        selectedRide['destinationCoords'] as LatLng?;
    if (pickupLatLng == null || destinationLatLng == null) {
      debugPrint(
          'Accept ride aborted: missing pickup/destination coordinates.');
      return;
    }

    setState(() {
      _activeRideData = selectedRide;
      activeRideDocId = selectedRide['id']?.toString();
      _currentState = DriverTerminalState.accepted;

      double distanceMeters = Geolocator.distanceBetween(
        _driverCurrentLocation.latitude,
        _driverCurrentLocation.longitude,
        pickupLatLng.latitude,
        pickupLatLng.longitude,
      );
      _etaMinutes = ((distanceMeters / 1000) * 2).round().clamp(2, 25);
    });

    _rebuildMapElements();
    _zoomToFitPoints(_driverCurrentLocation, pickupLatLng);

    // Also start the local trip simulation (route fetch + road points + marker
    // movement). Construct a lightweight MockRideRequest and delegate to the
    // existing simulation path so the "accept" action always results in the
    // driver moving to pickup then continuing to dropoff.
    try {
      final mock = MockRideRequest(
        id: selectedRide['id']?.toString() ?? activeRideDocId ?? '',
        riderName: selectedRide['riderName']?.toString() ??
            (widget.user?.displayName ?? 'Passenger'),
        createdAt: selectedRide['createdAt'] is DateTime
            ? selectedRide['createdAt']
                as DateTime? // Added null check for displayName
            : (selectedRide['createdAt'] is Timestamp
                ? (selectedRide['createdAt'] as Timestamp).toDate()
                : null),
        pickupName: selectedRide['pickupName']?.toString() ?? '',
        destinationName: selectedRide['destinationName']?.toString() ?? '',
        pickupCoords: pickupLatLng,
        destinationCoords: destinationLatLng,
        estimatedFare: (selectedRide['estimatedFare'] is num)
            ? (selectedRide['estimatedFare'] as num).toDouble()
            : 0.0,
      );

      unawaited(_startLocalDriverTripSimulation(mock));
    } catch (e) {
      debugPrint('Failed to start local trip simulation after accept: $e');
    }
  }

  void _startDriverRoadSimulationIfReady() {
    // Start the periodic simulation that walks the decoded route points and
    // updates location, progress, fare and earnings. Only start when we have
    // route points and we are at the pickup stage (arrivedAtPickup) or already
    // in passengerInTransit.
    if (_driverSimulationTimer != null) return;
    if (_driverActualRoadPoints.isEmpty) return;
    if (!mounted) return;
    if (_currentState != DriverTerminalState.arrived &&
        _currentState != DriverTerminalState.inTransit) return;

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

    setState(() {
      _currentState = DriverTerminalState.inTransit;
      // Ensure index starts at zero if not set
      _driverWaypointIndex =
          _driverWaypointIndex.clamp(0, _driverActualRoadPoints.length);
    });

    _driverSimulationTimer?.cancel();
    _driverSimulationTimer = null;
    _driverSimulationTimer = Timer.periodic(
      const Duration(milliseconds: 400),
      (timer) {
        if (!mounted) {
          timer.cancel();
          _driverSimulationTimer = null;
          return;
        }

        if (_driverWaypointIndex >= _driverActualRoadPoints.length) {
          timer.cancel();
          setState(() {
            _isTripActive = false;
            _currentState = DriverTerminalState.completing;
            _paymentReceived = false;
          });
          _driverSimulationTimer = null;
          return;
        }

        final currentPos = _driverActualRoadPoints[_driverWaypointIndex];
        final previousPos = _driverWaypointIndex > 0
            ? _driverActualRoadPoints[_driverWaypointIndex - 1]
            : _driverCurrentLocation;
        final segmentMeters = Geolocator.distanceBetween(
          previousPos.latitude,
          previousPos.longitude,
          currentPos.latitude,
          currentPos.longitude,
        );
        final segmentKm = segmentMeters / 1000.0;

        setState(() {
          // move the live vehicle marker
          _driverCurrentLocation = currentPos;

          // accumulate trip distance, then update fares and earnings using the
          // pricing calculator so fare rises as the journey progresses.
          _driverTraveledDistanceKm += segmentKm;
          final fareResult =
              computeFareAndEarnings(_driverTraveledDistanceKm, 0.0);
          _passengerLiveFareKsh = fareResult.passengerFare;
          _driverLiveEarningsKsh = fareResult.driverEarnings;

          _driverWaypointIndex++;
        });

        // Refresh marker collection so the map receives the new vehicle point.
        _rebuildMapElements();

        _mapController?.animateCamera(
          CameraUpdate.newLatLng(
            _driverActualRoadPoints[(_driverWaypointIndex - 1)
                .clamp(0, _driverActualRoadPoints.length - 1)],
          ),
        );
      },
    );
  }

  void _startPassengerTransitTrip() {
    final selectedRequest = _activeRequest ??
        (_availableRequests.isNotEmpty ? _availableRequests.first : null);
    if (selectedRequest == null) return;

    // Convert RideRequest to MockRideRequest for the simulation engine
    final mock = MockRideRequest(
      id: selectedRequest.id ?? '',
      riderName: selectedRequest.riderName ?? 'Passenger',
      createdAt: selectedRequest.createdAt,
      pickupName: selectedRequest.pickupAddress,
      destinationName: selectedRequest.destinationAddress,
      pickupCoords: selectedRequest.pickupLocation.toLatLng(),
      destinationCoords: selectedRequest.destinationLocation.toLatLng(),
      estimatedFare: selectedRequest.estimatedCost,
    );

    unawaited(_startLocalDriverTripSimulation(mock));
  }

  Future<void> _startLocalDriverTripSimulation(
      MockRideRequest selectedRequest) async {
    _driverSimulationTimer?.cancel();
    _simulationTimer?.cancel();

    setState(() {
      _activeRequest = RideRequest.fromMap(
          _activeRideData!, _activeRideData!['id'] ?? 'sim_ride');
      _activeRideData = {
        'id': selectedRequest.id,
        'riderName': selectedRequest.riderName,
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
      _paymentReceived = false;
      _isProcessingPaymentPush = false;
    });

    final pickupLatLng = selectedRequest.pickupCoords;
    final pickupRoute = await _fetchRoutePoints(
      _driverCurrentLocation,
      pickupLatLng,
    );

    if (!mounted) return;

    setState(() {
      _driverActualRoadPoints = pickupRoute.isNotEmpty
          ? pickupRoute
          : <LatLng>[_driverCurrentLocation, pickupLatLng];
      _driverWaypointIndex = 0;
      _currentState = DriverTerminalState.accepted;
    });

    _rebuildMapElements();
    _zoomToFitPoints(_driverCurrentLocation, pickupLatLng);
    _startNavigationSimulation(toPickup: true);
  }

  Future<List<LatLng>> _fetchRoutePoints(
    LatLng origin,
    LatLng destination,
  ) async {
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
        return MockRouteService.buildRoutePoints(origin, destination,
            steps: 18);
      }

      final route = routes[0] as Map<String, dynamic>;
      final polylineData = route['polyline'] as Map<String, dynamic>?;
      final encodedPolyline = polylineData?['encodedPolyline']?.toString();
      if (encodedPolyline == null || encodedPolyline.isEmpty) {
        return MockRouteService.buildRoutePoints(origin, destination,
            steps: 18);
      }

      final decodedPoints = PolylinePoints.decodePolyline(encodedPolyline);
      final roadPoints = decodedPoints
          .map((point) => LatLng(point.latitude, point.longitude))
          .toList();

      final durationString = route['duration'] as String?;
      if (durationString != null && durationString.endsWith('s')) {
        final seconds = num.tryParse(durationString.replaceAll('s', '')) ?? 0;
        if (seconds > 0 && mounted) {
          setState(() {
            _etaMinutes = (seconds / 60).ceil();
          });
        }
      }

      return roadPoints;
    } catch (e) {
      debugPrint('Route fetch failed: $e');
      return MockRouteService.buildRoutePoints(origin, destination, steps: 18);
    }
  }

  void _startNavigationSimulation({required bool toPickup}) {
    _simulationTimer?.cancel();
    _simulationTimer = null;
    _driverSimulationTimer?.cancel();
    _driverSimulationTimer = null;

    final routePoints = List<LatLng>.from(_driverActualRoadPoints);
    if (routePoints.isEmpty) return;

    setState(() {
      _driverWaypointIndex = 0;
      _currentState = toPickup
          ? DriverTerminalState.accepted
          : DriverTerminalState.inTransit;
    });

    _simulationTimer =
        Timer.periodic(const Duration(milliseconds: 150), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }

      if (_driverWaypointIndex >= routePoints.length) {
        timer.cancel();
        _simulationTimer = null;
        if (toPickup) {
          setState(() {
            _currentState = DriverTerminalState.arrived;
            _etaMinutes = 0;
            _driverTraveledDistanceKm = 0.0;
            _passengerLiveFareKsh = 100.0;
            _driverLiveEarningsKsh = 0.0;
          });

          final destinationLatLng = _activeRideData?['destinationLatLng'];
          if (destinationLatLng is LatLng) {
            final dropoffRoute = await _fetchRoutePoints(
              _driverCurrentLocation,
              destinationLatLng,
            );

            if (!mounted) return;

            setState(() {
              _driverActualRoadPoints = dropoffRoute.isNotEmpty
                  ? dropoffRoute
                  : <LatLng>[_driverCurrentLocation, destinationLatLng];
              _driverWaypointIndex = 0;
              _currentState = DriverTerminalState.inTransit;
            });

            _rebuildMapElements();
            _startDriverRoadSimulationIfReady();
          }
        } else {
          setState(() {
            _isTripActive = false;
            _currentState = DriverTerminalState.completing;
            _paymentReceived = false;
          });
          _simulationTimer = null;
        }
        return;
      }

      final currentPos = routePoints[_driverWaypointIndex];

      setState(() {
        _driverCurrentLocation = currentPos;

        _driverWaypointIndex++;
      });

      _rebuildMapElements();
      _mapController?.animateCamera(
        CameraUpdate.newLatLng(_driverCurrentLocation),
      );
    });
  }

  Future<void> _finalizeTripToCloudDatabase() async {
    setState(() {
      _isTripActive = false;
      _currentState = DriverTerminalState.completing;
    });
  }

  void _resetDriverDashboard() {
    setState(() {
      _currentState = DriverTerminalState.searching;
      _activeRideData = null;
      activeRideDocId = null;
      _isOnline = true;
      _mapPolylines.clear();
      _mapMarkers.clear();
    });
    _determineDriverGPSLocation();
    if (_isOnline) {
      _autoTriggerIncomingRideSearch();
    }
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

      List<LatLng> points;
      if ((_currentState == DriverTerminalState.accepted ||
              _currentState == DriverTerminalState.inTransit) &&
          _driverActualRoadPoints.isNotEmpty) {
        points = _driverActualRoadPoints;
      } else {
        points = [pickup, destination];
      }

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
    if (activeRideDocId == null || _activeRideData == null) {
      return const Center(
        child: Text('Waiting for incoming ride matching requests...'),
      );
    }

    final rideData = _activeRideData!;
    final pickupLatLng = rideData['pickupLatLng'] as LatLng?;
    final destinationLatLng = rideData['destinationLatLng'] as LatLng?;
    final vehicleGeoPoint = rideData['currentVehicleLocation'] as GeoPoint?;

    final currentCarLatLng = vehicleGeoPoint != null
        ? LatLng(vehicleGeoPoint.latitude, vehicleGeoPoint.longitude)
        : (_isTripActive &&
                _driverActualRoadPoints.isNotEmpty &&
                _driverWaypointIndex < _driverActualRoadPoints.length
            ? _driverActualRoadPoints[_driverWaypointIndex]
            : _driverCurrentLocation);

    final Set<Marker> driverScreenMarkers = {
      Marker(
        markerId: const MarkerId('driver_self_marker'),
        position: currentCarLatLng,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueYellow),
        infoWindow: const InfoWindow(title: 'My Vehicle Location'),
      ),
    };

    if (pickupLatLng != null) {
      driverScreenMarkers.add(
        Marker(
          markerId: const MarkerId('pickup_target'),
          position: pickupLatLng,
          icon:
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          infoWindow: const InfoWindow(title: 'Passenger Pickup'),
        ),
      );
    }

    if (destinationLatLng != null) {
      driverScreenMarkers.add(
        Marker(
          markerId: const MarkerId('dropoff_target'),
          position: destinationLatLng,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          infoWindow: const InfoWindow(title: 'Destination'),
        ),
      );
    }

    return GoogleMap(
      initialCameraPosition: CameraPosition(target: currentCarLatLng, zoom: 14),
      onMapCreated: (controller) => _mapController = controller,
      markers: driverScreenMarkers,
      myLocationButtonEnabled: false,
      zoomControlsEnabled: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    // 1. MARKER GENERATION GRID (Stays identical)
    Set<Marker> driverScreenMarkers = {};
    if (_currentState == DriverTerminalState.searching ||
        _currentState == DriverTerminalState.offline) {
      driverScreenMarkers.add(
        Marker(
          markerId: const MarkerId("driver_initial_car"),
          position: _mockDriverCurrentLocation,
          icon:
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueYellow),
          infoWindow: const InfoWindow(title: "My Vehicle (Online)"),
        ),
      );
    } else if (_activeRequest != null) {
      driverScreenMarkers.addAll([
        Marker(
          markerId: const MarkerId("moving_driver_car"),
          position: _driverCurrentLocation,
          icon:
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueYellow),
        ),
        Marker(
          markerId: const MarkerId("passenger_pickup_node"),
          position: _activeRequest!.pickupLocation.toLatLng(),
          icon:
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        ),
        Marker(
          markerId: const MarkerId("passenger_dropoff_node"),
          position: _activeRequest!.destinationLocation.toLatLng(),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        ),
      ]);
    }

    // 2. RENDERING THE CHOSEN TAB CONTROLLER
    return Scaffold(
      backgroundColor: charcoalBg,

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
                      markers: _mapMarkers.isNotEmpty
                          ? _mapMarkers
                          : driverScreenMarkers,
                      polylines: _mapPolylines.isNotEmpty
                          ? _mapPolylines
                          : (_driverActualRoadPoints.isNotEmpty
                              ? {
                                  Polyline(
                                    polylineId: const PolylineId(
                                        "driver_local_road_polyline"),
                                    points: _driverActualRoadPoints,
                                    color: Colors.blueAccent,
                                    width: 5,
                                  )
                                }
                              : {}),
                    ),
                  ],
                ),
              ),
              Expanded(
                flex: 5,
                child: Container(
                  color: Colors.transparent,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildDriverTaximeterDock(),
                        _buildDriverWorkflowControls(),
                        if (_isOnline) _buildTelemetryPanel(),
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
                  Text("My Profile",
                      style: GoogleFonts.urbanist(
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          color: Colors.white)),
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
                            (widget.user?.displayName ?? "A")
                                .substring(0, 1)
                                .toUpperCase(),
                            style: GoogleFonts.urbanist(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 16),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Added null check for displayName
                              Text(
                                  widget.user?.displayName ??
                                      "AeroRide Partner",
                                  style: GoogleFonts.urbanist(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 15,
                                      color: Colors.white)),
                              const SizedBox(height: 2),
                              Text(
                                  _isOnline
                                      ? "Duty Status: Available"
                                      : "Duty Status: Offline",
                                  style: GoogleFonts.urbanist(
                                      fontSize: 11,
                                      color:
                                          _isOnline ? Colors.green : Colors.red,
                                      fontWeight: FontWeight.w900)),
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
                                // Go offline: cancel live subscription and clear market
                                _isSearchingForRides = false;
                                _availableRequests.clear();
                                _driverSimulationTimer?.cancel();
                                _driverRequestsSub?.cancel();
                                _driverRequestsSub = null;
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
                  Text("VEHICLE & METRICS",
                      style: GoogleFonts.urbanist(
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          color: Colors.white38,
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
                    label: Text("LOG OUT",
                        style: GoogleFonts.urbanist(
                            fontSize: 13, fontWeight: FontWeight.w900)),
                    onPressed: () async {
                      _driverSimulationTimer?.cancel();

                      // ✅ Explicit page route instead of named route string
                      Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute(
                            builder: (context) =>
                                const AeroRideGatewayPortal()),
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
        unselectedItemColor: Colors.white30,
        backgroundColor: midnightSlate,
        selectedLabelStyle:
            GoogleFonts.urbanist(fontWeight: FontWeight.w900, fontSize: 11),
        unselectedLabelStyle: GoogleFonts.urbanist(fontSize: 11),
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
                      style: GoogleFonts.urbanist(
                          fontSize: 11, color: Colors.white38)),
                  const SizedBox(height: 1),
                  Text(value,
                      style: GoogleFonts.urbanist(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Colors.white)),
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
