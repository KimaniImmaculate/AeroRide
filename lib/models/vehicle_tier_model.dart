import 'package:cloud_firestore/cloud_firestore.dart';

class VehicleTier {
  final String id;
  final String name;
  final String description;
  final double baseFare;
  final double perKmRate;
  final int capacity;
  final List<String> benefits;
  final String iconPath;

  VehicleTier({
    required this.id,
    required this.name,
    required this.description,
    required this.baseFare,
    required this.perKmRate,
    required this.capacity,
    required this.benefits,
    this.iconPath = 'assets/images/cars/standard.png',
  });

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'description': description,
      'baseFare': baseFare,
      'perKmRate': perKmRate,
      'capacity': capacity,
      'benefits': benefits,
      'iconPath': iconPath,
    };
  }

  factory VehicleTier.fromMap(String id, Map<String, dynamic> map) {
    return VehicleTier(
      id: id,
      name: map['name'] ?? '',
      description: map['description'] ?? '',
      baseFare: (map['baseFare'] ?? 0.0).toDouble(),
      perKmRate: (map['perKmRate'] ?? 0.0).toDouble(),
      capacity: map['capacity'] ?? 4,
      benefits: List<String>.from(map['benefits'] ?? []),
      iconPath: map['iconPath'] ?? 'assets/images/cars/standard.png',
    );
  }

  double estimateFare(double distanceKm) {
    return baseFare + (distanceKm * perKmRate);
  }
}