import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_model.dart';
import '../models/ride_request_model.dart'; // <-- Crucial Import

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Save User profile info to DB
  Future<void> createUserProfile(UserModel user) async {
    await _db
        .collection('users')
        .doc(user.uid)
        .set(user.toMap())
        .timeout(const Duration(seconds: 12));
  }

  // Merge profile data for existing auth users.
  Future<void> upsertUserProfile(UserModel user) async {
    await _db
        .collection('users')
        .doc(user.uid)
        .set(user.toMap(), SetOptions(merge: true))
        .timeout(const Duration(seconds: 12));
  }

  // Fetch single User info
  Future<UserModel> getUserProfile(String uid) async {
    DocumentSnapshot doc = await _db
        .collection('users')
        .doc(uid)
        .get()
        .timeout(const Duration(seconds: 12));
    return UserModel.fromMap(doc.data() as Map<String, dynamic>, doc.id);
  }

  // CREATE: Post a new ride request document to Firestore
  Future<String> createRideRequest(RideRequest rideRequest) async {
    DocumentReference docRef = await _db
        .collection('rides')
        .add(rideRequest.toMap())
        .timeout(const Duration(seconds: 12));
    return docRef.id;
  }

  // STREAM: Real-time tracking of a ride request document
  Stream<RideRequest> streamRideStatus(String rideId) {
    return _db.collection('rides').doc(rideId).snapshots().map((snapshot) {
      if (!snapshot.exists || snapshot.data() == null) {
        throw Exception("Ride not found");
      }
      return RideRequest.fromMap(snapshot.data()!, snapshot.id);
    });
  }
}
