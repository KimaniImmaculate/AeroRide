import 'package:cloud_firestore/cloud_firestore.dart';

class RideRequest {
  final String? id;
  final String userId;
  final String? riderName;
  final String? driverId;
  final List<String>? candidateDrivers;
  final GeoPoint pickupLocation;
  final GeoPoint destinationLocation;
  final GeoPoint? currentVehicleLocation;
  final String pickupAddress;
  final String destinationAddress;
  final String status;
  final double estimatedCost;
  final String? rideType;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  RideRequest({
    this.id,
    required this.userId,
    this.riderName,
    this.driverId,
    this.candidateDrivers,
    required this.pickupLocation,
    required this.destinationLocation,
    this.currentVehicleLocation,
    required this.pickupAddress,
    required this.destinationAddress,
    required this.status,
    required this.estimatedCost,
    this.rideType,
    this.createdAt,
    this.updatedAt,
  });

  factory RideRequest.fromMap(Map<String, dynamic> map, String docId) {
    final fareValue = (map['finalFareCharged'] ?? map['estimatedCost']) as num?;
    return RideRequest(
      id: docId,
      userId: map['userId'] ?? map['riderId'] ?? '',
      riderName: map['riderName'] ??
          map['userName'] ??
          map['passengerName'] ??
          map['name'],
      driverId: map['driverId'],
      candidateDrivers: map['candidateDrivers'] != null
          ? List<String>.from(map['candidateDrivers'])
          : null,
      pickupLocation: (map['pickupLocation'] ?? map['pickup']) as GeoPoint,
      destinationLocation:
          (map['destinationLocation'] ?? map['dropoff']) as GeoPoint,
      currentVehicleLocation: (map['currentVehicleLocation'] ??
          map['current_vehicle_location']) as GeoPoint?,
      pickupAddress: map['pickupAddress'] ?? map['pickupName'] ?? '',
      destinationAddress:
          map['destinationAddress'] ?? map['destinationName'] ?? '',
      status: map['status'] ?? 'searching',
      estimatedCost: fareValue?.toDouble() ?? 0.0,
      createdAt: (map['createdAt'] as Timestamp?)?.toDate() ??
          (map['updatedAt'] as Timestamp?)?.toDate(),
      updatedAt: (map['updatedAt'] as Timestamp?)?.toDate(),
      rideType: map['rideType'] ?? 'standard',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      if (riderName != null) 'riderName': riderName,
      'driverId': driverId,
      'candidateDrivers': candidateDrivers,
      'pickupLocation': pickupLocation,
      'destinationLocation': destinationLocation,
      if (currentVehicleLocation != null)
        'currentVehicleLocation': currentVehicleLocation,
      'pickupAddress': pickupAddress,
      'destinationAddress': destinationAddress,
      'status': status,
      'estimatedCost': estimatedCost,
      'finalFareCharged': estimatedCost,
      'rideType': rideType ?? 'standard',
      if (createdAt != null) 'createdAt': Timestamp.fromDate(createdAt!),
      if (updatedAt != null) 'updatedAt': Timestamp.fromDate(updatedAt!),
    };
  }
}
