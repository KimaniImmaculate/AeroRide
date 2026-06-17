import 'register_screen.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/auth_service.dart';
import '../../services/role_service.dart';
import '../driver/driver_home_screen.dart';
import '../rider/rider_home_screen.dart';
import '../admin/admin_dashboard.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

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

  Future<void> login() async {
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
  }

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
                        "Welcome to AeroRide",
                        style: GoogleFonts.urbanist(
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "Sign in to your account to continue",
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
                      const SizedBox(height: 24),

                      // Route Nav text link to register
                      TextButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const RegisterScreen(),
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
