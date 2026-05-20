import 'package:google_maps_flutter/google_maps_flutter.dart';

class MockRouteService {
  // Returns a list of coordinates that form a simulated path/route line
  static List<LatLng> getMockRoutePoints() {
    return [
      const LatLng(-1.2833, 36.8167), // Start (Pickup)
      const LatLng(-1.2880, 36.8220), // Turn 1
      const LatLng(-1.2940, 36.8310), // Turn 2
      const LatLng(-1.3033, 36.8467), // End (Destination)
    ];
  }
}