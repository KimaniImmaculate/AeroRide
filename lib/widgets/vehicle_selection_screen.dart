import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:aeroride/models/vehicle_tier_model.dart';
import 'package:aeroride/widgets/main_layout_wrapper.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:aeroride/controllers/ride_controller.dart';
import 'package:aeroride/widgets/aero_welcome_view.dart';

class VehicleSelectionScreen extends StatefulWidget {
  final User user;
  const VehicleSelectionScreen({super.key, required this.user});

  @override
  State<VehicleSelectionScreen> createState() => _VehicleSelectionScreenState();
}

class _VehicleSelectionScreenState extends State<VehicleSelectionScreen> {
  static const Color primaryTurquoise = Color(0xFF16a085);

  List<VehicleTier> _availableTiers = [];
  VehicleTier? _selectedTier;

  @override
  void initState() {
    super.initState();
    _loadMockTiers();
  }

  void _loadMockTiers() {
    _availableTiers = [
      VehicleTier(
        id: 'tulia',
        name: 'Tulia',
        description: 'Sustainable, low-profile urban transit.',
        baseFare: 150.0,
        perKmRate: 45.0,
        capacity: 4,
        benefits: [
          'Eco-Conscious Carbon Footprint',
          'Silent Interior Environment',
          'Agile City Maneuvering'
        ],
        iconPath: 'assets/vitz.png',
      ),
      VehicleTier(
        id: 'nuru',
        name: 'Nuru',
        description: 'Elevated workspace travel designed for your comfort.',
        baseFare: 350.0,
        perKmRate: 80.0,
        capacity: 4,
        benefits: [
          'Curated Premium Audio & Mood Profiles',
          'Climate Controlled Sanctuary',
          'Top-Rated Five-Star Operators'
        ],
        iconPath: 'assets/premio.png',
      ),
      VehicleTier(
        id: 'pamoja',
        name: 'Pamoja',
        description: 'Expansive space for your whole collective.',
        baseFare: 500.0,
        perKmRate: 110.0,
        capacity: 7,
        benefits: [
          'Maximized Legroom & Lounge Seating',
          'Squad-Optimized High Capacity',
          'Expansive Multi-Luggage Cargo Hull'
        ],
        iconPath: 'assets/honda freed.png',
      ),
      VehicleTier(
        id: 'waziri',
        name: 'Waziri',
        description: 'Elite flagship command. Unmarked, unbothered.',
        baseFare: 700.0,
        perKmRate: 150.0,
        capacity: 5,
        benefits: [
          'VIP Full-Grain Leather Lounge',
          'Absolute Discretion Privacy Shield',
          'Certified Professional Executive Chauffeur'
        ],
        iconPath: 'assets/prado.png',
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // 1. Cinematic Background Layer
          Positioned.fill(
            child: Image.asset(
              'assets/busy city at night.jpg',
              fit: BoxFit.cover,
            ),
          ),

          // 2. Dark Luxury Dimming Mask
          Positioned.fill(
            child: Container(
              color: Colors.black.withValues(alpha: 0.65),
            ),
          ),

          // 3. Immersive Interactive Core Layout
          Positioned.fill(
            child: SafeArea(
              child: Column(
                children: [
                  // Space allocated cleanly for the floating navigation anchor
                  const SizedBox(height: 56),

                  // Cinematic Title Typography
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20.0),
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0.0, end: 1.0),
                      duration: const Duration(milliseconds: 1200),
                      curve: Curves.easeOutExpo,
                      builder: (context, value, child) {
                        return Opacity(
                          opacity: value,
                          child: Transform.translate(
                            offset: Offset(0, 20 * (1 - value)),
                            child: Text(
                              "Select Your Vibe",
                              style: GoogleFonts.urbanist(
                                color: Colors.white,
                                fontSize: 32,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 4.0,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),

                  // Immersive Full-Viewport Scrolling Hub
                  Expanded(
                    child: ListView.builder(
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 10),
                      itemCount: _availableTiers.length,
                      itemBuilder: (context, index) {
                        return _AeroVibeCard(
                          tier: _availableTiers[index],
                          isSelected:
                              _selectedTier?.id == _availableTiers[index].id,
                          onSelected: (tier) =>
                              setState(() => _selectedTier = tier),
                        );
                      },
                    ),
                  ),

                  // Action Confirmation Dock
                  Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: SizedBox(
                      width: double.infinity,
                      height: 72,
                      child: ElevatedButton(
                        onPressed: _selectedTier == null
                            ? null
                            : () {
                                final controller = Provider.of<RideController>(
                                    context,
                                    listen: false);
                                controller.selectedTier = _selectedTier;

                                Navigator.of(context).pushReplacement(
                                  MaterialPageRoute(
                                    builder: (_) => MainLayoutWrapper(
                                      user: FirebaseAuth.instance.currentUser ??
                                          widget.user,
                                    ),
                                  ),
                                );
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryTurquoise,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor:
                              Colors.white.withValues(alpha: 0.2),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                        child: Text(
                          _selectedTier == null
                              ? "CHOOSE YOUR RIDE"
                              : "CONFIRM ${_selectedTier!.name.toUpperCase()}",
                          style: GoogleFonts.urbanist(
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                            letterSpacing: 1.0,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 4. Secure Floating Navigation Anchor (Safely outside Column, direct child of Stack)
          Positioned(
            top: MediaQuery.of(context).padding.top + 12,
            left: 20,
            child: ClipOval(
              child: Material(
                color: Colors.white.withValues(alpha: 0.12),
                child: InkWell(
                  onTap: () {
                    if (Navigator.of(context).canPop()) {
                      Navigator.of(context).pop();
                    } else {
                      Navigator.of(context).pushReplacement(
                        MaterialPageRoute(
                            builder: (_) => const AeroWelcomeView()),
                      );
                    }
                  },
                  child: const Padding(
                    padding: EdgeInsets.all(12.0),
                    child: Icon(
                      Icons.arrow_back_ios_new_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
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

class _AeroVibeCard extends StatefulWidget {
  final VehicleTier tier;
  final bool isSelected;
  final Function(VehicleTier) onSelected;

  const _AeroVibeCard({
    required this.tier,
    required this.isSelected,
    required this.onSelected,
  });

  @override
  State<_AeroVibeCard> createState() => _AeroVibeCardState();
}

class _AeroVibeCardState extends State<_AeroVibeCard> {
  bool _isFlipped = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        widget.onSelected(widget.tier);
        setState(() => _isFlipped = !_isFlipped);
      },
      child: TweenAnimationBuilder<double>(
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeOutBack,
        tween: Tween(begin: 0.0, end: _isFlipped ? math.pi : 0.0),
        builder: (context, angle, child) {
          final isBack = angle >= math.pi / 2;
          final matrix = Matrix4.identity()
            ..setEntry(3, 2, 0.0012)
            ..rotateY(angle);

          return Transform(
            transform: matrix,
            alignment: Alignment.center,
            child: isBack
                ? Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()..rotateY(math.pi),
                    child: _buildBackSurface(),
                  )
                : _buildFrontSurface(),
          );
        },
      ),
    );
  }

  Widget _buildFrontSurface() {
    const Color primaryTurquoise = Color(0xFF16a085);
    return Container(
      height: 140,
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: widget.isSelected
            ? primaryTurquoise
            : Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 15,
            offset: const Offset(0, 10),
          )
        ],
      ),
      child: Row(
        children: [
          Hero(
            tag: 'vehicle_${widget.tier.id}',
            child: Image.asset(widget.tier.iconPath,
                width: 120, fit: BoxFit.contain),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  widget.tier.name.toUpperCase(),
                  style: GoogleFonts.urbanist(
                    fontWeight: FontWeight.w900,
                    fontSize: 22,
                    color: widget.isSelected ? Colors.white : Colors.black,
                    letterSpacing: 1.2,
                  ),
                ),
                Text(
                  widget.tier.description,
                  style: GoogleFonts.urbanist(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: widget.isSelected ? Colors.white70 : Colors.black54,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            Icons.info_outline,
            color: widget.isSelected ? Colors.white38 : Colors.black12,
          ),
        ],
      ),
    );
  }

  Widget _buildBackSurface() {
    const Color primaryTurquoise = Color(0xFF16a085);
    return Container(
      height: 140,
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: primaryTurquoise, width: 2),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            "ATMOSPHERE CONFIGURATION",
            style: GoogleFonts.urbanist(
              color: primaryTurquoise,
              fontWeight: FontWeight.w900,
              fontSize: 10,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Center(
              child: Text(
                widget.tier.benefits.join(" • "),
                textAlign: TextAlign.center,
                style: GoogleFonts.urbanist(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          const Divider(color: Colors.white10, height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildPriceMetric("BASE FARE",
                  "KES ${widget.tier.baseFare.toStringAsFixed(0)}"),
              _buildPriceMetric("KM RATE",
                  "KES ${widget.tier.perKmRate.toStringAsFixed(0)}/KM"),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPriceMetric(String label, String value) {
    return Column(
      children: [
        Text(
          label,
          style: GoogleFonts.urbanist(
            color: Colors.white38,
            fontSize: 9,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          value,
          style: GoogleFonts.urbanist(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}
