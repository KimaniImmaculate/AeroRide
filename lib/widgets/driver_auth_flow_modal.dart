import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart'; // For Lucide icons
import 'package:firebase_auth/firebase_auth.dart';

import '../controllers/driver_auth_controller.dart';
import '../screens/views/driver_dashboard_view.dart'; // Fixed path to the actual view

class DriverAuthFlowModal extends StatefulWidget {
  const DriverAuthFlowModal({super.key});

  @override
  State<DriverAuthFlowModal> createState() => _DriverAuthFlowModalState();
}

class _DriverAuthFlowModalState extends State<DriverAuthFlowModal> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _licenseController = TextEditingController();
  final TextEditingController _plateController = TextEditingController();
  final TextEditingController _modelController = TextEditingController();
  final TextEditingController _otpController = TextEditingController();

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final GlobalKey<FormState> _otpFormKey = GlobalKey<FormState>();

  String _selectedTier = 'tulia';
  final List<String> _tiers = ['tulia', 'nuru', 'pamoja', 'waziri'];

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _licenseController.dispose();
    _plateController.dispose();
    _modelController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => DriverAuthController(),
      child: Consumer<DriverAuthController>(
        builder: (context, controller, child) {
          return Container(
            height: MediaQuery.of(context).size.height * 0.85,
            decoration: BoxDecoration(
              color: Theme.of(context).canvasColor,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0).copyWith(
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Drag handle
                  Container(
                    width: 40,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    _getStepTitle(controller),
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 24),

                  if (!controller.isCodeSent)
                    Form(
                      key: _formKey,
                      child: Column(
                        children: [
                          if (controller.currentStep == 0) ...[
                            _buildTextField(_nameController, 'Full Legal Name',
                                LucideIcons.user),
                            const SizedBox(height: 16),
                            _buildTextField(_emailController, 'Email Address',
                                LucideIcons.mail,
                                keyboardType: TextInputType.emailAddress),
                            const SizedBox(height: 16),
                            _buildTextField(_phoneController,
                                'Phone Number (+254...)', LucideIcons.phone,
                                keyboardType: TextInputType.phone),
                          ] else if (controller.currentStep == 1) ...[
                            _buildTierDropdown(),
                            const SizedBox(height: 16),
                            _buildTextField(
                                _modelController,
                                'Vehicle Model (e.g. Toyota Fielder)',
                                LucideIcons.info),
                            const SizedBox(height: 16),
                            _buildTextField(_plateController, 'Number Plate',
                                LucideIcons.tag),
                            const SizedBox(height: 16),
                            _buildTextField(_licenseController,
                                'License Number', LucideIcons.fileText),
                          ],
                          const SizedBox(height: 32),
                          ElevatedButton(
                            onPressed: controller.isLoading
                                ? null
                                : () async {
                                    if (_formKey.currentState!.validate()) {
                                      if (controller.currentStep == 0) {
                                        controller.nextStep();
                                      } else {
                                        try {
                                          await controller.sendOtp(
                                              _phoneController.text.trim());
                                        } on FirebaseAuthException catch (e) {
                                          _showErrorSnackBar(e.message ??
                                              'An unknown error occurred.');
                                        } catch (e) {
                                          _showErrorSnackBar(e.toString());
                                        }
                                      }
                                    }
                                  },
                            style: ElevatedButton.styleFrom(
                              minimumSize: const Size.fromHeight(
                                  50), // Full width button
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: controller.isLoading
                                ? const CircularProgressIndicator(
                                    color: Colors.white)
                                : Text(controller.currentStep == 0
                                    ? 'Next: Vehicle Details'
                                    : 'Send Verification Code'),
                          ),
                          if (controller.currentStep > 0)
                            TextButton(
                              onPressed: () => controller.prevStep(),
                              child: const Text('Back to Identity'),
                            ),
                        ],
                      ),
                    )
                  else
                    // OTP Verification State
                    Form(
                      key: _otpFormKey,
                      child: Column(
                        children: [
                          TextFormField(
                            controller: _otpController,
                            keyboardType: TextInputType.number,
                            maxLength: 6,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                fontSize: 24, letterSpacing: 10),
                            decoration: InputDecoration(
                              labelText: '6-digit OTP',
                              hintText: '------',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              counterText: "", // Hide the default counter
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please enter the OTP';
                              }
                              if (value.length != 6) {
                                return 'OTP must be 6 digits';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 20),
                          ElevatedButton(
                            onPressed: controller.isLoading
                                ? null
                                : () async {
                                    if (_otpFormKey.currentState!.validate()) {
                                      try {
                                        final driverData = {
                                          'name': _nameController.text.trim(),
                                          'email': _emailController.text.trim(),
                                          'vehicleType': _selectedTier,
                                          'vehicleModel':
                                              _modelController.text.trim(),
                                          'licenseNumber':
                                              _licenseController.text.trim(),
                                          'plateNumber':
                                              _plateController.text.trim(),
                                        };
                                        final user = await controller.verifyOtp(
                                            _otpController.text.trim(),
                                            driverData: driverData);
                                        if (user != null && mounted) {
                                          Navigator.pop(
                                              context); // Close the modal
                                          Navigator.pushReplacement(
                                            context,
                                            MaterialPageRoute(
                                                builder: (context) =>
                                                    DriverDashboardView(
                                                        user: user)),
                                          );
                                        }
                                      } on FirebaseAuthException catch (e) {
                                        _showErrorSnackBar(e.message ??
                                            'An unknown error occurred.');
                                      } catch (e) {
                                        _showErrorSnackBar(e.toString());
                                      }
                                    }
                                  },
                            style: ElevatedButton.styleFrom(
                              minimumSize: const Size.fromHeight(50),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: controller.isLoading
                                ? const CircularProgressIndicator(
                                    color: Colors.white)
                                : const Text('Verify & Sign In'),
                          ),
                          TextButton(
                            onPressed: controller.isLoading
                                ? null
                                : () {
                                    // Reset state to go back to phone entry
                                    controller
                                        .resetState(); // Add this method to DriverAuthController
                                    _otpController.clear();
                                  },
                            child: const Text('Resend OTP or Change Number'),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  String _getStepTitle(DriverAuthController controller) {
    if (controller.isCodeSent) return 'Verify Terminal';
    return controller.currentStep == 0 ? 'Driver Identity' : 'Vehicle Registry';
  }

  Widget _buildTextField(
      TextEditingController controller, String label, IconData icon,
      {TextInputType keyboardType = TextInputType.text}) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      validator: (val) => val == null || val.isEmpty ? 'Required field' : null,
    );
  }

  Widget _buildTierDropdown() {
    return DropdownButtonFormField<String>(
      value: _selectedTier,
      decoration: InputDecoration(
        labelText: 'Service Tier',
        prefixIcon: const Icon(LucideIcons.car),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      items: _tiers
          .map((t) => DropdownMenuItem(value: t, child: Text(t.toUpperCase())))
          .toList(),
      onChanged: (val) => setState(() => _selectedTier = val!),
    );
  }
}
