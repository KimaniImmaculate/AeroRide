import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:aeroride/services/auth_service.dart';
import 'package:aeroride/controllers/ride_controller.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:aeroride/services/shimmer_placeholder.dart';

class UserProfileView extends StatefulWidget {
  const UserProfileView({super.key});

  @override
  State<UserProfileView> createState() => _UserProfileViewState();
}

class _UserProfileViewState extends State<UserProfileView> {
  final AuthService _authService = AuthService();
  bool _isUploading = false;
  bool _isUpdating = false;

  Future<void> _changeProfilePicture() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 70,
    );

    if (image != null && mounted) {
      setState(() => _isUploading = true);
      final String uid = _authService.currentUser!.uid;
      final String? url =
          await _authService.uploadProfileImage(uid, File(image.path));

      if (url != null) {
        await _authService.updateProfileData(uid, {'profilePic': url});
      }
      setState(() => _isUploading = false);
    }
  }

  Future<void> _editProfileField(
      String fieldKey, String label, String currentVal) async {
    final controller = TextEditingController(text: currentVal);
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Edit $label",
            style: GoogleFonts.urbanist(fontWeight: FontWeight.bold)),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(hintText: "Enter $label address"),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("CANCEL")),
          TextButton(
            onPressed: () async {
              final uid = _authService.currentUser!.uid;
              // Using dot notation to update specific fields in a nested Map
              await _authService.updateProfileData(uid, {
                'savedLocations.$label': controller.text.trim(),
              });
              if (mounted) Navigator.pop(context);
            },
            child: const Text("SAVE"),
          ),
        ],
      ),
    );
  }

  Future<void> _editVehicleTier(String currentTierId) async {
    final rideController = context.read<RideController>();
    String? tempSelectedTier = currentTierId;

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Edit Vehicle Tier",
            style: GoogleFonts.urbanist(fontWeight: FontWeight.bold)),
        content: StatefulBuilder(
          builder: (BuildContext context, StateSetter setDialogState) {
            return DropdownButtonFormField<String>(
              value: tempSelectedTier,
              decoration: InputDecoration(
                labelText: 'Vehicle Tier',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              items: rideController.vehicleTiers.map((tier) {
                return DropdownMenuItem(
                  value: tier.id,
                  child: Text('${tier.name} (Max ${tier.capacity} pax)'),
                );
              }).toList(),
              onChanged: (val) => setDialogState(() => tempSelectedTier = val),
              validator: (val) =>
                  val == null ? 'Please select a vehicle tier' : null,
            );
          },
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("CANCEL")),
          TextButton(
            onPressed: () async {
              if (tempSelectedTier != null &&
                  tempSelectedTier != currentTierId) {
                setState(() => _isUpdating = true);
                final uid = _authService.currentUser!.uid;
                await _authService
                    .updateProfileData(uid, {'vehicleTier': tempSelectedTier});
                setState(() => _isUpdating = false);
              }
              if (mounted) Navigator.pop(context);
            },
            child: _isUpdating
                ? ShimmerPlaceholder(
                    baseColor: Colors.grey[200],
                    highlightColor: Colors.grey[50],
                    child: Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: Colors.black,
                        shape: BoxShape.circle,
                      ),
                    ),
                  )
                : const Text("SAVE"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = _authService.currentUser;
    if (user == null)
      return const Scaffold(body: Center(child: Text("Not logged in")));

    return Scaffold(
      appBar: AppBar(
        title: Text("Profile",
            style: GoogleFonts.urbanist(fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData)
            return const Center(child: CircularProgressIndicator());

          final data = snapshot.data!.data() as Map<String, dynamic>? ?? {};
          final savedLocations =
              data['savedLocations'] as Map<String, dynamic>? ?? {};

          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Center(
                  child: Stack(
                    children: [
                      CircleAvatar(
                        radius: 60,
                        backgroundColor: Colors.grey[200],
                        backgroundImage: data['profilePic']?.isNotEmpty == true
                            ? NetworkImage(data['profilePic'])
                            : null,
                        child: data['profilePic']?.isNotEmpty != true
                            ? Icon(Icons.person,
                                size: 60, color: Colors.grey[400])
                            : null,
                      ),
                      if (_isUploading)
                        Positioned.fill(
                          child: ShimmerPlaceholder(
                            child: Container(
                              decoration: const BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                        ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: GestureDetector(
                          onTap: _changeProfilePicture,
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: const BoxDecoration(
                              color: Color(0xFF16a085),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.camera_alt,
                                color: Colors.white, size: 20),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Text(data['name'] ?? 'Guest',
                    style: GoogleFonts.urbanist(
                        fontSize: 24, fontWeight: FontWeight.bold)),
                Text(data['email'] ?? '',
                    style: GoogleFonts.urbanist(color: Colors.grey)),
                const SizedBox(height: 32),
                _buildSection("SAVED LOCATIONS"),
                _buildLocationTile("Home",
                    savedLocations['Home'] ?? "Add address", Icons.home),
                _buildLocationTile("Work",
                    savedLocations['Work'] ?? "Add address", Icons.work),

                // Conditional Vehicle Section for Drivers only
                if (data['role'] == 'driver') ...[
                  const SizedBox(height: 24),
                  _buildSection("VEHICLE ASSETS"),
                  _buildTile(
                    "Model",
                    data['vehicleModel'] ?? 'Unknown',
                    Icons.directions_car,
                    onEditTap: () => _editProfileField('vehicleModel',
                        'Vehicle Model', data['vehicleModel'] ?? ''),
                  ),
                  _buildTile(
                    "Color",
                    data['vehicleColor'] ?? 'Unknown',
                    Icons.palette,
                    onEditTap: () => _editProfileField('vehicleColor',
                        'Vehicle Color', data['vehicleColor'] ?? ''),
                  ),
                  _buildTile(
                    "Plate",
                    data['plateNumber'] ?? '---',
                    Icons.pin,
                    onEditTap: () => _editProfileField('plateNumber',
                        'Plate Number', data['plateNumber'] ?? ''),
                  ),
                  _buildTile(
                    "Tier",
                    (data['vehicleTier'] ?? 'tulia').toString().toUpperCase(),
                    Icons.layers,
                    onEditTap: () =>
                        _editVehicleTier(data['vehicleTier'] ?? 'tulia'),
                  ),
                ],

                const SizedBox(height: 24),
                _buildSection("ACTIVITY"),
                _buildTile(
                    "Rating", "${data['rating'] ?? '5.0'} ⭐", Icons.star),
                _buildTile("History", "View all rides", Icons.history,
                    onTap: () {}),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildSection(String title) => Align(
      alignment: Alignment.centerLeft,
      child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(title,
              style: GoogleFonts.urbanist(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                  color: Colors.grey))));

  Widget _buildLocationTile(String label, String val, IconData icon,
          {VoidCallback? onEditTap}) =>
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(icon, color: const Color(0xFF16a085)),
        title: Text(label,
            style: GoogleFonts.urbanist(fontWeight: FontWeight.bold)),
        subtitle: Text(val),
        trailing: onEditTap != null
            ? IconButton(
                icon: const Icon(Icons.edit, size: 18), onPressed: onEditTap)
            : null,
      );

  Widget _buildTile(String label, String val, IconData icon,
          {VoidCallback? onTap, VoidCallback? onEditTap}) =>
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(icon, color: Colors.grey),
        title: Text(label,
            style: GoogleFonts.urbanist(fontWeight: FontWeight.w600)),
        trailing: onEditTap != null
            ? IconButton(
                icon: const Icon(Icons.edit, size: 18), onPressed: onEditTap)
            : (onTap != null
                ? const Icon(Icons.chevron_right)
                : Text(val,
                    style: GoogleFonts.urbanist(fontWeight: FontWeight.bold))),
        onTap: onTap,
      );
}
