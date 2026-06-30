import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:convert';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../history_screen.dart';
import '../profile_screen.dart';
import '../chat_screen.dart';
import '../../gateway_portal.dart';

import '../../services/user_service.dart';
import '../../services/ride_service.dart';

class DriverHomeScreen extends StatefulWidget {
  const DriverHomeScreen({super.key});

  @override
  State<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends State<DriverHomeScreen> {
  bool isOnline = false;
  Timer? locationTimer;
  String driverTier = 'tulia';
  StreamSubscription<DocumentSnapshot>? driverProfileSubscription;
  bool isUploadingImage = false;

  Future<void> _uploadVehiclePhoto() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 50,
      maxWidth: 600,
      maxHeight: 600,
    );

    if (image == null) {
      debugPrint('[Vehicle Upload] No image selected');
      return;
    }

    setState(() {
      isUploadingImage = true;
    });

    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        debugPrint('[Vehicle Upload] Error: currentUser is null');
        return;
      }

      final bytes = await image.readAsBytes();
      final base64String = base64Encode(bytes);
      final downloadUrl = "data:image/jpeg;base64,$base64String";

      debugPrint('[Vehicle Upload] Updating Firestore user document with base64 vehicleImageUrl');
      await firestore.collection('users').doc(currentUser.uid).update({
        'vehicleImageUrl': downloadUrl,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Vehicle photo uploaded successfully!"),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('[Vehicle Upload] Exception encountered: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Upload failed: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          isUploadingImage = false;
        });
      }
    }
  }

  final UserService userService = UserService();
  final FirebaseFirestore firestore = FirebaseFirestore.instance;
  final RideService rideService = RideService();

  final TextEditingController sosMessageController = TextEditingController();
  final TextEditingController driverCancelController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _listenToDriverProfile();
    _initFCM();
  }

  /// Initializes Firebase Cloud Messaging: requests permission, gets token, saves to Firestore
  Future<void> _initFCM() async {
    try {
      final messaging = FirebaseMessaging.instance;

      // Request notification permission from the browser
      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      if (settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional) {
        // Get the FCM token
        final token = await messaging.getToken(
          vapidKey: null, // Uses the default VAPID key from Firebase project
        );

        if (token != null) {
          final currentUser = FirebaseAuth.instance.currentUser;
          if (currentUser != null) {
            await firestore.collection('users').doc(currentUser.uid).update({
              'fcmToken': token,
            });
            debugPrint('[FCM] Token saved to Firestore: ${token.substring(0, 20)}...');
          }
        }

        // Listen for token refresh
        messaging.onTokenRefresh.listen((newToken) async {
          final currentUser = FirebaseAuth.instance.currentUser;
          if (currentUser != null) {
            await firestore.collection('users').doc(currentUser.uid).update({
              'fcmToken': newToken,
            });
            debugPrint('[FCM] Token refreshed and saved.');
          }
        });

        // Handle foreground messages (show a snackbar)
        FirebaseMessaging.onMessage.listen((RemoteMessage message) {
          if (mounted) {
            final title = message.notification?.title ?? 'New Notification';
            final body = message.notification?.body ?? '';
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
                    if (body.isNotEmpty) Text(body),
                  ],
                ),
                backgroundColor: Colors.blue.shade700,
                duration: const Duration(seconds: 5),
              ),
            );
          }
        });
      } else {
        debugPrint('[FCM] Notification permission denied.');
      }
    } catch (e) {
      debugPrint('[FCM] Error initializing: $e');
    }
  }

  void _listenToDriverProfile() {
    final currentDriverId = FirebaseAuth.instance.currentUser?.uid;
    if (currentDriverId != null) {
      driverProfileSubscription = firestore
          .collection('users')
          .doc(currentDriverId)
          .snapshots()
          .listen((doc) {
        if (doc.exists) {
          final data = doc.data() ?? {};
          final tier = data['carTier'] ?? 'tulia';
          if (mounted && tier != driverTier) {
            setState(() {
              driverTier = tier;
            });
          }
        }
      });
    }
  }

  @override
  void dispose() {
    driverProfileSubscription?.cancel();
    locationTimer?.cancel();
    sosMessageController.dispose();
    driverCancelController.dispose();
    super.dispose();
  }

  
  Future<void> toggleDriverStatus() async {
    setState(() {
      isOnline = !isOnline;
    });

    if (isOnline) {
      await updateLocation();
      locationTimer = Timer.periodic(
        const Duration(seconds: 5),
        (timer) async {
          await updateLocation();
        },
      );
    } else {
      locationTimer?.cancel();
    }

    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser != null) {
      await userService.updateDriverStatus(
        uid: currentUser.uid,
        isOnline: isOnline,
      );
    }
  }

  Future<void> updateLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }

    Position position = await Geolocator.getCurrentPosition();
    final currentUser = FirebaseAuth.instance.currentUser;

    if (currentUser != null) {
      await userService.updateDriverLocation(
        uid: currentUser.uid,
        latitude: position.latitude,
        longitude: position.longitude,
      );
      
      final activeRides = await firestore
          .collection('rides')
          .where('driverId', isEqualTo: currentUser.uid)
          .where('status', whereIn: ['accepted', 'started'])
          .get();

      for (var ride in activeRides.docs) {
        await firestore.collection('rides').doc(ride.id).update({
          'driverLatitude': position.latitude,
          'driverLongitude': position.longitude,
        });
      }
    }
  }

  Future<void> _handleLogout(BuildContext context) async {
  // 1. Display the Confirmation Alert Dialog first
  final bool? shouldLogout = await showDialog<bool>(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.logout_rounded, color: Colors.redAccent),
            SizedBox(width: 8),
            Text("Confirm Log Out"),
          ],
        ),
        content: const Text("Are you sure you want to log out of your session?"),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        actions: [
          // Cancel Button
          TextButton(
            onPressed: () => Navigator.of(context).pop(false), // Returns false
            child: Text(
              "Cancel", 
              style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.w600)
            ),
          ),
          // OK Button
          TextButton(
            onPressed: () => Navigator.of(context).pop(true), // Returns true
            child: const Text(
              "OK", 
              style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)
            ),
          ),
        ],
      );
    },
  );

  // 2. If the user clicked Cancel (or dismissed the dialog), stop right here
  if (shouldLogout != true) return;

  // 3. If they clicked OK, proceed with the secure logout workflow
  if (!context.mounted) return;
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) => const Center(
      child: CircularProgressIndicator(color: Colors.blue),
    ),
  );

  try {
    // Sign out from Firebase Cloud
    await FirebaseAuth.instance.signOut();

    if (!context.mounted) return;
    Navigator.pop(context); // Dismiss loading spinner

    // Clear navigation stack tracking and return to landing page entry point
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const AeroRideGatewayPortal()),
      (route) => false,
    );
  } catch (e) {
    if (context.mounted) Navigator.pop(context); // Dismiss loading spinner on error
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Error logging out: ${e.toString()}"),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}

  /// Handles the logout functionality for the driver
  /*Future<void> _handleLogout(BuildContext context) async {
  // Show a quick loading dialog so the user knows it's processing
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) => const Center(
      child: CircularProgressIndicator(color: Colors.blue),
    ),
  );

  try {
    // 1. Sign out from Firebase Cloud Auth
    await FirebaseAuth.instance.signOut();

    if (!context.mounted) return;

    // 2. Pop the loading dialog safely
    Navigator.pop(context);

    // 3. Clear navigation stack and route directly back to the LandingScreen
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const LandingScreen()),
      (route) => false, // This condition destroys all previous dashboard history screens
    );
  } catch (e) {
    if (context.mounted) Navigator.pop(context); // Pop loading dialog if it fails
    
    // Alert the user if a cloud connection error happens
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("Error logging out: ${e.toString()}"),
        backgroundColor: Colors.red,
      ),
    );
  }
}*/


  @override
  Widget build(BuildContext context) {
    final currentDriverId = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title:  Text(MediaQuery.of(context).size.width < 500 ? "Driver" : "Driver Dashboard", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.grey.shade900,
        actions: [
          IconButton(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HistoryScreen(isDriver: true))),
            icon: const Icon(Icons.history_rounded),
            tooltip: "Ride History",
          ),
          IconButton(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen())),
            icon: const Icon(Icons.person_outline_rounded),
            tooltip: "Account Profile",
          ),
    Padding(
      padding: const EdgeInsets.only(right: 6.0),
      child: IconButton(
        onPressed: () => _handleLogout(context), // Triggers the sign-out method
        icon: const Icon(Icons.logout_rounded, color: Colors.redAccent, size: 22),
        tooltip: "Log Out",
      ),
    ),
          //const SizedBox(width: 8),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 1000), // Formats interface elegantly on desktop layout views
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // System Availability & Status Header Row
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: Colors.grey.shade200),
                  ),
                  color: Colors.white,
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final isMobile = constraints.maxWidth < 480;
                        final statusRow = Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                color: isOnline ? Colors.green : Colors.grey.shade400,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              isOnline ? "Active & Online" : "Currently Offline",
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey.shade900,
                              ),
                            ),
                          ],
                        );
                        final actionButtons = Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ElevatedButton.icon(
                              onPressed: () => _showEmergencyDialog(context),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red.shade50,
                                foregroundColor: Colors.red.shade700,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              icon: const Icon(Icons.gpp_bad_rounded, size: 18),
                              label: const Text("SOS", style: TextStyle(fontWeight: FontWeight.bold)),
                            ),
                            const SizedBox(width: 10),
                            ElevatedButton(
                              onPressed: toggleDriverStatus,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: isOnline ? Colors.grey.shade900 : Colors.blue.shade600,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              child: Text(
                                isOnline ? "Go Offline" : "Go Online",
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        );
                        if (isMobile) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              statusRow,
                              const SizedBox(height: 16),
                              actionButtons,
                            ],
                          );
                        }
                        return Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [statusRow, actionButtons],
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Responsive Grid for General Fleet Statistics
                LayoutBuilder(
                  builder: (context, constraints) {
                    int crossAxisCount = constraints.maxWidth > 650 ? 2 : 1;
                    return GridView(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 16,
                        childAspectRatio: 2.2,
                      ),
                      children: [
                        // Card Panel Left: Personal Earnings Pipeline Metrics
                        StreamBuilder<DocumentSnapshot>(
                          stream: firestore.collection('users').doc(currentDriverId).snapshots(),
                          builder: (context, snapshot) {
                            if (!snapshot.hasData) return const Center(child: LinearProgressIndicator());
                            final data = snapshot.data?.data() as Map<String, dynamic>? ?? {};
                            final earnings = data['earnings'] ?? 0;
                            final totalTrips = data['totalTrips'] ?? 0;
                            final rating = (data['rating'] ?? 0.0).toDouble();
                            final totalRatings = data['totalRatings'] ?? 0;
                            
                            return _buildMetricTile(
                              title: "Your Earnings",
                              value: "KES $earnings",
                              subtitle: "Total trips: $totalTrips • Commission: 75%\nRating: ${rating.toStringAsFixed(1)} ⭐ ($totalRatings reviews)",
                              backgroundColor: Colors.blue.shade50.withValues(alpha: 0.5),
                              accentColor: Colors.blue.shade700,
                              icon: Icons.account_balance_wallet_outlined,
                            );
                          },
                        ),


                        // Card Panel Right: Global Network Context Telemetry View
                        // Note: rules only allow reading 'searching' rides globally and
                        // this driver's own active rides — counts reflect what's accessible.
                        StreamBuilder<QuerySnapshot>(
                          stream: firestore.collection('users').where('isOnline', isEqualTo: true).snapshots(),
                          builder: (context, driverSnapshot) {
                            return StreamBuilder<QuerySnapshot>(
                              // Only searching rides are readable by any signed-in user
                              stream: currentDriverId == null
                                  ? const Stream.empty()
                                  : firestore
                                      .collection('rides')
                                      .where('status', isEqualTo: 'searching')
                                      .snapshots(),
                              builder: (context, searchingRideSnapshot) {
                                return StreamBuilder<QuerySnapshot>(
                                  // This driver's own active rides
                                  stream: currentDriverId == null
                                      ? const Stream.empty()
                                      : firestore
                                          .collection('rides')
                                          .where('driverId', isEqualTo: currentDriverId)
                                          .where('status', whereIn: ['accepted', 'arrived', 'started'])
                                          .snapshots(),
                                  builder: (context, activeRideSnapshot) {
                                    final int onlineDrivers = driverSnapshot.data?.docs.length ?? 0;
                                    final int pendingRides = searchingRideSnapshot.data?.docs.length ?? 0;
                                    final int ongoingRides = activeRideSnapshot.data?.docs.length ?? 0;

                                    return _buildMetricTile(
                                      title: "AeroRide Telemetry Status",
                                      value: "$onlineDrivers Active Drivers",
                                      subtitle: "$pendingRides rides awaiting dispatch • $ongoingRides running trips",
                                      backgroundColor: Colors.green.shade50.withValues(alpha: 0.5),
                                      accentColor: Colors.green.shade700,
                                      icon: Icons.language_rounded,
                                    );
                                  },
                                );
                              },
                            );
                          },
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 24),

                // Vehicle Verification Management Card
                StreamBuilder<DocumentSnapshot>(
                  stream: firestore.collection('users').doc(currentDriverId).snapshots(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) return const SizedBox.shrink();
                    final data = snapshot.data?.data() as Map<String, dynamic>? ?? {};
                    final uploadedUrl = data['vehicleImageUrl'] as String?;

                    return Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(color: Colors.grey.shade200),
                      ),
                      color: Colors.white,
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.purple.shade50,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(Icons.drive_eta_rounded, color: Colors.purple.shade700, size: 28),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    "Vehicle Verification",
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.grey.shade900,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    uploadedUrl != null
                                        ? "Vehicle photo uploaded. Status: ${data['vehicleVerified'] == true ? '✅ Approved by Admin' : '⏳ Pending Admin Verification'}"
                                        : "Please upload an exterior photo of your vehicle for tier verification.",
                                    style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 16),
                            if (isUploadingImage)
                              const CircularProgressIndicator()
                            else if (uploadedUrl != null)
                              Stack(
                                alignment: Alignment.topRight,
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: uploadedUrl.startsWith('data:image')
                                        ? Image.memory(
                                            base64Decode(uploadedUrl.split(',').last),
                                            width: 80,
                                            height: 60,
                                            fit: BoxFit.cover,
                                          )
                                        : Image.network(
                                            uploadedUrl,
                                            width: 80,
                                            height: 60,
                                            fit: BoxFit.cover,
                                          ),
                                  ),
                                  GestureDetector(
                                    onTap: _uploadVehiclePhoto,
                                    child: Container(
                                      decoration: const BoxDecoration(
                                        color: Colors.black54,
                                        shape: BoxShape.circle,
                                      ),
                                      padding: const EdgeInsets.all(4),
                                      child: const Icon(Icons.edit, color: Colors.white, size: 14),
                                    ),
                                  ),
                                ],
                              )
                            else
                              ElevatedButton.icon(
                                onPressed: _uploadVehiclePhoto,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.purple.shade600,
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                icon: const Icon(Icons.upload_file, size: 18),
                                label: const Text("Upload"),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 36),

                // Request Header Label Section
                Row(
                  children: [
                    Icon(Icons.local_taxi_rounded, color: Colors.grey.shade700),
                    const SizedBox(width: 8),
                    Text(
                      "Pending Ride Requests",
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.grey.shade800),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Core Modular Request Flow Streaming Pipeline Builder
                // Two separate Firestore-filtered queries satisfy security rules:
                //   1. searching rides for this driver's tier (rules allow status=='searching' reads)
                //   2. this driver's own active rides (rules allow driverId==uid reads)
                StreamBuilder<QuerySnapshot>(
                  stream: currentDriverId == null
                      ? const Stream.empty()
                      : firestore
                          .collection('rides')
                          .where('rideTier', isEqualTo: driverTier)
                          .where('status', isEqualTo: 'searching')
                          .snapshots(),
                  builder: (context, searchingSnapshot) {
                    return StreamBuilder<QuerySnapshot>(
                      stream: currentDriverId == null
                          ? const Stream.empty()
                          : firestore
                              .collection('rides')
                              .where('driverId', isEqualTo: currentDriverId)
                              .where('status', whereIn: ['accepted', 'arrived', 'started'])
                              .snapshots(),
                      builder: (context, activeSnapshot) {
                        // Surface any Firestore errors (e.g. missing composite index)
                        if (searchingSnapshot.hasError) {
                          debugPrint('[Rides Stream] Searching error: ${searchingSnapshot.error}');
                          return Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(24),
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(
                              color: Colors.red.shade50,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.red.shade200),
                            ),
                            child: Text(
                              '⚠️ Could not load rides: ${searchingSnapshot.error}',
                              style: TextStyle(color: Colors.red.shade800, fontSize: 13),
                            ),
                          );
                        }
                        if (activeSnapshot.hasError) {
                          debugPrint('[Rides Stream] Active error: ${activeSnapshot.error}');
                          return Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(24),
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(
                              color: Colors.red.shade50,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.red.shade200),
                            ),
                            child: Text(
                              '⚠️ Could not load active ride: ${activeSnapshot.error}',
                              style: TextStyle(color: Colors.red.shade800, fontSize: 13),
                            ),
                          );
                        }
                        // Show spinner only while both streams are still loading
                        if (!searchingSnapshot.hasData || !activeSnapshot.hasData) {
                          return const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()));
                        }

                        // Merge both result sets; deduplicate by document ID
                        final Map<String, QueryDocumentSnapshot> ridesMap = {};
                        for (final doc in searchingSnapshot.data!.docs) {
                          ridesMap[doc.id] = doc;
                        }
                        for (final doc in activeSnapshot.data!.docs) {
                          ridesMap[doc.id] = doc;
                        }
                        final rides = ridesMap.values.toList();

                        if (rides.isEmpty) {
                          return Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(48),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.grey.shade200),
                            ),
                            child: Column(
                              children: [
                                Icon(Icons.layers_clear_outlined, size: 48, color: Colors.grey.shade300),
                                const SizedBox(height: 12),
                                Text("No Ride Requests Available", style: TextStyle(color: Colors.grey.shade500, fontSize: 16, fontWeight: FontWeight.w500)),
                              ],
                            ),
                          );
                        }

                        return ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: rides.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final ride = rides[index];
                            final data = ride.data() as Map<String, dynamic>;
                            
                            return Card(
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                                side: BorderSide(color: Colors.grey.shade200),
                              ),
                              color: Colors.white,
                              child: Padding(
                                padding: const EdgeInsets.all(20),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        // Top row: status + tier + timestamp chips
                                        Wrap(
                                          spacing: 6,
                                          runSpacing: 6,
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                              decoration: BoxDecoration(
                                                color: _getStatusColor(data['status']).withValues(alpha: 0.1),
                                                borderRadius: BorderRadius.circular(30),
                                              ),
                                              child: Text(
                                                data['status'].toString().toUpperCase(),
                                                style: TextStyle(color: _getStatusColor(data['status']), fontWeight: FontWeight.bold, fontSize: 12),
                                              ),
                                            ),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFF16a085).withValues(alpha: 0.1),
                                                borderRadius: BorderRadius.circular(30),
                                              ),
                                              child: Text(
                                                (data['rideTier'] ?? 'tulia').toString().toUpperCase(),
                                                style: const TextStyle(color: Color(0xFF16a085), fontWeight: FontWeight.bold, fontSize: 11),
                                              ),
                                            ),
                                            if (data['createdAt'] != null)
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                                decoration: BoxDecoration(
                                                  color: Colors.grey.shade100,
                                                  borderRadius: BorderRadius.circular(30),
                                                ),
                                                child: Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Icon(Icons.access_time_rounded, size: 12, color: Colors.grey.shade600),
                                                    const SizedBox(width: 4),
                                                    Builder(
                                                      builder: (context) {
                                                        final dt = (data['createdAt'] as Timestamp).toDate();
                                                        final now = DateTime.now();
                                                        final isToday = dt.year == now.year && dt.month == now.month && dt.day == now.day;
                                                        final formatted = isToday
                                                            ? DateFormat('h:mm a').format(dt)
                                                            : DateFormat('MMM d • h:mm a').format(dt);
                                                        return Text(
                                                          formatted,
                                                          style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.bold, fontSize: 11),
                                                        );
                                                      },
                                                    ),
                                                  ],
                                                ),
                                              ),
                                          ],
                                        ),
                                        const SizedBox(height: 10),
                                        // Bottom row: fare aligned right
                                        Align(
                                          alignment: Alignment.centerRight,
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.end,
                                            children: [
                                              Text(
                                                "Fare: KES ${data['fare']}",
                                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green),
                                              ),
                                              if (data['status'] == 'completed') ...[
                                                const SizedBox(height: 2),
                                                Text(
                                                  "You earn: KES ${(data['driverEarnings'] ?? (data['fare'] * 0.75)).toStringAsFixed(0)} (75%)",
                                                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w500),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),

                                    const SizedBox(height: 16),
                                    _buildLocationLine(Icons.radio_button_checked_rounded, Colors.blue, "Pickup Location", data['pickup']),
                                    const Padding(
                                      padding: EdgeInsets.only(left: 11),
                                      child: SizedBox(height: 14, child: VerticalDivider(thickness: 2, width: 2)),
                                    ),
                                    _buildLocationLine(Icons.location_on_rounded, Colors.orange, "Destination Dropoff", data['destination']),
                                    if (data['notes'] != null && data['notes'].toString().isNotEmpty) ...[
                                      const SizedBox(height: 12),
                                      Container(
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: Colors.amber.shade50,
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(color: Colors.amber.shade200),
                                        ),
                                        child: Row(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Icon(Icons.info_outline_rounded, color: Colors.amber.shade800, size: 20),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                "Instructions: ${data['notes']}",
                                                style: TextStyle(color: Colors.amber.shade900, fontSize: 13, fontWeight: FontWeight.w500),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                    const SizedBox(height: 20),
                                    
                                    // Modular Action Controller View Strip
                                    LayoutBuilder(
                                      builder: (context, constraints) {
                                        final isNarrow = constraints.maxWidth < 360;
                                        final primaryButton = ElevatedButton(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.blue.shade600,
                                            foregroundColor: Colors.white,
                                            elevation: 0,
                                            padding: const EdgeInsets.symmetric(vertical: 14),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                          ),
                                          onPressed: ((data['status'] == 'searching' || data['status'] == 'pending') && !isOnline)
                                              ? null
                                              : () async {
                                                  if (data['status'] == 'searching' || data['status'] == 'pending') {
                                                    if (!isOnline) {
                                                      if (!context.mounted) return;
                                                      ScaffoldMessenger.of(context).showSnackBar(
                                                        const SnackBar(content: Text("Go online first to accept rides.")),
                                                      );
                                                      return;
                                                    }
                                                    await rideService.acceptRide(rideId: ride.id);
                                                  } else if (data['status'] == 'accepted') {
                                                    await rideService.startRide(rideId: ride.id);
                                                  } else if (data['status'] == 'started') {
                                                    await rideService.completeRide(rideId: ride.id);
                                                  }
                                                  if (!context.mounted) return;
                                                  ScaffoldMessenger.of(context).showSnackBar(
                                                    const SnackBar(content: Text("Ride track context updated successfully.")),
                                                  );
                                                },
                                          child: Text(
                                            (data['status'] == 'searching' || data['status'] == 'pending') ? (isOnline ? 'Accept Request' : 'Go Online to Accept') : data['status'] == 'accepted' ? 'Start Trip' : 'Complete Trip',
                                            style: const TextStyle(fontWeight: FontWeight.bold),
                                          ),
                                        );
                                        
                                        final iconButtons = Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            IconButton(
                                              style: IconButton.styleFrom(
                                                backgroundColor: Colors.grey.shade100,
                                                foregroundColor: Colors.grey.shade700,
                                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                                padding: const EdgeInsets.all(14),
                                              ),
                                              onPressed: () {
                                                Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(rideId: ride.id)));
                                              },
                                              icon: const Icon(Icons.chat_bubble_outline_rounded, size: 20),
                                              tooltip: "Message Rider",
                                            ),
                                            const SizedBox(width: 8),
                                            IconButton(
                                              style: IconButton.styleFrom(
                                                backgroundColor: Colors.red.shade50,
                                                foregroundColor: Colors.red.shade600,
                                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                                padding: const EdgeInsets.all(14),
                                              ),
                                              onPressed: () => _showCancelDialog(context, ride.id),
                                              icon: const Icon(Icons.close_rounded, size: 20),
                                              tooltip: "Cancel Dispatch",
                                            ),
                                          ],
                                        );

                                        if (isNarrow) {
                                          return Column(
                                            crossAxisAlignment: CrossAxisAlignment.stretch,
                                            children: [
                                              primaryButton,
                                              if (data['status'] != 'completed') ...[
                                                const SizedBox(height: 8),
                                                Row(
                                                  mainAxisAlignment: MainAxisAlignment.end,
                                                  children: [iconButtons],
                                                ),
                                              ],
                                            ],
                                          );
                                        }
                                        
                                        return Row(
                                          children: [
                                            Expanded(child: primaryButton),
                                            if (data['status'] != 'completed') ...[
                                              const SizedBox(width: 8),
                                              iconButtons,
                                            ],
                                          ],
                                        );
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        );
                      },
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Visual Utility View Layout Blocks
  Widget _buildMetricTile({
    required String title,
    required String value,
    required String subtitle,
    required Color backgroundColor,
    required Color accentColor,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: backgroundColor, borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: accentColor, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(title, style: TextStyle(fontSize: 13, color: Colors.grey.shade500, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.grey.shade900)),
                const SizedBox(height: 4),
                Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey.shade600), maxLines: 2, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationLine(IconData icon, Color color, String prefix, String dynamicText) {
    return Row(
      children: [
        Icon(icon, size: 24, color: color),
        const SizedBox(width: 12),
        Expanded(
          child: RichText(
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            text: TextSpan(
              style: const TextStyle(fontSize: 14, color: Colors.black87),
              children: [
                TextSpan(text: "$prefix: ", style: const TextStyle(fontWeight: FontWeight.bold)),
                TextSpan(text: dynamicText),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Color _getStatusColor(String? status) {
    switch (status) {
      case 'searching': return Colors.amber.shade700;
      case 'pending': return Colors.orange.shade700;
      case 'accepted': return Colors.blue.shade700;
      case 'started': return Colors.purple.shade700;
      case 'completed': return Colors.green.shade700;
      default: return Colors.grey.shade700;
    }
  }

  // Context Dialogue Handlers
  void _showEmergencyDialog(BuildContext context) {
    final TextEditingController localSosController = TextEditingController();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.gpp_bad_rounded, color: Colors.red),
            SizedBox(width: 8),
            Text("Emergency SOS Details", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Describe your emergency configuration context below for immediate admin review:"),
            const SizedBox(height: 16),
            TextField(
              controller: localSosController,
              maxLines: 3,
              style: const TextStyle(color: Colors.black),
              decoration: InputDecoration(
                hintText: "State danger situation elements...",
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              String msg = localSosController.text.trim().isEmpty ? "No explicit driver text context notes." : localSosController.text.trim();
              
              final user = FirebaseAuth.instance.currentUser;
              String? userName;
              String? userEmail;
              
              if (user != null) {
                final userDoc = await firestore.collection('users').doc(user.uid).get();
                if (userDoc.exists) {
                  final data = userDoc.data();
                  userName = data?['name'];
                  userEmail = data?['email'] ?? data?['phone'];
                }
              }

              await firestore.collection('emergencies').add({
                'type': 'SOS',
                'userRole': 'driver',
                'userId': user?.uid,
                'userName': userName,
                'userEmail': userEmail,
                'message': msg,
                'createdAt': Timestamp.now(),
                'status': 'active',
              });
              if (!context.mounted) return;
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(backgroundColor: Colors.red, content: Text("🚨 SOS Dispatched!")));
            },
            child: const Text("Send Alert", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showCancelDialog(BuildContext context, String rideId) {
    final TextEditingController localCancelController = TextEditingController();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text("Cancel Ride Confirmation", style: TextStyle(fontWeight: FontWeight.bold)),
        content: TextField(
          controller: localCancelController,
          decoration: const InputDecoration(hintText: "Enter reason for drop context..."),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Go Back")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              String reason = localCancelController.text.trim().isEmpty ? "Driver cancelled trip request." : localCancelController.text.trim();
              await rideService.cancelRide(
                rideId: rideId,
                cancelledBy: FirebaseAuth.instance.currentUser?.email ?? 'Unknown Driver',
                reason: reason,
              );
              if (!context.mounted) return;
              Navigator.pop(context);
            },
            child: const Text("Confirm Cancel", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
/*import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async';
import '../history_screen.dart';
import '../profile_screen.dart';
import '../chat_screen.dart';

import '../../services/user_service.dart';
import '../../services/ride_service.dart';

class DriverHomeScreen extends StatefulWidget {
  const DriverHomeScreen({super.key});

  @override
  State<DriverHomeScreen> createState() =>
      _DriverHomeScreenState();
}

class _DriverHomeScreenState
    extends State<DriverHomeScreen> {

  bool isOnline = false;
  Timer? locationTimer;

  final UserService userService =
      UserService();

  final FirebaseFirestore firestore =
      FirebaseFirestore.instance;

  final RideService rideService =
      RideService();

  final TextEditingController sosMessageController = TextEditingController();
  final TextEditingController driverCancelController = TextEditingController();


  Future<void> toggleDriverStatus() async {

    setState(() {
  isOnline = !isOnline;
});

if (isOnline) {

  await updateLocation();

  locationTimer = Timer.periodic(

    const Duration(seconds: 5),

    (timer) async {

      await updateLocation();
    },
  );

} else {

  locationTimer?.cancel();
}

    final currentUser =
        FirebaseAuth.instance.currentUser;

    if (currentUser != null) {

      await userService.updateDriverStatus(
        uid: currentUser.uid,
        isOnline: isOnline,
      );
    }
  }
  
  Future<void> updateLocation() async {

  bool serviceEnabled;
  LocationPermission permission;

  serviceEnabled =
      await Geolocator
          .isLocationServiceEnabled();

  if (!serviceEnabled) {
    return;
  }

  permission =
      await Geolocator.checkPermission();

  if (permission ==
      LocationPermission.denied) {

    permission =
        await Geolocator.requestPermission();

    if (permission ==
        LocationPermission.denied) {
      return;
    }
  }

  Position position =
      await Geolocator
          .getCurrentPosition();

  final currentUser =
      FirebaseAuth.instance.currentUser;

  if (currentUser != null) {

    await userService.updateDriverLocation(
      uid: currentUser.uid,
      latitude: position.latitude,
      longitude: position.longitude,
    );
    final activeRides =
    await firestore
        .collection('rides')
        .where(
          'driverId',
          isEqualTo:
              FirebaseAuth
                  .instance
                  .currentUser
                  ?.uid,
        )
        .where(
          'status',
          whereIn: [
            'accepted',
            'started',
          ],
        )
        .get();

for (var ride in activeRides.docs) {

  await firestore
      .collection('rides')
      .doc(ride.id)
      .update({

    'driverLatitude':
        position.latitude,

    'driverLongitude':
        position.longitude,
  });
}
  }
}

  @override
  Widget build(BuildContext context) {

    return Scaffold(

      appBar: AppBar(
        title: const Text(
          "Driver Dashboard",
        ),
        centerTitle: true,
        actions: [

  IconButton(

    onPressed: () {

      Navigator.push(

        context,

        MaterialPageRoute(

          builder: (_) =>
              const HistoryScreen(isDriver: true),
        ),
      );
    },

    icon: const Icon(
      Icons.history,
    ),
  ),
  IconButton(

  onPressed: () {

    Navigator.push(

      context,

      MaterialPageRoute(

        builder: (_) =>
            const ProfileScreen(),
      ),
    );
  },

  icon: const Icon(
    Icons.person,
  ),
),
],
      ),

      body: SingleChildScrollView(

        child: Center(

        child: Column(

          mainAxisAlignment:
              MainAxisAlignment.start,

          children: [

            const SizedBox(height: 20),

            Text(

              isOnline
                  ? "You are ONLINE"
                  : "You are OFFLINE",

              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(
  width: double.infinity,
  height: 50,
  child: ElevatedButton.icon(
    onPressed: () {
      // Create a local controller to capture the danger message input
      final TextEditingController sosMessageController = TextEditingController();

      showDialog(
        context: context,
        barrierDismissible: false, // User must choose an action to close it
        builder: (context) {
          return AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.gpp_bad, color: Colors.red),
                SizedBox(width: 8),
                Text("Emergency SOS Details", style: TextStyle(color: Colors.red)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Please quickly describe your emergency situation or danger context below:",
                  style: TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: sosMessageController,
                  maxLines: 3,
                  autofocus: true,
                  style: const TextStyle(color: Colors.black),
                  decoration: InputDecoration(
                    hintText: "e.g., Driver is speeding / I am being threatened / Car breakdown in unsafe area...",
                    hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                    border: const OutlineInputBorder(),
                    focusedBorder: const OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.red, width: 2),
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                onPressed: () async {
                  String emergencyNote = sosMessageController.text.trim();
                  
                  if (emergencyNote.isEmpty) {
                    emergencyNote = "No text message details provided by user.";
                  }

                  // Write data directly to firestore emergencies collection
                  await FirebaseFirestore.instance.collection('emergencies').add({
                    'type': 'SOS',
                    'userRole': 'driver', // Or change dynamically if used on driver side
                    'userId': FirebaseAuth.instance.currentUser?.uid,
                    'message': emergencyNote, // <-- THE NEW FIELD
                    'createdAt': Timestamp.now(),
                    'status': 'active',
                  });

                  Navigator.pop(context); // Close the dialog box

                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      backgroundColor: Colors.red,
                      content: Text("🚨 Emergency SOS Sent to Admin!"),
                    ),
                  );
                },
                child: const Text("Send Alert", style: TextStyle(color: Colors.white)),
              ),
            ],
          );
        },
      );
    },
    style: ElevatedButton.styleFrom(
      backgroundColor: Colors.red,
    ),
    icon: const Icon(Icons.warning, color: Colors.white),
    label: const Text("Emergency SOS", style: TextStyle(color: Colors.white)),
  ),
),
           
            StreamBuilder<DocumentSnapshot>(

  stream: firestore
      .collection('users')
      .doc(
        FirebaseAuth
            .instance
            .currentUser
            ?.uid,
      )
      .snapshots(),

  builder: (context, snapshot) {

    if (!snapshot.hasData) {
      return const SizedBox();
    }

    final data =
        snapshot.data!.data()
            as Map<String, dynamic>;

    return Text(

      "Your Earnings: KES "
      "${data['earnings'] ?? 0}",

      style: const TextStyle(
        fontSize: 22,
        fontWeight:
            FontWeight.bold,
        color: Colors.green,
      ),
    );
  },
),

            const SizedBox(height: 20),

            ElevatedButton(

              onPressed:
                  toggleDriverStatus,

              child: Text(

                isOnline
                    ? "Go Offline"
                    : "Go Online",
              ),
            ),
            StreamBuilder<QuerySnapshot>(

  stream: firestore
      .collection('rides')
      .where(
        'driverId',
        isEqualTo:
            FirebaseAuth
                .instance
                .currentUser
                ?.uid,
      )
      .snapshots(),

  builder: (context, snapshot) {

    if (!snapshot.hasData) {
      return const SizedBox();
    }

    final rides =
        snapshot.data!.docs;

    double totalEarnings = 0;

    int completedTrips = 0;

    int activeTrips = 0;

    for (var ride in rides) {

      final data =
          ride.data()
              as Map<String, dynamic>;

      if (data['status'] == 'completed' && data['fare'] != null) {
        final driverEarnings = (data['driverEarnings'] as num?)?.toDouble() ??
            ((data['fare'] as num).toDouble() * 0.75);
        totalEarnings += driverEarnings;
      }

      if (data['status'] ==
          'completed') {

        completedTrips++;
      }

      if (data['status'] ==
              'accepted' ||

          data['status'] ==
              'started') {

        activeTrips++;
      }
    }

    return Container(

      margin:
          const EdgeInsets.all(10),

      padding:
          const EdgeInsets.all(15),

      decoration: BoxDecoration(

        color: Colors.blue.shade50,

        borderRadius:
            BorderRadius.circular(12),
      ),

      child: Column(

        children: [

          Text(

            "Total Earnings: "
            "KES ${totalEarnings.toStringAsFixed(0)}",

            style: const TextStyle(

              fontSize: 20,
              fontWeight:
                  FontWeight.bold,
            ),
          ),

          const SizedBox(height: 10),

          Text(

            "Completed Trips: "
            "$completedTrips",

            style: const TextStyle(
              fontSize: 18,
            ),
          ),

          const SizedBox(height: 10),

          Text(

            "Active Trips: "
            "$activeTrips",

            style: const TextStyle(
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 10),

FutureBuilder<DocumentSnapshot>(

  future: firestore
      .collection('users')
      .doc(
        FirebaseAuth
            .instance
            .currentUser
            ?.uid,
      )
      .get(),

  builder: (context, snapshot) {

    if (!snapshot.hasData) {

      return const SizedBox();
    }

    final data =
        snapshot.data!.data()
            as Map<String, dynamic>;

    double rating =
        (data['rating'] ?? 0)
            .toDouble();

    int totalRatings =
        data['totalRatings'] ?? 0;

    return Column(

      children: [

        Text(

          "Driver Rating: "
          "${rating.toStringAsFixed(1)} ⭐",

          style: const TextStyle(
            fontSize: 18,
            fontWeight:
                FontWeight.bold,
          ),
        ),

        const SizedBox(height: 8),

        Text(

          "Total Ratings: "
          "$totalRatings",

          style: const TextStyle(
            fontSize: 16,
          ),
        ),
      ],
    );
  },
),
        ],
      ),
    );
  },
),
StreamBuilder<QuerySnapshot>(

  stream: firestore
      .collection('users')
      .where(
        'isOnline',
        isEqualTo: true,
      )
      .snapshots(),

  builder: (context, driverSnapshot) {

    return StreamBuilder<QuerySnapshot>(

      stream: firestore
          .collection('rides')
          .snapshots(),

      builder: (context, rideSnapshot) {

        if (!driverSnapshot.hasData ||
            !rideSnapshot.hasData) {

          return const SizedBox();
        }

        int onlineDrivers =
            driverSnapshot
                .data!
                .docs
                .length;

        int pendingRides = 0;

        int ongoingRides = 0;

        for (var ride
            in rideSnapshot.data!.docs) {

          final data =
              ride.data()
                  as Map<String, dynamic>;

          if (data['status'] ==
              'pending') {

            pendingRides++;
          }

          if (data['status'] ==
                  'accepted' ||

              data['status'] ==
                  'started') {

            ongoingRides++;
          }
        }

        return Container(

          margin:
              const EdgeInsets.symmetric(
            horizontal: 10,
          ),

          padding:
              const EdgeInsets.all(15),

          decoration: BoxDecoration(

            color:
                Colors.green.shade50,

            borderRadius:
                BorderRadius.circular(12),
          ),

          child: Column(

            children: [

              Text(

                "Drivers Online: "
                "$onlineDrivers",

                style: const TextStyle(
                  fontSize: 18,
                  fontWeight:
                      FontWeight.bold,
                ),
              ),

              const SizedBox(height: 10),

              Text(

                "Pending Rides: "
                "$pendingRides",

                style: const TextStyle(
                  fontSize: 18,
                ),
              ),

              const SizedBox(height: 10),

              Text(

                "Ongoing Trips: "
                "$ongoingRides",

                style: const TextStyle(
                  fontSize: 18,
                ),
              ),
            ],
          ),
        );
      },
    );
  },
),

            const SizedBox(height: 40),

            const Text(

              "Pending Ride Requests",

              style: TextStyle(
                fontSize: 22,
                fontWeight:
                    FontWeight.bold,
              ),
            ),

            const SizedBox(height: 20),

SizedBox(

  height: 500,

  child: StreamBuilder(

    stream: firestore
        .collection('rides')
        .snapshots(),

    builder:
        (context, snapshot) {
      

      if (!snapshot.hasData) {

        return const Center(
          child:
              CircularProgressIndicator(),
        );
      }

                  final currentDriverId =
    FirebaseAuth
        .instance
        .currentUser
        ?.uid;

final rides =
    snapshot.data!.docs.where((ride) {

  final data =
      ride.data()
          as Map<String, dynamic>;
  

  // Show pending rides to everyone
  if (data['status'] == 'pending') {
    return true;
  }

  // Show accepted/started rides
  // ONLY to assigned driver
  if ((data['status'] == 'accepted' ||
          data['status'] == 'started') &&

      data['driverId'] ==
          currentDriverId) {

    return true;
  }

  return false;

}).toList();

                  if (rides.isEmpty) {

                    return const Center(

                      child: Text(
                        "No Ride Requests Yet",
                      ),
                    );
                  }

                  return ListView.builder(

                    itemCount:
                        rides.length,

                    itemBuilder:
                        (context, index) {

                      final ride =
                          rides[index];

                      return Card(

  child: ListTile(

    leading: const Icon(
      Icons.local_taxi,
    ),

    title: Text(
      ride['pickup'],
    ),


    subtitle: Column(

  crossAxisAlignment:
      CrossAxisAlignment.start,

  children: [

    Text(
      "Destination: ${ride['destination']}",
    ),

    Text(
      "Status: ${ride['status']}",
    ),

    Text(
      "Fare: KES ${ride['fare']}",
    ),

    const SizedBox(height: 10),

    Row(

      children: [

        Expanded(

          child: ElevatedButton(

            onPressed: () async {

              if (ride['status'] == 'pending') {

                await rideService.acceptRide(
                  rideId: ride.id,
                );

              } else if (
                  ride['status'] == 'accepted') {

                await rideService.startRide(
                  rideId: ride.id,
                );

              } else if (
                  ride['status'] == 'started') {

                await rideService.completeRide(
                  rideId: ride.id,
                );
              }

              ScaffoldMessenger.of(context)
                  .showSnackBar(

                const SnackBar(

                  content: Text(
                    "Ride status updated",
                  ),
                ),
              );
            },

            child: Text(

              ride['status'] == 'pending'
                  ? 'Accept'
                  : ride['status'] == 'accepted'
                      ? 'Start'
                      : 'Complete',
            ),
          ),
        ),

         const SizedBox(width: 8),
if (ride['status'] != 'completed')
  Expanded(
    child: ElevatedButton(
      onPressed: () {
        // Create a local controller to capture the driver's cancellation reason input
        final TextEditingController driverCancelController = TextEditingController();

        showDialog(
          context: context,
          barrierDismissible: false, // Force driver to choose an action
          builder: (context) {
            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.cancel, color: Colors.red),
                  SizedBox(width: 8),
                  Text("Cancel Ride (Driver)"),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Please state your reason for cancelling this trip:",
                    style: TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: driverCancelController,
                    maxLines: 2,
                    autofocus: true,
                    style: const TextStyle(color: Colors.black),
                    decoration: InputDecoration(
                      hintText: "e.g., Heavy traffic, flat tire, rider not responding, location unreachable...",
                      hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                      border: const OutlineInputBorder(),
                      focusedBorder: const OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.red, width: 2),
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Go Back", style: TextStyle(color: Colors.grey)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  onPressed: () async {
                    String driverReason = driverCancelController.text.trim();
                    
                    // Fallback string if the field is submitted empty
                    if (driverReason.isEmpty) {
                      driverReason = "Driver cancelled without details.";
                    }

                    // Execute cancellation function using the driver's context variables
                    await rideService.cancelRide(
                      rideId: ride.id,
                      cancelledBy: FirebaseAuth.instance.currentUser?.email ?? 'Unknown Driver', // Set to driver
                      reason: driverReason, // Pass custom input string
                    );

                    Navigator.pop(context); // Dismiss the alert popup dialog box

                    ScaffoldMessenger.of(context).showSnackBar(
                       SnackBar(
                        backgroundColor: Colors.red,
                        content: Text("Ride Cancelled.\n"
                         "Reason: ${driverReason}"),
                      ),
                    );
                  },
                  child: const Text("Confirm Cancel", style: TextStyle(color: Colors.white)),
                ),
              ],
            );
          },
        );
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.red,
      ),
      child: const Text(
        "Cancel",
        style: TextStyle(color: Colors.white),
      ),
    ),
  ),
        
      ],
    ),

    const SizedBox(height: 8),

    SizedBox(

      width: double.infinity,

      child: ElevatedButton(

        onPressed: () {

          Navigator.push(

            context,

            MaterialPageRoute(

              builder: (_) => ChatScreen(
                rideId: ride.id,
              ),
            ),
          );
        },

        child: const Text(
          "Chat",
        ),
      ),
    ),
  ],
),
  ),
);
                    },
                  );
                                },
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }
}*/
