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

  static List<LatLng> buildRoutePoints(
    LatLng start,
    LatLng end, {
    int steps = 24,
  }) {
    if (steps < 2) {
      return [start, end];
    }

    final points = <LatLng>[];
    for (var i = 0; i <= steps; i++) {
      final t = i / steps;
      final latitude = start.latitude + (end.latitude - start.latitude) * t;
      final longitude = start.longitude + (end.longitude - start.longitude) * t;
      points.add(LatLng(latitude, longitude));
    }
    return points;
  }
}
