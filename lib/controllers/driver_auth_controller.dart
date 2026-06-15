import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';

class DriverAuthController extends ChangeNotifier {
  final AuthService _authService = AuthService();
  final FirestoreService _firestoreService = FirestoreService();

  String? _verificationId;
  bool _isLoading = false;
  bool _isCodeSent = false;

  // Collected Metadata
  String name = "";
  String email = "";
  String licenseNumber = "";
  String plateNumber = "";
  String vehicleType = "tulia"; // Default mapped value
  String phoneNumber = "";

  int _currentStep = 0;

  bool get isLoading => _isLoading;
  bool get isCodeSent => _isCodeSent;
  String? get verificationId => _verificationId;
  int get currentStep => _currentStep;

  void resetState() {
    _verificationId = null;
    _isLoading = false;
    _isCodeSent = false;
    _currentStep = 0;
    notifyListeners();
  }

  void nextStep() {
    _currentStep++;
    notifyListeners();
  }

  void prevStep() {
    if (_currentStep > 0) _currentStep--;
    notifyListeners();
  }

  /// Step 1: Trigger Firebase Phone Verification
  Future<void> sendOtp(String phoneNumber) async {
    _isLoading = true;
    this.phoneNumber = phoneNumber;
    notifyListeners();

    try {
      await _authService.signUpWithPhoneOtp(
        phoneNumber: phoneNumber,
        onCodeSent: (id) {
          _verificationId = id;
          _isCodeSent = true;
          _isLoading = false;
          notifyListeners();
        },
        onFailed: (error) {
          _isLoading = false;
          notifyListeners();
          throw Exception(error);
        },
      );
    } catch (e) {
      _isLoading = false;
      notifyListeners();
      rethrow;
    }
  }

  /// Step 2: Complete sign-in with the 6-digit SMS code
  Future<User?> verifyOtp(String smsCode,
      {Map<String, dynamic>? driverData}) async {
    if (_verificationId == null) throw Exception("Verification ID is missing.");

    _isLoading = true;
    notifyListeners();

    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: _verificationId!,
        smsCode: smsCode.trim(),
      );

      final userCredential =
          await FirebaseAuth.instance.signInWithCredential(credential);
      final user = userCredential.user;

      // Finalize Firestore record with collected metadata
      await _firestoreService.initializeDriverProfile(
        user!.uid,
        name: name,
        email: email,
        licenseNumber: licenseNumber,
        plateNumber: plateNumber,
        vehicleType: vehicleType,
      );

      _isLoading = false;
      notifyListeners();
      return user;
    } catch (e) {
      _isLoading = false;
      notifyListeners();
      rethrow;
    }
  }
}
