import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

Future<Map<String, dynamic>?> fetchDirectionsRouteImpl(
  LatLng origin,
  LatLng destination,
  String apiKey,
) async {
  const url = 'https://routes.googleapis.com/directions/v2:computeRoutes';

  final response = await http.post(
    Uri.parse(url),
    headers: {
      'Content-Type': 'application/json',
      'X-Goog-Api-Key': apiKey,
      'X-Goog-FieldMask':
          'routes.duration,routes.distanceMeters,routes.polyline.encodedPolyline',
    },
    body: jsonEncode({
      'origin': {
        'location': {
          'latLng': {
            'latitude': origin.latitude,
            'longitude': origin.longitude,
          }
        }
      },
      'destination': {
        'location': {
          'latLng': {
            'latitude': destination.latitude,
            'longitude': destination.longitude,
          }
        }
      },
      'travelMode': 'DRIVE',
      'routingPreference': 'TRAFFIC_AWARE',
    }),
  );

  if (response.statusCode < 200 || response.statusCode >= 300) {
    return null;
  }

  final data = jsonDecode(response.body);
  debugPrint('RAW ROUTES API RESPONSE: ${response.body}');
  if (data is Map<String, dynamic>) {
    return data;
  }

  return null;
}
