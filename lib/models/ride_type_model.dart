import 'package:cloud_firestore/cloud_firestore.dart';

class RideTypeModel {
  final String id;
  final String name;
  final String description;
  final double basePrice;
  final double pricePerKm;
  final String iconName;
  final double multiplier;
  final bool isActive;
  final int sortOrder;

  RideTypeModel({
    required this.id,
    required this.name,
    required this.description,
    required this.basePrice,
    required this.pricePerKm,
    required this.iconName,
    this.multiplier = 1.0,
    this.isActive = true,
    this.sortOrder = 0,
  });

  factory RideTypeModel.fromMap(Map<String, dynamic> map, String id) {
    return RideTypeModel(
      id: id,
      name: map['name'] ?? '',
      description: map['description'] ?? '',
      basePrice: (map['basePrice'] as num?)?.toDouble() ?? 0.0,
      pricePerKm: (map['pricePerKm'] as num?)?.toDouble() ?? 0.0,
      iconName: map['iconName'] ?? 'directions_car',
      multiplier: (map['multiplier'] as num?)?.toDouble() ?? 1.0,
      isActive: map['isActive'] ?? true,
      sortOrder: (map['sortOrder'] as int?) ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'description': description,
      'basePrice': basePrice,
      'pricePerKm': pricePerKm,
      'iconName': iconName,
      'multiplier': multiplier,
      'isActive': isActive,
      'sortOrder': sortOrder,
    };
  }

  String get formattedPrice => 'KES ${basePrice.toStringAsFixed(0)}';

  double calculatePrice(double distanceKm) {
    return (basePrice + (pricePerKm * distanceKm)) * multiplier;
  }
}

class RideTypesService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Stream<List<RideTypeModel>> streamRideTypes() {
    return _db
        .collection('rideTypes')
        .where('isActive', isEqualTo: true)
        .orderBy('sortOrder')
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => RideTypeModel.fromMap(doc.data()!, doc.id))
              .toList(),
        );
  }

  Future<List<RideTypeModel>> getRideTypes() async {
    final snapshot = await _db
        .collection('rideTypes')
        .where('isActive', isEqualTo: true)
        .orderBy('sortOrder')
        .get();
    return snapshot.docs
        .map((doc) => RideTypeModel.fromMap(doc.data()!, doc.id))
        .toList();
  }

  Future<void> seedDefaultRideTypes() async {
    final collection = _db.collection('rideTypes');
    final existing = await collection.get();

    if (existing.docs.isNotEmpty) return;

    final defaultTypes = [
      {
        'name': 'Economy',
        'description': 'Affordable rides for everyday trips',
        'basePrice': 150.0,
        'pricePerKm': 40.0,
        'iconName': 'directions_car_filled',
        'multiplier': 1.0,
        'isActive': true,
        'sortOrder': 0,
      },
      {
        'name': 'Standard',
        'description': 'Comfortable rides with professional drivers',
        'basePrice': 250.0,
        'pricePerKm': 60.0,
        'iconName': 'directions_car',
        'multiplier': 1.2,
        'isActive': true,
        'sortOrder': 1,
      },
      {
        'name': 'Premium',
        'description': 'Luxury vehicles for a premium experience',
        'basePrice': 500.0,
        'pricePerKm': 100.0,
        'iconName': 'local_taxi',
        'multiplier': 1.5,
        'isActive': true,
        'sortOrder': 2,
      },
    ];

    for (final type in defaultTypes) {
      await collection.add(type);
    }
  }
}
