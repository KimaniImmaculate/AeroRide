import 'package:flutter/material.dart';
import 'package:aeroride/widgets/vehicle_selection_screen.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:aeroride/services/auth_service.dart';

/// A premium welcome screen featuring centered glassmorphism and elite branding.
class AeroWelcomeView extends StatelessWidget {
  const AeroWelcomeView({super.key});

  static const Color primaryTurquoise = Color(0xFF16a085);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Layer 1: High-Resolution Immersive Background
          Positioned.fill(
            child: Image.asset(
              'assets/skyline (2).jpg',
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => Container(
                color: const Color(0xFF0A0A0A),
                child: const Center(
                  child: Icon(Icons.image_not_supported_outlined,
                      color: Colors.white24, size: 40),
                ),
              ),
            ),
          ),

          // Layer 2: Subtle Cinematic Overlay
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    primaryTurquoise.withValues(alpha: 0.1),
                    Colors.black.withValues(alpha: 0.5),
                    Colors.black.withValues(alpha: 0.85),
                  ],
                  stops: const [0.0, 0.5, 1.0],
                ),
              ),
            ),
          ),

          // Layer 3: Centered Floating Premium Experience Card
          Center(
            child: Container(
              width: MediaQuery.of(context).size.width * 0.88,
              padding:
                  const EdgeInsets.symmetric(horizontal: 24.0, vertical: 36.0),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.94),
                borderRadius: BorderRadius.circular(36),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: 30,
                    offset: const Offset(0, 15),
                  )
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Distinctive High-End Brand Signature
                  Text(
                    "AeroRide",
                    style: GoogleFonts.satisfy(
                      color: primaryTurquoise,
                      fontSize: 48,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Premium Lifestyle Subheading
                  Text(
                    "Welcome to the Glide.",
                    textAlign: TextAlign.center,
                    style: GoogleFonts.urbanist(
                      color: Colors.black87,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Elevated Brand Concept Copy
                  Text(
                    "The city moves fast, but you? You move beautifully. Skip the basic, choose the vibe, and arrive completely on your own terms.",
                    textAlign: TextAlign.center,
                    style: GoogleFonts.urbanist(
                      color: Colors.grey.shade800,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 28),

                  // Differentiating Curated Value Pillars
                  _buildBrandPillar("📊", "Predictive Equilibrium",
                      "Smart demand forecasting dynamically stabilizes rates ensuring transparent pricing balance."),
                  _buildBrandPillar("⚡", "Precision Trajectories",
                      "AI-driven route optimization monitors data to map the shortest, safest paths."),

                  const SizedBox(height: 32),

                  // Primary Executive Action Call
                  SizedBox(
                    width: double.infinity,
                    height: 60,
                    child: ElevatedButton(
                      onPressed: () async {
                        // Ensure user is signed in anonymously before proceeding
                        final user = await AuthService().signInAnonymously();

                        if (context.mounted && user != null) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  VehicleSelectionScreen(user: user),
                            ),
                          );
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryTurquoise,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(100),
                        ),
                        elevation: 6,
                        shadowColor: primaryTurquoise.withValues(alpha: 0.4),
                      ),
                      child: Text(
                        "LET'S GLIDE",
                        style: GoogleFonts.urbanist(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Helper widget to display elevated lifestyle features
  Widget _buildBrandPillar(String icon, String title, String description) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2.0),
            child: Text(icon, style: const TextStyle(fontSize: 20)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.urbanist(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: GoogleFonts.urbanist(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Colors.black54,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
