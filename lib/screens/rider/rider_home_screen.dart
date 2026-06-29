import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../../services/ride_service.dart';
import '../../vehicle_selection_screen.dart';
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
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'dart:js_interop';
import 'dart:developer' as dev;
import 'dart:js_interop_unsafe';
import '../../gateway_portal.dart';
import '../../services/payment_service.dart';
import '../../services/voice_booking_handler.dart';
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
  String? assignedDriverId;
  LatLng? assignedDriverLocation;
  bool selectingPickup = false;
  String? _lastAlertedStatus;
  bool isRecordingVoice = false;
  bool isVoiceProcessing = false;
  String voiceLanguageCode = 'en-US';

  BitmapDescriptor? carMarkerIconAssigned;
  BitmapDescriptor? carMarkerIconUnassigned;

  Future<BitmapDescriptor> _getMarkerFromIcon(IconData iconData, Color color, double size) async {
    final pictureRecorder = ui.PictureRecorder();
    final canvas = Canvas(pictureRecorder);
    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    textPainter.text = TextSpan(
      text: String.fromCharCode(iconData.codePoint),
      style: TextStyle(
        fontSize: size,
        fontFamily: iconData.fontFamily,
        package: iconData.fontPackage,
        color: color,
      ),
    );
    textPainter.layout();
    textPainter.paint(canvas, const Offset(0.0, 0.0));

    final picture = pictureRecorder.endRecording();
    final image = await picture.toImage(size.toInt(), size.toInt());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);

    return BitmapDescriptor.fromBytes(bytes!.buffer.asUint8List());
  }

  Future<void> _loadCarMarkerIcons() async {
    carMarkerIconAssigned = await _getMarkerFromIcon(LucideIcons.car, Colors.deepPurple, 48.0);
    carMarkerIconUnassigned = await _getMarkerFromIcon(LucideIcons.car, Colors.blue, 36.0);
    if (mounted) {
      setState(() {});
    }
  }

  final CameraPosition initialPosition = const CameraPosition(
    target: LatLng(-0.3031, 36.0800),
    zoom: 14,
  );

  @override
  void initState() {
    super.initState();
    _signInAnonymouslyIfNeeded();
    getCurrentLocation();
    _loadCarMarkerIcons();
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

  /// Adjusts the camera to perfectly frame the pickup, destination, and assigned driver.
  void _fitMapBounds() {
    if (mapController == null || pickupLocation == null) return;

    List<LatLng> points = [pickupLocation!];
    if (destinationLocation != null) points.add(destinationLocation!);
    if (assignedDriverLocation != null) points.add(assignedDriverLocation!);

    if (points.length <= 1) return;

    double minLat = points.first.latitude;
    double maxLat = points.first.latitude;
    double minLng = points.first.longitude;
    double maxLng = points.first.longitude;

    for (var point in points) {
      if (point.latitude < minLat) minLat = point.latitude;
      if (point.latitude > maxLat) maxLat = point.latitude;
      if (point.longitude < minLng) minLng = point.longitude;
      if (point.longitude > maxLng) maxLng = point.longitude;
    }

    try {
      mapController!.animateCamera(
        CameraUpdate.newLatLngBounds(
          LatLngBounds(
            southwest: LatLng(minLat, minLng),
            northeast: LatLng(maxLat, maxLng),
          ),
          80.0, // padding
        ),
      );
    } catch (e) {
      debugPrint("Error animating camera: $e");
    }
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

            if (doc.id == assignedDriverId || distance <= 5000 || pickupLocation == null) {
              if (doc.id == assignedDriverId) {
                assignedDriverLocation = LatLng(driverLat, driverLng);
                // Call fit bounds but slightly delayed so markers update first
                Future.microtask(() => _fitMapBounds());
              }

              updatedDriverMarkers.add(
                Marker(
                  markerId: MarkerId("driver_${doc.id}"),
                  position: LatLng(driverLat, driverLng),
                  icon: doc.id == assignedDriverId 
                      ? (carMarkerIconAssigned ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet))
                      : (carMarkerIconUnassigned ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue)),
                  infoWindow: InfoWindow(
                      title: "Driver: ${data['email']?.split('@')[0]}"),
                  zIndex: doc.id == assignedDriverId ? 10.0 : 1.0,
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
      if (context.mounted) {
        Navigator.pop(context); // Dismiss loading spinner on error
      }
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
    
    if (mapController != null && pickupLocation != null) {
      mapController!.animateCamera(
        CameraUpdate.newLatLngZoom(pickupLocation!, 15),
      );
    }
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

  Future<void> requestRide({String? voiceTier, String? voiceNotes}) async {
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

    if (pickupLocation == null || destinationLocation == null) {
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

    String selectedTierId = voiceTier ?? 'tulia';
    double fare = 0;

    if (voiceTier == null) {
      // Navigate to VehicleSelectionScreen to choose a tier
      if (!mounted) return;
      final bool? confirmed = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (context) => VehicleSelectionScreen(
            user: FirebaseAuth.instance.currentUser!,
            distanceKm: distanceKm,
          ),
        ),
      );

      if (confirmed != true) {
        dev.log("RIDER_LOG: Vehicle selection cancelled by user.");
        return;
      }
      
      final rideController = Provider.of<RideController>(context, listen: false);
      final selectedTierObj = rideController.selectedTier;

      if (selectedTierObj == null) {
        throw Exception("No vehicle tier was selected.");
      }
      selectedTierId = selectedTierObj.id;
      fare = selectedTierObj.baseFare + (distanceKm * selectedTierObj.perKmRate);
    } else {
      // Automatic fare calculation based on voice tier
      if (voiceTier == 'waziri') {
        fare = 700 + (distanceKm * 150);
      } else if (voiceTier == 'pamoja') {
        fare = 500 + (distanceKm * 110);
      } else if (voiceTier == 'nuru') {
        fare = 350 + (distanceKm * 80);
      } else {
        fare = 150 + (distanceKm * 45); // tulia
      }
    }

    setState(() {
      isLoading = true;
    });

    try {
      dev.log("RIDER_LOG: Distance: $distanceKm km");
      dev.log("RIDER_LOG: Selected Tier: $selectedTierId, calculated fare: $fare");

      final rideId = await rideService.requestRide(
        pickup: pickupController.text.trim().isEmpty ? "Current Location" : pickupController.text.trim(),
        destination: destinationController.text.trim().isEmpty ? "Selected Destination" : destinationController.text.trim(),
        fare: fare,
        rideTier: selectedTierId,
        notes: voiceNotes,
      );

      currentRideId = rideId;

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
    } catch (e) {
      dev.log("RIDER_LOG: Error requesting ride", error: e);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Failed to request ride: $e"),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  Widget _buildVoiceSearchButton() {
    if (isVoiceProcessing) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: primaryTurquoise.withValues(alpha: 0.1),
          shape: BoxShape.circle,
        ),
        child: const SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            color: primaryTurquoise,
            strokeWidth: 2.5,
          ),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message: isRecordingVoice ? "Stop Recording" : "Voice Book (Speak Origin & Destination)",
          child: GestureDetector(
            onTap: _handleVoiceRecordingToggle,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isRecordingVoice ? Colors.redAccent : primaryTurquoise,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: (isRecordingVoice ? Colors.redAccent : primaryTurquoise)
                        .withValues(alpha: 0.3),
                    blurRadius: 8,
                    spreadRadius: 2,
                  )
                ],
              ),
              child: Icon(
                isRecordingVoice ? Icons.stop_rounded : Icons.mic_rounded,
                color: Colors.white,
                size: 24,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Tooltip(
          message: voiceLanguageCode == 'en-US'
              ? "Switch to Swahili"
              : "Switch to English",
          child: GestureDetector(
            onTap: () {
              setState(() {
                voiceLanguageCode =
                    voiceLanguageCode == 'en-US' ? 'sw-KE' : 'en-US';
              });
              AerorideVoiceHandler.speak(
                voiceLanguageCode == 'en-US'
                    ? "Language set to English."
                    : "Lugha imebadilishwa kuwa Kiswahili.",
                languageCode: voiceLanguageCode,
              );
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: voiceLanguageCode == 'sw-KE'
                    ? primaryTurquoise
                    : const Color(0xFF1E3530),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: primaryTurquoise,
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: primaryTurquoise.withValues(alpha: 0.25),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                voiceLanguageCode == 'en-US' ? "🇬🇧 EN" : "🇰🇪 SW",
                style: TextStyle(
                  color: voiceLanguageCode == 'sw-KE'
                      ? Colors.white
                      : primaryTurquoise,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _speakWithLanguage(String key, {String? val1, String? val2}) {
    final isSwahili = voiceLanguageCode == 'sw-KE';
    String text = "";
    switch (key) {
      case 'processing':
        text = isSwahili 
            ? "Tafadhali subiri, tunashughulikia ombi lako la safari."
            : "Processing your voice booking request, please wait.";
        break;
      case 'decode_error':
        text = isSwahili
            ? "Pole, hatukuweza kuelewa maeneo yako. Tafadhali jaribu tena."
            : "Sorry, we could not decode your locations. Please try again.";
        break;
      case 'general_error':
        text = isSwahili
            ? "Hitilafu imetokea wakati wa kushughulikia sauti."
            : "An error occurred during voice processing.";
        break;
      case 'confirm_prompt':
        text = isSwahili
            ? "Tafadhali thibitisha ikiwa njia kutoka $val1 hadi $val2 ni sahihi."
            : "Please confirm if the route from $val1 to $val2 is correct.";
        break;
      case 'booking_cancelled':
        text = isSwahili
            ? "Safari imeghairiwa."
            : "Booking cancelled.";
        break;
      case 'booking_confirmed':
        text = isSwahili
            ? "Safari imethibitishwa. Ombi linatumwa."
            : "Booking confirmed. Dispatching ride request.";
        break;
      case 'accepted':
        text = isSwahili
            ? "Dereva amekubali safari yako. Dereva $val1 anakuja."
            : "Your ride request has been accepted. Driver $val1 is on the way.";
        break;
      case 'cancelled':
        text = isSwahili
            ? "Tahadhari. Safari yako imeghairiwa kwa sababu ya: $val1."
            : "Alert. Your trip has been cancelled due to: $val1.";
        break;
      case 'started':
        text = isSwahili
            ? "Safari imeanza. Safari njema!"
            : "Trip started successfully. Safe travels.";
        break;
      case 'completed':
        text = isSwahili
            ? "Safari imekamilika. Umefika."
            : "Trip completed. You have arrived.";
        break;
    }
    if (text.isNotEmpty) {
      AerorideVoiceHandler.speak(text, languageCode: voiceLanguageCode);
    }
  }

  Future<void> _handleVoiceRecordingToggle() async {
    if (!kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Voice booking is only supported on Web.")),
      );
      return;
    }

    if (isRecordingVoice) {
      // Stop recording and process voice
      setState(() {
        isRecordingVoice = false;
        isVoiceProcessing = true;
      });

      try {
        final audioUrl = await AerorideVoiceHandler.stopRecording();
        _speakWithLanguage('processing');

        final result = await AerorideVoiceHandler.decodeVoiceToIntent(audioUrl);

        setState(() {
          isVoiceProcessing = false;
        });

        if (result == null) {
          _speakWithLanguage('decode_error');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text("Failed to parse transit locations. Please speak clearly."),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
          return;
        }

        if (result.intent == 'sos') {
          String note = result.notes?.trim() ?? "Voice triggered SOS";
          await firestore.collection('emergencies').add({
            'type': 'SOS',
            'userRole': 'rider',
            'userId': FirebaseAuth.instance.currentUser?.uid,
            'message': note.isEmpty ? "Voice triggered SOS" : note,
            'createdAt': Timestamp.now(),
            'status': 'active',
          });
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                backgroundColor: Colors.red,
                content: Text("🚨 Voice SOS Sent to Admin!")));
          }
          AerorideVoiceHandler.speak("Emergency SOS sent.");
          return;
        }

        if (result.intent == 'cancel') {
          if (currentRideId != null) {
            String note = result.notes?.trim() ?? "Voice Cancellation";
            await rideService.cancelRide(
              rideId: currentRideId!,
              cancelledBy: 'rider',
              reason: note.isEmpty ? "Voice Cancellation" : note,
            );
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text("Ride cancelled successfully.")));
            }
            AerorideVoiceHandler.speak("Your ride has been cancelled.");
          } else {
            AerorideVoiceHandler.speak("You have no active ride to cancel.");
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text("No active ride to cancel.")));
            }
          }
          return;
        }

        // intent == 'book'
        // Fill pickup and destination text fields
        setState(() {
          pickupController.text = result.origin!;
          destinationController.text = result.destination!;
          pickupLocation = LatLng(result.originLat!, result.originLng!);
          destinationLocation = LatLng(result.destinationLat!, result.destinationLng!);
        });

        _syncMarkers();
        await getRoute();

        // Prompt the confirmation dialog
        if (mounted) {
          _showVoiceBookingConfirmation(result);
        }
      } catch (e) {
        setState(() {
          isVoiceProcessing = false;
        });
        _speakWithLanguage('general_error');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Error: ${e.toString()}")),
          );
        }
      }
    } else {
      // Start recording
      try {
        await AerorideVoiceHandler.startRecording();
        setState(() {
          isRecordingVoice = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("🎙️ Listening... Speak your origin and destination, then tap the stop button."),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 8),
          ),
        );
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Error starting voice recorder: ${e.toString()}")),
          );
        }
      }
    }
  }

  void _showVoiceBookingConfirmation(VoiceBookingResult result) {
    _speakWithLanguage('confirm_prompt', val1: result.origin!, val2: result.destination!);
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1A2522),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: const BorderSide(color: Colors.white24),
          ),
          title: Row(
            children: const [
              Icon(Icons.mic_rounded, color: primaryTurquoise),
              SizedBox(width: 8),
              Text("Confirm Route",
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Is this the correct route you want to book?",
                  style: TextStyle(color: Colors.white70)),
              const SizedBox(height: 16),
              const Text("Pickup Location:", style: TextStyle(color: Colors.white38, fontSize: 12)),
              Text(result.origin!, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              const Text("Destination Drop-off:", style: TextStyle(color: Colors.white38, fontSize: 12)),
              Text(result.destination!, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              if (result.rideTier != null) ...[
                const SizedBox(height: 12),
                const Text("Vehicle Tier:", style: TextStyle(color: Colors.white38, fontSize: 12)),
                Text(result.rideTier!.toUpperCase(), style: const TextStyle(color: primaryTurquoise, fontWeight: FontWeight.bold)),
              ],
              if (result.notes != null && result.notes!.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text("Instructions:", style: TextStyle(color: Colors.white38, fontSize: 12)),
                Text(result.notes!, style: const TextStyle(color: Colors.white70, fontStyle: FontStyle.italic)),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _speakWithLanguage('booking_cancelled');
              },
              child: const Text("No", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _speakWithLanguage('booking_confirmed');
                requestRide(voiceTier: result.rideTier, voiceNotes: result.notes);
              },
              child: const Text("Yes, Book Ride", style: TextStyle(color: primaryTurquoise, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
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
                            builder: (_) => const HistoryScreen(isDriver: false)));
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
                if (!snapshot.hasData || !snapshot.data!.exists) {
                  return const SizedBox.shrink();
                }
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
                        bool wasSelectingPickup = selectingPickup;
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
                        
                        if (wasSelectingPickup && mapController != null) {
                          mapController!.animateCamera(
                            CameraUpdate.newLatLngZoom(position, 15),
                          );
                        }

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
                  child: Row(
                    children: [
                      Expanded(
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
                      const SizedBox(width: 12),
                      _buildVoiceSearchButton(),
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
                  if (!ride.exists || ride.data() == null) {
                    return const SizedBox.shrink();
                  }

                  final data = ride.data() as Map<String, dynamic>;
                  final currentStatus = data['status']?.toString();

                  // --- SIDE EFFECTS GATEKEEPER (Triggers exactly ONCE per status shift) ---
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (currentStatus != _lastAlertedStatus) {
                      _lastAlertedStatus =
                          currentStatus; // Lock state immediately
                      _handleStatusNotifications(context, currentStatus, data);
                    }
                    if (data['driverId'] != null && data['driverId'] != assignedDriverId) {
                       assignedDriverId = data['driverId'];
                       // trigger map bounds update, and marker sync
                       _syncMarkers();
                       _fitMapBounds();
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
                              Text(
                                  currentStatus == 'cancelled'
                                      ? "Cancellation Fee"
                                      : "Estimated Fare",
                                  style: GoogleFonts.urbanist(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600)),
                              Builder(
                                builder: (context) {
                                  double displayFare = double.tryParse(data['fare'].toString()) ?? 0.0;
                                  if (currentStatus == 'cancelled') {
                                    final tier = (data['rideTier']?.toString() ?? 'tulia').trim().toLowerCase();
                                    if (tier == 'nuru') displayFare = 350.0;
                                    else if (tier == 'pamoja') displayFare = 500.0;
                                    else if (tier == 'waziri') displayFare = 700.0;
                                    else displayFare = 150.0;
                                  }
                                  return Text(
                                      "KES ${displayFare.toStringAsFixed(0)}",
                                      style: GoogleFonts.urbanist(
                                          fontSize: 24,
                                          fontWeight: FontWeight.w900,
                                          color: primaryTurquoise));
                                }
                              ),
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
                              const SizedBox(height: 16),
                              if (data['paymentStatus'] != 'paid') ...[
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton(
                                    onPressed: () =>
                                        _showPaymentForm(context, data),
                                    style: ElevatedButton.styleFrom(
                                        backgroundColor: primaryTurquoise,
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(12))),
                                    child: const Text("Pay Cancellation Fare",
                                        style:
                                            TextStyle(color: Colors.white)),
                                  ),
                                ),
                              ] else ...[
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: const [
                                    Icon(Icons.check_circle_rounded,
                                        color: Colors.green),
                                    SizedBox(width: 8),
                                    Text(
                                      "Cancellation Fee Paid",
                                      style: TextStyle(
                                          color: Colors.green,
                                          fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                SizedBox(
                                  width: double.infinity,
                                  child: TextButton(
                                    onPressed: () {
                                      setState(() {
                                        currentRideId = null;
                                      });
                                    },
                                    child: const Text("Book Another Ride",
                                        style: TextStyle(color: Colors.white70)),
                                  ),
                                ),
                              ],
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
                        if (data['driverId'] != null)
                          FutureBuilder<DocumentSnapshot>(
                            future: firestore
                                .collection('users')
                                .doc(data['driverId'] as String)
                                .get(),
                            builder: (context, driverSnap) {
                              if (!driverSnap.hasData || !driverSnap.data!.exists) {
                                return const SizedBox.shrink();
                              }
                              final driverData = driverSnap.data!.data() as Map<String, dynamic>;
                              final driverPhone = driverData['phone'] as String?;
                              final vehicleImageUrl = driverData['vehicleImageUrl'] as String?;

                              return _ProfessionalCard(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    ListTile(
                                      contentPadding: EdgeInsets.zero,
                                      leading: vehicleImageUrl != null
                                          ? CircleAvatar(
                                              radius: 24,
                                              backgroundImage: vehicleImageUrl.startsWith('data:image') 
                                                  ? MemoryImage(base64Decode(vehicleImageUrl.split(',').last)) as ImageProvider
                                                  : NetworkImage(vehicleImageUrl),
                                              backgroundColor: Colors.transparent,
                                            )
                                          : const CircleAvatar(
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
                                    if (driverPhone != null && driverPhone.trim().isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 4.0),
                                        child: Row(
                                          children: [
                                            const Icon(Icons.phone_rounded,
                                                color: primaryTurquoise, size: 16),
                                            const SizedBox(width: 6),
                                            Expanded(
                                              child: Text(
                                                driverPhone,
                                                style: GoogleFonts.urbanist(
                                                    color: Colors.white70,
                                                    fontSize: 14),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            GestureDetector(
                                              onTap: () {
                                                // Launch phone dialer via tel: URI
                                                final uri = Uri.parse('tel:$driverPhone');
                                                // Use js interop to open on web
                                                final window = globalContext
                                                    .getProperty('window'.toJS);
                                                if (window != null) {
                                                  (window as JSObject).callMethod(
                                                      'open'.toJS,
                                                      uri.toString().toJS);
                                                }
                                              },
                                              child: Container(
                                                padding: const EdgeInsets.symmetric(
                                                    horizontal: 14, vertical: 8),
                                                decoration: BoxDecoration(
                                                  color: primaryTurquoise
                                                      .withValues(alpha: 0.18),
                                                  borderRadius: BorderRadius.circular(10),
                                                  border: Border.all(
                                                      color: primaryTurquoise
                                                          .withValues(alpha: 0.5),
                                                      width: 1),
                                                ),
                                                child: Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    const Icon(Icons.call_rounded,
                                                        color: primaryTurquoise, size: 16),
                                                    const SizedBox(width: 4),
                                                    Text("Call Driver",
                                                        style: GoogleFonts.urbanist(
                                                            color: primaryTurquoise,
                                                            fontWeight: FontWeight.bold,
                                                            fontSize: 13)),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                  ],
                                ),
                              );
                            },
                          ),
                      ],

                      // --- 5. ACTION BAR (SOS & CANCEL RIDE) ---
                      if (data['status'] == 'searching' ||
                          data['status'] == 'pending' ||
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
                              if (data['paymentStatus'] == 'paid') ...[
                                const SizedBox(height: 16),
                                SizedBox(
                                  width: double.infinity,
                                  child: TextButton(
                                    onPressed: () {
                                      setState(() {
                                        currentRideId = null;
                                      });
                                    },
                                    child: const Text("Book Another Ride",
                                        style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
                                  ),
                                ),
                              ],
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

  void _handleStatusNotifications(
      BuildContext context, String? currentStatus, Map<String, dynamic> data) {
    if (currentStatus == 'accepted') {
      final driverEmail = data['driverEmail']?.toString() ?? 'assigned';
      final emailPrefix = driverEmail.split('@')[0];
      AerorideVoiceHandler.speak(
          "Your ride request has been accepted. Driver $emailPrefix is on the way.");

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
      final cancelReason = data['cancelReason']?.toString() ?? 'No specific reason';
      AerorideVoiceHandler.speak(
          "Alert. Your trip has been cancelled due to: $cancelReason.");

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
      AerorideVoiceHandler.speak("Trip started successfully. Safe travels.");

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
      AerorideVoiceHandler.speak("Trip completed. You have arrived.");

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
                Builder(
                  builder: (context) {
                    double displayFare = double.tryParse(data['fare'].toString()) ?? 0.0;
                    if (data['status'] == 'cancelled') {
                      final tier = (data['rideTier']?.toString() ?? 'tulia').trim().toLowerCase();
                      if (tier == 'nuru') displayFare = 350.0;
                      else if (tier == 'pamoja') displayFare = 500.0;
                      else if (tier == 'waziri') displayFare = 700.0;
                      else displayFare = 150.0;
                    }
                    return Text(
                      "Fare Amount: KES ${displayFare.toStringAsFixed(0)}",
                      style: GoogleFonts.urbanist(
                          color: primaryTurquoise,
                          fontSize: 18,
                          fontWeight: FontWeight.bold),
                    );
                  }
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
                    if (data['status'] == 'cancelled') {
                      final tier = (data['rideTier']?.toString() ?? 'tulia').trim().toLowerCase();
                      if (tier == 'nuru') actualFare = 350.0;
                      else if (tier == 'pamoja') actualFare = 500.0;
                      else if (tier == 'waziri') actualFare = 700.0;
                      else actualFare = 150.0;
                    }
                    String activeRideId =
                        currentRideId ?? data['rideId'] ?? "UNKNOWN_RIDE";

                    final nav = Navigator.of(context, rootNavigator: true);
                    final scaffold = ScaffoldMessenger.of(context);
                    
                    nav.pop(); // Close form

                    showDialog(
                      context: context,
                      barrierDismissible: false,
                      builder: (dialogCtx) => const Center(
                          child: CircularProgressIndicator(
                              color: primaryTurquoise)),
                    );

                    String result = await PaymentService.requestMpesaPrompt(
                      rawPhone: enteredPhone,
                      amount: actualFare,
                      context: context,
                      rideId: activeRideId,
                    );

                    nav.pop(); // Dismiss loading

                    if (result == 'COMPLETED') {
                      // Mark ride as paid
                      await firestore
                          .collection('rides')
                          .doc(activeRideId)
                          .update({'paymentStatus': 'paid'});

                      // Credit 100% of cancellation fee to the assigned driver
                      // (Driver wasted time showing up — they keep the full cancellation fee)
                      try {
                        final rideDoc = await firestore.collection('rides').doc(activeRideId).get();
                        final rideData = rideDoc.data();
                        final String? driverId = rideData?['driverId'] as String?;
                        final num fee = (rideData?['fare'] as num?) ?? 0;

                        if (driverId != null && fee > 0) {
                          await firestore.collection('users').doc(driverId).update({
                            'earnings': FieldValue.increment(fee),
                            'cancellationEarnings': FieldValue.increment(fee),
                          });
                          // Log the cancellation payout for admin visibility
                          await firestore.collection('rides').doc(activeRideId).update({
                            'driverEarnings': fee,
                            'platformFee': 0,
                            'cancellationPaidToDriver': true,
                          });
                        }
                      } catch (_) {}

                      if (mounted) {
                        setState(() {
                          currentRideId = null;
                        });
                        scaffold.showSnackBar(
                          const SnackBar(
                              content: Text("✅ Payment Successful!"),
                              backgroundColor: Colors.green),
                        );
                      }
                    } else {
                      // Payment was rejected or timed out — re-open the form so the rider can try again
                      if (mounted) {
                        final msg = result == 'FAILED'
                            ? "❌ Payment rejected. Please try again."
                            : "⏳ Payment timed out. Please try again.";
                        scaffold.showSnackBar(
                          SnackBar(
                            content: Text(msg),
                            backgroundColor: Colors.red,
                            duration: const Duration(seconds: 3),
                          ),
                        );
                        // Re-open the payment form after a short delay
                        await Future.delayed(const Duration(milliseconds: 300));
                        if (mounted) _showPaymentForm(context, data);
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
                
                final user = FirebaseAuth.instance.currentUser;
                String? userName;
                String? userEmail;
                
                if (user != null) {
                  final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
                  if (userDoc.exists) {
                    final data = userDoc.data();
                    userName = data?['name'];
                    userEmail = data?['email'] ?? data?['phone'];
                  }
                }

                await FirebaseFirestore.instance.collection('emergencies').add({
                  'type': 'SOS',
                  'userRole': 'rider',
                  'userId': user?.uid,
                  'userName': userName,
                  'userEmail': userEmail,
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
