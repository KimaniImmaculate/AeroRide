import 'package:cloud_firestore/cloud_firestore.dart';

class RoleService {

  final FirebaseFirestore _firestore =
      FirebaseFirestore.instance;

  Future<String?> getUserRole(String uid) async {

    try {

      DocumentSnapshot document =
          await _firestore
              .collection('users')
              .doc(uid)
              .get();

      return document['role'];

    } catch (e) {

      print(e.toString());
      return null;
    }
  }
}