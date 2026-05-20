import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../controllers/ride_controller.dart';
import '../../services/auth_service.dart';
import '../../services/drivers_service.dart';
import 'rider_profile_screen.dart';

class RiderHomeScreen extends StatefulWidget {
  final User user;
  const RiderHomeScreen({super.key, required this.user});

  @override
  State<RiderHomeScreen> createState() => _RiderHomeScreenState();
}

class _RiderHomeScreenState extends State<RiderHomeScreen> {
  late final RideController _rideController;
  final AuthService _authService = AuthService();
  late final PageController _pageController;

  LatLng? _pickup;
  LatLng? _destination;
  bool _isSelectingPickup = true;
  int _currentPageIndex = 0;
  final DriversService _driversService = DriversService();
  List<Map<String, dynamic>> _nearbyDrivers = [];
  String? _nearestInfo;
  List<String> _selectedDriverIds = [];

  @override
  void initState() {
    super.initState();
    _rideController = RideController();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _rideController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _onMapTap(LatLng location) {
    if (_rideController.activeRideId != null) return;

    setState(() {
      if (_isSelectingPickup) {
        _pickup = location;
        _isSelectingPickup = false;
        _refreshNearbyDrivers();
      } else {
        _destination = location;
      }
    });
    _updateMarkers();
  }

  Future<void> _refreshNearbyDrivers() async {
    if (_pickup == null) return;
    try {
      _nearbyDrivers = await _driversService.getNearbyDrivers(
        _pickup!.latitude,
        _pickup!.longitude,
        radiusKm: 5.0,
      );

      if (_nearbyDrivers.isNotEmpty) {
        final nearest = _nearbyDrivers.first;
        _nearestInfo =
            "Nearest: ${(nearest['distanceKm'] as double).toStringAsFixed(2)} km";
        // default select up to 3 drivers
        _selectedDriverIds = _nearbyDrivers
            .take(3)
            .map((d) => d['driverId'] as String)
            .toList();
      } else {
        _nearestInfo = "No drivers within 5 km";
      }
    } catch (e) {
      _nearestInfo = 'Error finding drivers';
    }
    _updateMarkers();
  }

  void _updateMarkers() {
    _rideController.markers.clear();
    if (_pickup != null) {
      _rideController.markers.add(
        Marker(
          markerId: const MarkerId('pickup'),
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
          markerId: const MarkerId('destination'),
          position: _destination!,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          infoWindow: const InfoWindow(title: "Destination"),
        ),
      );
    }

    // Add driver markers
    for (final d in _nearbyDrivers) {
      final LatLng loc = d['location'] as LatLng;
      _rideController.markers.add(
        Marker(
          markerId: MarkerId('driver-${d['driverId']}'),
          position: loc,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
          infoWindow: InfoWindow(
            title: 'Driver ${d['driverId']}',
            snippet: '${(d['distanceKm'] as double).toStringAsFixed(2)} km',
          ),
        ),
      );
    }

    _rideController.polylines.clear();
    if (_pickup != null && _destination != null) {
      _rideController.polylines.add(
        Polyline(
          polylineId: const PolylineId('route'),
          points: [_pickup!, _destination!],
          color: Colors.blue,
          width: 4,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListenableBuilder(
        listenable: _rideController,
        builder: (context, _) {
          return PageView(
            controller: _pageController,
            onPageChanged: (index) => setState(() => _currentPageIndex = index),
            children: [
              // Map Screen
              Stack(
                children: [
                  GoogleMap(
                    initialCameraPosition: const CameraPosition(
                      target: LatLng(-1.2833, 36.8167),
                      zoom: 13,
                    ),
                    onTap: _onMapTap,
                    markers: _rideController.markers,
                    polylines: _rideController.polylines,
                    onMapCreated: (controller) =>
                        _rideController.mapController = controller,
                  ),
                  Positioned(
                    top: 50,
                    left: 16,
                    right: 16,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: const [
                          BoxShadow(blurRadius: 6, color: Colors.black12),
                        ],
                      ),
                      child: Text(
                        _pickup == null
                            ? "Tap map for pickup"
                            : _destination == null
                            ? "Tap map for destination"
                            : "Ready to request",
                        style: const TextStyle(fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 20,
                    left: 16,
                    right: 16,
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: const [
                          BoxShadow(blurRadius: 8, color: Colors.black12),
                        ],
                      ),
                      child: _rideController.activeRideId == null
                          ? Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (_pickup != null)
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.location_on,
                                        color: Colors.green,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          "${_pickup!.latitude.toStringAsFixed(4)}, ${_pickup!.longitude.toStringAsFixed(4)}",
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                      ),
                                    ],
                                  ),
                                if (_destination != null) ...[
                                  const SizedBox(height: 8),
                                  if (_nearestInfo != null) ...[
                                    Text(
                                      _nearestInfo!,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                  ],
                                  if (_nearbyDrivers.isNotEmpty) ...[
                                    SizedBox(
                                      height: 72,
                                      child: ListView.builder(
                                        scrollDirection: Axis.horizontal,
                                        itemCount: _nearbyDrivers.length,
                                        itemBuilder: (context, idx) {
                                          final d = _nearbyDrivers[idx];
                                          final id = d['driverId'] as String;
                                          final dist =
                                              (d['distanceKm'] as double)
                                                  .toStringAsFixed(2);
                                          final selected = _selectedDriverIds
                                              .contains(id);
                                          return Padding(
                                            padding: const EdgeInsets.only(
                                              right: 8.0,
                                            ),
                                            child: ChoiceChip(
                                              label: Text(
                                                'Driver ${id.substring(0, 6)}\n${dist}km',
                                              ),
                                              selected: selected,
                                              onSelected: (v) {
                                                setState(() {
                                                  if (v) {
                                                    if (!_selectedDriverIds
                                                        .contains(id)) {
                                                      _selectedDriverIds.add(
                                                        id,
                                                      );
                                                    }
                                                  } else {
                                                    _selectedDriverIds.remove(
                                                      id,
                                                    );
                                                  }
                                                });
                                              },
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                  ],
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.location_on,
                                        color: Colors.red,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          "${_destination!.latitude.toStringAsFixed(4)}, ${_destination!.longitude.toStringAsFixed(4)}",
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      minimumSize: const Size(
                                        double.infinity,
                                        48,
                                      ),
                                    ),
                                    onPressed: () {
                                      _rideController.requestNewRide(
                                        userId: widget.user.uid,
                                        pickup: _pickup!,
                                        destination: _destination!,
                                        pickupText: "Pickup",
                                        dropoffText: "Dropoff",
                                        candidateDriverIds:
                                            _selectedDriverIds.isNotEmpty
                                            ? _selectedDriverIds
                                            : null,
                                      );
                                    },
                                    child: const Text("Request Ride"),
                                  ),
                                ],
                              ],
                            )
                          : Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text(
                                  "RIDE ACTIVE",
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    color: Colors.blue,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  "Status: ${_rideController.currentRideStatus}",
                                ),
                                const SizedBox(height: 12),
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.red,
                                    minimumSize: const Size(
                                      double.infinity,
                                      48,
                                    ),
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
                                  child: const Text(
                                    "Cancel Ride",
                                    style: TextStyle(color: Colors.white),
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                ],
              ),
              // Profile Screen
              RiderProfileScreen(user: widget.user),
            ],
          );
        },
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentPageIndex,
        onTap: (index) => _pageController.animateToPage(
          index,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        ),
        items: [
          BottomNavigationBarItem(
            icon: const Icon(Icons.map),
            label: "Ride",
            tooltip: "Request a ride",
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.person),
            label: "Profile",
            tooltip: "Your profile",
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          _rideController.cancelActiveTracking();
          _authService.logout();
        },
        backgroundColor: Colors.red,
        label: const Text("Logout"),
        icon: const Icon(Icons.logout),
      ),
    );
  }
}
