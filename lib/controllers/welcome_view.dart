import 'package:flutter/material.dart';
import 'package:aeroride/widgets/vehicle_selection_screen.dart';

class AeroWelcomeView extends StatelessWidget {
  const AeroWelcomeView({super.key});

  // Define the vibrant turquoise color
  static const Color primaryTurquoise = Color(0xFF16a085);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: primaryTurquoise,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Top Section: Branding
              const Text(
                "AeroRide",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 36,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                ),
              ),

              // Middle Section: Floating Card with Content
              Expanded(
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.all(24.0),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    constraints: const BoxConstraints(
                        maxWidth: 400), // Max width for larger screens
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          "Your Ride, Your Way",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: primaryTurquoise,
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          "Premium Travel, Reimagined",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: primaryTurquoise.withOpacity(0.8),
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Spacer(),
                        // Minimalist outline icon as requested
                        Icon(
                          Icons.directions_car_outlined,
                          size: 140,
                          color: primaryTurquoise.withOpacity(0.8),
                        ),
                        const Spacer(),
                        _buildBenefitRow(
                          context,
                          Icons.taxi_alert,
                          "Book instantly, ride in style.",
                        ),
                        const SizedBox(height: 12),
                        _buildBenefitRow(
                          context,
                          Icons.location_on,
                          "Track real-time, arrive on time.",
                        ),
                        const SizedBox(height: 12),
                        _buildBenefitRow(
                          context,
                          Icons.star_border,
                          "Top-rated drivers, every journey.",
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // Bottom Section: CTA Button
              ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(
                      builder: (context) => const VehicleSelectionScreen(),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      Colors.white, // White button on turquoise background
                  foregroundColor: primaryTurquoise, // Turquoise text
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                  elevation: 8,
                  shadowColor: Colors.black.withOpacity(0.2),
                ),
                child: const Text(
                  "Get Started",
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBenefitRow(BuildContext context, IconData icon, String text) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, color: primaryTurquoise, size: 20),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            text,
            style: TextStyle(
              color: primaryTurquoise.withOpacity(0.9),
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}