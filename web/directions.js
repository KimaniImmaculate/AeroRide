function aerorideWaitForGoogleMaps(remainingAttempts, callback) {
  if (window.google && window.google.maps && window.google.maps.DirectionsService && window.google.maps.geometry && window.google.maps.geometry.encoding) {
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
        const route = result.routes[0];
        const leg = route.legs && route.legs.length > 0 ? route.legs[0] : null;

        let encodedPath = ''; // Still provide for mobile fallback or older web versions
        let pointsList = [];
        try {
          const path = route.overview_path || [];
          encodedPath = google.maps.geometry.encoding.encodePath(path) || '';
          
          // Map the path to a simple array of coordinates for web-safe transfer
          for (let i = 0; i < path.length; i++) {
            pointsList.push({ lat: path[i].lat(), lng: path[i].lng() });
          }
        } catch (e) {
          console.error('Aeroride JS: Error encoding path', e);
        }

        console.log('Aeroride JS: Route processed. Points count:', pointsList.length); // Log for debugging

        const payload = {
          status: 'OK',
          routes: [
            {
              overview_polyline: {
                points: encodedPath,
                points_list: pointsList
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
        console.error('Aeroride: Directions request failed with status: ' + status);
        callback(JSON.stringify({ status: status || 'ERROR', routes: [] }), status || 'ERROR');
      }
    });
  });
};

window.aerorideGetPlaceName = function(lat, lng, apiKey, callback) {
  aerorideWaitForGoogleMaps(100, function(isReady) {
    if (!isReady) {
      callback('Unknown Location', 'NO_MAPS');
      return;
    }
    var geocoder = new google.maps.Geocoder();
    var latlng = { lat: lat, lng: lng };
    geocoder.geocode({ location: latlng }, function(results, status) {
      if (status === 'OK') {
        if (results[0]) {
          callback(results[0].formatted_address, status);
        } else {
          callback('No results found', status);
        }
      } else {
        callback('Geocoder failed: ' + status, status);
      }
    });
  });
};

window.aerorideGeocodeAddress = function(address, callback) {
  aerorideWaitForGoogleMaps(100, function(isReady) {
    if (!isReady) {
      callback(JSON.stringify({ status: 'NO_MAPS' }), 'NO_MAPS');
      return;
    }
    var geocoder = new google.maps.Geocoder();
    geocoder.geocode({ address: address }, function(results, status) {
      if (status === 'OK' && results[0] && results[0].geometry && results[0].geometry.location) {
        var loc = results[0].geometry.location;
        var payload = {
          status: 'OK',
          lat: loc.lat(),
          lng: loc.lng(),
          formatted_address: results[0].formatted_address
        };
        callback(JSON.stringify(payload), status);
      } else {
        callback(JSON.stringify({ status: status || 'ERROR' }), status || 'ERROR');
      }
    });
  });
};