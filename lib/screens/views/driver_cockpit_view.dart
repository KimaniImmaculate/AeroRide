import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../services/auth_service.dart';
import '../../widgets/driver_auth_flow_modal.dart';
import 'driver_dashboard_view.dart';

class DriverCockpitView extends StatelessWidget {
  const DriverCockpitView({super.key});

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context, listen: false);

    return Scaffold(
      backgroundColor: const Color(0xFF0F1013), // Charcoal Background
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),
              Icon(
                LucideIcons.car,
                size: 80,
                color: const Color(0xFF16A085), // Signature Turquoise
              ),
              const SizedBox(height: 32),
              Text(
                "AeroRide Partner",
                style: GoogleFonts.urbanist(
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                "Enter the elite fleet network. Verify your terminal session to start receiving premium dispatches.",
                textAlign: TextAlign.center,
                style: GoogleFonts.urbanist(
                  fontSize: 16,
                  color: Colors.grey[400],
                ),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                height: 60,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF16A085),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                  ),
                  onPressed: () async {
                    debugPrint(
                        'DriverCockpitView: "START YOUR JOURNEY" button pressed.');
                    // 1. Session Awareness Gate
                    final bool isDriver =
                        await authService.isCurrentUserDriver();
                    debugPrint(
                        'DriverCockpitView: isCurrentUserDriver() returned: $isDriver');

                    if (!context.mounted) return;

                    if (isDriver) {
                      debugPrint(
                          'DriverCockpitView: User is a driver. Navigating to DriverDashboardView.');
                      // 2. Immediate Routing if authenticated
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                          builder: (context) => DriverDashboardView(
                              user: authService.currentUser),
                        ),
                      );
                    } else {
                      debugPrint(
                          'DriverCockpitView: User is NOT a driver. Showing DriverAuthFlowModal.');
                      // 3. Trigger Login Flow Modal
                      showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: Colors.transparent,
                        builder: (context) => const DriverAuthFlowModal(),
                      );
                    }
                  },
                  child: Text(
                    "START YOUR JOURNEY",
                    style: GoogleFonts.urbanist(
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                      letterSpacing: 1.2,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 48),
            ],
          ),
        ),
      ),
    );
  }
}
