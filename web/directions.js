function aerorideWaitForGoogleMaps(remainingAttempts, callback) {
  if (window.google && window.google.maps && window.google.maps.DirectionsService) {
    callback(true);
    return;
  }

  if (remainingAttempts <= 0) {
    callback(false);
    return;
  }

  setTimeout(function() {
    aerorideWaitForGoogleMaps(remainingAttempts - 1, callback);
  }, 100);
}

window.aerorideFetchDirections = function(originLat, originLng, destinationLat, destinationLng, apiKey, callback) {
  aerorideWaitForGoogleMaps(100, function(isReady) {
    if (!isReady) {
      callback(JSON.stringify({ status: 'NO_MAPS', routes: [] }), 'NO_MAPS');
      return;
    }

    var service = new google.maps.DirectionsService();
    var request = {
      origin: new google.maps.LatLng(originLat, originLng),
      destination: new google.maps.LatLng(destinationLat, destinationLng),
      travelMode: google.maps.TravelMode.DRIVING
    };

    service.route(request, function(result, status) {
      if (status === 'OK' && result && result.routes && result.routes.length > 0) {
        var route = result.routes[0];
        var leg = route.legs && route.legs.length > 0 ? route.legs[0] : null;
        var payload = {
          status: 'OK',
          routes: [
            {
              overview_polyline: {
                points: route.overview_polyline ? route.overview_polyline.points : ''
              },
              legs: [
                {
                  distance: { value: leg && leg.distance ? leg.distance.value : 0 },
                  duration: { value: leg && leg.duration ? leg.duration.value : 0 }
                }
              ]
            }
          ]
        };
        callback(JSON.stringify(payload), status);
      } else {
        callback(JSON.stringify({ status: status || 'ERROR', routes: [] }), status || 'ERROR');
      }
    });
  });
};