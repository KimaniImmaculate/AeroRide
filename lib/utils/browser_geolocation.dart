import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'browser_geolocation_stub.dart'
    if (dart.library.html) 'browser_geolocation_web.dart';

Future<LatLng?> requestBrowserLocation() {
  return requestBrowserLocationImpl();
}
