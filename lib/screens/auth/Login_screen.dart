import 'register_screen.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/auth_service.dart';
import '../../services/role_service.dart';
import '../driver/driver_home_screen.dart';
import '../admin/admin_dashboard.dart';
import '../rider/rider_home_screen.dart';

class LoginScreen extends StatefulWidget {
  final String? expectedRole;
  const LoginScreen({super.key, this.expectedRole});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  final AuthService authService = AuthService();
  final RoleService roleService = RoleService();

  bool isLoading = false;
  bool obscurePassword = true;

  // AeroRide Turquoise Theme Color
  static const Color primaryTurquoise = Color(0xFF16A085);
  Future<void> sendOtpChallenge({
    required String phoneNumber,
    required Function(String verificationId) onCodeSent,
  }) async {
    String formattedPhone = phoneNumber.trim();
    if (formattedPhone.startsWith('0')) {
      formattedPhone = '+254${formattedPhone.substring(1)}';
    } else if (!formattedPhone.startsWith('+')) {
      formattedPhone = '+$formattedPhone';
    }

    await FirebaseAuth.instance.verifyPhoneNumber(
      phoneNumber: formattedPhone,
      verificationCompleted: (PhoneAuthCredential credential) async {
        try {
          await FirebaseAuth.instance.currentUser?.linkWithCredential(credential);
        } on FirebaseAuthException catch (linkError) {
          if (linkError.code != 'provider-already-linked' &&
              linkError.code != 'credential-already-in-use' &&
              linkError.code != 'account-exists-with-different-credential') {
            debugPrint("Verification completed auto-link error: $linkError");
          }
        }
      },
      verificationFailed: (FirebaseAuthException e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text("❌ SMS 2FA Delivery Failed: ${e.message}"),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating),
        );
        setState(() {
          isLoading = false;
        });
      },
      codeSent: (String verificationId, int? resendToken) {
        onCodeSent(verificationId);
      },
      codeAutoRetrievalTimeout: (String verificationId) {},
    );
  }

  // 🌟 Enforces verification challenge UI before dashboard access routing
  void show2FaOtpDialog(String verificationId, String role) {
    final TextEditingController otpController = TextEditingController();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1A2522),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(
                color: Colors.white.withValues(alpha: 0.12), width: 1),
          ),
          title: Row(
            children: [
              const Icon(Icons.security_rounded,
                  color: primaryTurquoise, size: 28),
              const SizedBox(width: 12),
              Text(
                "Two-Factor Auth",
                style: GoogleFonts.urbanist(
                    fontWeight: FontWeight.bold,
                    fontSize: 22,
                    color: Colors.white),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "A secure verification code has been dispatched to your registered phone number. Enter it below to proceed.",
                style: GoogleFonts.urbanist(
                    fontSize: 14,
                    color: Colors.white.withValues(alpha: 0.65),
                    height: 1.4),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: otpController,
                keyboardType: TextInputType.number,
                maxLength: 6,
                style: GoogleFonts.urbanist(color: Colors.white),
                decoration: InputDecoration(
                  labelText: "6-Digit Code",
                  labelStyle:
                      TextStyle(color: Colors.white.withValues(alpha: 0.5)),
                  prefixIcon:
                      const Icon(Icons.pin_outlined, color: primaryTurquoise),
                  filled: true,
                  fillColor: Colors.black.withValues(alpha: 0.25),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide:
                        BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide:
                        BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide:
                        const BorderSide(color: primaryTurquoise, width: 2),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                setState(() {
                  isLoading = false;
                });
              },
              child: Text("Cancel",
                  style: GoogleFonts.urbanist(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontWeight: FontWeight.w600)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryTurquoise,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
              onPressed: () async {
                try {
                  PhoneAuthCredential credential = PhoneAuthProvider.credential(
                    verificationId: verificationId,
                    smsCode: otpController.text.trim(),
                  );

                  // Complete the verification block check by linking the credential to the current user session
                  try {
                    await FirebaseAuth.instance.currentUser?.linkWithCredential(credential);
                  } on FirebaseAuthException catch (linkError) {
                    if (linkError.code != 'provider-already-linked' &&
                        linkError.code != 'credential-already-in-use' &&
                        linkError.code != 'account-exists-with-different-credential') {
                      rethrow;
                    }
                  }

                  if (!mounted) return;
                  Navigator.pop(context); // Close dialog

                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("Login Successful"),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );

                  // Route based on role after 2FA verified.
                  _navigateByRole(role, isRiderSubFlow: true);
                } catch (e) {
                  debugPrint("OTP Verification Error: $e");
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        backgroundColor: Colors.red,
                        content: Text(
                            "Error: $e",
                            style: GoogleFonts.urbanist(color: Colors.white))),
                  );
                }
              },
              child: Text("Verify & Enter",
                  style: GoogleFonts.urbanist(
                      color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  /// Central role-based routing. Always navigates definitively — never
  /// leaves the user stranded on the login screen after a successful auth.
  ///
  /// [isRiderSubFlow] — true when LoginScreen was pushed as a sub-flow from
  /// the RiderHomeScreen's anonymous guard (so we pop instead of push, to
  /// preserve the rider's already-entered coordinates).
  void _navigateByRole(String? role, {bool isRiderSubFlow = false}) {
    if (!mounted) return;

    if (role == 'admin') {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const AdminDashboard()),
        (route) => false,
      );
    } else if (role == 'driver') {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const DriverHomeScreen()),
        (route) => false,
      );
    } else if (role == 'rider') {
      if (isRiderSubFlow && Navigator.of(context).canPop()) {
        // Pop back to RiderHomeScreen so the pre-entered coordinates are kept.
        Navigator.of(context).pop(true);
      } else {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const RiderHomeScreen()),
          (route) => false,
        );
      }
    } else {
      // Unknown or null role — show a clear error instead of silently routing
      // to the wrong dashboard.
      setState(() => isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.orange.shade800,
          behavior: SnackBarBehavior.floating,
          content: Text(
            role == null
                ? "Your account role is not set. Please contact support."
                : "Unrecognised role '$role'. Please contact support.",
            style: GoogleFonts.urbanist(color: Colors.white),
          ),
        ),
      );
    }
  }

  Future<void> login() async {
    setState(() {
      isLoading = true;
    });

    final user = await authService.loginUser(
      email: emailController.text.trim(),
      password: passwordController.text.trim(),
    );

    if (user != null) {
      // 1. Fetch user's profile info from Firestore to extract their registered phone number
      try {
        DocumentSnapshot userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        final data = userDoc.data() as Map<String, dynamic>?;
        bool isFlagged = data?['isFlagged'] ?? false;

        if (isFlagged) {
          await FirebaseAuth.instance.signOut();
          setState(() {
            isLoading = false;
          });
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
              content: Text("This account has been suspended for violating terms."),
            ),
          );
          return;
        }

        String? role = await roleService.getUserRole(user.uid);

        // Grab phone number from database map data
        String? registeredPhone =
            (userDoc.data() as Map<String, dynamic>?)?['phone'];

        if (registeredPhone != null && registeredPhone.isNotEmpty) {
          if (!mounted) return;

          // 2. Credentials matched! Fire up the 2FA SMS Gateway Challenge
          await sendOtpChallenge(
            phoneNumber: registeredPhone,
            onCodeSent: (verificationId) {
              setState(() {
                isLoading = false;
              });
              show2FaOtpDialog(verificationId, role ?? 'rider');
            },
          );
        } else {
          // Fallback: no 2FA phone on profile — route directly by role.
          setState(() => isLoading = false);
          if (!mounted) return;
          // isRiderSubFlow=true: if a rider was already on the Rider Dashboard
          // (anonymous) and the login was triggered by requestRide(), we pop
          // back so the coordinates they entered are preserved.
          _navigateByRole(role, isRiderSubFlow: true);
        }
      } catch (e) {
        setState(() {
          isLoading = false;
        });
        debugPrint("Error pulling user verification credentials: $e");
      }
    } else {
      setState(() {
        isLoading = false;
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          content:
              Text("Login Failed! Please check your credentials and try again"),
        ),
      );
    }
  }

  /*Future<void> login() async {
    setState(() {
      isLoading = true;
    });

    final user = await authService.loginUser(
      email: emailController.text.trim(),
      password: passwordController.text.trim(),
    );

    setState(() {
      isLoading = false;
    });

    if (user != null) {
      String? role = await roleService.getUserRole(user.uid);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Login Successful"),
          behavior: SnackBarBehavior.floating,
        ),
      );

      if (role == 'admin') {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => const AdminDashboard(),
          ),
        );
      } else if (role == 'driver') {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => const DriverHomeScreen(),
          ),
        );
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => const RiderHomeScreen(),
          ),
        );
      }
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          content:
              Text("Login Failed! Please check your credentials and try again"),
        ),
      );
    }
  }*/

  void showForgotPasswordDialog() {
    final TextEditingController resetEmailController = TextEditingController();
    resetEmailController.text = emailController.text.trim();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor:
              const Color(0xFF1A2522), // Dark Slate blended with Turquoise
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(
                color: Colors.white.withValues(alpha: 0.12), width: 1),
          ),
          title: Row(
            children: [
              const Icon(Icons.lock_reset_rounded,
                  color: primaryTurquoise, size: 28),
              const SizedBox(width: 12),
              Text(
                "Reset Password",
                style: GoogleFonts.urbanist(
                    fontWeight: FontWeight.bold,
                    fontSize: 22,
                    color: Colors.white),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Enter your email address and we will send you a secure link to reset your password.",
                style: GoogleFonts.urbanist(
                    fontSize: 14,
                    color: Colors.white.withValues(alpha: 0.65),
                    height: 1.4),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: resetEmailController,
                keyboardType: TextInputType.emailAddress,
                style: GoogleFonts.urbanist(color: Colors.white),
                decoration: InputDecoration(
                  labelText: "Email Address",
                  labelStyle:
                      TextStyle(color: Colors.white.withValues(alpha: 0.5)),
                  prefixIcon:
                      const Icon(Icons.email_outlined, color: primaryTurquoise),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.05),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide:
                        BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide:
                        BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide:
                        const BorderSide(color: primaryTurquoise, width: 2),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text("Cancel",
                  style: GoogleFonts.urbanist(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontWeight: FontWeight.w600)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryTurquoise,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
              onPressed: () async {
                String email = resetEmailController.text.trim();
                if (email.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text("Please enter your email"),
                        behavior: SnackBarBehavior.floating),
                  );
                  return;
                }

                try {
                  await authService.sendPasswordReset(email);
                  if (!mounted) return;
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      backgroundColor: primaryTurquoise,
                      behavior: SnackBarBehavior.floating,
                      content: Text("Password reset link sent to $email 📩"),
                    ),
                  );
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      backgroundColor: Colors.red,
                      behavior: SnackBarBehavior.floating,
                      content:
                          Text("Error: Email address not found or invalid."),
                    ),
                  );
                }
              },
              child: Text("Send Link",
                  style: GoogleFonts.urbanist(
                      color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // 🌆 City Background Asset
          Positioned.fill(
            child: Image.asset(
              'assets/busy city at night.jpg',
              fit: BoxFit.cover,
            ),
          ),
          // 🕶️ Tint Overlay
          Positioned.fill(
            child: Container(
              color: Colors.black.withValues(alpha: 0.72),
            ),
          ),
          // Main Card UI Layout
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 440),
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: const Color(0xFF131D1A).withValues(
                        alpha: 0.85), // Web safe dark translucent teal glass
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.12),
                      width: 1.2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.4),
                        blurRadius: 32,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Turquoise Branded Icon Base
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: primaryTurquoise.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: primaryTurquoise.withValues(alpha: 0.3)),
                        ),
                        child: const Icon(
                          Icons.local_taxi_rounded,
                          size: 44,
                          color: primaryTurquoise,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        widget.expectedRole == 'admin' 
                            ? "Admin Portal Login" 
                            : widget.expectedRole == 'driver' 
                                ? "Driver Portal Login" 
                                : "Welcome to AeroRide",
                        style: GoogleFonts.urbanist(
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        widget.expectedRole != null 
                            ? "Sign in to your ${widget.expectedRole} account"
                            : "Sign in to your account to continue",
                        style: GoogleFonts.urbanist(
                          fontSize: 14,
                          color: Colors.white.withValues(alpha: 0.5),
                        ),
                      ),
                      const SizedBox(height: 36),

                      // Email Input Box
                      TextField(
                        controller: emailController,
                        keyboardType: TextInputType.emailAddress,
                        style: GoogleFonts.urbanist(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: "Email Address",
                          labelStyle: TextStyle(
                              color: Colors.white.withValues(alpha: 0.4)),
                          prefixIcon: const Icon(Icons.email_outlined,
                              color: primaryTurquoise),
                          filled: true,
                          fillColor: Colors.black.withValues(alpha: 0.25),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(
                                color: Colors.white.withValues(alpha: 0.08)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(
                                color: Colors.white.withValues(alpha: 0.08)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(
                                color: primaryTurquoise, width: 2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Password Input Box
                      TextField(
                        controller: passwordController,
                        obscureText: obscurePassword,
                        style: GoogleFonts.urbanist(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: "Password",
                          labelStyle: TextStyle(
                              color: Colors.white.withValues(alpha: 0.4)),
                          prefixIcon: const Icon(Icons.lock_outline_rounded,
                              color: primaryTurquoise),
                          suffixIcon: IconButton(
                            icon: Icon(
                              obscurePassword
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                              color: Colors.white.withValues(alpha: 0.4),
                            ),
                            onPressed: () {
                              setState(() {
                                obscurePassword = !obscurePassword;
                              });
                            },
                          ),
                          filled: true,
                          fillColor: Colors.black.withValues(alpha: 0.25),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(
                                color: Colors.white.withValues(alpha: 0.08)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(
                                color: Colors.white.withValues(alpha: 0.08)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(
                                color: primaryTurquoise, width: 2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Forgot Password action link
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: showForgotPasswordDialog,
                          style: TextButton.styleFrom(
                              minimumSize: Size.zero, padding: EdgeInsets.zero),
                          child: Text(
                            "Forgot Password?",
                            style: GoogleFonts.urbanist(
                                color: primaryTurquoise,
                                fontWeight: FontWeight.bold,
                                fontSize: 13),
                          ),
                        ),
                      ),
                      const SizedBox(height: 28),

                      // Primary Elevated Turquoise Button
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primaryTurquoise,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          onPressed: isLoading ? null : login,
                          child: isLoading
                              ? const SizedBox(
                                  height: 24,
                                  width: 24,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2.5,
                                  ),
                                )
                              : Text(
                                  "Sign In",
                                  style: GoogleFonts.urbanist(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white),
                                ),
                        ),
                      ),
                      if (widget.expectedRole != 'driver') ...[
                        const SizedBox(height: 24),
                        // Route Nav text link to register
                        TextButton(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => RegisterScreen(expectedRole: widget.expectedRole),
                              ),
                            );
                          },
                          child: RichText(
                            text: TextSpan(
                              style: GoogleFonts.urbanist(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Colors.white.withValues(alpha: 0.6),
                              ),
                              children: const [
                                TextSpan(text: "Don't have an account? "),
                                TextSpan(
                                  text: 'Register',
                                  style: TextStyle(
                                    color: primaryTurquoise,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
