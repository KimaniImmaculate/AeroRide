import 'package:cloud_firestore/cloud_firestore.dart';

class UserService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<void> saveUserData({
    required String uid,
    required String email,
    required String role,
    required String phone,
  }) async {
    await _firestore.collection('users').doc(uid).set({
      'email': email,
      'role': role,
      'phone': phone,
      'createdAt': Timestamp.now(),
      'isOnline': false,
    });
  }

  Future<void> updateDriverStatus({
    required String uid,
    required bool isOnline,
  }) async {
    await _firestore.collection('users').doc(uid).update({
      'isOnline': isOnline,
    });
  }

  Future<void> updateDriverLocation({
    required String uid,
    required double latitude,
    required double longitude,
  }) async {
    await _firestore.collection('users').doc(uid).update({
      'latitude': latitude,
      'longitude': longitude,
    });
  }
}
