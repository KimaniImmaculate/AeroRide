import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'services/ride_service.dart'; // ⚡ FIXED: Direct path to your integrated state & service engine
import 'gateway_portal.dart';

class VehicleSelectionScreen extends StatefulWidget {
  final double distanceKm;
  final String pickupName;
  final String destinationName;
  const VehicleSelectionScreen({
    super.key,
    required this.distanceKm,
    required this.pickupName,
    required this.destinationName,
  });

  @override
  State<VehicleSelectionScreen> createState() => _VehicleSelectionScreenState();
}

class _VehicleSelectionScreenState extends State<VehicleSelectionScreen> {
  static const Color primaryTurquoise = Color(0xFF16a085);
  List<VehicleTier> _availableTiers = [];
  VehicleTier? _selectedTier;

  void _confirmSelection() {
    if (_selectedTier == null) return;

    // ⚡ FIXED: Safely calling the dynamic method to alert the global app architecture
    Provider.of<RideController>(context, listen: false)
        .selectTier(_selectedTier!);

    final double fare = _selectedTier!.baseFare + (widget.distanceKm * _selectedTier!.perKmRate);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return TweenAnimationBuilder<double>(
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOutBack,
          tween: Tween(begin: 0.0, end: 1.0),
          builder: (context, value, child) {
            return Transform.scale(
              scale: value,
              child: Opacity(opacity: value.clamp(0.0, 1.0), child: child),
            );
          },
          child: AlertDialog(
            backgroundColor: const Color(0xFF1A2522),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
              side: BorderSide(
                color: Colors.white.withValues(alpha: 0.12),
                width: 1,
              ),
            ),
            contentPadding: const EdgeInsets.all(24),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: primaryTurquoise.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.confirmation_num_rounded,
                      color: primaryTurquoise, size: 36),
                ),
                const SizedBox(height: 20),
                Text(
                  "CONFIRM YOUR SELECTION",
                  textAlign: TextAlign.center,
                  style: GoogleFonts.urbanist(
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                      color: Colors.white,
                      letterSpacing: 1.0),
                ),
                const SizedBox(height: 16),
                RichText(
                  textAlign: TextAlign.center,
                  text: TextSpan(
                    style: GoogleFonts.urbanist(
                      color: Colors.white70,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      height: 1.5,
                    ),
                    children: [
                      const TextSpan(text: "Are you comfortable with the selected "),
                      TextSpan(
                        text: _selectedTier!.name,
                        style: const TextStyle(
                          color: primaryTurquoise,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const TextSpan(text: " tier from "),
                      TextSpan(
                        text: widget.pickupName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const TextSpan(text: " to "),
                      TextSpan(
                        text: widget.destinationName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const TextSpan(text: " with a total estimated fare of "),
                      TextSpan(
                        text: "KES ${fare.toStringAsFixed(0)}",
                        style: const TextStyle(
                          color: primaryTurquoise,
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                        ),
                      ),
                      const TextSpan(text: "?"),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 50,
                        child: OutlinedButton(
                          onPressed: () {
                            Navigator.of(context).pop(); // pop dialog
                            Navigator.of(context).pop(false); // pop screen back to map with false
                          },
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(
                              color: Colors.redAccent.withValues(alpha: 0.8),
                              width: 1.5,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: Text(
                            "NO, REJECT",
                            style: GoogleFonts.urbanist(
                              fontWeight: FontWeight.w800,
                              color: Colors.redAccent,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SizedBox(
                        height: 50,
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.of(context).pop(); // pop dialog
                            Navigator.of(context).pop(true); // pop screen back with approval
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primaryTurquoise,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: Text(
                            "YES, PROCEED",
                            style: GoogleFonts.urbanist(
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

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
          'Eco-Conscious Footprint',
          'Silent Cabin',
          'Agile City Navigation'
        ],
        iconPath: 'assets/vitz.png',
      ),
      VehicleTier(
        id: 'nuru',
        name: 'Nuru',
        description: 'Elevated workspace travel designed for premium comfort.',
        baseFare: 350.0,
        perKmRate: 80.0,
        capacity: 4,
        benefits: [
          'Premium Audio & Ambient Profiles',
          'Climate Control Sanctuary',
          '5-Star Operators'
        ],
        iconPath: 'assets/premio.png',
      ),
      VehicleTier(
        id: 'pamoja',
        name: 'Pamoja',
        description: 'Expansive space for your whole collective group.',
        baseFare: 500.0,
        perKmRate: 110.0,
        capacity: 7,
        benefits: [
          'Lounge Seating Matrix',
          'Squad-Optimized High Capacity',
          'Expansive Luggage Cargo Hull'
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
          'Absolute Discretion Shield',
          'Certified Executive Chauffeur'
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
          Positioned.fill(
            child: Container(color: const Color(0xFF111827)),
          ),
          Positioned.fill(
            child: SafeArea(
              child: Column(
                children: [
                  const SizedBox(height: 60),
                  Text(
                    "Select Your Vibe",
                    style: GoogleFonts.urbanist(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2.0,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: ListView.builder(
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 12),
                      itemCount: _availableTiers.length,
                      itemBuilder: (context, index) {
                        return _AeroVibeCard(
                          tier: _availableTiers[index],
                          isSelected:
                              _selectedTier?.id == _availableTiers[index].id,
                          onSelected: (tier) =>
                              setState(() => _selectedTier = tier),
                          distanceKm: widget.distanceKm,
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: SizedBox(
                      width: double.infinity,
                      height: 64,
                      child: ElevatedButton(
                        onPressed:
                            _selectedTier == null ? null : _confirmSelection,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryTurquoise,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor:
                              Colors.white.withValues(alpha: 0.15),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16)),
                        ),
                        child: Text(
                          _selectedTier == null
                              ? "CHOOSE YOUR RIDE"
                              : "CONFIRM ${_selectedTier!.name.toUpperCase()}",
                          style: GoogleFonts.urbanist(
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                              letterSpacing: 1.0),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 12,
            left: 20,
            child: ClipOval(
              child: Material(
                color: Colors.white.withValues(alpha: 0.1),
                child: InkWell(
                  onTap: () {
                    if (Navigator.of(context).canPop()) {
                      Navigator.of(context).pop();
                    } else {
                      Navigator.of(context).pushReplacement(
                        MaterialPageRoute(
                            builder: (_) => const AeroRideGatewayPortal()),
                      );
                    }
                  },
                  child: const Padding(
                    padding: EdgeInsets.all(12.0),
                    child: Icon(Icons.arrow_back_ios_new_rounded,
                        color: Colors.white, size: 18),
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
  final double distanceKm;

  const _AeroVibeCard({
    required this.tier,
    required this.isSelected,
    required this.onSelected,
    required this.distanceKm,
  });

  @override
  State<_AeroVibeCard> createState() => _AeroVibeCardState();
}

class _AeroVibeCardState extends State<_AeroVibeCard> {
  bool _isFlipped = false;

  @override
  Widget build(BuildContext context) {
    if (!widget.isSelected && _isFlipped) {
      _isFlipped = false;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: GestureDetector(
        onTap: () => widget.onSelected(widget.tier),
        child: TweenAnimationBuilder<double>(
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOutCubic,
          tween: Tween(begin: 0.0, end: _isFlipped ? math.pi : 0.0),
          builder: (context, angle, child) {
            final isBack = angle >= math.pi / 2;
            final matrix = Matrix4.identity()
              ..setEntry(3, 2, 0.0015)
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
      ),
    );
  }

  Widget _buildFrontSurface() {
    const Color primaryTurquoise = Color(0xFF16a085);
    final double estimatedTotal = widget.tier.baseFare + (widget.distanceKm * widget.tier.perKmRate);
    return Container(
      constraints: const BoxConstraints(minHeight: 130),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: widget.isSelected
            ? primaryTurquoise
            : Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 10,
              offset: const Offset(0, 4))
        ],
      ),
      child: Row(
        children: [
          Image.asset(
            widget.tier.iconPath,
            width: 60,
            fit: BoxFit.contain,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  widget.tier.name.toUpperCase(),
                  style: GoogleFonts.urbanist(
                    fontWeight: FontWeight.w900,
                    fontSize: 20,
                    color: widget.isSelected ? Colors.white : Colors.black87,
                  ),
                ),
                Text(
                  widget.tier.description,
                  style: GoogleFonts.urbanist(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: widget.isSelected ? Colors.white70 : Colors.black54,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  "Est. Fare: KES ${estimatedTotal.toStringAsFixed(0)}",
                  style: GoogleFonts.urbanist(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: widget.isSelected ? Colors.white : primaryTurquoise,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.info_outline_rounded,
                color: widget.isSelected ? Colors.white60 : Colors.black26),
            onPressed: () {
              widget.onSelected(widget.tier);
              setState(() => _isFlipped = !_isFlipped);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildBackSurface() {
    const Color primaryTurquoise = Color(0xFF16a085);
    final double estimatedTotal = widget.tier.baseFare + (widget.distanceKm * widget.tier.perKmRate);
    return Container(
      constraints: const BoxConstraints(minHeight: 130),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1F2937),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: primaryTurquoise, width: 2),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            "ATMOSPHERE CONFIGURATION",
            style: GoogleFonts.urbanist(
                color: primaryTurquoise,
                fontWeight: FontWeight.w900,
                fontSize: 10,
                letterSpacing: 1.5),
          ),
          Text(
            widget.tier.benefits.join("  •  "),
            textAlign: TextAlign.center,
            style: GoogleFonts.urbanist(
                color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const Divider(color: Colors.white10, height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildPriceMetric("BASE FARE",
                  "KES ${widget.tier.baseFare.toStringAsFixed(0)}"),
              _buildPriceMetric("KM RATE",
                  "KES ${widget.tier.perKmRate.toStringAsFixed(0)}/KM"),
              _buildPriceMetric("TOTAL EST.",
                  "KES ${estimatedTotal.toStringAsFixed(0)}"),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPriceMetric(String label, String value) {
    return Column(
      children: [
        Text(label,
            style: GoogleFonts.urbanist(
                color: Colors.white38,
                fontSize: 9,
                fontWeight: FontWeight.bold)),
        Text(value,
            style: GoogleFonts.urbanist(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w900)),
      ],
    );
  }
}
