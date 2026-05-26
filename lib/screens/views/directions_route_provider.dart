import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'directions_route_provider_stub.dart'
    if (dart.library.html) 'directions_route_provider_web.dart';

Future<Map<String, dynamic>?> fetchDirectionsRoute(
  LatLng origin,
  LatLng destination,
  String apiKey,
) {
  return fetchDirectionsRouteImpl(origin, destination, apiKey);
}
