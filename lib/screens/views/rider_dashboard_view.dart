import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../controllers/ride_controller.dart';
import '../../models/ride_request_model.dart';
import '../../models/user_model.dart';
import '../../services/firestore_service.dart';
import '../../theme/aeroride_theme.dart';
import '../../widgets/aeroride_components.dart';

class RiderHomeScreen extends StatefulWidget {
  final User user;

  const RiderHomeScreen({super.key, required this.user});

  @override
  State<RiderHomeScreen> createState() => _RiderHomeScreenState();
}

class _RiderHomeScreenState extends State<RiderHomeScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  late final RideController _rideController;
  int _panelIndex = 0;
  LatLng? _pickup;
  LatLng? _destination;
  int _selectedRideTypeIndex = 1;
  String? _pickupPlaceName;
  String? _pickupPlaceSubtitle;
  String? _destinationPlaceName;
  String? _destinationPlaceSubtitle;
  bool _selectingPickup = true;
  bool _requestingRide = false;
  double _selectedTip = 2;

  @override
  void initState() {
    super.initState();
    _rideController = RideController();
    _rideController.addListener(_syncPanelWithRideState);
  }

  @override
  void dispose() {
    _rideController.removeListener(_syncPanelWithRideState);
    _rideController.dispose();
    super.dispose();
  }

  void _syncPanelWithRideState() {
    if (!mounted) return;
    final status = _rideController.currentRideStatus.toUpperCase();

    if (_rideController.activeRideId != null &&
        status != 'COMPLETED' &&
        status != 'CANCELLED' &&
        _panelIndex == 0) {
      setState(() => _panelIndex = 1);
    }

    if (status == 'COMPLETED' && _panelIndex != 2) {
      setState(() => _panelIndex = 2);
    }
  }

  String _formatLocation(LatLng location) {
    return '${location.latitude.toStringAsFixed(5)}, ${location.longitude.toStringAsFixed(5)}';
  }

  Future<String> _resolvePlaceName(LatLng location) async {
    final placemarks = await placemarkFromCoordinates(
      location.latitude,
      location.longitude,
    );

    if (placemarks.isEmpty) {
      return _formatLocation(location);
    }

    final place = placemarks.first;
    final parts = <String>[];
    if ((place.name ?? '').trim().isNotEmpty) parts.add(place.name!.trim());
    if ((place.street ?? '').trim().isNotEmpty) parts.add(place.street!.trim());
    if ((place.locality ?? '').trim().isNotEmpty)
      parts.add(place.locality!.trim());

    if (parts.isEmpty) {
      return _formatLocation(location);
    }

    return parts.take(2).join(', ');
  }

  Future<void> _resolveSelectedLocationLabel({required bool pickup}) async {
    final location = pickup ? _pickup : _destination;
    if (location == null) return;

    try {
      final placeName = await _resolvePlaceName(location);
      if (!mounted) return;
      setState(() {
        if (pickup) {
          _pickupPlaceName = placeName;
          _pickupPlaceSubtitle = _formatLocation(location);
        } else {
          _destinationPlaceName = placeName;
          _destinationPlaceSubtitle = _formatLocation(location);
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        if (pickup) {
          _pickupPlaceName = 'Selected pickup point';
          _pickupPlaceSubtitle = _formatLocation(location);
        } else {
          _destinationPlaceName = 'Selected destination';
          _destinationPlaceSubtitle = _formatLocation(location);
        }
      });
    }
  }

  void _onMapTap(LatLng location) {
    if (_rideController.activeRideId != null || _requestingRide) {
      return;
    }

    final selectingPickup = _selectingPickup;
    setState(() {
      if (selectingPickup) {
        _pickup = location;
        _pickupPlaceName = null;
        _pickupPlaceSubtitle = null;
        _selectingPickup = false;
      } else {
        _destination = location;
        _destinationPlaceName = null;
        _destinationPlaceSubtitle = null;
        _selectingPickup = true;
      }
    });

    _updatePreviewMarkers();
    unawaited(_resolveSelectedLocationLabel(pickup: selectingPickup));
  }

  void _updatePreviewMarkers() {
    _rideController.markers.clear();
    _rideController.polylines.clear();

    if (_pickup != null) {
      _rideController.markers.add(
        Marker(
          markerId: const MarkerId('pickup_select'),
          position: _pickup!,
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueGreen,
          ),
          infoWindow: const InfoWindow(title: 'Pickup'),
        ),
      );
    }

    if (_destination != null) {
      _rideController.markers.add(
        Marker(
          markerId: const MarkerId('destination_select'),
          position: _destination!,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          infoWindow: const InfoWindow(title: 'Destination'),
        ),
      );
    }

    if (_pickup != null && _destination != null) {
      _rideController.polylines.add(
        Polyline(
          polylineId: const PolylineId('preview_route'),
          points: [_pickup!, _destination!],
          color: Colors.blue,
          width: 4,
          patterns: [PatternItem.dash(20), PatternItem.gap(10)],
        ),
      );
    }

    setState(() {});
  }

  Future<void> _requestRide() async {
    if (_pickup == null || _destination == null || _requestingRide) {
      return;
    }

    setState(() => _requestingRide = true);

    try {
      await _rideController.requestNewRide(
        userId: widget.user.uid,
        pickup: _pickup!,
        destination: _destination!,
        pickupText: _pickupPlaceName ?? _formatLocation(_pickup!),
        dropoffText: _destinationPlaceName ?? _formatLocation(_destination!),
        candidateDriverIds: null,
      );

      final requestFailed = _rideController.activeRideId == null;
      if (requestFailed) {
        final message = _rideController.currentRideStatus.startsWith('ERROR:')
            ? _rideController.currentRideStatus
                  .replaceFirst('ERROR:', '')
                  .trim()
            : 'Could not request ride. Please try again.';
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(message)));
          setState(() => _panelIndex = 0);
        }
        return;
      }

      if (mounted) {
        setState(() => _panelIndex = 1);
      }
    } finally {
      if (mounted) {
        setState(() => _requestingRide = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _rideController,
      builder: (context, _) {
        return Scaffold(
          body: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            AeroRidePillButton(
                              label: 'Request',
                              selected: _panelIndex == 0,
                              onTap: () => setState(() => _panelIndex = 0),
                            ),
                            AeroRidePillButton(
                              label: 'Trip',
                              selected: _panelIndex == 1,
                              onTap: () => setState(() => _panelIndex = 1),
                            ),
                            AeroRidePillButton(
                              label: 'Payment',
                              selected: _panelIndex == 2,
                              onTap: () => setState(() => _panelIndex = 2),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Material(
                        color: Colors.white,
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: _showProfileSheet,
                          child: SizedBox(
                            width: 44,
                            height: 44,
                            child: Icon(
                              Icons.person_outline_rounded,
                              color: context.aeroTokens.primaryDarkBlue,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    child: _panelIndex == 0
                        ? _RideRequestPanel(
                            rideController: _rideController,
                            pickup: _pickup,
                            destination: _destination,
                            pickupPlaceName: _pickupPlaceName,
                            pickupPlaceSubtitle: _pickupPlaceSubtitle,
                            destinationPlaceName: _destinationPlaceName,
                            destinationPlaceSubtitle: _destinationPlaceSubtitle,
                            selectedRideTypeIndex: _selectedRideTypeIndex,
                            onSelectRideType: (index) =>
                                setState(() => _selectedRideTypeIndex = index),
                            selectingPickup: _selectingPickup,
                            requestingRide: _requestingRide,
                            onMapTap: _onMapTap,
                            onProfileTap: _showProfileSheet,
                            onRequestRide: _requestRide,
                          )
                        : _panelIndex == 1
                        ? _RideActivePanel(
                            rideController: _rideController,
                            onContinue: () => setState(() => _panelIndex = 2),
                          )
                        : _RideSummaryPanel(
                            selectedTip: _selectedTip,
                            onTipChanged: (value) =>
                                setState(() => _selectedTip = value),
                          ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showProfileSheet() async {
    final future = Future.wait<dynamic>([
      _firestoreService.getUserProfile(widget.user.uid),
      _firestoreService.getUserRideHistory(widget.user.uid),
    ]);

    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.82,
          minChildSize: 0.55,
          maxChildSize: 0.95,
          builder: (context, scrollController) {
            return FutureBuilder<List<dynamic>>(
              future: future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return _ProfileSheetScaffold(
                    child: const Center(child: CircularProgressIndicator()),
                  );
                }

                if (snapshot.hasError || !snapshot.hasData) {
                  return _ProfileSheetScaffold(
                    child: Center(
                      child: Text(
                        'Could not load profile.',
                        style: TextStyle(color: Colors.grey.shade700),
                      ),
                    ),
                  );
                }

                final profile = snapshot.data![0] as UserModel;
                final rides = snapshot.data![1] as List<RideRequest>;

                return _ProfileSheetScaffold(
                  child: ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                    children: [
                      Center(
                        child: Container(
                          width: 44,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 32,
                            backgroundColor: context.aeroTokens.primaryDarkBlue,
                            child: Text(
                              profile.name.isNotEmpty
                                  ? profile.name.characters.first.toUpperCase()
                                  : 'U',
                              style: const TextStyle(
                                fontSize: 24,
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  profile.name.isEmpty
                                      ? 'Rider profile'
                                      : profile.name,
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w900,
                                    color: Color(0xFF0D2B52),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  profile.email,
                                  style: TextStyle(
                                    color: Colors.grey.shade600,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      AeroRidePanelCard(
                        child: Column(
                          children: [
                            _ProfileRow(label: 'Name', value: profile.name),
                            _ProfileRow(label: 'Email', value: profile.email),
                            _ProfileRow(label: 'Role', value: profile.role),
                            _ProfileRow(
                              label: 'Signed up',
                              value: widget.user.metadata.creationTime == null
                                  ? 'Unknown'
                                  : widget.user.metadata.creationTime!
                                        .toLocal()
                                        .toString()
                                        .split('.')[0],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        'Travel history',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF0D2B52),
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (rides.isEmpty)
                        const AeroRidePanelCard(child: Text('No trips yet.'))
                      else
                        ...rides.map(
                          (ride) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: AeroRidePanelCard(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          '${ride.pickupAddress} → ${ride.destinationAddress}',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                            color: Color(0xFF0D2B52),
                                          ),
                                        ),
                                      ),
                                      Text(
                                        ride.status.toUpperCase(),
                                        style: TextStyle(
                                          color: Colors.grey.shade600,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Fare: \$${ride.estimatedCost.toStringAsFixed(2)}',
                                    style: TextStyle(
                                      color: Colors.grey.shade700,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    ride.createdAt == null
                                        ? 'Date unavailable'
                                        : ride.createdAt!
                                              .toLocal()
                                              .toString()
                                              .split('.')[0],
                                    style: TextStyle(
                                      color: Colors.grey.shade600,
                                      fontSize: 12,
                                    ),
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
          },
        );
      },
    );
  }
}

class _RideRequestPanel extends StatelessWidget {
  final RideController rideController;
  final LatLng? pickup;
  final LatLng? destination;
  final String? pickupPlaceName;
  final String? pickupPlaceSubtitle;
  final String? destinationPlaceName;
  final String? destinationPlaceSubtitle;
  final int? selectedRideTypeIndex;
  final ValueChanged<int>? onSelectRideType;
  final bool selectingPickup;
  final bool requestingRide;
  final ValueChanged<LatLng> onMapTap;
  final VoidCallback onProfileTap;
  final VoidCallback onRequestRide;

  const _RideRequestPanel({
    required this.rideController,
    required this.pickup,
    required this.destination,
    required this.pickupPlaceName,
    required this.pickupPlaceSubtitle,
    required this.destinationPlaceName,
    required this.destinationPlaceSubtitle,
    required this.selectingPickup,
    required this.requestingRide,
    required this.onMapTap,
    required this.onProfileTap,
    required this.onRequestRide,
    this.selectedRideTypeIndex,
    this.onSelectRideType,
  });

  @override
  Widget build(BuildContext context) {
    return AeroRideMapShell(
      map: GoogleMap(
        initialCameraPosition: const CameraPosition(
          target: LatLng(-1.286389, 36.817223),
          zoom: 13.4,
        ),
        myLocationButtonEnabled: false,
        zoomControlsEnabled: false,
        compassEnabled: false,
        markers: rideController.markers,
        polylines: rideController.polylines,
        onTap: onMapTap,
        onMapCreated: (controller) {
          rideController.mapController = controller;
        },
      ),
      overlays: [
        Positioned(
          top: 16,
          left: 16,
          child: _FloatingIconButton(icon: Icons.menu_rounded, onTap: () {}),
        ),
        Positioned(
          top: 16,
          right: 16,
          child: _FloatingIconButton(
            icon: Icons.person_outline_rounded,
            onTap: onProfileTap,
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
              child: AnimatedSize(
                duration: const Duration(milliseconds: 180),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.56,
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _LocationField(
                          label: pickup == null
                              ? 'Tap map to set pickup'
                              : pickupPlaceName ?? 'Resolving pickup place...',
                          subtitle: pickup == null
                              ? null
                              : pickupPlaceSubtitle ?? _coords(pickup!),
                          icon: Icons.my_location_rounded,
                          borderColor: const Color(0xFF10B981),
                        ),
                        const SizedBox(height: 12),
                        _LocationField(
                          label: destination == null
                              ? 'Tap map to set destination'
                              : destinationPlaceName ??
                                    'Resolving destination place...',
                          subtitle: destination == null
                              ? null
                              : destinationPlaceSubtitle ??
                                    _coords(destination!),
                          icon: Icons.place_rounded,
                          borderColor: const Color(0xFFEF4444),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          selectingPickup
                              ? 'Select your pickup point on the map'
                              : 'Now select your destination on the map',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Colors.grey.shade700,
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          height: 106,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            children: [
                              AeroRideRideTypeCard(
                                title: 'Economy',
                                price: '\$12.50',
                                eta: '3 min',
                                icon: Icons.directions_car_filled_rounded,
                                selected: (selectedRideTypeIndex ?? 1) == 0,
                                onTap: () => onSelectRideType?.call(0),
                              ),
                              const SizedBox(width: 12),
                              AeroRideRideTypeCard(
                                title: 'Standard',
                                price: '\$18.00',
                                eta: '2 min',
                                icon: Icons.directions_car_rounded,
                                selected: (selectedRideTypeIndex ?? 1) == 1,
                                onTap: () => onSelectRideType?.call(1),
                              ),
                              const SizedBox(width: 12),
                              AeroRideRideTypeCard(
                                title: 'Premium',
                                price: '\$28.50',
                                eta: '4 min',
                                icon: Icons.directions_car_filled_sharp,
                                selected: (selectedRideTypeIndex ?? 1) == 2,
                                onTap: () => onSelectRideType?.call(2),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        AeroRidePrimaryButton(
                          label: requestingRide
                              ? 'Requesting...'
                              : 'Request Ride',
                          backgroundColor: const Color(0xFF64748B),
                          trailing: const Icon(
                            Icons.navigation_rounded,
                            size: 18,
                          ),
                          onPressed:
                              (pickup != null &&
                                  destination != null &&
                                  !requestingRide)
                              ? onRequestRide
                              : null,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  String _coords(LatLng location) {
    return '${location.latitude.toStringAsFixed(5)}, ${location.longitude.toStringAsFixed(5)}';
  }
}

class _RideActivePanel extends StatelessWidget {
  final RideController rideController;
  final VoidCallback onContinue;

  const _RideActivePanel({
    required this.rideController,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.aeroTokens;
    final status = rideController.currentRideStatus.toUpperCase();
    final driverName =
        rideController.assignedDriverProfile?.name ?? 'Driver assigning...';
    final vehicle = rideController.driverVehicle ?? 'Vehicle details pending';
    final rating = rideController.driverRating ?? '--';
    final distance =
        rideController.driverLocation != null &&
            rideController.pickupLocation != null
        ? 'Live'
        : 'Tracking';
    final timelinePickupComplete = [
      'ACCEPTED',
      'ARRIVED',
      'STARTED',
      'COMPLETED',
    ].contains(status);
    final timelineDestinationComplete = [
      'STARTED',
      'COMPLETED',
    ].contains(status);

    return AeroRideMapShell(
      map: GoogleMap(
        initialCameraPosition: const CameraPosition(
          target: LatLng(-1.2833, 36.8167),
          zoom: 13.4,
        ),
        myLocationButtonEnabled: false,
        zoomControlsEnabled: false,
        compassEnabled: false,
        markers: rideController.markers,
        polylines: rideController.polylines,
        onMapCreated: (controller) {
          rideController.mapController = controller;
        },
      ),
      overlays: [
        Positioned(
          top: 16,
          left: 16,
          child: AeroRideStatusPill(
            label: status.isEmpty ? 'Searching...' : status.toLowerCase(),
            color: tokens.successGreen,
          ),
        ),
        Positioned(
          top: 16,
          right: 16,
          child: AeroRideStatusPill(
            label: '1 min',
            color: tokens.warningOrange,
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
              child: AnimatedSize(
                duration: const Duration(milliseconds: 180),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 6,
                      decoration: BoxDecoration(
                        color: tokens.softSurface,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: status == 'COMPLETED'
                            ? 1.0
                            : status == 'STARTED'
                            ? 0.9
                            : status == 'ARRIVED'
                            ? 0.6
                            : 0.3,
                        child: Container(
                          decoration: BoxDecoration(
                            color: tokens.successGreen,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
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
                                '$driverName - $rating',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF0D2B52),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                vehicle,
                                style: const TextStyle(
                                  color: Colors.black54,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        _QuickAction(icon: Icons.call_rounded, onTap: () {}),
                        const SizedBox(width: 10),
                        _QuickAction(icon: Icons.message_rounded, onTap: () {}),
                      ],
                    ),
                    const SizedBox(height: 18),
                    AeroRideTimeline(
                      steps: [
                        AeroRideTimelineStep(
                          title: 'Pickup',
                          subtitle: timelinePickupComplete
                              ? 'Completed'
                              : rideController.pickupLocation == null
                              ? 'Waiting for driver'
                              : 'Driver en route',
                          completed: timelinePickupComplete,
                        ),
                        AeroRideTimelineStep(
                          title: 'Destination',
                          subtitle: timelineDestinationComplete
                              ? 'Completed'
                              : 'Trip in progress',
                          completed: timelineDestinationComplete,
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: AeroRideMetricCard(
                            label: 'Distance',
                            value: distance,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: AeroRideMetricCard(
                            label: 'Fare',
                            value: rideController.estimatedCost == null
                                ? '\$18.00'
                                : '\$${rideController.estimatedCost!.toStringAsFixed(2)}',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    AeroRidePrimaryButton(
                      label: status == 'COMPLETED'
                          ? 'Trip Completed'
                          : 'Continue',
                      trailing: const Icon(
                        Icons.arrow_forward_rounded,
                        size: 18,
                      ),
                      onPressed: status == 'COMPLETED' ? null : onContinue,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _RideSummaryPanel extends StatelessWidget {
  final double selectedTip;
  final ValueChanged<double> onTipChanged;

  const _RideSummaryPanel({
    required this.selectedTip,
    required this.onTipChanged,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.aeroTokens;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Trip Summary',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF0D2B52),
                  ),
                ),
              ),
              TextButton(
                onPressed: () {},
                child: const Text(
                  'Skip',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          AeroRidePanelCard(
            child: Column(
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: tokens.softSurface,
                      child: Icon(Icons.person, color: tokens.primaryDarkBlue),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'John Driver',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF0D2B52),
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            '3.5 km - 15 min - Today',
                            style: TextStyle(color: Colors.black54),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: tokens.softSurface,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Text(
                        '4.9',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                const _BreakdownRow(label: 'Base fare', value: '\$12.00'),
                const _BreakdownRow(label: 'Service fee', value: '\$2.50'),
                const _BreakdownRow(
                  label: 'Subtotal',
                  value: '\$14.50',
                  emphasize: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Add a tip',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: Color(0xFF0D2B52),
            ),
          ),
          const SizedBox(height: 12),
          AeroRideTipSelector(
            tips: const [0, 2, 3, 5],
            selectedTip: selectedTip,
            onChanged: onTipChanged,
          ),
          const SizedBox(height: 10),
          Text(
            'Tip amount: \$${selectedTip.toStringAsFixed(2)}',
            style: TextStyle(
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Payment Method',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: Color(0xFF0D2B52),
            ),
          ),
          const SizedBox(height: 12),
          const AeroRidePaymentOption(
            label: 'Credit Card (**** 4242)',
            subtitle: 'Primary card on file',
            selected: true,
            trailing: Icon(
              Icons.check_circle_rounded,
              color: Color(0xFF10B981),
            ),
          ),
          const AeroRidePaymentOption(
            label: 'Mobile Money (+1 555-0000)',
            subtitle: 'Alternate payment method',
          ),
          const SizedBox(height: 20),
          AeroRidePanelCard(
            padding: const EdgeInsets.all(16),
            color: const Color(0xFFF8FBFF),
            child: Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Total',
                        style: TextStyle(
                          color: Colors.black54,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        '\$16.50',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF0D2B52),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  width: 150,
                  child: AeroRidePrimaryButton(
                    label: 'Pay Now',
                    onPressed: () {},
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LocationField extends StatelessWidget {
  final String label;
  final String? subtitle;
  final IconData icon;
  final Color borderColor;

  const _LocationField({
    required this.label,
    this.subtitle,
    required this.icon,
    required this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: borderColor.withValues(alpha: 0.65),
          width: 1.2,
        ),
      ),
      child: Row(
        children: [
          Icon(icon, color: borderColor),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0D2B52),
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileSheetScaffold extends StatelessWidget {
  final Widget child;

  const _ProfileSheetScaffold({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFF8FBFF),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: child,
    );
  }
}

class _ProfileRow extends StatelessWidget {
  final String label;
  final String value;

  const _ProfileRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? 'Not set' : value,
              style: const TextStyle(
                color: Color(0xFF0D2B52),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FloatingIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _FloatingIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 6,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          width: 48,
          height: 48,
          child: Icon(icon, color: const Color(0xFF0D2B52)),
        ),
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _QuickAction({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final tokens = context.aeroTokens;
    return Material(
      color: tokens.softSurface,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 42,
          height: 42,
          child: Icon(icon, color: tokens.primaryDarkBlue, size: 20),
        ),
      ),
    );
  }
}

class _BreakdownRow extends StatelessWidget {
  final String label;
  final String value;
  final bool emphasize;

  const _BreakdownRow({
    required this.label,
    required this.value,
    this.emphasize = false,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.aeroTokens;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: emphasize
                    ? tokens.primaryDarkBlue
                    : Colors.grey.shade600,
                fontWeight: emphasize ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: tokens.primaryDarkBlue,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
