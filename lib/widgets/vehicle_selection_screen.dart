import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:aeroride/models/vehicle_tier_model.dart';
import 'package:aeroride/widgets/vehicle_selection_sheet.dart';
import 'package:aeroride/screens/views/rider_dashboard_view.dart'; // Assuming this is the next screen

class VehicleSelectionScreen extends StatefulWidget {
  const VehicleSelectionScreen({super.key});

  @override
  State<VehicleSelectionScreen> createState() => _VehicleSelectionScreenState();
}

class _VehicleSelectionScreenState extends State<VehicleSelectionScreen> {
  static const Color primaryTurquoise = Color(0xFF16a085);

  // Mock data for vehicle tiers (in a real app, this would come from a service/controller)
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
        id: 'standard',
        name: 'Standard',
        description: 'Affordable everyday rides',
        baseFare: 150.0,
        perKmRate: 45.0,
        capacity: 4,
        benefits: ['Budget friendly', 'Comfortable'],
        iconPath: 'assets/images/cars/standard.png',
      ),
      VehicleTier(
        id: 'premium',
        name: 'Premium',
        description: 'Luxury vehicles, elite service',
        baseFare: 350.0,
        perKmRate: 80.0,
        capacity: 4,
        benefits: ['Luxury sedan', 'Top-rated drivers'],
        iconPath: 'assets/images/cars/premium.png',
      ),
      VehicleTier(
        id: 'xl',
        name: 'Executive XL',
        description: 'Spacious SUVs for groups',
        baseFare: 500.0,
        perKmRate: 110.0,
        capacity: 6,
        benefits: ['Extra legroom', 'Group friendly'],
        iconPath: 'assets/images/cars/xl.png',
      ),
      VehicleTier(
        id: 'executive',
        name: 'Executive',
        description: 'Business class travel',
        baseFare: 700.0,
        perKmRate: 150.0,
        capacity: 4,
        benefits: ['Executive sedan', 'Professional chauffeurs'],
        iconPath: 'assets/images/cars/executive.png',
      ),
    ];
    _selectedTier = _availableTiers.first; // Select the first tier by default
  }

  void _onTierSelected(VehicleTier tier) {
    setState(() {
      _selectedTier = tier;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: primaryTurquoise,
        elevation: 0,
        title: const Text(
          "AeroRide",
          style: TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.2,
          ),
        ),
        centerTitle: true,
        iconTheme:
            const IconThemeData(color: Colors.white), // Back button color
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Select Your Ride Type",
              style: TextStyle(
                color: primaryTurquoise,
                fontSize: 26,
                fontWeight: FontWeight.w900,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              "Choose the perfect vehicle for your journey. From budget-friendly to luxurious, we have a ride for every occasion.",
              style: TextStyle(
                color: Colors.grey.shade700,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 32),

            // Core Component: Vehicle Selection Sheet
            VehicleSelectionSheet(
              tiers: _availableTiers,
              selectedTier: _selectedTier,
              onTierSelected: _onTierSelected,
              primaryTurquoise: primaryTurquoise,
            ),
            const SizedBox(height: 32),

            // Bottom Section: Confirm Ride Type Button
            ElevatedButton(
              onPressed: _selectedTier == null
                  ? () {
                      // Handle null case or show a snackbar
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text("Please select a vehicle type")));
                    }
                  : () {
                      // Navigate to the RiderDashboardView after selecting a tier
                      Navigator.of(context).pushReplacement(
                        MaterialPageRoute(
                          builder: (context) => RiderDashboardView(
                            user: FirebaseAuth.instance.currentUser,
                          ),
                        ),
                      );
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    _selectedTier == null ? Colors.grey : primaryTurquoise,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 60),
                elevation: _selectedTier == null ? 0 : 8,
                shadowColor: primaryTurquoise.withOpacity(0.4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: Text(
                _selectedTier == null
                    ? "Select a Ride Type"
                    : "Confirm ${_selectedTier!.name} Ride",
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
