import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'firestore_service.dart';
import '../models/user_model.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirestoreService _firestoreService = FirestoreService();
  DateTime? _profileWriteBackoffUntil;

  // Stream to listen to the user's login state (logged in vs logged out)
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  String _authErrorMessage(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-email':
        return 'Enter a valid email address.';
      case 'user-not-found':
        return 'No account found for that email.';
      case 'wrong-password':
        return 'Incorrect password.';
      case 'invalid-credential':
        return 'Invalid email or password.';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'operation-not-allowed':
        return 'Email/password sign-in is not enabled in Firebase Auth.';
      case 'weak-password':
        return 'Password is too weak.';
      case 'email-already-in-use':
        return 'That email is already in use.';
      case 'network-request-failed':
        return 'Network error. Check your connection and try again.';
      case 'too-many-requests':
        return 'Too many attempts. Try again later.';
      default:
        return e.message ?? e.code;
    }
  }

  bool _isNonFatalFirestoreError(Object error) {
    if (error is FirebaseException) {
      return error.code == 'resource-exhausted' ||
          error.code == 'deadline-exceeded' ||
          error.code == 'unavailable';
    }
    return false;
  }

  bool _shouldBackOffProfileWrite() {
    final until = _profileWriteBackoffUntil;
    if (until == null) return false;
    return DateTime.now().isBefore(until);
  }

  void _beginProfileWriteBackoff() {
    _profileWriteBackoffUntil = DateTime.now().add(const Duration(minutes: 2));
  }

  // 1. SIGN UP
  Future<User?> signUp(
    String name,
    String email,
    String password,
    String role,
  ) async {
    try {
      if (email.trim().isEmpty || password.trim().isEmpty) {
        throw Exception('Email and password are required.');
      }
      UserCredential result = await _auth
          .createUserWithEmailAndPassword(
            email: email.trim(),
            password: password.trim(),
          )
          .timeout(const Duration(seconds: 15));
      User? user = result.user;

      if (user != null) {
        // Automatically create their document record inside Firestore collection
        UserModel newUser = UserModel(
          uid: user.uid,
          name: name,
          email: email,
          role: role,
        );
        try {
          await _firestoreService
              .createUserProfile(newUser)
              .timeout(const Duration(seconds: 8));
        } catch (error) {
          if (_isNonFatalFirestoreError(error) || error is TimeoutException) {
            debugPrint('Signup profile write skipped: $error');
          } else {
            rethrow;
          }
        }
      }
      return user;
    } on TimeoutException {
      throw Exception(
        'Request timed out. Please check your internet and try again.',
      );
    } on FirebaseAuthException catch (e) {
      throw Exception(_authErrorMessage(e));
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        throw Exception(
          'Firestore permission denied. Update Firestore rules for authenticated users.',
        );
      }
      throw Exception(e.message ?? e.code);
    } catch (e) {
      debugPrint("Signup Error: $e");
      rethrow;
    }
  }

  // 2. LOGIN
  Future<User?> login(String email, String password) async {
    try {
      if (email.trim().isEmpty || password.trim().isEmpty) {
        throw Exception('Email and password are required.');
      }
      UserCredential result = await _auth
          .signInWithEmailAndPassword(
            email: email.trim(),
            password: password.trim(),
          )
          .timeout(const Duration(seconds: 15));
      return result.user;
    } on TimeoutException {
      throw Exception(
        'Login timed out. Please check your internet and try again.',
      );
    } on FirebaseAuthException catch (e) {
      throw Exception(_authErrorMessage(e));
    } catch (e) {
      debugPrint("Login Error: $e");
      rethrow;
    }
  }

  Future<void> ensureUserProfileForRole({
    required User user,
    required String role,
    String? name,
  }) async {
    if (_shouldBackOffProfileWrite()) {
      debugPrint('Profile upsert skipped: Firestore backoff window is active.');
      return;
    }

    final profile = UserModel(
      uid: user.uid,
      name: (name == null || name.trim().isEmpty)
          ? (user.displayName ?? 'AeroRide User')
          : name.trim(),
      email: user.email ?? '',
      role: role,
    );
    try {
      await _firestoreService
          .upsertUserProfile(profile)
          .timeout(const Duration(seconds: 8));
      _profileWriteBackoffUntil = null;
    } catch (error) {
      if (_isNonFatalFirestoreError(error) || error is TimeoutException) {
        _beginProfileWriteBackoff();
        debugPrint('Profile upsert skipped: $error');
      } else {
        rethrow;
      }
    }
  }

  // 3. LOGOUT
  Future<void> logout() async {
    await _auth.signOut();
  }
}
