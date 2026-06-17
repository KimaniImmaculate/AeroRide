import 'package:flutter/material.dart';
import 'auth/Login_screen.dart'; // Handles both registration and login paths

class LandingScreen extends StatefulWidget {
  const LandingScreen({super.key});

  @override
  State<LandingScreen> createState() => _LandingScreenState();
}

class _LandingScreenState extends State<LandingScreen> {
  bool isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.of(context).size;
    final bool isWeb = size.width > 600;

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              theme.primaryColor.withOpacity(0.05),
              Colors.white,
            ],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: isWeb ? size.width * 0.15 : 24.0,
                vertical: 40.0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(height: 20),
                  // --- APP LOGO & BRANDING ---
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: theme.primaryColor.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.local_taxi_rounded,
                      size: 64,
                      color: theme.primaryColor,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    "AeroRide",
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w900,
                      color: theme.primaryColor,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "Your Premium Ride, Just a Tap Away",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 48),

                  // --- VALUE PROPOSITION CARDS ---
                  // --- VALUE PROPOSITION CARDS ---
LayoutBuilder(
  builder: (context, constraints) {
    // If screen width is tight, use vertical stack. Otherwise, use auto-wrapping row grid.
    if (MediaQuery.of(context).size.width < 850) {
      return Column(
        children: _buildFeatureCards(isWeb: false)
            .map((card) => Padding(
                  padding: const EdgeInsets.only(bottom: 16.0),
                  child: card,
                ))
            .toList(),
      );
    } else {
      return Wrap(
        spacing: 20,      // Horizontal space between cards
        runSpacing: 20,   // Vertical space if cards wrap to a new line
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: _buildFeatureCards(isWeb: true),
      );
    }
  },
),
                  /*isWeb
                      ? Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: _buildFeatureCards(),
                        )
                      : Column(
                          children: _buildFeatureCards()
                              .map((card) => Padding(
                                    padding: const EdgeInsets.only(bottom: 16.0),
                                    child: card,
                                  ))
                              .toList(),
                        ),*/
                  
                  const SizedBox(height: 60),

                  // --- INTERACTIVE GET STARTED BUTTON ---
                  MouseRegion(
                    onEnter: (_) => setState(() => isHovered = true),
                    onExit: (_) => setState(() => isHovered = false),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: isWeb ? 400 : double.infinity,
                      height: 56,
                      transform: isHovered
                          ? (Matrix4.identity()..translate(0, -4, 0))
                          : Matrix4.identity(),
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const LoginScreen(),
                            ),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: theme.primaryColor,
                          elevation: isHovered ? 8 : 2,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              "Get Started",
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            SizedBox(width: 8),
                            Icon(
                              Icons.arrow_forward_rounded,
                              color: Colors.white,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildFeatureCards({required bool isWeb}) {
  return [
    _FeatureCard(
      icon: Icons.map_rounded,
      iconColor: Colors.blue,
      title: "Easy Booking",
      description: "Set your live pickup and drop-off targets seamlessly right from the interactive viewport.",
      isWeb: isWeb,
    ),
    _FeatureCard(
      icon: Icons.gpp_good_rounded,
      iconColor: Colors.green,
      title: "Verified Safety",
      description: "Travel confidently with built-in instant SOS modules and continuous live cloud trip tracking.",
      isWeb: isWeb,
    ),
    _FeatureCard(
      icon: Icons.bolt_rounded,
      iconColor: Colors.orange,
      title: "M-Pesa Express",
      description: "Instant fair fare calculation and integrated one-tap STK push updates straight to your phone.",
      isWeb: isWeb,
    ),
  ];
}
  /*List<Widget> _buildFeatureCards() {
    return [
      _FeatureCard(
        icon: Icons.map_rounded,
        iconColor: Colors.blue,
        title: "Easy Booking",
        description: "Set your live pickup and drop-off targets seamlessly right from the interactive viewport.",
      ),
      _FeatureCard(
        icon: Icons.gpp_good_rounded,
        iconColor: Colors.green,
        title: "Verified Safety",
        description: "Travel confidently with built-in instant SOS modules and continuous live cloud trip tracking.",
      ),
      _FeatureCard(
        icon: Icons.bolt_rounded,
        iconColor: Colors.orange,
        title: "M-Pesa Express",
        description: "Instant fair fare calculation and integrated one-tap STK push updates straight to your phone.",
      ),
    ];
  }*/
}

class _FeatureCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String description;
  final bool isWeb; // Pass web-state constraint down

  const _FeatureCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.description,
    required this.isWeb,
  });

  @override
  Widget build(BuildContext context) {
    // Dynamically calculate individual card width to prevent hard text-clipping
    final screenWidth = MediaQuery.of(context).size.width;
    double cardWidth = double.infinity;
    
    if (isWeb) {
      // If window is wide desktop, split available space evenly or use safe fixed width
      cardWidth = screenWidth > 1100 ? 280 : 230; 
    }

    return Container(
      width: cardWidth,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.06),
            spreadRadius: 4,
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: iconColor, size: 28),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            description,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.shade600,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}
/*class _FeatureCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String description;

  const _FeatureCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    final bool isWeb = MediaQuery.of(context).size.width > 600;

    return Container(
      width: isWeb ? 260 : double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.06),
            spreadRadius: 4,
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: iconColor, size: 28),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            description,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.shade600,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}*/