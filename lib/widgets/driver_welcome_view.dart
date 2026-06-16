import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:aeroride/screens/views/driver_dashboard_view.dart';
import 'package:provider/provider.dart';
import 'package:aeroride/services/auth_service.dart';
import 'package:aeroride/services/firestore_service.dart';
import 'package:aeroride/widgets/driver_signup_view.dart';

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

                      // 2. Navigate to the Multi-Step Driver Signup View
                      if (!context.mounted) return;
                      // Present DriverSignupView as a dialog for the floating effect
                      showGeneralDialog(
                        context: context,
                        barrierDismissible: true,
                        barrierLabel: MaterialLocalizations.of(context)
                            .modalBarrierDismissLabel,
                        barrierColor: Colors.black.withOpacity(0.5),
                        transitionDuration: const Duration(milliseconds: 300),
                        pageBuilder: (BuildContext buildContext,
                            Animation animation, Animation secondaryAnimation) {
                          return const DriverSignupView();
                        },
                        transitionBuilder:
                            (context, animation, secondaryAnimation, child) {
                          return ScaleTransition(
                              scale: animation, child: child);
                        },
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
}
