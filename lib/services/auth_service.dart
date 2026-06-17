import 'package:firebase_auth/firebase_auth.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Future<User?> loginUser({
    required String email,
    required String password,
  }) async {
    try {
      UserCredential userCredential =
          await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      return userCredential.user;
    } catch (e) {
      print(e.toString());
      return null;
    }
  }
  Future<User?> registerUser({
  required String email,
  required String password,
}) async {
  try {

    UserCredential userCredential =
        await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );

    return userCredential.user;

  } catch (e) {

    print(e.toString());
    return null;
  }
}
Future<void> sendPasswordReset(String email) async {
  try {
    await _auth.sendPasswordResetEmail(email: email);
  } catch (e) {
    // Rethrow the error to catch it in the UI and show a clean message
    throw Exception(e.toString());
  }
}
}