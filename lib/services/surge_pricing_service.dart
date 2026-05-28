import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class GeofencedZone {
  final String id;
  final LatLng center;
  final double radiusKm;
  final double requestToDriverThreshold;
  final double maxMultiplier;

  const GeofencedZone({
    required this.id,
    required this.center,
    required this.radiusKm,
    required this.requestToDriverThreshold,
    required this.maxMultiplier,
  });
}

class SurgeQuote {
  final double baseFare;
  final double multiplier;
  final double finalFare;
  final int ridersRequesting;
  final int driversOnline;
  final String zoneId;

  const SurgeQuote({
    required this.baseFare,
    required this.multiplier,
    required this.finalFare,
    required this.ridersRequesting,
    required this.driversOnline,
    required this.zoneId,
  });
}

class SurgePricingService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  static const GeofencedZone fallbackZone = GeofencedZone(
    id: 'fallback_nairobi_cbd',
    center: LatLng(-1.286389, 36.817223),
    radiusKm: 12,
    requestToDriverThreshold: 1.4,
    maxMultiplier: 2.5,
  );

  Future<SurgeQuote> quoteForPickup({
    required double baseFare,
    required LatLng pickup,
    GeofencedZone? zone,
  }) async {
    try {
      final activeZone = zone ?? fallbackZone;
      if (!_isWithinZone(pickup, activeZone)) {
        return SurgeQuote(
          baseFare: baseFare,
          multiplier: 1.0,
          finalFare: baseFare,
          ridersRequesting: 0,
          driversOnline: 0,
          zoneId: activeZone.id,
        );
      }

      final ridersRequesting = await _countRidersRequesting(activeZone);
      final driversOnline = await _countDriversOnline(activeZone);

      if (driversOnline <= 0) {
        return SurgeQuote(
          baseFare: baseFare,
          multiplier: activeZone.maxMultiplier,
          finalFare: baseFare * activeZone.maxMultiplier,
          ridersRequesting: ridersRequesting,
          driversOnline: 0,
          zoneId: activeZone.id,
        );
      }

      final ratio = ridersRequesting / driversOnline;
      if (ratio <= activeZone.requestToDriverThreshold) {
        return SurgeQuote(
          baseFare: baseFare,
          multiplier: 1.0,
          finalFare: baseFare,
          ridersRequesting: ridersRequesting,
          driversOnline: driversOnline,
          zoneId: activeZone.id,
        );
      }

      final multiplier =
          (1 + ((ratio - activeZone.requestToDriverThreshold) * 0.5))
              .clamp(1.0, activeZone.maxMultiplier)
              .toDouble();

      return SurgeQuote(
        baseFare: baseFare,
        multiplier: multiplier,
        finalFare: baseFare * multiplier,
        ridersRequesting: ridersRequesting,
        driversOnline: driversOnline,
        zoneId: activeZone.id,
      );
    } catch (_) {
      final activeZone = zone ?? fallbackZone;
      return SurgeQuote(
        baseFare: baseFare,
        multiplier: 1.0,
        finalFare: baseFare,
        ridersRequesting: 0,
        driversOnline: 0,
        zoneId: activeZone.id,
      );
    }
  }

  bool _isWithinZone(LatLng point, GeofencedZone zone) {
    final distanceKm = _distanceKm(
      point.latitude,
      point.longitude,
      zone.center.latitude,
      zone.center.longitude,
    );
    return distanceKm <= zone.radiusKm;
  }

  Future<int> _countDriversOnline(GeofencedZone zone) async {
    final cutoff = Timestamp.fromDate(
      DateTime.now().subtract(const Duration(minutes: 5)),
    );
    final snapshot = await _db
        .collection('users')
        .where('role', isEqualTo: 'driver')
        .where('updatedAt', isGreaterThan: cutoff)
        .get();

    var count = 0;
    for (final doc in snapshot.docs) {
      final data = doc.data();
      if (data['isOnline'] != true) continue;
      final location = data['current_location'] as GeoPoint?;
      if (location == null) continue;
      if (_isWithinZone(LatLng(location.latitude, location.longitude), zone)) {
        count += 1;
      }
    }

    return count;
  }

  Future<int> _countRidersRequesting(GeofencedZone zone) async {
    final cutoff = Timestamp.fromDate(
      DateTime.now().subtract(const Duration(minutes: 10)),
    );
    final snapshot = await _db
        .collection('rides')
        .where('createdAt', isGreaterThan: cutoff)
        .get();

    var count = 0;
    for (final doc in snapshot.docs) {
      final data = doc.data();
      if (data['status'] != 'searching') continue;
      final pickup = data['pickupLocation'] as GeoPoint?;
      if (pickup == null) continue;
      if (_isWithinZone(LatLng(pickup.latitude, pickup.longitude), zone)) {
        count += 1;
      }
    }

    return count;
  }

  double _distanceKm(double lat1, double lon1, double lat2, double lon2) {
    const earthRadiusKm = 6371.0;
    final dLat = _degToRad(lat2 - lat1);
    final dLon = _degToRad(lon2 - lon1);
    final a = (sin(dLat / 2) * sin(dLat / 2)) +
        cos(_degToRad(lat1)) *
            cos(_degToRad(lat2)) *
            (sin(dLon / 2) * sin(dLon / 2));
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadiusKm * c;
  }

  double _degToRad(double deg) => deg * (pi / 180);
}
