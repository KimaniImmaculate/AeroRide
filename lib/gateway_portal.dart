import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:ui';
import 'package:aeroride/screens/auth/Login_screen.dart';
import 'package:aeroride/screens/rider/rider_home_screen.dart';

class AeroRideGatewayPortal extends StatefulWidget {
  const AeroRideGatewayPortal({super.key});

  @override
  State<AeroRideGatewayPortal> createState() => _AeroRideGatewayPortalState();
}

class _AeroRideGatewayPortalState extends State<AeroRideGatewayPortal>
    with TickerProviderStateMixin {
  late AnimationController _shimmerController;
  late AnimationController _danceController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    )..repeat();

    _danceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _scaleAnimation = Tween<double>(begin: 0.97, end: 1.03).animate(
      CurvedAnimation(parent: _danceController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _shimmerController.dispose();
    _danceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const Color primaryTurquoise = Color(0xFF16A085);
    const Color instructionGreen =
        Color(0xFF1ABC9C); // Matching green tone from image

    return Scaffold(
      body: Stack(
        children: [
          // 🌆 BACKDROP FRAME IMAGE
          Positioned.fill(
            child: Image.asset(
              'assets/busy city at night 2.jpg',
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                );
              },
            ),
          ),

          // 🕶️ DARK MATTE LAYER OVERLAY
          Positioned.fill(
            child: Container(
              color: Colors.black.withValues(alpha: 0.60),
            ),
          ),

          // 📲 INTERACTIVE INTERFACE FOREGROUND LAYER
          Positioned.fill(
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(28.0, 50.0, 28.0, 20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 🏷️ "Navigate" Script Brand Header (No box around it now)
                    Text(
                      "Navigate",
                      style: GoogleFonts.playfairDisplay(
                        color: primaryTurquoise,
                        fontSize: 32,
                        fontWeight: FontWeight.w600,
                        fontStyle: FontStyle.italic,
                      ),
                    ),

                    // 🚀 MAIN LOGO LABEL
                    Text(
                      "AeroRide",
                      style: GoogleFonts.urbanist(
                        color: Colors.white,
                        fontSize: 54,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.5,
                        height: 1.0,
                      ),
                    ),

                    const SizedBox(height: 18),

                    // 🎵 APP SLOGAN (Transparent look)
                    Text(
                      "The Symphony of Movement.\nEngineered for the Adaptive Road.",
                      style: GoogleFonts.urbanist(
                        color: Colors.white
                            .withValues(alpha: 0.70), // Fluid transparency feel
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                        height: 1.3,
                      ),
                    ),

                    // ⚡ Pushes instructions and cards down dynamically
                    const Spacer(),

                    // 🕺 RHYTHMIC INSTRUCTION LINK (Corrected to green)
                    Center(
                      child: ScaleTransition(
                        scale: _scaleAnimation,
                        child: Text(
                          "Select your terminal to coordinate live fleet operations.",
                          textAlign: TextAlign.center,
                          style: GoogleFonts.urbanist(
                            color: instructionGreen,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // 🗂️ MAIN CARD PACK AT BOTTOM GRID
                    _buildGlassTerminalCard(
                      context: context,
                      title: "Rider Dashboard",
                      subtitle: "Experience luxury urban mobility",
                      icon: Icons.location_on_rounded,
                      iconBgColor: primaryTurquoise.withValues(alpha: 0.20),
                      iconColor: const Color(0xFF1ABC9C),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (context) => const RiderHomeScreen()),
                        );
                      },
                    ),

                    const SizedBox(height: 14),

                    _buildGlassTerminalCard(
                      context: context,
                      title: "Driver Terminal",
                      subtitle: "High-performance cockpit for partners",
                      icon: Icons.airline_seat_recline_extra_rounded,
                      iconBgColor: Colors.white.withValues(alpha: 0.08),
                      iconColor: Colors.white.withValues(alpha: 0.75),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (context) => const LoginScreen(expectedRole: 'driver')),
                        );
                      },
                    ),

                    const SizedBox(height: 14),

                    _buildGlassTerminalCard(
                      context: context,
                      title: "Operations Admin",
                      subtitle: "Fleet oversight & dynamic pricing",
                      icon: Icons.admin_panel_settings_rounded,
                      iconBgColor: Colors.indigo.withValues(alpha: 0.15),
                      iconColor: const Color(0xFF5D6D7E),
                      iconCustomColor: const Color(0xFF5D8AA8),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (context) => const LoginScreen(expectedRole: 'admin')),
                        );
                      },
                    ),
                    const SizedBox(height: 10),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // GLASS CARD WIDGET BUILDER
  Widget _buildGlassTerminalCard({
    required BuildContext context,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color iconBgColor,
    required Color iconColor,
    Color? iconCustomColor,
    required VoidCallback onTap,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.10),
              width: 1.0,
            ),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              splashColor: Colors.white.withValues(alpha: 0.05),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 24.0, vertical: 22.0),
                child: Row(
                  children: [
                    Container(
                      height: 54,
                      width: 54,
                      decoration: BoxDecoration(
                        color: iconBgColor,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        icon,
                        color: iconCustomColor ?? iconColor,
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 18),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: GoogleFonts.urbanist(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.2,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            subtitle,
                            style: GoogleFonts.urbanist(
                              color: Colors.white.withValues(alpha: 0.45),
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.arrow_forward_ios_rounded,
                      color: Colors.white.withValues(alpha: 0.18),
                      size: 16,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
