import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:aeroride/screens/views/rider_dashboard_view.dart';
import 'package:aeroride/screens/views/driver_dashboard_view.dart';
import 'package:aeroride/widgets/aero_welcome_view.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:aeroride/services/auth_service.dart';
import 'package:aeroride/widgets/driver_welcome_view.dart'; // Import the new driver welcome view

class AeroRideGatewayPortal extends StatelessWidget {
  const AeroRideGatewayPortal({super.key});

  static const Color signatureTurquoise = Color(0xFF16A085);
  static const Color lightTurquoise = Color(0xFF1ABC9C);
  static const Color deepTurquoise = Color(0xFF0E6251);
  static const Color scaffoldBg = Color(0xFFF8F9FA);

  /// Enforces production security rules by ensuring a valid session
  /// and user profile exist before entering the dashboard pipelines.
  Future<void> _secureNavigate(BuildContext context, String role,
      Widget Function(User? user) targetBuilder) async {
    final auth = AuthService();

    // Show loading overlay
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(
          child: CircularProgressIndicator(color: signatureTurquoise)),
    );

    try {
      final User? user = await auth.signInAnonymously();
      if (user != null) {
        await auth.ensureUserProfileForRole(user: user, role: role);
        if (context.mounted) {
          // Ensure context is still valid
          Navigator.pop(context); // Dismiss loader
          Navigator.push(
              context, MaterialPageRoute(builder: (_) => targetBuilder(user)));
        }
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Security Handshake Failed: $e")));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. CINEMATIC BACKGROUND LAYER
          Positioned.fill(
            child: Image.asset(
              'assets/busy city at night 2.jpg',
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF0F2027),
                      Color(0xFF203A43),
                      Color(0xFF2C5364)
                    ],
                  ),
                ),
              ),
            ),
          ),

          // 2. OBSIDIAN VIGNETTE MASK
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.4),
                    Colors.black.withValues(alpha: 0.85),
                  ],
                  stops: const [0.0, 0.85],
                ),
              ),
            ),
          ),

          // 3. ANIMATED INTERFACE TERMINAL
          SafeArea(
            child: TweenAnimationBuilder<double>(
              duration: const Duration(milliseconds: 800),
              tween: Tween(begin: 0.0, end: 1.0),
              curve: Curves.easeOutQuart,
              builder: (context, value, child) {
                return Opacity(
                  opacity: value,
                  child: Transform.translate(
                    offset: Offset(0, 20 * (1 - value)),
                    child: child,
                  ),
                );
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 40),

                    // Script Introductory Layer
                    Text(
                      "Navigate",
                      style: GoogleFonts.playfairDisplay(
                        fontStyle: FontStyle.italic,
                        fontSize: 22,
                        color: lightTurquoise.withValues(alpha: 0.9),
                      ),
                    ),

                    // Main Branding
                    Text(
                      "AeroRide",
                      style: GoogleFonts.urbanist(
                        fontSize: 52,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -1.5,
                        color: Colors.white,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Symphony Tagline
                    Text(
                      "The Symphony of Movement.\nEngineered for the Adaptive Road.",
                      style: GoogleFonts.urbanist(
                        fontSize: 16,
                        color: Colors.white.withValues(alpha: 0.7),
                        fontWeight: FontWeight.w500,
                        height: 1.4,
                      ),
                    ),

                    const Spacer(),

                    // Continuous Animated Description Anchor
                    const _FloatingActionDescription(),
                    const SizedBox(height: 20),

                    // Glassmorphic Interaction Keys
                    _GlassmorphicRoleCard(
                      title: "Rider Dashboard",
                      tagline: "Experience luxury urban mobility",
                      icon: Icons.person_pin_circle_rounded,
                      accentColor: lightTurquoise,
                      onTap: () => _secureNavigate(
                        context,
                        'rider',
                        (user) => const AeroWelcomeView(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _GlassmorphicRoleCard(
                      title: "Driver Terminal",
                      tagline: "High-performance cockpit for partners",
                      icon: Icons.airline_seat_recline_extra_rounded,
                      accentColor: Colors.white,
                      onTap: () => _secureNavigate(
                        context,
                        'driver',
                        (user) => DriverWelcomeView(user: user),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _GlassmorphicRoleCard(
                      title: "Operations Admin",
                      tagline: "Fleet oversight & dynamic pricing",
                      icon: Icons.admin_panel_settings_rounded,
                      accentColor: Colors.indigoAccent,
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text("Admin Module: Access Restricted"),
                            backgroundColor: Colors.black,
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A dedicated component that provides a continuous "breathing" pulse
/// and vertical float animation for the action copy.
class _FloatingActionDescription extends StatefulWidget {
  const _FloatingActionDescription();

  @override
  State<_FloatingActionDescription> createState() =>
      _FloatingActionDescriptionState();
}

class _FloatingActionDescriptionState extends State<_FloatingActionDescription>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _floatAnimation;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);

    // Subtle Y-axis translation between -4 and 4 pixels
    _floatAnimation = Tween<double>(begin: -4.0, end: 4.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutSine),
    );

    // Subtle 3% scaling pulse to create a "breathing" effect
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.03).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutSine),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, _floatAnimation.value),
          child: Transform.scale(
            scale: _pulseAnimation.value,
            child: child,
          ),
        );
      },
      child: Text(
        "Select your terminal to coordinate live fleet operations.",
        style: GoogleFonts.urbanist(
          fontSize: 12,
          color: AeroRideGatewayPortal.lightTurquoise.withValues(alpha: 0.8),
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

/// A Glassmorphic interaction module with tactile scaling feedback.
class _GlassmorphicRoleCard extends StatefulWidget {
  final String title;
  final String tagline;
  final IconData icon;
  final Color accentColor;
  final VoidCallback onTap;

  const _GlassmorphicRoleCard({
    required this.title,
    required this.tagline,
    required this.icon,
    required this.accentColor,
    required this.onTap,
  });

  @override
  State<_GlassmorphicRoleCard> createState() => _GlassmorphicRoleCardState();
}

class _GlassmorphicRoleCardState extends State<_GlassmorphicRoleCard> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: _isPressed ? 0.98 : 1.0,
      duration: const Duration(milliseconds: 100),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: Colors.white.withOpacity(0.12),
                width: 1.5,
              ),
            ),
            child: InkWell(
              onTap: widget.onTap,
              onTapDown: (_) => setState(() => _isPressed = true),
              onTapCancel: () => setState(() => _isPressed = false),
              onTapUp: (_) => setState(() => _isPressed = false),
              splashColor: AeroRideGatewayPortal.signatureTurquoise
                  .withValues(alpha: 0.3),
              highlightColor: Colors.transparent,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: widget.accentColor.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(widget.icon,
                          color: widget.accentColor, size: 26),
                    ),
                    const SizedBox(width: 18),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.title,
                            style: GoogleFonts.urbanist(
                              fontWeight: FontWeight.w800,
                              fontSize: 18,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.tagline,
                            style: GoogleFonts.urbanist(
                              fontSize: 12,
                              color: Colors.white.withValues(alpha: 0.5),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: Colors.white.withValues(alpha: 0.2),
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
