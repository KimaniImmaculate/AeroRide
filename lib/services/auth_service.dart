import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:aeroride/models/user_model.dart';
import 'package:aeroride/services/firestore_service.dart';
import 'package:firebase_auth_platform_interface/firebase_auth_platform_interface.dart'
    show FirebaseAuthPlatform;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/foundation.dart'; // For debugPrint and kIsWeb

/// A wrapper class to pass both a potential User or an active MFA Session back to your UI
class AeroRideLoginResult {
  final User? user;
  final MultiFactorResolver? mfaResolver;
  final bool isMfaRequired;

  AeroRideLoginResult({
    this.user,
    this.mfaResolver,
    this.isMfaRequired = false,
  });
}

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;
  final FirestoreService _firestoreService = FirestoreService();

  ConfirmationResult? _webConfirmationResult;
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
        return 'Sign-in provider is not enabled in Firebase Auth.';
      case 'weak-password':
        return 'Password is too weak.';
      case 'email-already-in-use':
        return 'That email is already in use.';
      case 'credential-already-in-use':
        return 'This account is already linked to another user.';
      case 'network-request-failed':
        return 'Network error. Check your connection and try again.';
      case 'too-many-requests':
        return 'Too many attempts. Try again later.';
      case 'multi-factor-auth-required':
        return 'Two-step verification code required.';
      case 'quota-exceeded':
        return 'SMS daily limits exceeded. Try again later.';
      case 'invalid-verification-code':
        return 'The code you entered is incorrect.';
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

  // ✨ SILENT ANONYMOUS SIGN IN (Lazy Authentication)
  Future<User?> signInAnonymously() async {
    try {
      debugPrint(
          "👤 AeroRide: Signing in guest anonymously in the background...");
      UserCredential result =
          await _auth.signInAnonymously().timeout(const Duration(seconds: 12));
      User? user = result.user;

      if (user != null) {
        // Ensure Auth profile has a default name for immediate UI display
        await user.updateDisplayName("Guest Rider");
        await user.reload();

        UserModel guestUser = UserModel(
          uid: user.uid,
          name: "Guest Rider",
          email: "",
          role: "rider",
        );

        try {
          await _firestoreService
              .createUserProfile(guestUser)
              .timeout(const Duration(seconds: 8));
        } catch (error) {
          debugPrint('Silent guest profile write skipped or caught: $error');
        }
      }
      return user;
    } on FirebaseAuthException catch (e) {
      throw Exception(_authErrorMessage(e));
    } catch (e) {
      debugPrint("Anonymous Auth Error: $e");
      rethrow;
    }
  }

  // ✨ GOOGLE INTERACTION SIGN-IN ENGINE (v7.x API - Multiplatform Safe)
  Future<User?> signInWithGoogle() async {
    try {
      // 1. Initialize the plugin instance
      await _googleSignIn.initialize();

      AuthCredential credential;

      // 2. Platform Check: If running on Web, bypass native SDK sheet and use Firebase Web standard
      if (kIsWeb) {
        GoogleAuthProvider googleProvider = GoogleAuthProvider();

        // Force the account chooser every single time on the web
        googleProvider.setCustomParameters({
          'prompt': 'select_account',
        });

        final UserCredential userCredential =
            await _auth.signInWithPopup(googleProvider);
        final User? user = userCredential.user;

        if (user != null) {
          await syncGoogleUserProfile(user);
        }
        return user;
      }

      // 3. Native Flow (Android / iOS): Use version 7 specification
      if (_googleSignIn.supportsAuthenticate()) {
        final GoogleSignInAccount? googleUser =
            await _googleSignIn.authenticate();

        if (googleUser == null) {
          return null; // User cancelled the screen sheet
        }

        // Fetch the Identity Token
        final GoogleSignInAuthentication identityData =
            await googleUser.authentication;

        // Fetch the Authorization Access Token using the new v7 client layout
        final clientAuth = await googleUser.authorizationClient
            .authorizeScopes(['email', 'profile']);

        // Fixed: credential is safe, and both tokens map correctly now
        credential = GoogleAuthProvider.credential(
          accessToken: clientAuth.accessToken,
          idToken: identityData.idToken,
        );
      } else {
        throw Exception(
            "This platform does not have a known native authentication method.");
      }

      // 4. Complete login via credential payload for Mobile clients
      final UserCredential userCredential =
          await _auth.signInWithCredential(credential);
      final User? user = userCredential.user;

      if (user != null) {
        // Check if user exists in Firestore
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        if (!doc.exists) {
          await logout(); // Sign them out of Firebase/Google if no profile exists
          throw Exception(
              "No AeroRide account found for this email. Please sign up first to create your profile.");
        }
      }

      if (user != null) {
        await syncGoogleUserProfile(user);
      }

      return user;
    } on FirebaseAuthException catch (e) {
      throw Exception(_authErrorMessage(e));
    } catch (e) {
      debugPrint("Google Sign-In Error: $e");
      rethrow;
    }
  }

  /// HELPER: Normalizes phone numbers to E.164 format (+254...)
  String _normalizePhone(String phone) {
    String p = phone.trim().replaceAll(RegExp(r'\D'), '');
    // Handle already full format
    if (p.startsWith('254') && p.length == 12) {
      return '+$p';
    }
    // Handle local 07... format
    if (p.startsWith('0')) {
      return '+254${p.substring(1)}';
    }
    // Handle 7... format
    if (p.length == 9 && (p.startsWith('7') || p.startsWith('1'))) {
      return '+254$p';
    }
    return phone.startsWith('+') ? phone : '+$p';
  }

  // ✨ COMPATIBILITY SHIM: Single-shot signUp for legacy views
  Future<User?> signUp(
    String name,
    String email,
    String password,
    String role, {
    required String phoneNumber,
  }) async {
    // This bypasses the multi-step OTP flow for legacy components.
    // In production, use signUpWithPhoneOtp + verifyOtpAndCompleteSignup.
    try {
      final credential = await _auth
          .createUserWithEmailAndPassword(
            email: email.trim(),
            password: password.trim(),
          )
          .timeout(const Duration(seconds: 15));

      User? user = credential.user;
      if (user != null) {
        await user.updateDisplayName(name.trim());
        await user.reload();

        final freshUser = _auth.currentUser;
        final profile = UserModel(
          uid: freshUser!.uid,
          name: name,
          email: email,
          role: role,
        );

        final userMap = profile.toJson();
        userMap['phoneNumber'] = _normalizePhone(phoneNumber);
        await FirebaseFirestore.instance
            .collection('users')
            .doc(freshUser.uid)
            .set(userMap, SetOptions(merge: true));
      }
      return user;
    } on FirebaseAuthException catch (e) {
      throw Exception(_authErrorMessage(e));
    } catch (e) {
      debugPrint("Legacy Signup Error: $e");
      rethrow;
    }
  }

  // ✨ PRODUCTION SIGNUP FLOW: Trigger verifyPhoneNumber SMS OTP
  Future<void> signUpWithPhoneOtp({
    required String phoneNumber,
    required Function(String verificationId) onCodeSent,
    required Function(String error) onFailed,
    RecaptchaVerifier? webVerifier,
  }) async {
    try {
      final formattedPhone = _normalizePhone(phoneNumber);

      if (formattedPhone.isEmpty || !formattedPhone.startsWith('+')) {
        onFailed('Invalid phone number format. Please use +254XXXXXXXXX.');
        return;
      }
      if (kIsWeb) {
        final verifier = RecaptchaVerifier(
          auth: FirebaseAuthPlatform.instance,
          container: 'recaptcha-container',
          size: RecaptchaVerifierSize.compact,
        );

        try {
          _webConfirmationResult = await _auth.signInWithPhoneNumber(
            formattedPhone,
            verifier,
          );

          // ✅ FIX: Force the HTML box to close right here on structural success!
          verifier.clear();

          onCodeSent(_webConfirmationResult!.verificationId);
        } catch (authError) {
          verifier.clear(); // Clear on failure too
          rethrow;
        }
      } else {
        // NATIVE MOBILE CHANNELS
        await _auth.verifyPhoneNumber(
          phoneNumber: formattedPhone,
          timeout: const Duration(seconds: 60),
          verificationCompleted: (PhoneAuthCredential credential) async {},
          verificationFailed: (FirebaseAuthException e) {
            onFailed(_authErrorMessage(e));
          },
          codeSent: (String verificationId, int? resendToken) {
            onCodeSent(verificationId);
          },
          codeAutoRetrievalTimeout: (_) {},
        );
      }
    } catch (e) {
      debugPrint("Fatal Catch Block Triggered: $e");
      onFailed(
          e is FirebaseAuthException ? _authErrorMessage(e) : e.toString());
    }
  }

  // ✨ COMPLETE SIGNUP: Verify SMS code and link/create account
  Future<User?> verifyOtpAndCompleteSignup({
    required String verificationId,
    required String smsCode,
    required String name,
    required String email,
    required String password,
    String role = 'rider',
  }) async {
    try {
      User? currentUser = _auth.currentUser;

      UserCredential? result;

      if (kIsWeb && _webConfirmationResult != null) {
        // For Web, we confirm the token directly through the stored ConfirmationResult
        result = await _webConfirmationResult!.confirm(smsCode.trim());
      } else if (currentUser != null && currentUser.isAnonymous) {
        PhoneAuthCredential phoneCred = PhoneAuthProvider.credential(
          verificationId: verificationId,
          smsCode: smsCode.trim(),
        );
        await currentUser.linkWithCredential(phoneCred);

        AuthCredential emailCred = EmailAuthProvider.credential(
          email: email.trim(),
          password: password.trim(),
        );
        result = await currentUser.linkWithCredential(emailCred);
      } else {
        PhoneAuthCredential phoneCred = PhoneAuthProvider.credential(
          verificationId: verificationId,
          smsCode: smsCode.trim(),
        );
        // New user: Create email account and update profile
        result = await _auth
            .createUserWithEmailAndPassword(
              email: email.trim(),
              password: password.trim(),
            )
            .timeout(const Duration(seconds: 15));

        // Link phone factor to the new account
        await result.user?.linkWithCredential(phoneCred);
      }

      User? finalUser = result?.user;
      if (finalUser != null) {
        await finalUser.updateDisplayName(name.trim());
        await finalUser.reload();
        finalUser = _auth.currentUser;

        UserModel upgradedUser = UserModel(
          uid: finalUser!.uid,
          name: name,
          email: email,
          role: role,
        );

        final userMap = upgradedUser.toJson();
        userMap['phoneNumber'] = finalUser.phoneNumber;
        await FirebaseFirestore.instance
            .collection('users')
            .doc(finalUser.uid)
            .set(userMap, SetOptions(merge: true));
      }
      return finalUser;
    } on TimeoutException {
      throw Exception(
          'Request timed out. Please check your internet and try again.');
    } on FirebaseAuthException catch (e) {
      throw Exception(_authErrorMessage(e));
    } catch (e) {
      debugPrint("Signup Error: $e");
      rethrow;
    }
  }

  // ─── ADDED: GOOGLE SIGN-IN PROFILE SYNCHRONIZATION ───
  Future<void> syncGoogleUserProfile(User user) async {
    try {
      final userDocRef =
          FirebaseFirestore.instance.collection('users').doc(user.uid);
      final docSnapshot =
          await userDocRef.get().timeout(const Duration(seconds: 10));

      if (docSnapshot.exists) {
        // Just update existing profile with latest Google info if needed
        await userDocRef.update({
          'profilePic': user.photoURL ?? '',
          'lastLogin': FieldValue.serverTimestamp(),
        });
        debugPrint("Google profile synced for ${user.displayName}.");
      }
    } catch (e) {
      debugPrint("Error running profile synchronization task: $e");
    }
  }

  // ✨ UNIFIED LOGIN: Accept Email OR Phone Number
  Future<AeroRideLoginResult> login(String identity, String password) async {
    try {
      String email = identity.trim();

      // If input is a phone number, resolve the email from Firestore
      if (!email.contains('@')) {
        final formattedPhone = _normalizePhone(email);
        final userQuery = await FirebaseFirestore.instance
            .collection('users')
            .where('phoneNumber', isEqualTo: formattedPhone)
            .limit(1)
            .get();

        if (userQuery.docs.isEmpty) {
          throw Exception('No account found for this phone number.');
        }
        email = userQuery.docs.first.get('email');
      }

      UserCredential result = await _auth
          .signInWithEmailAndPassword(
            email: email,
            password: password.trim(),
          )
          .timeout(const Duration(seconds: 15));

      return AeroRideLoginResult(user: result.user);
    } on FirebaseAuthMultiFactorException catch (e) {
      debugPrint(
          "🔒 AeroRide Identity Platform: Two-Step Challenge triggered.");
      return AeroRideLoginResult(
        mfaResolver: e.resolver,
        isMfaRequired: true,
      );
    } on FirebaseAuthException catch (e) {
      throw Exception(_authErrorMessage(e));
    } catch (e) {
      debugPrint("Login Error: $e");
      rethrow;
    }
  }

  // ✨ MFA STEP 2 - INTERCEPT SESSIONS TO START SMS HANDSHAKE
  Future<String> sendMfaVerificationSms({
    required MultiFactorResolver resolver,
    int hintIndex = 0,
  }) async {
    final completer = Completer<String>();

    try {
      MultiFactorInfo selectedHint = resolver.hints[hintIndex];
      MultiFactorSession session = resolver.session;

      if (selectedHint is! PhoneMultiFactorInfo) {
        throw Exception(
            "The selected authentication factor is not an SMS option.");
      }

      await _auth
          .verifyPhoneNumber(
            multiFactorSession: session,
            multiFactorInfo: selectedHint,
            verificationCompleted: (_) {},
            verificationFailed: (FirebaseAuthException error) {
              if (!completer.isCompleted) {
                completer.completeError(Exception(_authErrorMessage(error)));
              }
            },
            codeSent: (String verificationId, int? resendToken) {
              if (!completer.isCompleted) {
                completer.complete(verificationId);
              }
            },
            codeAutoRetrievalTimeout: (_) {},
          )
          .timeout(const Duration(seconds: 15));

      return completer.future;
    } on TimeoutException {
      throw Exception('SMS request timed out. Please check your network.');
    } on FirebaseAuthException catch (e) {
      throw Exception(_authErrorMessage(e));
    } catch (e) {
      debugPrint("SMS Dispatch Error: $e");
      rethrow;
    }
  }

  // ✨ MFA STEP 3 - SUBMIT THE ONE-TIME PASSWORD ASSERTION
  Future<User?> completeMfaVerification({
    required MultiFactorResolver resolver,
    required String verificationId,
    required String smsCode,
  }) async {
    try {
      PhoneAuthCredential credential = PhoneAuthProvider.credential(
        verificationId: verificationId,
        smsCode: smsCode.trim(),
      );

      MultiFactorAssertion assertion =
          PhoneMultiFactorGenerator.getAssertion(credential);

      UserCredential result = await resolver
          .resolveSignIn(assertion)
          .timeout(const Duration(seconds: 15));

      return result.user;
    } on TimeoutException {
      throw Exception('Verification timeout. Please check your network.');
    } on FirebaseAuthException catch (e) {
      throw Exception(_authErrorMessage(e));
    } catch (e) {
      debugPrint("MFA Complete Resolution Error: $e");
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

    final nameToUse = (name == null || name.trim().isEmpty)
        ? (user.displayName ??
            (user.isAnonymous ? 'Guest Rider' : 'AeroRide User'))
        : name.trim();

    // Sync the name back to Firebase Auth if provided and different
    if (user.displayName != nameToUse) {
      await user.updateDisplayName(nameToUse);
    }

    final profile = UserModel(
      uid: user.uid,
      name: nameToUse,
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

  // 3. LOGOUT (Completely clears both Firebase and Google system sessions)
  Future<void> logout() async {
    try {
      // Forcefully wipe Google's background OAuth memory to clear automatic auto-selection behaviors
      await _googleSignIn.disconnect();
      await _googleSignIn.signOut();
    } catch (e) {
      debugPrint("Non-fatal error clearing Google OAuth session: $e");
    }

    // Finally, close out the primary Firebase session wrapper
    await _auth.signOut();
  }
}
