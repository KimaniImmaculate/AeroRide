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
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'dart:js_interop';
import 'dart:developer' as dev;
import 'dart:js_interop_unsafe';
import '../../gateway_portal.dart';
import '../../services/payment_service.dart';
import '../auth/Login_screen.dart';

class RiderHomeScreen extends StatefulWidget {
  const RiderHomeScreen({super.key});

  @override
  State<RiderHomeScreen> createState() => _RiderHomeScreenState();
}

class _RiderHomeScreenState extends State<RiderHomeScreen> {
  // Vibrant Turquoise Theme Color
  static const Color primaryTurquoise = Color(0xFF16A085);

  static const String _googleMapsApiKey =
      "AIzaSyANuwPwm1dRFvh_ySIIiW22-dWnUsMrp0k";

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
  Set<Polyline> _polylines = {};
  Set<Marker> markers = {};
  Set<Marker> _driverMarkers = {};
  StreamSubscription<QuerySnapshot>? _driverSubscription;

  List<LatLng> polylineCoordinates = [];

  PolylinePoints polylinePoints = PolylinePoints(
    apiKey: _googleMapsApiKey,
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
    _signInAnonymouslyIfNeeded();
    getCurrentLocation();
    _startDriverListener();
  }

  /// Signs in the user as a guest if they are not already logged in.
  Future<void> _signInAnonymouslyIfNeeded() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      try {
        await FirebaseAuth.instance.signInAnonymously();
        dev.log("RIDER_LOG: Signed in anonymously.");
      } catch (e) {
        dev.log("RIDER_LOG: Anonymous sign-in failed", error: e);
      }
    }
    setState(() {}); // Refresh UI to reflect guest/user status
  }

  @override
  void dispose() {
    _driverSubscription?.cancel();
    pickupController.dispose();
    destinationController.dispose();
    _mpesaPhoneController.dispose();
    sosMessageController.dispose();
    cancelReasonController.dispose();
    super.dispose();
  }

  /// Centralized marker management to prevent markers from disappearing
  void _syncMarkers() {
    if (!mounted) return;
    setState(() {
      markers = {
        if (pickupLocation != null)
          Marker(
            markerId: const MarkerId('pickup'),
            position: pickupLocation!,
            icon: BitmapDescriptor.defaultMarkerWithHue(
                BitmapDescriptor.hueGreen),
            infoWindow: const InfoWindow(title: "My Location"),
          ),
        if (destinationLocation != null)
          Marker(
            markerId: const MarkerId('destination'),
            position: destinationLocation!,
            icon:
                BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
            infoWindow: const InfoWindow(title: "Destination"),
          ),
        ..._driverMarkers,
      };
    });
  }

  void _startDriverListener() {
    _driverSubscription =
        firestore.collection('users').snapshots().listen((snapshot) {
      if (!mounted) return;

      Set<Marker> updatedDriverMarkers = {};
      for (var doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>?;
        if (data != null &&
            data['latitude'] != null &&
            data['longitude'] != null &&
            data['isOnline'] == true) {
          try {
            double driverLat = (data['latitude'] as num).toDouble();
            double driverLng = (data['longitude'] as num).toDouble();

            double distance = 10000; // Default large distance
            if (pickupLocation != null) {
              distance = Geolocator.distanceBetween(
                pickupLocation!.latitude,
                pickupLocation!.longitude,
                driverLat,
                driverLng,
              );
            }

            if (distance <= 5000 || pickupLocation == null) {
              updatedDriverMarkers.add(
                Marker(
                  markerId: MarkerId("driver_${doc.id}"),
                  position: LatLng(driverLat, driverLng),
                  icon: BitmapDescriptor.defaultMarkerWithHue(
                      BitmapDescriptor.hueBlue),
                  infoWindow: InfoWindow(
                      title: "Driver: ${data['email']?.split('@')[0]}"),
                ),
              );
            }
          } catch (e) {
            debugPrint("Error parsing driver loc: $e");
            dev.log("RIDER_LOG: Error parsing driver loc", error: e);
          }
        }
      }

      _driverMarkers = updatedDriverMarkers;
      _syncMarkers();
    });
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
        MaterialPageRoute(builder: (context) => const AeroRideGatewayPortal()),
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
      _syncMarkers();
    });
  }

  Future<String> getPlaceName(double latitude, double longitude) async {
    if (kIsWeb) {
      final completer = Completer<String>();
      void handleGeocodeResponse(JSString address, JSString status) {
        completer.complete(address.toDart);
      }

      globalContext.callMethodVarArgs(
        'aerorideGetPlaceName'.toJS,
        [
          latitude.toJS,
          longitude.toJS,
          _googleMapsApiKey.toJS,
          handleGeocodeResponse.toJS,
        ],
      );
      return completer.future;
    }

    try {
      final url = "https://maps.googleapis.com/maps/api/geocode/json"
          "?latlng=$latitude,$longitude"
          "&key=$_googleMapsApiKey";

      final response = await http.get(Uri.parse(url));
      dev.log("RIDER_LOG: Geocode status: ${response.statusCode}");

      final data = jsonDecode(response.body);

      if (data["results"] != null && data["results"].isNotEmpty) {
        return data["results"][0]["formatted_address"];
      }
      return "Unknown Location";
    } catch (e) {
      dev.log("RIDER_LOG: Geocoding failed", error: e);
      return "Unknown Location";
    }
  }

  Future<void> getRoute() async {
    debugPrint("RIDER_LOG: GET ROUTE STARTED");
    if (pickupLocation == null || destinationLocation == null) {
      return;
    }

    if (kIsWeb) {
      void handleDirectionsResponse(
          JSString? jsonString, JSString? status) async {
        try {
          final dartStatus = status?.toDart ?? 'ERROR';
          final dartJson = jsonString?.toDart ?? '{}';
          dev.log("RIDER_LOG: JS Interop Status: $dartStatus");

          if (dartStatus == 'OK' && dartJson != '{}') {
            final data = jsonDecode(dartJson) as Map<String, dynamic>;
            final List? routes = data["routes"];

            if (routes != null && routes.isNotEmpty) {
              final polylineData = routes[0]["overview_polyline"];

              // STRATEGY 1: Use pre-decoded list from JS (most robust for Web)
              final List? pointsListRaw = polylineData?["points_list"];
              if (pointsListRaw != null && pointsListRaw.isNotEmpty) {
                try {
                  List<LatLng> routePoints = [];
                  for (final p in pointsListRaw) {
                    // Defensive parsing: check if p is a Map and contains 'lat'/'lng'
                    if (p is Map<Object?, Object?>) {
                      final lat = p['lat'];
                      final lng = p['lng'];
                      if (lat is num && lng is num) {
                        routePoints.add(LatLng(lat.toDouble(), lng.toDouble()));
                      } else {
                        dev.log(
                            "RIDER_LOG: Invalid lat/lng type in pointsList item: $p");
                      }
                    } else {
                      dev.log(
                          "RIDER_LOG: Unexpected item type in pointsList: $p");
                    }
                  }

                  if (routePoints.isNotEmpty) {
                    await Future.delayed(const Duration(milliseconds: 100));
                    _updateRouteUI(routePoints);
                    return; // Successfully updated from JS pointsList
                  } else {
                    dev.log(
                        "RIDER_LOG: Parsed pointsList was empty after filtering. Attempting encoded string fallback.");
                  }
                } catch (e, stack) {
                  dev.log("RIDER_LOG: Error during pointsList parsing from JS",
                      error: e, stackTrace: stack);
                  // Fall through to encoded string or straight line fallback
                }
              }

              // STRATEGY 2: Falling back to string decoding (inside try-catch)
              final String? encoded = polylineData?["points"];
              if (encoded != null && encoded.isNotEmpty) {
                try {
                  List<LatLng> decoded = decodePolyline(encoded);
                  if (decoded.isNotEmpty) {
                    await Future.delayed(const Duration(milliseconds: 100));
                    _updateRouteUI(decoded);
                    return; // Successfully updated from encoded string
                  } else {
                    dev.log(
                        "RIDER_LOG: decodePolyline returned empty list. Falling back to straight line.");
                  }
                } catch (e, stack) {
                  dev.log("RIDER_LOG: Error during decodePolyline fallback",
                      error: e, stackTrace: stack);
                  // Fall through to straight line fallback
                }
              }

              // Final fallback if all else fails
              dev.log(
                  "RIDER_LOG: All polyline decoding strategies failed. Drawing straight line.");
              await Future.delayed(const Duration(milliseconds: 100));
              _updateRouteUI([pickupLocation!, destinationLocation!]);
              return;
            } else {
              dev.log("RIDER_LOG: Routes array empty despite OK status.");
              await Future.delayed(const Duration(milliseconds: 100));
              _updateRouteUI([pickupLocation!, destinationLocation!]);
            }
          } else {
            dev.log("RIDER_LOG: Directions failed via JS: $dartStatus");
            if (dartStatus == 'ZERO_RESULTS' && mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                      "No driving route found. Showing direct path instead."),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }
            // Fallback for failed API status
            await Future.delayed(const Duration(milliseconds: 100));
            _updateRouteUI([pickupLocation!, destinationLocation!]);
          }
        } catch (e, stack) {
          dev.log("RIDER_LOG: Fatal exception in JS Callback loop",
              error: e, stackTrace: stack);
          await Future.delayed(const Duration(milliseconds: 100));
          _updateRouteUI([pickupLocation!, destinationLocation!]);
        }
      }

      // Use globalContext and callMethodVarArgs from dart:js_interop_unsafe.
      // callMethod only supports up to 4 arguments, but we need 6.
      globalContext.callMethodVarArgs(
        'aerorideFetchDirections'.toJS,
        [
          pickupLocation!.latitude.toJS,
          pickupLocation!.longitude.toJS,
          destinationLocation!.latitude.toJS,
          destinationLocation!.longitude.toJS,
          _googleMapsApiKey.toJS,
          handleDirectionsResponse.toJS,
        ],
      );
    } else {
      // Use direct HTTP on Mobile (CORS doesn't apply)
      final url = "https://maps.googleapis.com/maps/api/directions/json"
          "?origin=${pickupLocation!.latitude},${pickupLocation!.longitude}"
          "&destination=${destinationLocation!.latitude},${destinationLocation!.longitude}"
          "&mode=driving"
          "&key=$_googleMapsApiKey";

      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        // Safe Array Bounds Check for Mobile
        if (data["routes"] != null && (data["routes"] as List).isNotEmpty) {
          String encodedPolyline =
              data["routes"][0]["overview_polyline"]["points"];
          List<LatLng> routePoints = decodePolyline(encodedPolyline);
          _updateRouteUI(routePoints); // Mobile decode is generally stable
        } else {
          dev.log("RIDER_LOG: No routes found on mobile: ${data["status"]}");
          _updateRouteUI([pickupLocation!, destinationLocation!]);
        }
      }
    }
  }

  void _updateRouteUI(List<LatLng> routePoints) {
    if (!mounted) return;
    try {
      if (routePoints.isEmpty) return;
      final validPoints = routePoints
          .where((p) => p.latitude.isFinite && p.longitude.isFinite)
          .toList();

      if (validPoints.isEmpty) {
        dev.log("RIDER_LOG: No valid points found for route.");
        return;
      }

      dev.log("RIDER_LOG: Updating UI with ${validPoints.length} points");

      if (!mounted) return;
      setState(() {
        // Clean Literal Reassignment to prevent mutation deadlocks
        _polylines = {
          Polyline(
            polylineId: const PolylineId("active_ride_route"),
            points: validPoints,
            color: const Color(0xFF00796B),
            width: 5,
          ),
        };
      });

      if (mapController == null) return;

      double minLat = validPoints.first.latitude;
      double maxLat = validPoints.first.latitude;
      double minLng = validPoints.first.longitude;
      double maxLng = validPoints.first.longitude;

      final List<LatLng> boundsPoints = List.from(validPoints);
      if (pickupLocation != null) boundsPoints.add(pickupLocation!);
      if (destinationLocation != null) boundsPoints.add(destinationLocation!);

      for (var point in boundsPoints) {
        if (point.latitude < minLat) minLat = point.latitude;
        if (point.latitude > maxLat) maxLat = point.latitude;
        if (point.longitude < minLng) minLng = point.longitude;
        if (point.longitude > maxLng) maxLng = point.longitude;
      }

      // Buffer to prevent zero-size bounds
      const double delta = 0.001;
      if (minLat == maxLat) {
        minLat -= delta;
        maxLat += delta;
      }
      if (minLng == maxLng) {
        minLng -= delta;
        maxLng += delta;
      }

      // Hard validation of bounds for Web JS Bridge
      final LatLng sw = LatLng(minLat, minLng);
      final LatLng ne = LatLng(maxLat, maxLng);

      if (sw.latitude >= ne.latitude || sw.longitude >= ne.longitude) {
        dev.log("RIDER_LOG: Invalid bounds detected, skipping animation.");
        return;
      }

      final bounds = LatLngBounds(southwest: sw, northeast: ne);
      if (!mounted) return;
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted && mapController != null) {
          try {
            mapController!
                .animateCamera(
              CameraUpdate.newLatLngBounds(bounds, kIsWeb ? 30 : 50),
            )
                .catchError((e) {
              dev.log("RIDER_LOG: animateCamera catchError", error: e);
              mapController?.moveCamera(CameraUpdate.newLatLng(sw));
            });
          } catch (e) {
            dev.log("RIDER_LOG: Camera update failed", error: e);
            mapController?.moveCamera(CameraUpdate.newLatLng(sw));
          }
        }
      });
    } catch (e) {
      dev.log("RIDER_LOG: Fatal exception in _updateRouteUI", error: e);
    }
  }

  Future<void> requestRide() async {
    // --- AUTHENTICATION GATE ---
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null || currentUser.isAnonymous) {
      dev.log(
          "RIDER_LOG: Anonymous user attempting to book. Redirecting to login.");
      if (!mounted) return;

      // Navigate to the login screen and wait for a result.
      final bool? loginSuccess = await Navigator.push<bool>(
        context,
        MaterialPageRoute(builder: (context) => const LoginScreen()),
      );

      // If login was successful, the user is now authenticated.
      // We can refresh the state and proceed with the original request.
      if (loginSuccess != true) {
        dev.log("RIDER_LOG: Login was not successful. Aborting ride request.");
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Please log in to request a ride.")),
        );
        return;
      }
    }

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
    dev.log("RIDER_LOG: Distance: $distanceKm km");
    dev.log("RIDER_LOG: Fare: $fare");

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
    final currentUser = FirebaseAuth.instance.currentUser;
    final isGuest = currentUser == null || currentUser.isAnonymous;
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
        actions: isGuest
            ? [] // Show no actions for guest users
            : [
                IconButton(
                  onPressed: () {
                    Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const HistoryScreen()));
                  },
                  icon:
                      const Icon(Icons.history_rounded, color: Colors.white70),
                  tooltip: "Ride History",
                ),
                IconButton(
                  onPressed: () {
                    Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const ProfileScreen()));
                  },
                  icon: const Icon(Icons.account_circle_rounded,
                      color: Colors.white70),
                  tooltip: "Profile Settings",
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: IconButton(
                    onPressed: () =>
                        _handleLogout(context), // Triggers the sign-out method
                    icon: const Icon(Icons.logout_rounded,
                        color: Colors.redAccent),
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
              // --- PERMANENT STABLE MAP VIEWPORT ---
              Container(
                height: 380,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: const Color(0xFF1A2522),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white10, width: 1.0),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: SizedBox.expand(
                    child: GoogleMap(
                      // The ValueKey ensures the Map's identity is preserved during builds
                      key: const ValueKey('aeroride_web_stable_map'),
                      initialCameraPosition: initialPosition,
                      mapType: MapType.normal,
                      myLocationEnabled: true,
                      myLocationButtonEnabled: true,
                      onMapCreated: (controller) => mapController = controller,
                      // markers and polylines are now updated by the background listener and getRoute()
                      markers: markers,
                      polylines: _polylines,
                      onTap: (LatLng position) async {
                        String placeName = await getPlaceName(
                            position.latitude, position.longitude);
                        setState(() {
                          if (selectingPickup) {
                            pickupLocation = position;
                            pickupController.text = placeName;
                            selectingPickup = false;
                          } else {
                            destinationLocation = position;
                            destinationController.text = placeName;
                          }
                          _syncMarkers();
                        });
                        if (pickupLocation != null &&
                            destinationLocation != null) {
                          getRoute();
                        }
                      },
                    ),
                  ),
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
                      _handleStatusNotifications(context, currentStatus);
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
                        _ProfessionalCard(
                          color: data['paymentStatus'] == 'paid'
                              ? Colors.green.withValues(alpha: 0.1)
                              : Colors.orange.withValues(alpha: 0.05),
                          child: Column(
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                      data['paymentStatus'] == 'paid'
                                          ? Icons.check_circle_rounded
                                          : Icons.pending_actions,
                                      color: data['paymentStatus'] == 'paid'
                                          ? Colors.green
                                          : Colors.orangeAccent),
                                  const SizedBox(width: 8),
                                  Text(
                                    data['paymentStatus'] == 'paid'
                                        ? "Trip Completed & Paid"
                                        : "Payment Collection Pending",
                                    style: GoogleFonts.urbanist(
                                        fontWeight: FontWeight.bold,
                                        color: data['paymentStatus'] == 'paid'
                                            ? Colors.green
                                            : Colors.orangeAccent),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  if (data['paymentStatus'] != 'paid') ...[
                                    Expanded(
                                      child: ElevatedButton(
                                        onPressed: () =>
                                            _showPaymentForm(context, data),
                                        style: ElevatedButton.styleFrom(
                                            backgroundColor: primaryTurquoise,
                                            shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(12))),
                                        child: const Text("Pay Fare",
                                            style:
                                                TextStyle(color: Colors.white)),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                  ],
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      onPressed: () =>
                                          _showRatingDialog(context, data),
                                      icon: const Icon(Icons.star_rate_rounded,
                                          color: Colors.white, size: 20),
                                      label: const Text("Rate Driver",
                                          style: TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold)),
                                      style: ElevatedButton.styleFrom(
                                          backgroundColor:
                                              data['paymentStatus'] == 'paid'
                                                  ? primaryTurquoise
                                                  : Colors.white10,
                                          padding: const EdgeInsets.symmetric(
                                              vertical: 12),
                                          shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12))),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
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
                        : Text(
                            isGuest
                                ? "Login to Request Ride"
                                : "Confirm & Request Ride",
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

  void _handleStatusNotifications(BuildContext context, String? currentStatus) {
    if (currentStatus == 'accepted') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 4),
          content: Text("Driver accepted your ride 🚖",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ),
      );
    } else if (currentStatus == 'cancelled') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 5),
          content: Text("🚨 This trip has been cancelled!",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ),
      );
    } else if (currentStatus == 'started') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.blue,
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 4),
          content: Text("Trip started successfully 🛣️",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ),
      );
    } else if (currentStatus == 'completed') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.purple,
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 4),
          content: Text("Trip completed ✅",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ),
      );
    }
  }

  void _showPaymentForm(BuildContext context, Map<String, dynamic> data) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1A2522),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
              side: const BorderSide(color: Colors.white12)),
          title: Text("Trip Payment",
              style: GoogleFonts.urbanist(
                  color: Colors.white, fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  "Fare Amount: KES ${data['fare']}",
                  style: GoogleFonts.urbanist(
                      color: primaryTurquoise,
                      fontSize: 18,
                      fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _mpesaPhoneController,
                  keyboardType: TextInputType.phone,
                  style: GoogleFonts.urbanist(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: "M-Pesa Number",
                    labelStyle: const TextStyle(color: Colors.white38),
                    prefixIcon:
                        const Icon(Icons.phone_android, color: Colors.green),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () async {
                    String enteredPhone = _mpesaPhoneController.text.trim();
                    if (enteredPhone.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('📱 Please enter a phone number')),
                      );
                      return;
                    }
                    double actualFare =
                        double.tryParse(data['fare'].toString()) ?? 1.0;
                    String activeRideId =
                        currentRideId ?? data['rideId'] ?? "UNKNOWN_RIDE";

                    Navigator.pop(context); // Close form

                    showDialog(
                      context: context,
                      barrierDismissible: false,
                      builder: (context) => const Center(
                          child: CircularProgressIndicator(
                              color: primaryTurquoise)),
                    );

                    String result = await PaymentService.requestMpesaPrompt(
                      rawPhone: enteredPhone,
                      amount: actualFare,
                      context: context,
                    );

                    if (context.mounted)
                      Navigator.pop(context); // Dismiss loading

                    if (result == 'COMPLETED') {
                      await firestore
                          .collection('rides')
                          .doc(activeRideId)
                          .update({'paymentStatus': 'paid'});
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text("✅ Payment Successful!"),
                              backgroundColor: Colors.green),
                        );
                      }
                    } else {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                              content: Text(result == 'FAILED'
                                  ? "❌ Payment Failed"
                                  : "⏳ Timeout"),
                              backgroundColor: Colors.red),
                        );
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryTurquoise,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text("Pay Now",
                      style: GoogleFonts.urbanist(
                          color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showRatingDialog(BuildContext context, Map<String, dynamic> data) {
    showDialog(
      context: context,
      builder: (context) {
        double rating = 5;
        return AlertDialog(
          backgroundColor: const Color(0xFF1A2522),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
              side: const BorderSide(color: Colors.white12)),
          title: Text("Rate Driver",
              style: GoogleFonts.urbanist(
                  color: Colors.white, fontWeight: FontWeight.bold)),
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
                          color: Colors.white, fontWeight: FontWeight.bold)),
                ],
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text("Cancel",
                  style: GoogleFonts.urbanist(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () async {
                await firestore
                    .collection('rides')
                    .doc(currentRideId ?? data['rideId'])
                    .update({
                  'rating': rating.toInt(),
                });
                await rideService.updateDriverRating(
                  driverId: data['driverId'],
                );
                Navigator.pop(context);
              },
              child: Text("Submit Rating",
                  style: GoogleFonts.urbanist(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
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
