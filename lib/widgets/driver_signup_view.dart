import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:aeroride/services/auth_service.dart';
import 'package:aeroride/controllers/ride_controller.dart';
import 'package:aeroride/services/shimmer_placeholder.dart';
import 'package:firebase_auth/firebase_auth.dart'; // Import FirebaseAuthException
import 'package:aeroride/screens/views/driver_dashboard_view.dart';

class DriverSignupView extends StatefulWidget {
  const DriverSignupView({super.key});

  @override
  State<DriverSignupView> createState() => _DriverSignupViewState();
}

class _DriverSignupViewState extends State<DriverSignupView> {
  final _step1Key = GlobalKey<FormState>();
  final _step2Key = GlobalKey<FormState>();
  final PageController _pageController = PageController();
  int _currentStep = 0;
  final _authService = AuthService();
  bool _isLoginMode = false; // Toggle for side-by-side mode

  // Personal Details
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();

  // Login Details
  final _loginEmailController = TextEditingController();
  final _loginPasswordController = TextEditingController();
  bool _isLoggingIn = false;

  // Profile Pic
  File? _profileImage;

  // Vehicle Details
  String? _selectedTier;
  final _modelController = TextEditingController();
  final _colorController = TextEditingController();
  final _plateController = TextEditingController(); // Main brand color
  final Color _signatureTurquoise = const Color(0xFF16a085);

  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // Ensure tiers are loaded so the dropdown is populated
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<RideController>().loadRideTypes();
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _modelController.dispose();
    _colorController.dispose();
    _plateController.dispose();
    _loginEmailController.dispose();
    _loginPasswordController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final pickedFile = await ImagePicker()
        .pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (pickedFile != null) {
      setState(() => _profileImage = File(pickedFile.path));
    }
  }

  void _nextStep() {
    bool isValid =
        _currentStep == 0 ? _step1Key.currentState!.validate() : true;
    if (isValid) {
      setState(() => _currentStep++);
      _pageController.nextPage(
          duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    }
  }

  void _previousStep() {
    setState(() => _currentStep--);
    _pageController.previousPage(
        duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
  }

  Future<void> _handleSignUp() async {
    if (!_step2Key.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      await _authService.signUp(
        _nameController.text.trim(),
        _emailController.text.trim(),
        _passwordController.text.trim(),
        'driver',
        phoneNumber: _phoneController.text.trim(),
        vehicleTier: _selectedTier,
        vehicleModel: _modelController.text.trim(),
        vehicleColor: _colorController.text.trim(),
        plateNumber: _plateController.text.trim().toUpperCase(),
        profileImage: _profileImage,
      );

      // On successful signup, navigate to the dashboard
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Driver registration successful!')),
        );
        // After successful signup, navigate to the driver dashboard
        // Assuming the user object is returned by authService.signUp
        // For now, we'll just pop and let the main AuthWrapper handle navigation
        // or you can directly push to DriverDashboardView if user is returned.
        // For this example, let's assume `signUp` returns the User.
        // If `signUp` doesn't return User, you might need to fetch it or
        // rely on the AuthWrapper in main.dart to redirect.
        // For now, let's just pop the signup view.
        Navigator.pop(context);
      }
    } on FirebaseAuthException catch (e) {
      if (e.code == 'email-already-in-use') {
        if (mounted) {
          _showErrorSnackBar(
              'This email is already registered. Please log in.');
          // Optionally, automatically open the login dialog
          await _showLoginDialog();
        }
      } else {
        if (mounted) {
          _showErrorSnackBar(
              e.message ?? 'An unknown authentication error occurred.');
        }
      }
    } catch (e) {
      if (mounted) {
        _showErrorSnackBar(e.toString());
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleLogin() async {
    if (_loginEmailController.text.isEmpty ||
        _loginPasswordController.text.isEmpty) {
      _showErrorSnackBar("Please enter credentials");
      return;
    }
    setState(() => _isLoggingIn = true);
    try {
      final loginResult = await _authService.login(
        _loginEmailController.text.trim(),
        _loginPasswordController.text.trim(),
      );

      if (loginResult.user != null && mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => DriverDashboardView(user: loginResult.user!),
          ),
        );
      } else if (loginResult.isMfaRequired) {
        _showErrorSnackBar('Two-factor authentication is required.');
      }
    } on FirebaseAuthException catch (e) {
      _showErrorSnackBar(e.message ?? 'Authentication failed.');
    } catch (e) {
      _showErrorSnackBar(e.toString());
    } finally {
      if (mounted) setState(() => _isLoggingIn = false);
    }
  }

  // Compatibility with user request for Login Modal - redirecting to toggle
  Future<void> _showLoginDialog() async {
    setState(() {
      _isLoginMode = true;
    });
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          // Full Screen Background
          const ShimmerBackground(
            assetPath: 'assets/skyline (2).jpg',
            opacity: 1.0,
          ),
          Positioned.fill(
              child: Container(color: Colors.black.withOpacity(0.55))),

          // Glassmorphism Blur
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
              child: Container(color: Colors.transparent),
            ),
          ),

          Center(
            child: SingleChildScrollView(
              child: Container(
                width: MediaQuery.of(context).size.width * 0.92,
                constraints: const BoxConstraints(maxWidth: 460),
                padding: const EdgeInsets.symmetric(vertical: 24),
                decoration: BoxDecoration(
                  color: _signatureTurquoise.withOpacity(0.92),
                  borderRadius: BorderRadius.circular(32),
                  border: Border.all(
                      color: Colors.white.withOpacity(0.1), width: 1.5),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black45,
                        blurRadius: 40,
                        offset: const Offset(0, 20))
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildHeader(),
                    _buildAuthToggle(),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 410,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 400),
                        child: _isLoginMode
                            ? _buildLoginForm()
                            : PageView(
                                controller: _pageController,
                                physics: const NeverScrollableScrollPhysics(),
                                children: [
                                  _buildStep1(),
                                  _buildStep2(),
                                  _buildStep3()
                                ],
                              ),
                      ),
                    ),
                    _buildBottomActions(),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAuthToggle() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _isLoginMode = false),
              child: Column(
                children: [
                  Text("SIGN UP",
                      style: GoogleFonts.urbanist(
                          fontWeight: FontWeight.w900,
                          color:
                              !_isLoginMode ? Colors.white : Colors.white54)),
                  if (!_isLoginMode)
                    Container(
                        height: 2,
                        color: Colors.white,
                        margin: const EdgeInsets.only(top: 4))
                ],
              ),
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _isLoginMode = true),
              child: Column(
                children: [
                  Text("LOG IN",
                      style: GoogleFonts.urbanist(
                          fontWeight: FontWeight.w900,
                          color: _isLoginMode ? Colors.white : Colors.white54)),
                  if (_isLoginMode)
                    Container(
                        height: 2,
                        color: Colors.white,
                        margin: const EdgeInsets.only(top: 4))
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
      child: Row(
        children: [
          if (_currentStep > 0)
            IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: _previousStep,
            )
          else
            const Icon(Icons.shield, color: Colors.white, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _isLoginMode
                  ? 'Access Terminal'
                  : (_currentStep == 0
                      ? 'Driver Identity'
                      : _currentStep == 1
                          ? 'Profile Image'
                          : 'Vehicle Registry'),
              style: GoogleFonts.urbanist(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: Colors.white,
              ),
            ),
          ),
          if (_currentStep == 0)
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white70),
              onPressed: () => Navigator.pop(context),
            )
        ],
      ),
    );
  }

  Widget _buildLoginForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        children: [
          _buildTextField(
              _loginEmailController, 'Email or Phone', Icons.person_outline),
          _buildTextField(
              _loginPasswordController, 'Password', Icons.lock_outline,
              obscureText: true),
        ],
      ),
    );
  }

  Widget _buildStep1() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Form(
          key: _step1Key,
          child: Column(children: [
            _buildTextField(_nameController, 'Full Name', Icons.person),
            _buildTextField(_emailController, 'Email', Icons.email,
                keyboardType: TextInputType.emailAddress),
            _buildTextField(_phoneController, 'Phone', Icons.phone,
                hint: '+254...'),
            _buildTextField(_passwordController, 'Password', Icons.lock,
                obscureText: true),
          ])),
    );
  }

  Widget _buildStep2() {
    return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      GestureDetector(
        onTap: _pickImage,
        child: CircleAvatar(
          radius: 80,
          backgroundColor: Colors.grey[200],
          backgroundImage:
              _profileImage != null ? FileImage(_profileImage!) : null,
          child: _profileImage == null
              ? Icon(Icons.camera_alt, size: 40, color: _signatureTurquoise)
              : null,
        ),
      ),
      const SizedBox(height: 24),
      Text("Upload Profile Picture",
          style: GoogleFonts.urbanist(
              fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white)),
      const SizedBox(height: 8),
      Text("Help riders recognize you",
          style: GoogleFonts.urbanist(color: Colors.white70)),
    ]);
  }

  Widget _buildStep3() {
    final rideController = context.watch<RideController>();
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Form(
          key: _step2Key,
          child: Column(children: [
            DropdownButtonFormField<String>(
              value: _selectedTier,
              dropdownColor: Colors.white,
              style: const TextStyle(
                  color: Colors.black87, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                  labelText: 'Vehicle Tier',
                  labelStyle: const TextStyle(color: Colors.white70),
                  prefixIcon: const Icon(Icons.layers, color: Colors.white),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.1),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none)),
              items: rideController.vehicleTiers
                  .map((tier) =>
                      DropdownMenuItem(value: tier.id, child: Text(tier.name)))
                  .toList(),
              onChanged: (val) => setState(() => _selectedTier = val),
              validator: (val) => val == null ? 'Select tier' : null,
            ),
            const SizedBox(height: 16),
            _buildTextField(_modelController, 'Model', Icons.directions_car),
            _buildTextField(_colorController, 'Color', Icons.palette),
            _buildTextField(_plateController, 'Plate Number', Icons.pin,
                hint: 'KAA 123A'),
          ])),
    );
  }

  Widget _buildBottomActions() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 54,
            width: double.infinity,
            child: ElevatedButton(
              onPressed: (_isLoading || _isLoggingIn)
                  ? null
                  : (_isLoginMode
                      ? _handleLogin
                      : (_currentStep < 2 ? _nextStep : _handleSignUp)),
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12))),
              child: (_isLoading || _isLoggingIn)
                  ? ShimmerPlaceholder(
                      child: Container(
                          width: 24,
                          height: 24,
                          decoration: const BoxDecoration(
                              color: Colors.black, shape: BoxShape.circle)))
                  : Text(
                      _isLoginMode
                          ? 'SECURE LOG IN'
                          : (_currentStep < 2
                              ? 'CONTINUE'
                              : 'FINISH REGISTRATION'),
                      style: const TextStyle(fontWeight: FontWeight.w900)),
            ),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: () => setState(() => _isLoginMode = !_isLoginMode),
            child: Text(
              _isLoginMode
                  ? "Need an account? Register"
                  : 'Already have an account? Log In',
              style: const TextStyle(
                  color: Colors.white70, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField(
    TextEditingController controller,
    String label,
    IconData icon, {
    bool obscureText = false,
    TextInputType? keyboardType,
    String? hint,
    String? Function(String?)? validator,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: TextFormField(
        controller: controller,
        obscureText: obscureText,
        keyboardType: keyboardType,
        style:
            const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(
              color: Colors.black45, fontSize: 16, fontWeight: FontWeight.w600),
          hintText: hint,
          prefixIcon: Icon(icon, color: _signatureTurquoise, size: 20),
          filled: true,
          fillColor: Colors.white,
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.black87, width: 1.5)),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
        validator: validator ??
            (val) => val == null || val.isEmpty ? '$label is required' : null,
      ),
    );
  }
}
