import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:aeroride/screens/views/driver_dashboard_view.dart';
import 'package:provider/provider.dart';
import 'package:aeroride/services/auth_service.dart';
import 'package:aeroride/services/driver_auth_flow_modal.dart';
import 'package:aeroride/services/firestore_service.dart';

class DriverWelcomeView extends StatelessWidget {
  final User? user;
  const DriverWelcomeView({super.key, this.user});

  static const Color signatureTurquoise = Color(0xFF16A085);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Background Image
          Positioned.fill(
            child: Image.asset(
              'assets/busy city at night.jpg', // Using a similar luxury background
              fit: BoxFit.cover,
            ),
          ),
          // Dark Overlay
          Positioned.fill(
            child: Container(
              color: Colors.black.withOpacity(0.7),
            ),
          ),
          // Content
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    "Your Cockpit Awaits",
                    style: GoogleFonts.urbanist(
                      fontSize: 38,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: -0.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    "Elevate your earnings with AeroRide's premium platform. Seamless dispatches, real-time telemetry, and unparalleled support.",
                    style: GoogleFonts.urbanist(
                      fontSize: 16,
                      color: Colors.white70,
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 60),
                  ElevatedButton(
                    onPressed: () async {
                      final authService =
                          Provider.of<AuthService>(context, listen: false);
                      final currentUser = FirebaseAuth.instance.currentUser;

                      // 1. Session Check: Immediate bypass for authenticated drivers
                      if (currentUser != null && !currentUser.isAnonymous) {
                        final isDriver =
                            await authService.isCurrentUserDriver();
                        if (isDriver && context.mounted) {
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(
                                builder: (_) =>
                                    DriverDashboardView(user: currentUser)),
                          );
                          return;
                        }
                      }

                      // 2. Launch Floating Turquoise Auth Dialog
                      if (!context.mounted) return;

                      final emailController = TextEditingController();
                      final passwordController = TextEditingController();
                      final nameController = TextEditingController();
                      final phoneController = TextEditingController();
                      final licenseController = TextEditingController();
                      final plateController = TextEditingController();
                      final otpController = TextEditingController();

                      bool isSignUpMode = true;
                      bool isProcessingAuth = false;
                      bool isWaitingForSignupOtp = false;
                      String currentVerificationId = '';
                      Timer? countdownTimer;
                      int resendCountdown = 0;

                      showDialog(
                        context: context,
                        barrierDismissible: false,
                        builder: (dialogCtx) => StatefulBuilder(
                            builder: (statefulCtx, setDialogState) {
                          void startCountdown() {
                            setDialogState(() => resendCountdown = 60);
                            countdownTimer?.cancel();
                            countdownTimer = Timer.periodic(
                                const Duration(seconds: 1), (timer) {
                              setDialogState(() {
                                if (resendCountdown > 0) {
                                  resendCountdown--;
                                } else {
                                  timer.cancel();
                                }
                              });
                            });
                          }

                          return Dialog(
                            backgroundColor: signatureTurquoise,
                            elevation: 16,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20)),
                            child: Container(
                              constraints: const BoxConstraints(maxWidth: 400),
                              padding: const EdgeInsets.all(24),
                              child: SingleChildScrollView(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        const Icon(Icons.shield,
                                            color: Colors.white, size: 28),
                                        IconButton(
                                          icon: const Icon(Icons.close,
                                              color: Colors.white),
                                          onPressed: () {
                                            countdownTimer?.cancel();
                                            Navigator.pop(dialogCtx);
                                          },
                                        )
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      isSignUpMode
                                          ? "Driver Registration"
                                          : "Welcome Back",
                                      style: GoogleFonts.urbanist(
                                          fontSize: 24,
                                          fontWeight: FontWeight.w900,
                                          color: Colors.white),
                                    ),
                                    const SizedBox(height: 16),
                                    if (isWaitingForSignupOtp) ...[
                                      // Leg 1: OTP Verification
                                      TextField(
                                        controller: otpController,
                                        keyboardType: TextInputType.number,
                                        maxLength: 6,
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                            color: Colors.black87,
                                            fontSize: 32,
                                            letterSpacing: 8,
                                            fontWeight: FontWeight.bold),
                                        decoration: const InputDecoration(
                                            hintText: "000000",
                                            hintStyle: TextStyle(
                                                color: Colors.white38),
                                            counterText: ""),
                                      ),
                                      const SizedBox(height: 10),
                                      Text(
                                          "Enter the 6-digit code sent to your phone",
                                          textAlign: TextAlign.center,
                                          style: GoogleFonts.urbanist(
                                              color: Colors.white70,
                                              fontSize: 13)),
                                    ] else ...[
                                      // Leg 2: Form Fields
                                      if (isSignUpMode) ...[
                                        _buildAuthField(
                                            nameController,
                                            "Full Legal Name",
                                            Icons.person_outline),
                                        const SizedBox(height: 12),
                                        _buildAuthField(
                                            phoneController,
                                            "Phone (07...)",
                                            Icons.phone_android_outlined,
                                            inputType: TextInputType.phone),
                                        const SizedBox(height: 8),
                                        _buildAuthField(
                                            licenseController,
                                            "Driving License Number",
                                            Icons.badge_outlined),
                                        const SizedBox(height: 8),
                                        _buildAuthField(
                                            plateController,
                                            "Vehicle Number Plate",
                                            Icons.numbers_outlined),
                                        const SizedBox(height: 8),
                                      ],
                                      _buildAuthField(emailController,
                                          "Email Address", Icons.email_outlined,
                                          inputType:
                                              TextInputType.emailAddress),
                                      const SizedBox(height: 8),
                                      _buildAuthField(passwordController,
                                          "Password", Icons.lock_outline,
                                          isObscure: true),
                                    ],
                                    const SizedBox(height: 24),
                                    ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.white,
                                        foregroundColor: Colors.black,
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 16),
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(12)),
                                      ),
                                      onPressed: isProcessingAuth
                                          ? null
                                          : () async {
                                              setDialogState(() =>
                                                  isProcessingAuth = true);
                                              try {
                                                if (isWaitingForSignupOtp) {
                                                  final user = await authService
                                                      .verifyOtpAndCompleteSignup(
                                                    verificationId:
                                                        currentVerificationId,
                                                    smsCode: otpController.text
                                                        .trim(),
                                                    name: nameController.text
                                                        .trim(),
                                                    email: emailController.text
                                                        .trim(),
                                                    password: passwordController
                                                        .text
                                                        .trim(),
                                                    role: 'driver',
                                                  );
                                                  if (user != null &&
                                                      dialogCtx.mounted) {
                                                    // Initialize detailed driver metadata in Firestore
                                                    final firestore =
                                                        FirestoreService();
                                                    await firestore
                                                        .initializeDriverProfile(
                                                      user.uid,
                                                      name: nameController.text
                                                          .trim(),
                                                      email: emailController
                                                          .text
                                                          .trim(),
                                                      phoneNumber:
                                                          user.phoneNumber,
                                                      licenseNumber:
                                                          licenseController.text
                                                              .trim(),
                                                      plateNumber:
                                                          plateController.text
                                                              .trim(),
                                                      vehicleType:
                                                          'tulia', // Default tier
                                                    );

                                                    Navigator.pop(dialogCtx);
                                                    Navigator.pushReplacement(
                                                        context,
                                                        MaterialPageRoute(
                                                            builder: (_) =>
                                                                DriverDashboardView(
                                                                    user:
                                                                        user)));
                                                  }
                                                } else if (isSignUpMode) {
                                                  await authService
                                                      .signUpWithPhoneOtp(
                                                    phoneNumber: phoneController
                                                        .text
                                                        .trim(),
                                                    onCodeSent: (id) {
                                                      setDialogState(() {
                                                        currentVerificationId =
                                                            id;
                                                        isWaitingForSignupOtp =
                                                            true;
                                                        isProcessingAuth =
                                                            false;
                                                      });
                                                      startCountdown();
                                                    },
                                                    onFailed: (err) {
                                                      setDialogState(() =>
                                                          isProcessingAuth =
                                                              false);
                                                      ScaffoldMessenger.of(
                                                              context)
                                                          .showSnackBar(
                                                              SnackBar(
                                                                  content: Text(
                                                                      err)));
                                                    },
                                                  );
                                                } else {
                                                  final result =
                                                      await authService.login(
                                                          emailController.text
                                                              .trim(),
                                                          passwordController
                                                              .text
                                                              .trim());
                                                  if (!result.isMfaRequired &&
                                                      dialogCtx.mounted) {
                                                    Navigator.pop(dialogCtx);
                                                    Navigator.pushReplacement(
                                                        context,
                                                        MaterialPageRoute(
                                                            builder: (_) =>
                                                                DriverDashboardView(
                                                                    user: result
                                                                        .user)));
                                                  }
                                                }
                                              } on FirebaseAuthException catch (e) {
                                                setDialogState(() =>
                                                    isProcessingAuth = false);
                                                if (e.code ==
                                                    'email-already-in-use') {
                                                  _handleEmailConflict(
                                                      statefulCtx,
                                                      setDialogState,
                                                      isSignUpMode);
                                                } else {
                                                  ScaffoldMessenger.of(context)
                                                      .showSnackBar(SnackBar(
                                                          content: Text(e
                                                                  .message ??
                                                              'Auth Failed')));
                                                }
                                              } finally {
                                                setDialogState(() =>
                                                    isProcessingAuth = false);
                                              }
                                            },
                                      child: isProcessingAuth
                                          ? const SizedBox(
                                              height: 20,
                                              width: 20,
                                              child: CircularProgressIndicator(
                                                  strokeWidth: 3,
                                                  color: Colors.black))
                                          : Text(
                                              isWaitingForSignupOtp
                                                  ? "VERIFY & INITIALIZE"
                                                  : (isSignUpMode
                                                      ? "CREATE DRIVER ACCOUNT"
                                                      : "SECURE LOGIN"),
                                              style: GoogleFonts.urbanist(
                                                  fontWeight: FontWeight.w900,
                                                  letterSpacing: 0.5),
                                            ),
                                    ),
                                    const SizedBox(height: 16),
                                    TextButton(
                                      onPressed: isProcessingAuth
                                          ? null
                                          : () {
                                              setDialogState(() {
                                                isSignUpMode = !isSignUpMode;
                                                isWaitingForSignupOtp = false;
                                              });
                                            },
                                      child: Text(
                                        isSignUpMode
                                            ? "Already a Driver? Log In"
                                            : "No account? Register as Driver",
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          signatureTurquoise, // Use existing theme color
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Text(
                      "START YOUR JOURNEY",
                      style: GoogleFonts.urbanist(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAuthField(
      TextEditingController controller, String label, IconData icon,
      {TextInputType inputType = TextInputType.text, bool isObscure = false}) {
    return TextField(
      controller: controller,
      obscureText: isObscure,
      keyboardType: inputType,
      style:
          const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.black45, fontSize: 13),
        prefixIcon: Icon(icon, color: signatureTurquoise, size: 20),
        filled: true,
        fillColor: Colors.white,
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.black87, width: 1.5)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }

  void _handleEmailConflict(
      BuildContext context, Function setDialogState, bool isSignUpMode) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Account Exists"),
        content: const Text(
            "This email is already registered. Switch to login mode?"),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          TextButton(
              onPressed: () {
                setDialogState(() {
                  Navigator.pop(ctx);
                  // We can't directly modify the caller's state easily without a controller,
                  // but this triggers the visual switch in the parent StatefulBuilder
                });
              },
              child: const Text("Switch")),
        ],
      ),
    );
  }
}
