import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geocoding/geocoding.dart';
import '../controllers/ride_controller.dart';
import '../services/auth_service.dart';

class HomeScreen extends StatefulWidget {
  final User user;
  const HomeScreen({super.key, required this.user});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final RideController _rideController;
  final AuthService _authService = AuthService();

  LatLng? _pickup;
  LatLng? _destination;
  String? _pickupPlaceName;
  String? _destinationPlaceName;
  bool _isSelectingPickup = true;

  @override
  void initState() {
    super.initState();
    _rideController = RideController();
    unawaited(_rideController.startRiderLocationTracking());
  }

  @override
  void dispose() {
    _rideController.dispose();
    super.dispose();
  }

  void _onMapTap(LatLng location) {
    if (_rideController.activeRideId != null) {
      return; // Can't change during active ride
    }

    setState(() {
      if (_isSelectingPickup) {
        _pickup = location;
        _pickupPlaceName = null;
        _isSelectingPickup = false; // Next tap is destination
      } else {
        _destination = location;
        _destinationPlaceName = null;
        _isSelectingPickup = true; // Reset or keep changing destination
      }
    });

    _updateMarkers();
    _resolvePlaceNameFor(location, _isSelectingPickup ? false : true);
  }

  Future<void> _resolvePlaceNameFor(LatLng location, bool isPickup) async {
    try {
      final places = await placemarkFromCoordinates(
        location.latitude,
        location.longitude,
      );
      if (places.isNotEmpty) {
        final p = places.first;
        final parts = <String>[];
        if ((p.name ?? '').trim().isNotEmpty) parts.add(p.name!.trim());
        if ((p.street ?? '').trim().isNotEmpty) parts.add(p.street!.trim());
        final label = parts.isEmpty
            ? '${location.latitude.toStringAsFixed(4)}, ${location.longitude.toStringAsFixed(4)}'
            : parts.take(2).join(', ');
        setState(() {
          if (isPickup)
            _pickupPlaceName = label;
          else
            _destinationPlaceName = label;
        });
      }
    } catch (_) {
      // ignore and leave coordinate fallback
    }
  }

  void _updateMarkers() {
    _rideController.markers.clear();
    if (_pickup != null) {
      _rideController.markers.add(
        Marker(
          markerId: const MarkerId('pickup_select'),
          position: _pickup!,
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueGreen,
          ),
          infoWindow: const InfoWindow(title: "Pickup"),
        ),
      );
    }
    if (_destination != null) {
      _rideController.markers.add(
        Marker(
          markerId: const MarkerId('dest_select'),
          position: _destination!,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          infoWindow: const InfoWindow(title: "Destination"),
        ),
      );
    }

    // Draw straight line preview
    _rideController.polylines.clear();
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
    // Manually trigger Map update
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AeroRide'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () {
              _rideController.cancelActiveTracking();
              _authService.logout();
            },
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: _rideController,
        builder: (context, _) {
          return Stack(
            children: [
              GoogleMap(
                initialCameraPosition: const CameraPosition(
                  target: LatLng(-1.2833, 36.8167), // Default Nairobi
                  zoom: 13,
                ),
                onTap: _onMapTap,
                markers: _rideController.markers,
                polylines: _rideController.polylines,
                onMapCreated: (controller) =>
                    _rideController.mapController = controller,
              ),

              // Bottom Sheet Control Action
              Positioned(
                bottom: 20,
                left: 20,
                right: 20,
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: const [
                      BoxShadow(blurRadius: 10, color: Colors.black26),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_rideController.activeRideId == null) ...[
                        Text(
                          _pickup == null
                              ? "Tap the map to set Pickup location"
                              : _destination == null
                              ? "Tap the map to set Destination"
                              : "Ready to request ride",
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            const Icon(Icons.my_location, color: Colors.green),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _pickupPlaceName ??
                                    (_pickup != null
                                        ? "${_pickup!.latitude.toStringAsFixed(4)}, ${_pickup!.longitude.toStringAsFixed(4)}"
                                        : "Not set"),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(Icons.place, color: Colors.red),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _destinationPlaceName ??
                                    (_destination != null
                                        ? "${_destination!.latitude.toStringAsFixed(4)}, ${_destination!.longitude.toStringAsFixed(4)}"
                                        : "Not set"),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size(double.infinity, 50),
                          ),
                          onPressed: (_pickup != null && _destination != null)
                              ? () {
                                  _rideController.requestNewRide(
                                    userId: widget.user.uid,
                                    pickup: _pickup!,
                                    destination: _destination!,
                                    pickupText: "Custom Pickup",
                                    dropoffText: "Custom Destination",
                                  );
                                }
                              : null,
                          child: const Text("Request Ride"),
                        ),
                      ] else ...[
                        const Text(
                          "RIDE ACTIVE",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                            color: Colors.blue,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text("Status: ${_rideController.currentRideStatus}"),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                            minimumSize: const Size(double.infinity, 50),
                          ),
                          onPressed: () {
                            _rideController.cancelActiveTracking();
                            setState(() {
                              _pickup = null;
                              _destination = null;
                              _isSelectingPickup = true;
                              _updateMarkers();
                            });
                          },
                          child: const Text("Cancel Ride"),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
