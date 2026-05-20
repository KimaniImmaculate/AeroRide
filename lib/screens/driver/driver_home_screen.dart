import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import 'dart:math';
import 'package:geolocator/geolocator.dart';
import '../../services/auth_service.dart';
import '../../services/drivers_service.dart';
import 'driver_profile_screen.dart';

class DriverHomeScreen extends StatefulWidget {
  final User user;
  const DriverHomeScreen({super.key, required this.user});

  @override
  State<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends State<DriverHomeScreen> {
  final AuthService _authService = AuthService();
  late final PageController _pageController;
  int _currentPageIndex = 0;
  bool _isOnline = false;
  final DriversService _driversService = DriversService();
  StreamSubscription<QuerySnapshot>? _assignedRideSub;
  StreamSubscription<QuerySnapshot>? _targetedRidesSub;
  String? _activeRideId;
  Timer? _arrivalTimer;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    if (_isOnline) {
      _driversService.stopLocationUpdates(widget.user.uid);
      // cancel targeted rides listener
      _targetedRidesSub?.cancel();
      _targetedRidesSub = null;
      _assignedRideSub?.cancel();
      _assignedRideSub = null;
      _arrivalTimer?.cancel();
      _arrivalTimer = null;
    }
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PageView(
        controller: _pageController,
        onPageChanged: (index) => setState(() => _currentPageIndex = index),
        children: [
          // Active Rides Screen
          Scaffold(
            appBar: AppBar(
              title: const Text("Available Rides"),
              actions: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Center(
                    child: GestureDetector(
                      onTap: () async {
                        // Toggle online/offline and start/stop location writes
                        if (!_isOnline) {
                          try {
                            await _driversService.startLocationUpdates(
                              widget.user.uid,
                            );
                            setState(() => _isOnline = true);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('You are online')),
                            );
                            // start listening for rides assigned to this driver
                            _assignedRideSub = FirebaseFirestore.instance
                                .collection('rides')
                                .where('driverId', isEqualTo: widget.user.uid)
                                .where('status', isEqualTo: 'accepted')
                                .snapshots()
                                .listen((snap) {
                                  if (snap.docs.isNotEmpty) {
                                    final doc = snap.docs.first;
                                    _activeRideId = doc.id;
                                    _startArrivalWatcher(
                                      doc.data() as Map<String, dynamic>,
                                      doc.id,
                                    );
                                  }
                                });
                            // targeted rides listener (optional for background notifications)
                            _targetedRidesSub = FirebaseFirestore.instance
                                .collection('rides')
                                .where('status', isEqualTo: 'searching')
                                .where(
                                  'candidateDrivers',
                                  arrayContains: widget.user.uid,
                                )
                                .snapshots()
                                .listen((_) {});
                          } catch (e) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Failed to go online: $e'),
                              ),
                            );
                          }
                        } else {
                          await _driversService.stopLocationUpdates(
                            widget.user.uid,
                          );
                          // cancel listeners and timers
                          _targetedRidesSub?.cancel();
                          _targetedRidesSub = null;
                          _assignedRideSub?.cancel();
                          _assignedRideSub = null;
                          _arrivalTimer?.cancel();
                          _arrivalTimer = null;
                          setState(() => _isOnline = false);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('You are offline')),
                          );
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: _isOnline ? Colors.green : Colors.grey,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          _isOnline ? "🟢 Online" : "⚫ Offline",
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            body: _isOnline
                ? StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('rides')
                        .where('status', isEqualTo: 'searching')
                        .where(
                          'candidateDrivers',
                          arrayContains: widget.user.uid,
                        )
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.search_off,
                                size: 80,
                                color: Colors.grey[300],
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                "No rides available right now",
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        );
                      }

                      return ListView.builder(
                        itemCount: snapshot.data!.docs.length,
                        itemBuilder: (context, index) {
                          final ride =
                              snapshot.data!.docs[index].data()
                                  as Map<String, dynamic>;
                          final rideId = snapshot.data!.docs[index].id;

                          return Card(
                            margin: const EdgeInsets.all(12),
                            child: ListTile(
                              leading: const Icon(
                                Icons.location_on,
                                color: Colors.red,
                              ),
                              title: Text(
                                "${ride['pickupAddress'] ?? 'Pickup'} → ${ride['destinationAddress'] ?? 'Destination'}",
                              ),
                              subtitle: Text(
                                "Cost: KES ${ride['estimatedCost'] ?? 0}",
                              ),
                              trailing: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                ),
                                onPressed: () async {
                                  // Use transaction to ensure only one driver wins
                                  try {
                                    await FirebaseFirestore.instance
                                        .runTransaction((tx) async {
                                          final docRef = FirebaseFirestore
                                              .instance
                                              .collection('rides')
                                              .doc(rideId);
                                          final snapshot = await tx.get(docRef);
                                          final data = snapshot.data();
                                          if (data == null)
                                            throw Exception('Ride not found');
                                          final status = data['status'];
                                          if (status != 'searching')
                                            throw Exception(
                                              'Ride no longer available',
                                            );
                                          tx.update(docRef, {
                                            'status': 'accepted',
                                            'driverId': widget.user.uid,
                                          });
                                        });
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text("Ride accepted!"),
                                      ),
                                    );
                                  } catch (e) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'Could not accept ride: $e',
                                        ),
                                      ),
                                    );
                                  }
                                },
                                child: const Text("Accept"),
                              ),
                            ),
                          );
                        },
                      );
                    },
                  )
                : Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.power_settings_new,
                          size: 80,
                          color: Colors.grey[300],
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          "You are offline",
                          style: TextStyle(fontSize: 16, color: Colors.grey),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          "Go online to accept rides",
                          style: TextStyle(fontSize: 14, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
          ),
          // Profile Screen
          DriverProfileScreen(user: widget.user),
        ],
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
            icon: const Icon(Icons.assignment),
            label: "Rides",
            tooltip: "Available rides",
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.person),
            label: "Profile",
            tooltip: "Your profile",
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _authService.logout(),
        backgroundColor: Colors.red,
        label: const Text("Logout"),
        icon: const Icon(Icons.logout),
      ),
    );
  }

  void _startArrivalWatcher(Map<String, dynamic> rideData, String rideId) {
    _arrivalTimer?.cancel();
    _arrivalTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      try {
        final pos = await Geolocator.getCurrentPosition();
        final gpPickup = rideData['pickupLocation'] as GeoPoint;
        final gpDest = rideData['destinationLocation'] as GeoPoint;
        final double distToPickup =
            _distanceKm(
              pos.latitude,
              pos.longitude,
              gpPickup.latitude,
              gpPickup.longitude,
            ) *
            1000; // meters
        final double distToDest =
            _distanceKm(
              pos.latitude,
              pos.longitude,
              gpDest.latitude,
              gpDest.longitude,
            ) *
            1000; // meters

        // If close to pickup and ride is still 'accepted', set to 'started'
        await FirebaseFirestore.instance.runTransaction((tx) async {
          final docRef = FirebaseFirestore.instance
              .collection('rides')
              .doc(rideId);
          final snapshot = await tx.get(docRef);
          if (!snapshot.exists) return;
          final status = snapshot.data()?['status'];
          if (status == 'accepted' && distToPickup <= 30) {
            tx.update(docRef, {'status': 'started'});
          } else if (status == 'started' && distToDest <= 30) {
            tx.update(docRef, {'status': 'completed'});
            // stop timer once completed
            _arrivalTimer?.cancel();
            _arrivalTimer = null;
            _activeRideId = null;
          }
        });
      } catch (e) {
        // swallow for now
      }
    });
  }

  double _distanceKm(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371; // km
    final dLat = _deg2rad(lat2 - lat1);
    final dLon = _deg2rad(lon2 - lon1);
    final a =
        (sin(dLat / 2) * sin(dLat / 2)) +
        cos(_deg2rad(lat1)) *
            cos(_deg2rad(lat2)) *
            (sin(dLon / 2) * sin(dLon / 2));
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return R * c;
  }

  double _deg2rad(double deg) => deg * (pi / 180);
}
