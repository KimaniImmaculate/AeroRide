import 'package:flutter/material.dart';
import 'package:aeroride/services/auth_service.dart';
import 'package:aeroride/widgets/aero_welcome_view.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:aeroride/services/shimmer_placeholder.dart';

class AeroSplashScreen extends StatefulWidget {
  const AeroSplashScreen({super.key});

  @override
  State<AeroSplashScreen> createState() => _AeroSplashScreenState();
}

class _AeroSplashScreenState extends State<AeroSplashScreen> {
  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    // 1. Start pre-caching high-res backgrounds immediately
    // We use context here so Flutter knows which ImageCache to populate
    await AuthService().precacheBackgrounds(context);

    // 2. Add a small artificial delay if assets load too fast (for brand visibility)
    await Future.delayed(const Duration(seconds: 2));

    if (!mounted) return;

    // 3. Navigate to the next view
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (context) => const AeroWelcomeView()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF16a085), // AeroRide Primary Turquoise
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              "AeroRide",
              style: GoogleFonts.satisfy(
                color: Colors.white,
                fontSize: 64,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 24),
            ShimmerPlaceholder(
              child: Container(
                width: 44, // Circular shimmer
                height: 44, // Circular shimmer
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
              ),
            )
          ],
        ),
      ),
    );
  }
}
