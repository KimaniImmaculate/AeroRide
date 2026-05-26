import 'dart:async';
import 'dart:html' as html;

import 'package:google_maps_flutter/google_maps_flutter.dart';

Future<LatLng?> requestBrowserLocationImpl() async {
  final geo = html.window.navigator.geolocation;
  if (geo == null) {
    return null;
  }

  try {
    final position = await geo.getCurrentPosition();
    final coords = position.coords;
    final latitude = coords?.latitude?.toDouble();
    final longitude = coords?.longitude?.toDouble();

    if (latitude == null || longitude == null) {
      return null;
    }

    return LatLng(latitude, longitude);
  } catch (_) {
    return null;
  }
}
