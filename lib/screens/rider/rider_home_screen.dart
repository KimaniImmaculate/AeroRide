import 'package:flutter/material.dart';
import '../../services/ride_service.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../history_screen.dart';
import '../profile_screen.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'dart:async';
import '../chat_screen.dart';
import 'package:geocoding/geocoding.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../landing_screen.dart';
import '../../services/payment_service.dart';

class RiderHomeScreen extends StatefulWidget {
  const RiderHomeScreen({super.key});

  @override
  State<RiderHomeScreen> createState() => _RiderHomeScreenState();
}

class _RiderHomeScreenState extends State<RiderHomeScreen> {
  // Vibrant Turquoise Theme Color
  static const Color primaryTurquoise = Color(0xFF16A085);

  final TextEditingController pickupController = TextEditingController();
  final TextEditingController destinationController = TextEditingController();
  final RideService rideService = RideService();
  final FirebaseFirestore firestore = FirebaseFirestore.instance;
  final TextEditingController _mpesaPhoneController = TextEditingController();
  final TextEditingController sosMessageController = TextEditingController();
  final TextEditingController cancelReasonController = TextEditingController();

  LatLng? pickupLocation;
  LatLng? destinationLocation;

  bool isLoading = false;
  GoogleMapController? mapController;
  Set<Polyline> polylines = {};
  Set<Marker> markers = {};

  List<LatLng> polylineCoordinates = [];

  PolylinePoints polylinePoints = PolylinePoints(
    apiKey: "AIzaSyDvFvwSP5-BBLhOvzj3o_1UKKkuGfF1y4U",
  );
  String? currentRideId;
  bool selectingPickup = false;
  String? _lastAlertedStatus;

  final CameraPosition initialPosition = const CameraPosition(
    target: LatLng(-0.3031, 36.0800),
    zoom: 14,
  );

  @override
  void initState() {
    super.initState();
    getCurrentLocation();
  }

  Future<void> _handleLogout(BuildContext context) async {
    // 1. Display the Confirmation Alert Dialog first
    final bool? shouldLogout = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1A2522),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: const BorderSide(color: Colors.white24),
          ),
          title: Row(
            children: [
              const Icon(Icons.logout_rounded, color: Colors.redAccent),
              const SizedBox(width: 8),
              Text("Confirm Log Out",
                  style: GoogleFonts.urbanist(
                      color: Colors.white, fontWeight: FontWeight.bold)),
            ],
          ),
          content: Text("Are you sure you want to log out of your session?",
              style: GoogleFonts.urbanist(
                  color: Colors.white.withValues(alpha: 0.7))),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.of(context).pop(false), // Returns false
              child: Text("Cancel",
                  style: TextStyle(
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w600)),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true), // Returns true
              child: Text("OK",
                  style: GoogleFonts.urbanist(
                      color: Colors.redAccent, fontWeight: FontWeight.bold)),
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
        child: CircularProgressIndicator(color: primaryTurquoise),
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
        MaterialPageRoute(builder: (context) => const LandingScreen()),
        (route) => false,
      );
    } catch (e) {
      if (context.mounted)
        Navigator.pop(context); // Dismiss loading spinner on error
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

  List<LatLng> decodePolyline(String encoded) {
    List<LatLng> polyline = [];
    int index = 0;
    int len = encoded.length;
    int lat = 0;
    int lng = 0;

    while (index < len) {
      int shift = 0;
      int result = 0;
      int b;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlat = ((result & 1) != 0) ? ~(result >> 1) : (result >> 1);
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlng = ((result & 1) != 0) ? ~(result >> 1) : (result >> 1);
      lng += dlng;

      polyline.add(
        LatLng(lat / 1E5, lng / 1E5),
      );
    }
    return polyline;
  }

  Future<void> getCurrentLocation() async {
    Position position = await Geolocator.getCurrentPosition();
    String pickupName = await getPlaceName(
      position.latitude,
      position.longitude,
    );

    setState(() {
      pickupLocation = LatLng(
        position.latitude,
        position.longitude,
      );
      pickupController.text = pickupName;
    });
  }

  Future<String> getPlaceName(double latitude, double longitude) async {
    try {
      final url = "https://maps.googleapis.com/maps/api/geocode/json"
          "?latlng=$latitude,$longitude"
          "&key=AIzaSyDvFvwSP5-BBLhOvzj3o_1UKKkuGfF1y4U";

      final response = await http.get(Uri.parse(url));
      print(response.statusCode);
      print(response.body);

      final data = jsonDecode(response.body);

      if (data["results"] != null && data["results"].isNotEmpty) {
        return data["results"][0]["formatted_address"];
      }
      return "Unknown Location";
    } catch (e) {
      print("Geocoding failed: $e");
      return "Unknown Location";
    }
  }

  Future<void> getRoute() async {
    print("GET ROUTE STARTED");
    if (pickupLocation == null || destinationLocation == null) {
      return;
    }

    final url = "https://maps.googleapis.com/maps/api/directions/json"
        "?origin=${pickupLocation!.latitude},${pickupLocation!.longitude}"
        "&destination=${destinationLocation!.latitude},${destinationLocation!.longitude}"
        "&mode=driving"
        "&key=AIzaSyDvFvwSP5-BBLhOvzj3o_1UKKkuGfF1y4U";

    final response = await http.get(Uri.parse(url));
    final data = jsonDecode(response.body);
    print(response.body);
    print("Directions Status: ${data["status"]}");

    if (data["routes"].isEmpty) {
      print("No routes found");
      return;
    }

    String encodedPolyline = data["routes"][0]["overview_polyline"]["points"];
    List<LatLng> routePoints = decodePolyline(encodedPolyline);
    print("Route points: ${routePoints.length}");
    print("Adding polyline...");

    setState(() {
      polylines = {
        Polyline(
          polylineId:
              PolylineId("route_${DateTime.now().millisecondsSinceEpoch}"),
          width: 5,
          color: Theme.of(context).primaryColor,
          points: routePoints,
        ),
      };
    });
    print("Polylines count: ${polylines.length}");

    if (mapController != null && routePoints.isNotEmpty) {
      LatLng boundsSouthWest;
      LatLng boundsNorthEast;

      double minLat = pickupLocation!.latitude < destinationLocation!.latitude
          ? pickupLocation!.latitude
          : destinationLocation!.latitude;
      double maxLat = pickupLocation!.latitude > destinationLocation!.latitude
          ? pickupLocation!.latitude
          : destinationLocation!.latitude;
      double minLng = pickupLocation!.longitude < destinationLocation!.longitude
          ? pickupLocation!.longitude
          : destinationLocation!.longitude;
      double maxLng = pickupLocation!.longitude > destinationLocation!.longitude
          ? pickupLocation!.longitude
          : destinationLocation!.longitude;

      boundsSouthWest = LatLng(minLat, minLng);
      boundsNorthEast = LatLng(maxLat, maxLng);

      mapController!.animateCamera(
        CameraUpdate.newLatLngBounds(
          LatLngBounds(southwest: boundsSouthWest, northeast: boundsNorthEast),
          70,
        ),
      );
    }
  }

  Future<void> requestRide() async {
    setState(() {
      isLoading = true;
    });
    if (pickupLocation == null || destinationLocation == null) {
      setState(() {
        isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Select destination on map"),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    double distanceMeters = Geolocator.distanceBetween(
      pickupLocation!.latitude,
      pickupLocation!.longitude,
      destinationLocation!.latitude,
      destinationLocation!.longitude,
    );

    double distanceKm = distanceMeters / 1000;
    double fare = distanceKm * 20;
    print("Distance: $distanceKm km");
    print("Fare: $fare");

    final rideId = await rideService.requestRide(
      pickup: pickupController.text.trim(),
      destination: destinationController.text.trim(),
      fare: fare,
    );

    currentRideId = rideId;

    setState(() {
      isLoading = false;
    });

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Ride Requested Successfully 🎉"),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.green,
      ),
    );

    pickupController.clear();
    destinationController.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1715), // Deep dark base
      appBar: AppBar(
        backgroundColor: const Color(0xFF131D1A),
        title: Text(
          "Rider Dashboard",
          style: GoogleFonts.urbanist(
              fontWeight: FontWeight.bold, fontSize: 22, color: Colors.white),
        ),
        automaticallyImplyLeading: false,
        elevation: 0,
        centerTitle: true,
        actions: [
          IconButton(
            onPressed: () {
              Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const HistoryScreen()));
            },
            icon: const Icon(Icons.history_rounded, color: Colors.white70),
            tooltip: "Ride History",
          ),
          IconButton(
            onPressed: () {
              Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const ProfileScreen()));
            },
            icon:
                const Icon(Icons.account_circle_rounded, color: Colors.white70),
            tooltip: "Profile Settings",
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: IconButton(
              onPressed: () =>
                  _handleLogout(context), // Triggers the sign-out method
              icon: const Icon(Icons.logout_rounded, color: Colors.redAccent),
              tooltip: "Log Out",
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      // Move Chat to a dedicated prominent button on the bottom right
      floatingActionButton: currentRideId != null
          ? StreamBuilder<DocumentSnapshot>(
              stream:
                  firestore.collection('rides').doc(currentRideId).snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData || !snapshot.data!.exists)
                  return const SizedBox.shrink();
                final data = snapshot.data!.data() as Map<String, dynamic>;
                final status = data['status'];

                // Only show chat if a driver is assigned or trip is in progress
                if (status == 'accepted' || status == 'started') {
                  return FloatingActionButton.extended(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => ChatScreen(rideId: currentRideId!)),
                    ),
                    backgroundColor: primaryTurquoise,
                    icon: const Icon(Icons.chat_bubble_rounded,
                        color: Colors.white),
                    label: Text("Chat",
                        style: GoogleFonts.urbanist(
                            fontWeight: FontWeight.bold, color: Colors.white)),
                  );
                }
                return const SizedBox.shrink();
              },
            )
          : null,
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // --- FIRESTORE STREAM (MARKER UPDATES) ---
              SizedBox(
                height: 0.1,
                child: StreamBuilder<QuerySnapshot>(
                  stream: firestore.collection('users').snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.hasData) {
                      Set<Marker> updatedMarkers = {};

                      if (pickupLocation != null) {
                        updatedMarkers.add(
                          Marker(
                            markerId: const MarkerId('pickup'),
                            position: pickupLocation!,
                            icon: BitmapDescriptor.defaultMarkerWithHue(
                                BitmapDescriptor.hueGreen),
                            infoWindow:
                                const InfoWindow(title: 'Pickup Location'),
                          ),
                        );
                      }

                      if (destinationLocation != null) {
                        updatedMarkers.add(
                          Marker(
                            markerId: const MarkerId('destination'),
                            position: destinationLocation!,
                            infoWindow:
                                const InfoWindow(title: 'Destination Target'),
                          ),
                        );
                      }

                      for (var doc in snapshot.data!.docs) {
                        final data = doc.data() as Map<String, dynamic>;
                        if (data['latitude'] != null &&
                            data['longitude'] != null &&
                            data['isOnline'] == true &&
                            pickupLocation != null) {
                          double distance = Geolocator.distanceBetween(
                            pickupLocation!.latitude,
                            pickupLocation!.longitude,
                            (data['latitude'] as num).toDouble(),
                            (data['longitude'] as num).toDouble(),
                          );

                          if (distance <= 5000) {
                            updatedMarkers.add(
                              Marker(
                                markerId: MarkerId(doc.id),
                                position: LatLng(
                                  double.parse(data['latitude'].toString()),
                                  double.parse(data['longitude'].toString()),
                                ),
                                icon: BitmapDescriptor.defaultMarkerWithHue(
                                    BitmapDescriptor.hueBlue),
                                infoWindow: InfoWindow(title: data['email']),
                              ),
                            );
                          }
                        }
                      }

                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) {
                          setState(() {
                            markers = updatedMarkers;
                          });
                        }
                      });
                    }
                    return const SizedBox.shrink();
                  },
                ),
              ),

              // --- PERMANENT INDEPENDENT MAP VIEWPORT (HCI CARD UPGRADE) ---
              Container(
                height: 380,
                decoration: BoxDecoration(
                  color: const Color(0xFF1A2522),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: Colors.white10,
                    width: 1.0,
                  ),
                ),
                child: GoogleMap(
                  initialCameraPosition: initialPosition,
                  mapType: MapType.normal,
                  myLocationEnabled: true,
                  myLocationButtonEnabled: true,
                  onMapCreated: (controller) {
                    mapController = controller;
                  },
                  markers: markers,
                  polylines: polylines,
                  onTap: (LatLng position) async {
                    if (selectingPickup) {
                      String placeName = await getPlaceName(
                          position.latitude, position.longitude);
                      setState(() {
                        pickupLocation = position;
                        pickupController.text = placeName;
                        selectingPickup = false;
                      });

                      // Re-calculate route if destination is already set
                      if (destinationLocation != null) {
                        WidgetsBinding.instance
                            .addPostFrameCallback((_) => getRoute());
                      }
                      return;
                    }

                    String placeName = await getPlaceName(
                        position.latitude, position.longitude);
                    setState(() {
                      destinationLocation = position;
                      destinationController.text = placeName;
                    });

                    // Calculate route after state is committed
                    WidgetsBinding.instance
                        .addPostFrameCallback((_) => getRoute());
                  },
                ),
              ),
              const SizedBox(height: 24),

              // --- INPUT ADAPTIVE SECTION CARD ---
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      TextField(
                        controller: pickupController,
                        readOnly: true,
                        onTap: () {
                          showModalBottomSheet(
                            context: context,
                            shape: const RoundedRectangleBorder(
                              borderRadius: BorderRadius.vertical(
                                  top: Radius.circular(20)),
                            ),
                            builder: (context) {
                              return SafeArea(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const SizedBox(height: 8),
                                    Container(
                                        width: 40,
                                        height: 4,
                                        decoration: BoxDecoration(
                                            color: Colors.grey.shade300,
                                            borderRadius:
                                                BorderRadius.circular(2))),
                                    ListTile(
                                      leading: const Icon(
                                          Icons.my_location_rounded,
                                          color: Colors.blue),
                                      title: const Text("Use Current Location",
                                          style: TextStyle(
                                              fontWeight: FontWeight.w600)),
                                      onTap: () {
                                        Navigator.pop(context);
                                        getCurrentLocation();
                                      },
                                    ),
                                    ListTile(
                                      leading: const Icon(Icons.map_rounded,
                                          color: Colors.green),
                                      title: const Text("Select point from Map",
                                          style: TextStyle(
                                              fontWeight: FontWeight.w600)),
                                      onTap: () {
                                        Navigator.pop(context);
                                        selectingPickup = true;
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                                "Tap a pickup point on the map"),
                                            behavior: SnackBarBehavior.floating,
                                          ),
                                        );
                                      },
                                    ),
                                  ],
                                ),
                              );
                            },
                          );
                        },
                        decoration: InputDecoration(
                          labelText: "Pickup From",
                          prefixIcon: const Icon(Icons.location_on,
                              color: Colors.green),
                          filled: true,
                          fillColor: Colors.grey.shade50,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: destinationController,
                        decoration: InputDecoration(
                          labelText: "Drop-off Destination",
                          prefixIcon: const Icon(Icons.flag_rounded,
                              color: Colors.redAccent),
                          filled: true,
                          fillColor: Colors.grey.shade50,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              if (destinationLocation != null) ...[
                const SizedBox(height: 12),
                Chip(
                  avatar: const Icon(Icons.pin_drop_outlined,
                      size: 16, color: Colors.grey),
                  label: Text(
                    "Coordinates: ${destinationLocation!.latitude.toStringAsFixed(4)}, ${destinationLocation!.longitude.toStringAsFixed(4)}",
                    style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                  ),
                  backgroundColor: Colors.grey.shade100,
                ),
              ],

              // --- ACTIVE TRIP MONITORING SYSTEM ---
              StreamBuilder<DocumentSnapshot>(
                stream: firestore
                    .collection('rides')
                    .doc(currentRideId)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) return const SizedBox.shrink();

                  final ride = snapshot.data!;
                  if (!ride.exists || ride.data() == null)
                    return const SizedBox.shrink();

                  final data = ride.data() as Map<String, dynamic>;
                  final currentStatus = data['status']?.toString();

                  // --- SIDE EFFECTS GATEKEEPER (Triggers exactly ONCE per status shift) ---
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (currentStatus != _lastAlertedStatus) {
                      _lastAlertedStatus =
                          currentStatus; // Lock state immediately

                      if (currentStatus == 'accepted') {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            backgroundColor: Colors.green,
                            behavior: SnackBarBehavior.floating,
                            duration: Duration(seconds: 4),
                            content: Text("Driver accepted your ride 🚖",
                                style: TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.bold)),
                          ),
                        );
                      } else if (currentStatus == 'cancelled') {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            backgroundColor: Colors.red,
                            behavior: SnackBarBehavior.floating,
                            duration: Duration(seconds: 5),
                            content: Text("🚨 This trip has been cancelled!",
                                style: TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.bold)),
                          ),
                        );
                      } else if (currentStatus == 'started') {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            backgroundColor: Colors.blue,
                            behavior: SnackBarBehavior.floating,
                            duration: Duration(seconds: 4),
                            content: Text("Trip started successfully 🛣️",
                                style: TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.bold)),
                          ),
                        );
                      } else if (currentStatus == 'completed') {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            backgroundColor: Colors.purple,
                            behavior: SnackBarBehavior.floating,
                            duration: Duration(seconds: 4),
                            content: Text("Trip completed ✅",
                                style: TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.bold)),
                          ),
                        );
                      }
                    }
                  });

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 12),
                      // --- 1. ESTIMATED FARE (Priority Top Position) ---
                      if (data['fare'] != null)
                        _ProfessionalCard(
                          color: primaryTurquoise.withValues(alpha: 0.15),
                          borderColor: primaryTurquoise.withValues(alpha: 0.3),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text("Estimated Fare",
                                  style: GoogleFonts.urbanist(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600)),
                              Text("KES ${data['fare']}",
                                  style: GoogleFonts.urbanist(
                                      fontSize: 24,
                                      fontWeight: FontWeight.w900,
                                      color: primaryTurquoise)),
                            ],
                          ),
                        ),

                      const SizedBox(height: 12),
                      // --- 2. TRIP STATUS ---
                      _ProfessionalCard(
                        color: currentStatus == 'cancelled'
                            ? Colors.red.withValues(alpha: 0.1)
                            : const Color(0xFF1A2522),
                        child: Text(
                          "STATUS: ${currentStatus?.toUpperCase()}",
                          textAlign: TextAlign.center,
                          style: GoogleFonts.urbanist(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2,
                            color: currentStatus == 'cancelled'
                                ? Colors.redAccent
                                : primaryTurquoise,
                          ),
                        ),
                      ),
                      if (currentStatus == 'cancelled') ...[
                        _ProfessionalCard(
                          color: Colors.red.withValues(alpha: 0.05),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                children: const [
                                  Icon(Icons.error_outline_rounded,
                                      color: Colors.red),
                                  SizedBox(width: 8),
                                  Text(
                                    "Trip Cancelled",
                                    style: TextStyle(
                                        color: Colors.redAccent,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                "This ride was cancelled by: ${data['cancelledBy'] ?? 'system'}.\n\n"
                                "Reason: ${data['cancelReason'] ?? 'No specific reason provided.'}",
                                style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.7),
                                    fontSize: 14,
                                    height: 1.4),
                              ),
                            ],
                          ),
                        ),
                      ],

                      if (data['driverEmail'] != null) ...[
                        const SizedBox(height: 12),
                        ListTile(
                          leading: const CircleAvatar(
                              child: Icon(Icons.directions_car_filled_rounded)),
                          title: const Text("Assigned Driver"),
                          subtitle: Text("${data['driverEmail']}",
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold)),
                          tileColor: Colors.grey.shade100,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ],

                      if (data['driverLatitude'] != null &&
                          data['driverLongitude'] != null &&
                          pickupLocation != null) ...[
                        const SizedBox(height: 16),
                        // --- 3. DISTANCE & ETA ---
                        _ProfessionalCard(
                          color: Colors.blue.withValues(alpha: 0.1),
                          borderColor: Colors.blue.withValues(alpha: 0.2),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8.0),
                            child: Builder(
                              builder: (context) {
                                double distance = Geolocator.distanceBetween(
                                  pickupLocation!.latitude,
                                  pickupLocation!.longitude,
                                  (data['driverLatitude'] as num).toDouble(),
                                  (data['driverLongitude'] as num).toDouble(),
                                );
                                double distanceKm = distance / 1000;
                                double etaMinutes = distanceKm * 2;

                                return Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceAround,
                                  children: [
                                    Column(
                                      children: [
                                        Text("DISTANCE",
                                            style: GoogleFonts.urbanist(
                                                fontSize: 11,
                                                color: Colors.white54)),
                                        const SizedBox(height: 4),
                                        Text(
                                            "${distanceKm.toStringAsFixed(2)} km",
                                            style: GoogleFonts.urbanist(
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.white)),
                                      ],
                                    ),
                                    Container(
                                        width: 1,
                                        height: 30,
                                        color: Colors.white12),
                                    Column(
                                      children: [
                                        Text("ESTIMATED ETA",
                                            style: GoogleFonts.urbanist(
                                                fontSize: 11,
                                                color: Colors.white54)),
                                        const SizedBox(height: 4),
                                        Text(
                                            "${etaMinutes.toStringAsFixed(0)} mins",
                                            style: GoogleFonts.urbanist(
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                                color: primaryTurquoise)),
                                      ],
                                    ),
                                  ],
                                );
                              },
                            ),
                          ),
                        ),
                      ],

                      if (data['driverEmail'] != null) ...[
                        const SizedBox(height: 12),
                        // --- 4. DRIVER INFO ---
                        _ProfessionalCard(
                          child: ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const CircleAvatar(
                                backgroundColor: primaryTurquoise,
                                child: Icon(Icons.directions_car_filled_rounded,
                                    color: Colors.white)),
                            title: const Text("Assigned Driver",
                                style: TextStyle(
                                    color: Colors.white70, fontSize: 12)),
                            subtitle: Text("${data['driverEmail']}",
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16)),
                          ),
                        ),
                      ],

                      // --- 5. ACTION BAR (SOS & CANCEL RIDE) ---
                      if (data['status'] == 'pending' ||
                          data['status'] == 'accepted' ||
                          data['status'] == 'started') ...[
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: _TripActionButton(
                                label: "SOS",
                                icon: Icons.gpp_bad_rounded,
                                color: Colors.redAccent,
                                onTap: () => _showEmergencyDialog(context),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _TripActionButton(
                                label: "Cancel Ride",
                                icon: Icons.close_rounded,
                                color: Colors.white70,
                                onTap: () => _showCancelRideDialog(context),
                              ),
                            ),
                          ],
                        ),
                      ],

                      if (data['status'] == 'completed') ...[
                        const SizedBox(height: 16),
                        StreamBuilder<DocumentSnapshot>(
                          stream: FirebaseFirestore.instance
                              .collection('rides')
                              .doc(currentRideId ?? data['rideId'])
                              .snapshots(),
                          builder: (context, snapshot) {
                            if (!snapshot.hasData || !snapshot.data!.exists) {
                              return const Center(
                                  child: CircularProgressIndicator(
                                      color: Colors.green));
                            }

                            var liveData =
                                snapshot.data!.data() as Map<String, dynamic>;
                            String currentPaymentStatus =
                                liveData['paymentStatus'] ?? 'pending';

                            if (currentPaymentStatus == 'paid' ||
                                currentPaymentStatus == 'completed') {
                              return _ProfessionalCard(
                                color: Colors.green.withValues(alpha: 0.1),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: const [
                                    Icon(Icons.check_circle_rounded,
                                        color: Colors.green, size: 24),
                                    SizedBox(width: 10),
                                    Text(
                                      "Payment Received: PAID",
                                      style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.green),
                                    ),
                                  ],
                                ),
                              );
                            }

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.pending_actions,
                                        color: Colors.orangeAccent),
                                    const SizedBox(width: 8),
                                    Text(
                                      "Payment: Collection Pending",
                                      style: GoogleFonts.urbanist(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.orangeAccent),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                TextField(
                                  controller: _mpesaPhoneController,
                                  keyboardType: TextInputType.phone,
                                  style:
                                      GoogleFonts.urbanist(color: Colors.white),
                                  decoration: InputDecoration(
                                    labelText: "M-Pesa Mobile Number",
                                    labelStyle:
                                        const TextStyle(color: Colors.white38),
                                    prefixIcon: const Icon(Icons.phone_android,
                                        color: Colors.green),
                                    border: OutlineInputBorder(
                                        borderRadius:
                                            BorderRadius.circular(12)),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                ElevatedButton(
                                  onPressed: () async {
                                    String enteredPhone =
                                        _mpesaPhoneController.text.trim();

                                    if (enteredPhone.isEmpty) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                              '📱 Please enter an M-Pesa phone number first'),
                                          backgroundColor: Colors.orange,
                                        ),
                                      );
                                      return;
                                    }

                                    double actualFare = 1.0;
                                    if (liveData['fare'] != null) {
                                      actualFare = double.tryParse(
                                              liveData['fare'].toString()) ??
                                          1.0;
                                    }

                                    String activeRideId = currentRideId ??
                                        liveData['rideId'] ??
                                        "UNKNOWN_RIDE";
                                    print(
                                        "DEBUG: Dispatching STK to Backend -> Fare: $actualFare, RideID: $activeRideId");

                                    // 1. Display the processing loading circle
                                    showDialog(
                                      context: context,
                                      barrierDismissible: false,
                                      builder: (context) => const Center(
                                        child: CircularProgressIndicator(
                                            color: primaryTurquoise),
                                      ),
                                    );

                                    // 2. Fire request and await the long-polling result string from backend
                                    String paymentResult =
                                        await PaymentService.requestMpesaPrompt(
                                      rawPhone: enteredPhone,
                                      amount: actualFare,
                                      context: context,
                                    );

                                    // 3. Safely dismiss the loading dialog box
                                    if (context.mounted) Navigator.pop(context);

                                    // 4. Act dynamically based on what the phone user did
                                    if (paymentResult == 'COMPLETED') {
                                      // Update Cloud Firestore database. This triggers the StreamBuilder instantly!
                                      await FirebaseFirestore.instance
                                          .collection('rides')
                                          .doc(activeRideId)
                                          .update({'paymentStatus': 'paid'});

                                      if (!context.mounted) return;
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                              "✅ Payment Received Successfully!"),
                                          backgroundColor: Colors.green,
                                        ),
                                      );
                                    } else if (paymentResult == 'FAILED') {
                                      if (!context.mounted) return;
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                              "❌ Transaction Failed or Canceled by user."),
                                          backgroundColor: Colors.red,
                                        ),
                                      );
                                    } else {
                                      if (!context.mounted) return;
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                              "⏳ Request timed out. Verify your balance and try again."),
                                          backgroundColor: Colors.amber,
                                        ),
                                      );
                                    }
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: primaryTurquoise,
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 14),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(12)),
                                  ),
                                  child: Text(
                                    "Pay via M-Pesa Express",
                                    style: GoogleFonts.urbanist(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 12),
                        ElevatedButton.icon(
                          onPressed: () {
                            showDialog(
                              context: context,
                              builder: (context) {
                                double rating = 5;
                                return AlertDialog(
                                  backgroundColor: const Color(0xFF1A2522),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(24),
                                      side: const BorderSide(
                                          color: Colors.white12)),
                                  title: Text("Rate Driver",
                                      style: GoogleFonts.urbanist(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold)),
                                  content: StatefulBuilder(
                                    builder: (context, setDialogState) {
                                      return Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Slider(
                                            activeColor: primaryTurquoise,
                                            inactiveColor: Colors.white12,
                                            value: rating,
                                            min: 1,
                                            max: 5,
                                            divisions: 4,
                                            label: rating.toString(),
                                            onChanged: (value) {
                                              setDialogState(() {
                                                rating = value;
                                              });
                                            },
                                          ),
                                          Text("${rating.toInt()} / 5 Stars",
                                              style: GoogleFonts.urbanist(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.bold)),
                                        ],
                                      );
                                    },
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(context),
                                      child: Text("Cancel",
                                          style: GoogleFonts.urbanist(
                                              color: Colors.grey)),
                                    ),
                                    ElevatedButton(
                                      onPressed: () async {
                                        await firestore
                                            .collection('rides')
                                            .doc(currentRideId)
                                            .update({
                                          'rating': rating.toInt(),
                                        });

                                        await rideService.updateDriverRating(
                                          driverId: data['driverId'],
                                        );

                                        Navigator.pop(context);
                                      },
                                      child: Text("Submit Rating",
                                          style: GoogleFonts.urbanist(
                                              fontWeight: FontWeight.bold)),
                                    ),
                                  ],
                                );
                              },
                            );
                          },
                          icon: const Icon(Icons.star_rate_rounded),
                          label: Text("Rate Driver",
                              style: GoogleFonts.urbanist(
                                  fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 12)),
                        ),
                      ],
                    ],
                  );
                },
              ),

              // --- BASE EXECUTION ROUTING TRIGGER (DEFAULT VIEW) ---
              const SizedBox(height: 16),
              if (currentRideId == null)
                SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: isLoading ? null : requestRide,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryTurquoise,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                    child: isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : Text("Confirm & Request Ride",
                            style: GoogleFonts.urbanist(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showEmergencyDialog(BuildContext context) {
    final TextEditingController localSosController = TextEditingController();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1A2522),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
              side: const BorderSide(color: Colors.white12)),
          title: Row(
            children: [
              const Icon(Icons.gpp_bad_rounded, color: Colors.red),
              const SizedBox(width: 8),
              Text("Emergency SOS Details",
                  style: GoogleFonts.urbanist(
                      color: Colors.red, fontWeight: FontWeight.bold)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Please describe the danger context below:",
                  style: GoogleFonts.urbanist(
                      fontSize: 14, color: Colors.white70)),
              const SizedBox(height: 12),
              TextField(
                controller: localSosController,
                maxLines: 3,
                autofocus: true,
                style: GoogleFonts.urbanist(color: Colors.white),
                decoration: InputDecoration(
                  hintText: "e.g., Car breakdown in unsafe area...",
                  hintStyle:
                      TextStyle(color: Colors.grey.shade400, fontSize: 13),
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
              child: Text("Cancel",
                  style: GoogleFonts.urbanist(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () async {
                String note = localSosController.text.trim();
                await FirebaseFirestore.instance.collection('emergencies').add({
                  'type': 'SOS',
                  'userRole': 'rider',
                  'message': note.isEmpty ? "No details provided" : note,
                  'createdAt': Timestamp.now(),
                  'status': 'active',
                });
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    backgroundColor: Colors.red,
                    content: Text("🚨 SOS Sent to Admin!")));
              },
              child: Text("Send Alert",
                  style: GoogleFonts.urbanist(
                      color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  void _showCancelRideDialog(BuildContext context) {
    final TextEditingController reasonController = TextEditingController();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1A2522),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
              side: const BorderSide(color: Colors.white12)),
          title: Row(
            children: [
              const Icon(Icons.cancel_outlined, color: Colors.red),
              const SizedBox(width: 8),
              Text("Cancel Ride",
                  style: GoogleFonts.urbanist(
                      color: Colors.white, fontWeight: FontWeight.bold)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text("State your reason for cancelling:",
                  style: GoogleFonts.urbanist(color: Colors.white70)),
              const SizedBox(height: 12),
              TextField(
                controller: reasonController,
                style: GoogleFonts.urbanist(color: Colors.white),
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: "Driver too far...",
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Back")),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () async {
                await rideService.cancelRide(
                  rideId: currentRideId!,
                  cancelledBy:
                      FirebaseAuth.instance.currentUser?.email ?? 'Rider',
                  reason: reasonController.text.trim(),
                );
                Navigator.pop(context);
              },
              child: const Text("Confirm"),
            ),
          ],
        );
      },
    );
  }
}

/// Reusable Professional Material Card
class _ProfessionalCard extends StatelessWidget {
  final Widget child;
  final Color? color;
  final Color? borderColor;

  const _ProfessionalCard({required this.child, this.color, this.borderColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color ?? const Color(0xFF1A2522),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: borderColor ?? Colors.white.withValues(alpha: 0.08),
            width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: child,
    );
  }
}

/// Horizontal Action Button
class _TripActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _TripActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 8),
            Text(label,
                style: GoogleFonts.urbanist(
                    color: Colors.white, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}

InputDecoration _inputDecoration(String label, IconData icon, Color iconColor) {
  return InputDecoration(
    labelText: label,
    labelStyle:
        GoogleFonts.urbanist(color: Colors.white.withValues(alpha: 0.4)),
    prefixIcon: Icon(icon, color: iconColor),
    filled: true,
    fillColor: Colors.black.withValues(alpha: 0.2),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: Color(0xFF16A085), width: 2),
    ),
  );
}

Future<void> triggerMpesaStkPush({
  required BuildContext context,
  required String phoneNumber,
  required double amount,
  required String rideId,
}) async {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) => const Center(
      child: Card(
        child: Padding(
          padding: EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: Colors.green),
              SizedBox(height: 16),
              Text("Sending M-Pesa STK Prompt...",
                  style: TextStyle(fontWeight: FontWeight.w500)),
              SizedBox(height: 4),
              Text("Complete processing authorization on phone",
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
        ),
      ),
    ),
  );

  try {
    final HttpsCallable callable =
        FirebaseFunctions.instance.httpsCallable('initiateStkPush');
    final response = await callable.call({
      'phoneNumber': phoneNumber,
      'amount': amount,
      'rideId': rideId,
    });

    Navigator.pop(context);

    if (response.data['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('📱 M-Pesa Prompt sent successfully! Check your phone.'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  } catch (e) {
    Navigator.pop(context);
    print("M-Pesa Trigger Error: $e");
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('❌ Failed to trigger M-Pesa prompt: $e'),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
