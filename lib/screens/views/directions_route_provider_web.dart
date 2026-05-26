import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'dart:js' as js;

import 'package:google_maps_flutter/google_maps_flutter.dart';

Future<Map<String, dynamic>?> fetchDirectionsRouteImpl(
  LatLng origin,
  LatLng destination,
  String apiKey,
) async {
  final completer = Completer<Map<String, dynamic>?>();
  js.context.callMethod('aerorideFetchDirections', [
    origin.latitude,
    origin.longitude,
    destination.latitude,
    destination.longitude,
    apiKey,
    (dynamic payload, dynamic status) {
      if (payload is String) {
        debugPrint('RAW GOOGLE API RESPONSE: $payload');
        final decoded = jsonDecode(payload);
        if (decoded is Map<String, dynamic>) {
          completer.complete(decoded);
          return;
        }
      }

      completer.complete(null);
    },
  ]);

  return completer.future
      .timeout(const Duration(seconds: 10), onTimeout: () => null);
}
