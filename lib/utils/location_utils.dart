import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class LocationUtils {
  /// Calculates distance between two coordinates in Kilometers.
  /// Uses the WGS84 ellipsoid for high precision.
  static double calculateDistanceKm(LatLng p1, LatLng p2) {
    return Geolocator.distanceBetween(
          p1.latitude,
          p1.longitude,
          p2.latitude,
          p2.longitude,
        ) /
        1000.0;
  }

  /// Calculates ETA in minutes based on distance.
  /// Default speed: 30 km/h (standard urban traffic constant).
  static int calculateETA(double distanceKm, {double averageSpeedKmh = 30.0}) {
    if (distanceKm <= 0) return 0;
    return (distanceKm / averageSpeedKmh * 60).ceil();
  }
}
