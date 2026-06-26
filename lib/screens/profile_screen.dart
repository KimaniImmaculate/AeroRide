import 'dart:convert'; // Added to handle base64 encoding conversion
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_fonts/google_fonts.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final TextEditingController nameController = TextEditingController();
  final TextEditingController phoneController = TextEditingController();

  bool isLoading = false;
  bool isSaving = false;
  bool isUploadingImage = false;
  String?
      profileImageUrl; // Holds either our base64 data string or standard string links

  String? role;
  String? licenseNumber;
  String? bio;
  String? documents;
  String? passportPhotoUrl;
  String? carTier;

  // Vibrant Turquoise Theme Color
  static const Color primaryTurquoise = Color(0xFF16A085);

  final currentUser = FirebaseAuth.instance.currentUser;
  final firestore = FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    loadProfile();
  }

  @override
  void dispose() {
    nameController.dispose();
    phoneController.dispose();
    super.dispose();
  }

  Future<void> loadProfile() async {
    if (currentUser == null) return;

    setState(() {
      isLoading = true;
    });

    try {
      final doc =
          await firestore.collection('users').doc(currentUser!.uid).get();

      if (doc.exists) {
        final data = doc.data()!;
        nameController.text = data['name'] ?? '';
        phoneController.text = data['phone'] ?? '';
        profileImageUrl = data['profilePicture'];
        role = data['role'] ?? 'rider';
        licenseNumber = data['licenseNumber'] ?? '';
        bio = data['bio'] ?? '';
        documents = data['documents'] ?? '';
        passportPhotoUrl = data['passportPhotoUrl'] ?? '';
        carTier = data['carTier'] ?? 'tulia';
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error fetching data: $e")),
      );
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  Future<void> _handleImageSelection() async {
    final ImagePicker picker = ImagePicker();

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading:
                  const Icon(Icons.photo_library_rounded, color: Colors.blue),
              title: const Text("Upload New Photo"),
              onTap: () {
                Navigator.pop(context);
                _pickAndProcessImage(picker);
              },
            ),
            if (profileImageUrl != null)
              ListTile(
                leading:
                    const Icon(Icons.delete_outline_rounded, color: Colors.red),
                title: const Text("Remove Photo",
                    style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(context);
                  _removeProfileImage();
                },
              ),
          ],
        ),
      ),
    );
  }

  // Base64 Local Converter Engine
  Future<void> _pickAndProcessImage(ImagePicker picker) async {
    try {
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality:
            40, // Compressed aggressively to stay safely within Firestore document limits
      );

      if (image == null) return;

      setState(() {
        isUploadingImage = true;
      });

      // Convert raw selected file bytes to base64 structural image text
      final Uint8List imageBytes = await image.readAsBytes();
      String base64String = base64Encode(imageBytes);
      String completedBase64DataUri = "data:image/jpeg;base64,$base64String";

      // Save directly to the user Firestore Document as standard string field data
      await firestore.collection('users').doc(currentUser!.uid).update({
        'profilePicture': completedBase64DataUri,
      });

      setState(() {
        profileImageUrl = completedBase64DataUri;
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("Profile picture updated locally inside database!"),
            backgroundColor: Colors.green),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text("Processing failed: $e"),
            backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) {
        setState(() {
          isUploadingImage = false;
        });
      }
    }
  }

  Future<void> _removeProfileImage() async {
    setState(() {
      isUploadingImage = true;
    });

    try {
      await firestore.collection('users').doc(currentUser!.uid).update({
        'profilePicture': FieldValue.delete(),
      });

      setState(() {
        profileImageUrl = null;
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("Profile picture removed"),
            backgroundColor: Colors.orange),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error eliminating photo: $e")),
      );
    } finally {
      if (mounted) {
        setState(() {
          isUploadingImage = false;
        });
      }
    }
  }

  Future<void> saveProfile() async {
    if (currentUser == null) return;

    setState(() {
      isSaving = true;
    });

    try {
      await firestore.collection('users').doc(currentUser!.uid).update({
        'name': nameController.text.trim(),
        'phone': phoneController.text.trim(),
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Profile Updated Successfully"),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Failed to update profile: $e"),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Evaluation utility verifying if current string path pattern is a local base64 variant
    final bool isBase64 =
        profileImageUrl != null && profileImageUrl!.startsWith("data:image");

    return Scaffold(
      backgroundColor: const Color(0xFF0F1715),
      appBar: AppBar(
        title: Text("Profile Settings",
            style: GoogleFonts.urbanist(
                fontWeight: FontWeight.bold, color: Colors.white)),
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        centerTitle: true,
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 500),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(28),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                      child: Container(
                        decoration: BoxDecoration(
                          color:
                              const Color(0xFF131D1A).withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.12),
                              width: 1.2),
                        ),
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            GestureDetector(
                              onTap: isUploadingImage
                                  ? null
                                  : _handleImageSelection,
                              child: Stack(
                                children: [
                                  CircleAvatar(
                                    radius: 56,
                                    backgroundColor: primaryTurquoise
                                        .withValues(alpha: 0.15),
                                    backgroundImage: profileImageUrl != null
                                        ? (isBase64
                                            ? MemoryImage(base64Decode(
                                                profileImageUrl!.split(',')[1]))
                                            : NetworkImage(profileImageUrl!)
                                                as ImageProvider)
                                        : null,
                                    child: isUploadingImage
                                        ? const CircularProgressIndicator(
                                            color: primaryTurquoise)
                                        : (profileImageUrl == null
                                            ? const Icon(Icons.person_rounded,
                                                size: 60,
                                                color: primaryTurquoise)
                                            : null),
                                  ),
                                  Positioned(
                                    bottom: 0,
                                    right: 0,
                                    child: CircleAvatar(
                                      radius: 18,
                                      backgroundColor: primaryTurquoise,
                                      child: const Icon(
                                          Icons.camera_alt_rounded,
                                          size: 18,
                                          color: Colors.white),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              currentUser?.email ?? 'Account User',
                              style: GoogleFonts.urbanist(
                                  color: Colors.white.withValues(alpha: 0.5),
                                  fontSize: 14),
                            ),
                            const SizedBox(height: 32),
                            TextField(
                              controller: nameController,
                              keyboardType: TextInputType.name,
                              style: GoogleFonts.urbanist(color: Colors.white),
                              decoration: _glassInputDecoration(
                                  "Full Name", Icons.person_outline_rounded),
                            ),
                            const SizedBox(height: 20),
                            TextField(
                              controller: phoneController,
                              keyboardType: TextInputType.phone,
                              style: GoogleFonts.urbanist(color: Colors.white),
                              decoration: _glassInputDecoration(
                                  "Phone Number", Icons.phone_android_rounded),
                            ),
                            if (role == 'driver') ...[
                              const SizedBox(height: 20),
                              if (passportPhotoUrl != null && passportPhotoUrl!.isNotEmpty) ...[
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.25),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(color: Colors.white10),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        "Admin Passport Photo",
                                        style: GoogleFonts.urbanist(
                                          color: Colors.white60,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(10),
                                        child: Image.network(
                                          passportPhotoUrl!,
                                          height: 120,
                                          width: 120,
                                          fit: BoxFit.cover,
                                          errorBuilder: (context, error, stackTrace) =>
                                              const Icon(Icons.broken_image, color: Colors.white30, size: 40),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 20),
                              ],
                              TextFormField(
                                key: ValueKey('tier_$carTier'),
                                initialValue: carTier?.toUpperCase(),
                                readOnly: true,
                                style: GoogleFonts.urbanist(color: Colors.white, fontWeight: FontWeight.bold),
                                decoration: _glassInputDecoration(
                                    "Vehicle Tier / Class", Icons.drive_eta_rounded),
                              ),
                              const SizedBox(height: 20),
                              TextFormField(
                                key: ValueKey('license_$licenseNumber'),
                                initialValue: licenseNumber,
                                readOnly: true,
                                style: GoogleFonts.urbanist(color: Colors.white70),
                                decoration: _glassInputDecoration(
                                    "Driver's License (Read-only)", Icons.card_membership_rounded),
                              ),
                              const SizedBox(height: 20),
                              TextFormField(
                                key: ValueKey('bio_$bio'),
                                initialValue: bio,
                                readOnly: true,
                                style: GoogleFonts.urbanist(color: Colors.white70),
                                decoration: _glassInputDecoration(
                                    "Bio / Description (Read-only)", Icons.description_rounded),
                              ),
                              const SizedBox(height: 20),
                              TextFormField(
                                key: ValueKey('docs_$documents'),
                                initialValue: documents,
                                readOnly: true,
                                style: GoogleFonts.urbanist(color: Colors.white70),
                                decoration: _glassInputDecoration(
                                    "Documents Link (Read-only)", Icons.folder_open_rounded),
                              ),
                              const SizedBox(height: 20),
                              SizedBox(
                                width: double.infinity,
                                height: 48,
                                child: OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: primaryTurquoise,
                                    side: const BorderSide(color: primaryTurquoise),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  onPressed: _showUpdateRequestDialog,
                                  icon: const Icon(Icons.edit_note_rounded),
                                  label: Text(
                                    "Request Details Change",
                                    style: GoogleFonts.urbanist(fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ),
                            ],
                            const SizedBox(height: 32),
                            SizedBox(
                              width: double.infinity,
                              height: 54,
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: primaryTurquoise,
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14)),
                                ),
                                onPressed: isSaving ? null : saveProfile,
                                child: isSaving
                                    ? const SizedBox(
                                        height: 24,
                                        width: 24,
                                        child: CircularProgressIndicator(
                                          color: Colors.white,
                                          strokeWidth: 2.5,
                                        ),
                                      )
                                    : Text(
                                        "Save Changes",
                                        style: GoogleFonts.urbanist(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold),
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  void _showUpdateRequestDialog() {
    final TextEditingController reasonController = TextEditingController();
    final TextEditingController detailsController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF131D1A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: const BorderSide(color: Colors.white12),
          ),
          title: Text(
            "Request Profile Update",
            style: GoogleFonts.urbanist(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  "Explain what details you need updated (e.g. bio, documents, license, passport photo) and why. The admin will review it and reach out to you via email.",
                  style: GoogleFonts.urbanist(
                    color: Colors.white60,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: reasonController,
                  style: GoogleFonts.urbanist(color: Colors.white),
                  decoration: _glassInputDecoration(
                    "Reason for Change",
                    Icons.help_outline_rounded,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: detailsController,
                  style: GoogleFonts.urbanist(color: Colors.white),
                  maxLines: 4,
                  decoration: _glassInputDecoration(
                    "Update Details",
                    Icons.edit_note_rounded,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                "Cancel",
                style: GoogleFonts.urbanist(color: Colors.grey),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryTurquoise,
              ),
              onPressed: () async {
                String reason = reasonController.text.trim();
                String details = detailsController.text.trim();
                if (reason.isEmpty || details.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Please fill all fields")),
                  );
                  return;
                }

                await firestore.collection('driver_change_requests').add({
                  'driverId': currentUser!.uid,
                  'driverEmail': currentUser!.email,
                  'reason': reason,
                  'details': details,
                  'requestedAt': FieldValue.serverTimestamp(),
                  'status': 'pending',
                });

                if (!context.mounted) return;
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("Update request submitted! Admin will email you."),
                    backgroundColor: Colors.green,
                  ),
                );
              },
              child: Text(
                "Submit Request",
                style: GoogleFonts.urbanist(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  InputDecoration _glassInputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
      prefixIcon: Icon(icon, color: primaryTurquoise),
      filled: true,
      fillColor: Colors.black.withValues(alpha: 0.25),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: primaryTurquoise, width: 2),
      ),
    );
  }
}
/*import 'package:flutter/foundation.dart'; // Required for kIsWeb check
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final TextEditingController nameController = TextEditingController();
  final TextEditingController phoneController = TextEditingController();
  
  bool isLoading = false;
  bool isSaving = false;
  bool isUploadingImage = false;
  String? profileImageUrl;
  
  final currentUser = FirebaseAuth.instance.currentUser;
  final firestore = FirebaseFirestore.instance;
  final storage = FirebaseStorage.instance;

  @override
  void initState() {
    super.initState();
    loadProfile();
  }

  @override
  void dispose() {
    nameController.dispose();
    phoneController.dispose();
    super.dispose();
  }

  Future<void> loadProfile() async {
    if (currentUser == null) return;

    setState(() {
      isLoading = true;
    });

    try {
      final doc = await firestore.collection('users').doc(currentUser!.uid).get();

      if (doc.exists) {
        final data = doc.data()!;
        nameController.text = data['name'] ?? '';
        phoneController.text = data['phone'] ?? '';
        profileImageUrl = data['profilePicture']; // Fetches saved photo URL string if it exists
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error fetching data: $e")),
      );
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  // Multi-platform Profile Image Picker and Uploader Logic
  Future<void> _handleImageSelection() async {
    final ImagePicker picker = ImagePicker();
    
    // Show an options sheet to either upload a new image or remove the current one
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_rounded, color: Colors.blue),
              title: const Text("Upload New Photo"),
              onTap: () {
                Navigator.pop(context);
                _pickAndUploadAndSave(picker);
              },
            ),
            if (profileImageUrl != null)
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded, color: Colors.red),
                title: const Text("Remove Photo", style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(context);
                  _removeProfileImage();
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickAndUploadAndSave(ImagePicker picker) async {
    try {
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 75, // Compressed slightly for optimized database performance
      );

      if (image == null) return;

      setState(() {
        isUploadingImage = true;
      });

      String downloadUrl = '';
      final storageRef = storage.ref().child('profile_pictures/${currentUser!.uid}.jpg');

      if (kIsWeb) {
        // Safe byte-casting for clean running on Chrome desktop web channels
        final Uint8List webImageBytes = await image.readAsBytes();
        final UploadTask uploadTask = storageRef.putData(
          webImageBytes,
          SettableMetadata(contentType: 'image/jpeg'),
        );
        final TaskSnapshot snapshot = await uploadTask;
        downloadUrl = await snapshot.ref.getDownloadURL();
      } else {
        // Fallback reference for native mobile test devices
        final UploadTask uploadTask = storageRef.putData(await image.readAsBytes());
        final TaskSnapshot snapshot = await uploadTask;
        downloadUrl = await snapshot.ref.getDownloadURL();
      }

      // Sync the cloud storage link down to the user's Firestore Document
      await firestore.collection('users').doc(currentUser!.uid).update({
        'profilePicture': downloadUrl,
      });

      setState(() {
        profileImageUrl = downloadUrl;
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Profile picture updated successfully!"), backgroundColor: Colors.green),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to upload image: $e"), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) {
        setState(() {
          isUploadingImage = false;
        });
      }
    }
  }

  Future<void> _removeProfileImage() async {
    setState(() {
      isUploadingImage = true;
    });

    try {
      // Remove file from Firebase Storage
      try {
        await storage.ref().child('profile_pictures/${currentUser!.uid}.jpg').delete();
      } catch (_) {
        // If file doesn't exist in storage bucket, proceed silently to reset field reference
      }

      // Erase reference string value out of Firestore
      await firestore.collection('users').doc(currentUser!.uid).update({
        'profilePicture': FieldValue.delete(),
      });

      setState(() {
        profileImageUrl = null;
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Profile picture removed"), backgroundColor: Colors.orange),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error eliminating photo: $e")),
      );
    } finally {
      if (mounted) {
        setState(() {
          isUploadingImage = false;
        });
      }
    }
  }

  Future<void> saveProfile() async {
    if (currentUser == null) return;

    setState(() {
      isSaving = true;
    });

    try {
      await firestore.collection('users').doc(currentUser!.uid).update({
        'name': nameController.text.trim(),
        'phone': phoneController.text.trim(),
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Profile Updated Successfully"),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Failed to update profile: $e"),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text("Profile Settings", style: TextStyle(fontWeight: FontWeight.bold)),
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.grey.shade900,
        centerTitle: true,
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 500),
                  child: Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: Colors.grey.shade200),
                    ),
                    color: Colors.white,
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Interactive Stack handling image picking & dynamic loading states
                          GestureDetector(
                            onTap: isUploadingImage ? null : _handleImageSelection,
                            child: Stack(
                              children: [
                                CircleAvatar(
                                  radius: 52,
                                  backgroundColor: Colors.blue.shade50,
                                  backgroundImage: profileImageUrl != null
                                      ? NetworkImage(profileImageUrl!)
                                      : null,
                                  child: isUploadingImage
                                      ? const CircularProgressIndicator()
                                      : (profileImageUrl == null
                                          ? Icon(Icons.person_rounded, size: 56, color: Colors.blue.shade600)
                                          : null),
                                ),
                                Positioned(
                                  bottom: 0,
                                  right: 0,
                                  child: CircleAvatar(
                                    radius: 16,
                                    backgroundColor: Colors.blue.shade600,
                                    child: const Icon(Icons.edit_rounded, size: 16, color: Colors.white),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            currentUser?.email ?? 'Account User',
                            style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                          ),
                          const SizedBox(height: 32),
                          TextField(
                            controller: nameController,
                            keyboardType: TextInputType.name,
                            decoration: InputDecoration(
                              labelText: "Full Name",
                              prefixIcon: const Icon(Icons.person_outline_rounded),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: Colors.grey.shade300),
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          TextField(
                            controller: phoneController,
                            keyboardType: TextInputType.phone,
                            decoration: InputDecoration(
                              labelText: "Phone Number",
                              prefixIcon: const Icon(Icons.phone_android_rounded),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: Colors.grey.shade300),
                              ),
                            ),
                          ),
                          const SizedBox(height: 32),
                          SizedBox(
                            width: double.infinity,
                            height: 50,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue.shade600,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              onPressed: isSaving ? null : saveProfile,
                              child: isSaving
                                  ? const SizedBox(
                                      height: 24,
                                      width: 24,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2.5,
                                      ),
                                    )
                                  : const Text(
                                      "Save Changes",
                                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                                    ),
                            ),
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
}*/
/*import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final TextEditingController nameController = TextEditingController();
  final TextEditingController phoneController = TextEditingController();
  
  bool isLoading = false;
  bool isSaving = false;
  
  final currentUser = FirebaseAuth.instance.currentUser;
  final firestore = FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    loadProfile();
  }

  @override
  void dispose() {
    nameController.dispose();
    phoneController.dispose();
    super.dispose();
  }

  Future<void> loadProfile() async {
    if (currentUser == null) return;

    setState(() {
      isLoading = true;
    });

    try {
      final doc = await firestore.collection('users').doc(currentUser!.uid).get();

      if (doc.exists) {
        final data = doc.data()!;
        nameController.text = data['name'] ?? '';
        phoneController.text = data['phone'] ?? '';
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error fetching data: $e")),
      );
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  Future<void> saveProfile() async {
    if (currentUser == null) return;

    setState(() {
      isSaving = true;
    });

    try {
      await firestore.collection('users').doc(currentUser!.uid).update({
        'name': nameController.text.trim(),
        'phone': phoneController.text.trim(),
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Profile Updated Successfully"),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Failed to update profile: $e"),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text("Profile Settings", style: TextStyle(fontWeight: FontWeight.bold)),
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.grey.shade900,
        centerTitle: true,
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 500),
                  child: Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: Colors.grey.shade200),
                    ),
                    color: Colors.white,
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Stack(
                            children: [
                              CircleAvatar(
                                radius: 52,
                                backgroundColor: Colors.blue.shade50,
                                child: Icon(
                                  Icons.person_rounded,
                                  size: 56,
                                  color: Colors.blue.shade600,
                                ),
                              ),
                              Positioned(
                                bottom: 0,
                                right: 0,
                                child: CircleAvatar(
                                  radius: 16,
                                  backgroundColor: Colors.blue.shade600,
                                  child: const Icon(Icons.edit_rounded, size: 16, color: Colors.white),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            currentUser?.email ?? 'Account User',
                            style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                          ),
                          const SizedBox(height: 32),
                          TextField(
                            controller: nameController,
                            keyboardType: TextInputType.name,
                            decoration: InputDecoration(
                              labelText: "Full Name",
                              prefixIcon: const Icon(Icons.person_outline_rounded),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: Colors.grey.shade300),
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          TextField(
                            controller: phoneController,
                            keyboardType: TextInputType.phone,
                            decoration: InputDecoration(
                              labelText: "Phone Number",
                              prefixIcon: const Icon(Icons.phone_android_rounded),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: Colors.grey.shade300),
                              ),
                            ),
                          ),
                          const SizedBox(height: 32),
                          SizedBox(
                            width: double.infinity,
                            height: 50,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue.shade600,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              onPressed: isSaving ? null : saveProfile,
                              child: isSaving
                                  ? const SizedBox(
                                      height: 24,
                                      width: 24,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2.5,
                                      ),
                                    )
                                  : const Text(
                                      "Save Changes",
                                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                                    ),
                            ),
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
}*/
/*import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() =>
      _ProfileScreenState();
}

class _ProfileScreenState
    extends State<ProfileScreen> {

  final TextEditingController
      nameController =
          TextEditingController();

  final TextEditingController
      phoneController =
          TextEditingController();

  bool isLoading = false;

  final currentUser =
      FirebaseAuth.instance.currentUser;

  final firestore =
      FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    loadProfile();
  }

  Future<void> loadProfile() async {

    final doc =
        await firestore
            .collection('users')
            .doc(currentUser!.uid)
            .get();

    if (doc.exists) {

      final data = doc.data()!;

      nameController.text =
          data['name'] ?? '';

      phoneController.text =
          data['phone'] ?? '';
    }

    setState(() {});
  }

  Future<void> saveProfile() async {

    setState(() {
      isLoading = true;
    });

    await firestore
        .collection('users')
        .doc(currentUser!.uid)
        .update({

      'name':
          nameController.text.trim(),

      'phone':
          phoneController.text.trim(),
    });

    setState(() {
      isLoading = false;
    });

    if (!mounted) return;

    ScaffoldMessenger.of(context)
        .showSnackBar(

      const SnackBar(
        content: Text(
          "Profile Updated",
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(

      appBar: AppBar(
        title: const Text(
          "Profile",
        ),
        centerTitle: true,
      ),

      body: Padding(

        padding:
            const EdgeInsets.all(20),

        child: Column(

          children: [

            const CircleAvatar(

              radius: 50,

              child: Icon(
                Icons.person,
                size: 50,
              ),
            ),

            const SizedBox(height: 30),

            TextField(

              controller:
                  nameController,

              decoration:
                  const InputDecoration(

                labelText: "Full Name",
                border:
                    OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 20),

            TextField(

              controller:
                  phoneController,

              decoration:
                  const InputDecoration(

                labelText:
                    "Phone Number",

                border:
                    OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 30),

            SizedBox(

              width: double.infinity,
              height: 50,

              child: ElevatedButton(

                onPressed:
                    isLoading
                        ? null
                        : saveProfile,

                child: isLoading

                    ? const CircularProgressIndicator(
                        color:
                            Colors.white,
                      )

                    : const Text(
                        "Save Profile",
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}*/
