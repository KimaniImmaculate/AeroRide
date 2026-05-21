import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../controllers/ride_controller.dart';
import '../../models/ride_request_model.dart';
import '../../services/drivers_service.dart';
import '../../services/firestore_service.dart';
import '../../theme/aeroride_theme.dart';
import '../../widgets/aeroride_components.dart';

class DriverHomeScreen extends StatefulWidget {
  final User user;

  const DriverHomeScreen({super.key, required this.user});

  @override
  State<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends State<DriverHomeScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  final DriversService _driversService = DriversService();
  late final RideController _journeyController;

  Timer? _arrivalWatcher;
  String? _trackedRideId;
  int _panelIndex = 0;
  bool _isOnline = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _journeyController = RideController();
  }

  @override
  void dispose() {
    _arrivalWatcher?.cancel();
    _journeyController.dispose();
    super.dispose();
  }

  Future<void> _toggleOnline() async {
    if (_busy) return;

    setState(() => _busy = true);
    try {
      if (_isOnline) {
        await _driversService.stopLocationUpdates(widget.user.uid);
        _arrivalWatcher?.cancel();
        if (!mounted) return;
        setState(() {
          _isOnline = false;
          if (_trackedRideId == null) {
            _panelIndex = 0;
          }
        });
      } else {
        await _driversService.startLocationUpdates(widget.user.uid);
        if (!mounted) return;
        setState(() {
          _isOnline = true;
          _panelIndex = 1;
        });
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to update driver status: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _acceptRide(RideRequest ride) async {
    if (_busy || ride.id == null) return;

    setState(() => _busy = true);
    try {
      await _firestoreService.acceptRide(
        rideId: ride.id!,
        driverId: widget.user.uid,
      );
      if (!mounted) return;
      _attachActiveRide(ride);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not accept ride: $error')));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void _attachActiveRide(RideRequest ride) {
    if (ride.id == null) return;

    if (_trackedRideId != ride.id) {
      _trackedRideId = ride.id;
      _journeyController.listenToLiveRide(ride.id!);
      _startArrivalWatcher(ride.id!);
    }

    if (mounted) {
      setState(() => _panelIndex = ride.status == 'completed' ? 2 : 1);
    }
  }

  void _startArrivalWatcher(String rideId) {
    _arrivalWatcher?.cancel();
    _arrivalWatcher = Timer.periodic(const Duration(seconds: 6), (_) {
      _checkJourneyProgress(rideId);
    });
    _checkJourneyProgress(rideId);
  }

  Future<void> _checkJourneyProgress(String rideId) async {
    try {
      final rideSnapshot = await FirebaseFirestore.instance
          .collection('rides')
          .doc(rideId)
          .get();
      if (!rideSnapshot.exists || rideSnapshot.data() == null) {
        return;
      }

      final ride = RideRequest.fromMap(rideSnapshot.data()!, rideSnapshot.id);
      if (ride.driverId != widget.user.uid) {
        return;
      }

      if (ride.status == 'completed' || ride.status == 'cancelled') {
        _arrivalWatcher?.cancel();
        return;
      }

      final driverSnapshot = await FirebaseFirestore.instance
          .collection('drivers')
          .doc(widget.user.uid)
          .get();
      final driverLocation =
          driverSnapshot.data()?['current_location'] as GeoPoint?;
      if (driverLocation == null) {
        return;
      }

      final driverLat = driverLocation.latitude;
      final driverLng = driverLocation.longitude;

      if (ride.status == 'accepted') {
        final distanceToPickup = _distanceMeters(
          driverLat,
          driverLng,
          ride.pickupLocation.latitude,
          ride.pickupLocation.longitude,
        );

        if (distanceToPickup <= 250) {
          await _firestoreService.updateRideStatus(rideId, 'arrived');
          if (mounted) {
            setState(() => _panelIndex = 2);
          }
        }
        return;
      }

      if (ride.status == 'started') {
        final distanceToDestination = _distanceMeters(
          driverLat,
          driverLng,
          ride.destinationLocation.latitude,
          ride.destinationLocation.longitude,
        );

        if (distanceToDestination <= 250) {
          await _firestoreService.completeRideAndSettlePayment(
            rideId: rideId,
            riderId: ride.userId,
            driverId: widget.user.uid,
            fare: ride.estimatedCost,
          );
          _arrivalWatcher?.cancel();
          if (mounted) {
            setState(() => _panelIndex = 2);
          }
        }
      }
    } catch (_) {
      // Keep the watcher silent. The next tick will retry.
    }
  }

  double _distanceMeters(double lat1, double lng1, double lat2, double lng2) {
    const earthRadius = 6371000.0;
    final dLat = _degToRad(lat2 - lat1);
    final dLng = _degToRad(lng2 - lng1);
    final a =
        (sin(dLat / 2) * sin(dLat / 2)) +
        cos(_degToRad(lat1)) *
            cos(_degToRad(lat2)) *
            (sin(dLng / 2) * sin(dLng / 2));
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadius * c;
  }

  double _degToRad(double degrees) => degrees * (pi / 180);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  AeroRidePillButton(
                    label: _isOnline ? 'Online' : 'Offline',
                    selected: _isOnline,
                    onTap: _busy ? null : _toggleOnline,
                  ),
                  AeroRidePillButton(
                    label: 'Queue',
                    selected: _panelIndex == 0,
                    onTap: _isOnline
                        ? () => setState(() => _panelIndex = 0)
                        : null,
                  ),
                  AeroRidePillButton(
                    label: 'Journey',
                    selected: _panelIndex == 1,
                    onTap: _trackedRideId == null && _isOnline
                        ? () => setState(() => _panelIndex = 1)
                        : null,
                  ),
                  AeroRidePillButton(
                    label: 'Arrival',
                    selected: _panelIndex == 2,
                    onTap: _trackedRideId == null && _isOnline
                        ? () => setState(() => _panelIndex = 2)
                        : null,
                  ),
                ],
              ),
            ),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: !_isOnline
                    ? _DriverOfflinePanel(onToggleOnline: _toggleOnline)
                    : _panelIndex == 0
                    ? _DriverRequestPanel(
                        firestoreService: _firestoreService,
                        driverId: widget.user.uid,
                        acceptRide: _acceptRide,
                      )
                    : _panelIndex == 1
                    ? _DriverNavigationPanel(
                        firestoreService: _firestoreService,
                        journeyController: _journeyController,
                        driverId: widget.user.uid,
                        onRideDetected: _attachActiveRide,
                        onAdvanceRide: (rideId, nextStatus) async {
                          if (nextStatus == 'completed') {
                            final rideSnapshot = await FirebaseFirestore
                                .instance
                                .collection('rides')
                                .doc(rideId)
                                .get();
                            if (!rideSnapshot.exists ||
                                rideSnapshot.data() == null) {
                              return;
                            }

                            final ride = RideRequest.fromMap(
                              rideSnapshot.data()!,
                              rideSnapshot.id,
                            );
                            await _firestoreService
                                .completeRideAndSettlePayment(
                                  rideId: rideId,
                                  riderId: ride.userId,
                                  driverId: widget.user.uid,
                                  fare: ride.estimatedCost,
                                );
                          } else {
                            await _firestoreService.updateRideStatus(
                              rideId,
                              nextStatus,
                            );
                          }
                        },
                      )
                    : _DriverArrivalPanel(
                        firestoreService: _firestoreService,
                        journeyController: _journeyController,
                        driverId: widget.user.uid,
                        onRideDetected: _attachActiveRide,
                        onCompleteRide: (rideId) async {
                          await _firestoreService.updateRideStatus(
                            rideId,
                            'completed',
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DriverOfflinePanel extends StatelessWidget {
  final Future<void> Function() onToggleOnline;

  const _DriverOfflinePanel({required this.onToggleOnline});

  @override
  Widget build(BuildContext context) {
    final tokens = context.aeroTokens;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: AeroRidePanelCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.route_outlined,
                size: 72,
                color: tokens.primaryDarkBlue,
              ),
              const SizedBox(height: 16),
              Text(
                'You are offline',
                style: TextStyle(
                  color: tokens.primaryDarkBlue,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Go online to receive nearby ride requests and start live trip tracking.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: onToggleOnline,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: tokens.primaryDarkBlue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  child: const Text(
                    'Go Online',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DriverRequestPanel extends StatelessWidget {
  final FirestoreService firestoreService;
  final String driverId;
  final Future<void> Function(RideRequest ride) acceptRide;

  const _DriverRequestPanel({
    required this.firestoreService,
    required this.driverId,
    required this.acceptRide,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.aeroTokens;
    return StreamBuilder<List<RideRequest>>(
      stream: firestoreService.watchDriverRequests(driverId),
      builder: (context, snapshot) {
        final requests = snapshot.data ?? [];

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              _CountdownDial(seconds: 10),
              const SizedBox(height: 18),
              if (requests.isEmpty)
                AeroRidePanelCard(
                  child: Column(
                    children: [
                      Icon(
                        Icons.hourglass_empty_rounded,
                        color: tokens.primaryDarkBlue,
                        size: 42,
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'No incoming rides right now',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: tokens.primaryDarkBlue,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Stay online and AeroRide will push nearby requests here.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                )
              else
                ...requests.map(
                  (ride) => Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: AeroRidePanelCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              CircleAvatar(
                                radius: 24,
                                backgroundColor: tokens.softSurface,
                                child: Icon(
                                  Icons.person,
                                  color: tokens.primaryDarkBlue,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Ride request',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        color: tokens.primaryDarkBlue,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Rider waiting nearby',
                                      style: TextStyle(
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: AeroRideMetricCard(
                                  label: 'Fare',
                                  value:
                                      '\$${ride.estimatedCost.toStringAsFixed(2)}',
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: AeroRideMetricCard(
                                  label: 'Pickup',
                                  value: 'Live',
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: AeroRideMetricCard(
                                  label: 'Status',
                                  value: ride.status.toUpperCase(),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          AeroRideInfoRow(
                            label: 'Pickup Address',
                            value: ride.pickupAddress,
                          ),
                          AeroRideInfoRow(
                            label: 'Destination',
                            value: ride.destinationAddress,
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () async {
                                    if (ride.id == null) return;
                                    await firestoreService.updateRideStatus(
                                      ride.id!,
                                      'cancelled',
                                    );
                                  },
                                  style: OutlinedButton.styleFrom(
                                    side: BorderSide(color: tokens.mutedBorder),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(18),
                                    ),
                                    minimumSize: const Size.fromHeight(54),
                                  ),
                                  child: const Text(
                                    'Decline',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                flex: 2,
                                child: SizedBox(
                                  height: 54,
                                  child: ElevatedButton(
                                    onPressed: () => acceptRide(ride),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: tokens.successGreen,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(18),
                                      ),
                                    ),
                                    child: const Text(
                                      'Accept',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _DriverNavigationPanel extends StatelessWidget {
  final FirestoreService firestoreService;
  final RideController journeyController;
  final String driverId;
  final void Function(RideRequest ride) onRideDetected;
  final Future<void> Function(String rideId, String nextStatus) onAdvanceRide;

  const _DriverNavigationPanel({
    required this.firestoreService,
    required this.journeyController,
    required this.driverId,
    required this.onRideDetected,
    required this.onAdvanceRide,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.aeroTokens;
    return StreamBuilder<List<RideRequest>>(
      stream: firestoreService.watchActiveDriverRides(driverId),
      builder: (context, snapshot) {
        final activeRide = snapshot.data == null || snapshot.data!.isEmpty
            ? null
            : snapshot.data!.first;

        if (activeRide == null) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.route_outlined, size: 72, color: tokens.mutedBorder),
                const SizedBox(height: 16),
                Text(
                  'No active journey yet',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: tokens.primaryDarkBlue,
                  ),
                ),
              ],
            ),
          );
        }

        WidgetsBinding.instance.addPostFrameCallback((_) {
          onRideDetected(activeRide);
        });

        return ListenableBuilder(
          listenable: journeyController,
          builder: (context, _) {
            final rideStatus = journeyController.currentRideStatus
                .toUpperCase();
            final bannerLabel = rideStatus == 'ACCEPTED'
                ? 'Arrive at Pickup'
                : rideStatus == 'ARRIVED'
                ? 'Start Trip'
                : rideStatus == 'STARTED'
                ? 'Complete Trip'
                : 'Journey Complete';

            final nextStatus = rideStatus == 'ACCEPTED'
                ? 'arrived'
                : rideStatus == 'ARRIVED'
                ? 'started'
                : rideStatus == 'STARTED'
                ? 'completed'
                : null;

            return AeroRideMapShell(
              map: GoogleMap(
                initialCameraPosition: const CameraPosition(
                  target: LatLng(-1.286389, 36.817223),
                  zoom: 13.3,
                ),
                myLocationButtonEnabled: false,
                zoomControlsEnabled: false,
                compassEnabled: false,
                markers: journeyController.markers,
                polylines: journeyController.polylines,
                onMapCreated: (controller) {
                  journeyController.mapController = controller;
                },
              ),
              overlays: [
                Positioned(
                  top: 16,
                  left: 16,
                  child: AeroRideStatusPill(
                    label: 'Navigating',
                    color: tokens.primaryDarkBlue,
                  ),
                ),
                Positioned(
                  top: 16,
                  right: 16,
                  child: AeroRideStatusPill(
                    label: rideStatus,
                    color: tokens.warningOrange,
                  ),
                ),
                Positioned(
                  left: 16,
                  right: 16,
                  top: 70,
                  child: AeroRidePanelCard(
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                activeRide.pickupAddress,
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: tokens.primaryDarkBlue,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Fare \$${activeRide.estimatedCost.toStringAsFixed(2)}',
                                style: TextStyle(
                                  color: Colors.grey.shade600,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.navigation_rounded,
                          color: tokens.primaryDarkBlue,
                        ),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 0,
                  child: SafeArea(
                    top: false,
                    child: AeroRidePanelCard(
                      radius: 28,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: AeroRideMetricCard(
                                  label: 'Pickup',
                                  value: activeRide.pickupAddress,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: AeroRideMetricCard(
                                  label: 'Destination',
                                  value: activeRide.destinationAddress,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          AeroRideInfoRow(label: 'Driver', value: driverId),
                          const SizedBox(height: 6),
                          AeroRideTimeline(
                            steps: [
                              AeroRideTimelineStep(
                                title: 'Accepted',
                                subtitle: 'Driver assigned',
                                completed: true,
                              ),
                              AeroRideTimelineStep(
                                title: 'Arrived',
                                subtitle: 'At pickup point',
                                completed:
                                    rideStatus == 'ARRIVED' ||
                                    rideStatus == 'STARTED' ||
                                    rideStatus == 'COMPLETED',
                              ),
                              AeroRideTimelineStep(
                                title: 'In Transit',
                                subtitle: 'Heading to destination',
                                completed:
                                    rideStatus == 'STARTED' ||
                                    rideStatus == 'COMPLETED',
                              ),
                              AeroRideTimelineStep(
                                title: 'Completed',
                                subtitle: 'Trip finished',
                                completed: rideStatus == 'COMPLETED',
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            height: 56,
                            child: ElevatedButton(
                              onPressed:
                                  nextStatus == null || activeRide.id == null
                                  ? null
                                  : () => onAdvanceRide(
                                      activeRide.id!,
                                      nextStatus,
                                    ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: tokens.successGreen,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(18),
                                ),
                              ),
                              child: Text(
                                bannerLabel,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _DriverArrivalPanel extends StatelessWidget {
  final FirestoreService firestoreService;
  final RideController journeyController;
  final String driverId;
  final void Function(RideRequest ride) onRideDetected;
  final Future<void> Function(String rideId) onCompleteRide;

  const _DriverArrivalPanel({
    required this.firestoreService,
    required this.journeyController,
    required this.driverId,
    required this.onRideDetected,
    required this.onCompleteRide,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.aeroTokens;
    return StreamBuilder<List<RideRequest>>(
      stream: firestoreService.watchActiveDriverRides(driverId),
      builder: (context, snapshot) {
        final activeRide = snapshot.data == null || snapshot.data!.isEmpty
            ? null
            : snapshot.data!.first;

        if (activeRide == null) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.verified_outlined,
                  size: 72,
                  color: tokens.successGreen,
                ),
                const SizedBox(height: 16),
                Text(
                  'No completed trip yet',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: tokens.primaryDarkBlue,
                  ),
                ),
              ],
            ),
          );
        }

        WidgetsBinding.instance.addPostFrameCallback((_) {
          onRideDetected(activeRide);
        });

        return ListenableBuilder(
          listenable: journeyController,
          builder: (context, _) {
            return AeroRideMapShell(
              map: GoogleMap(
                initialCameraPosition: const CameraPosition(
                  target: LatLng(-1.286389, 36.817223),
                  zoom: 13.3,
                ),
                myLocationButtonEnabled: false,
                zoomControlsEnabled: false,
                compassEnabled: false,
                markers: journeyController.markers,
                polylines: journeyController.polylines,
                onMapCreated: (controller) {
                  journeyController.mapController = controller;
                },
              ),
              overlays: [
                Positioned(
                  top: 16,
                  left: 16,
                  child: AeroRideStatusPill(
                    label: activeRide.status.toUpperCase(),
                    color: tokens.successGreen,
                  ),
                ),
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 0,
                  child: SafeArea(
                    top: false,
                    child: AeroRidePanelCard(
                      radius: 28,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: AeroRideMetricCard(
                                  label: 'Distance',
                                  value: 'Live',
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: AeroRideMetricCard(
                                  label: 'ETA',
                                  value: 'Live',
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: AeroRideMetricCard(
                                  label: 'Fare',
                                  value:
                                      '\$${activeRide.estimatedCost.toStringAsFixed(2)}',
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          AeroRideTimeline(
                            steps: [
                              const AeroRideTimelineStep(
                                title: 'Accepted',
                                subtitle: 'Driver assigned',
                                completed: true,
                              ),
                              AeroRideTimelineStep(
                                title: 'Arrived',
                                subtitle: 'At pickup point',
                                completed:
                                    activeRide.status == 'arrived' ||
                                    activeRide.status == 'started' ||
                                    activeRide.status == 'completed',
                              ),
                              AeroRideTimelineStep(
                                title: 'In Transit',
                                subtitle: 'Heading to destination',
                                completed:
                                    activeRide.status == 'started' ||
                                    activeRide.status == 'completed',
                              ),
                              AeroRideTimelineStep(
                                title: 'Completed',
                                subtitle: 'Trip finished',
                                completed: activeRide.status == 'completed',
                              ),
                            ],
                          ),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEFFAF4),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: tokens.successGreen.withValues(
                                  alpha: 0.3,
                                ),
                              ),
                            ),
                            child: Text(
                              activeRide.status == 'completed'
                                  ? 'Trip complete. Payment can now be collected.'
                                  : 'Keep the ride moving from accepted to arrived, started, and completed.',
                              style: TextStyle(
                                color: tokens.successGreen,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            height: 56,
                            child: ElevatedButton(
                              onPressed:
                                  activeRide.status == 'completed' ||
                                      activeRide.id == null
                                  ? null
                                  : () => onCompleteRide(activeRide.id!),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: tokens.successGreen,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(18),
                                ),
                              ),
                              child: const Text(
                                'Complete Trip',
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _CountdownDial extends StatelessWidget {
  final int seconds;

  const _CountdownDial({required this.seconds});

  @override
  Widget build(BuildContext context) {
    final tokens = context.aeroTokens;
    return Center(
      child: Container(
        width: 240,
        height: 240,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: const [
            BoxShadow(
              color: Color(0x180D2B52),
              blurRadius: 32,
              offset: Offset(0, 16),
            ),
          ],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            CustomPaint(
              size: const Size(240, 240),
              painter: _DialPainter(
                baseColor: tokens.mutedBorder,
                progressColor: tokens.warningOrange,
                progress: 0.75,
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$seconds',
                  style: TextStyle(
                    fontSize: 58,
                    fontWeight: FontWeight.w900,
                    color: tokens.primaryDarkBlue,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'seconds to respond',
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DialPainter extends CustomPainter {
  final Color baseColor;
  final Color progressColor;
  final double progress;

  _DialPainter({
    required this.baseColor,
    required this.progressColor,
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 16;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 16
      ..strokeCap = StrokeCap.round;
    stroke.color = baseColor;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -2.3,
      4.6,
      false,
      stroke,
    );
    stroke.shader = SweepGradient(
      startAngle: -2.3,
      endAngle: 2.3,
      colors: [progressColor, const Color(0xFF14B8A6), const Color(0xFF0D2B52)],
    ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -2.3,
      4.6 * progress,
      false,
      stroke,
    );
  }

  @override
  bool shouldRepaint(covariant _DialPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.baseColor != baseColor ||
      oldDelegate.progressColor != progressColor;
}
