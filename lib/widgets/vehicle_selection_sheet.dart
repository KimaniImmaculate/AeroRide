import 'package:flutter/material.dart';
import 'package:aeroride/models/vehicle_tier_model.dart';

class VehicleSelectionSheet extends StatelessWidget {
  final List<VehicleTier> tiers;
  final VehicleTier? selectedTier;
  final Function(VehicleTier) onTierSelected;
  final Color primaryTurquoise;

  const VehicleSelectionSheet({
    super.key,
    required this.tiers,
    required this.selectedTier,
    required this.onTierSelected,
    required this.primaryTurquoise,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SizedBox(
          height: 240, // Slightly taller for better spacing
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: tiers.length,
            padding: const EdgeInsets.symmetric(vertical: 10),
            physics: const BouncingScrollPhysics(),
            itemBuilder: (context, index) {
              final tier = tiers[index];
              final isSelected = selectedTier?.id == tier.id;

              return GestureDetector(
                onTap: () => onTierSelected(tier),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOutCubic,
                  width: 190,
                  margin: EdgeInsets.only(
                    left: index == 0 ? 0 : 0,
                    right: 16,
                  ),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color:
                          isSelected ? primaryTurquoise : Colors.grey.shade200,
                      width: isSelected ? 2.5 : 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: isSelected
                            ? primaryTurquoise.withOpacity(0.15)
                            : Colors.black.withOpacity(0.04),
                        blurRadius: isSelected ? 16 : 8,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        _getVehicleIcon(tier.id),
                        size: 50,
                        color: primaryTurquoise,
                      ),
                      const Spacer(),
                      Text(
                        tier.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 18,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        tier.description,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                          height: 1.2,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'KSh ${tier.baseFare.toInt()} • 👤 ${tier.capacity}',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: primaryTurquoise,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  // Helper to get a relevant icon based on tier ID
  IconData _getVehicleIcon(String tierId) {
    switch (tierId) {
      case 'standard':
        return Icons.directions_car;
      case 'premium':
        return Icons.local_taxi;
      case 'xl':
        return Icons.airport_shuttle;
      case 'executive':
        return Icons.drive_eta;
      default:
        return Icons.directions_car;
    }
  }
}
