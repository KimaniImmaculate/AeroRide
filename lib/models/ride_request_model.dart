import 'package:cloud_firestore/cloud_firestore.dart';

class RideRequest {
  final String? id;
  final String userId;
  final String? driverId;
  final List<String>? candidateDrivers;
  final GeoPoint pickupLocation;
  final GeoPoint destinationLocation;
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
    this.driverId,
    this.candidateDrivers,
    required this.pickupLocation,
    required this.destinationLocation,
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
      userId: map['userId'] ?? '',
      driverId: map['driverId'],
      candidateDrivers: map['candidateDrivers'] != null
          ? List<String>.from(map['candidateDrivers'])
          : null,
      pickupLocation: map['pickupLocation'] as GeoPoint,
      destinationLocation: map['destinationLocation'] as GeoPoint,
      pickupAddress: map['pickupAddress'] ?? '',
      destinationAddress: map['destinationAddress'] ?? '',
      status: map['status'] ?? 'searching',
      estimatedCost: fareValue?.toDouble() ?? 0.0,
      createdAt: (map['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (map['updatedAt'] as Timestamp?)?.toDate(),
      rideType: map['rideType'] ?? 'standard',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'driverId': driverId,
      'candidateDrivers': candidateDrivers,
      'pickupLocation': pickupLocation,
      'destinationLocation': destinationLocation,
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
