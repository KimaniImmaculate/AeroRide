import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import 'views/rider_dashboard_view.dart';
import 'views/driver_dashboard_view.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _authService = AuthService();
  bool _isLoading = false;
  String? _errorMsg;

  Future<void> _signUp() async {
    setState(() {
      _isLoading = true;
      _errorMsg = null;
    });
    try {
      // 1️⃣ Dynamic Role Check: If their email contains 'driver', register them as one!
      final String detectedRole =
          _emailCtrl.text.trim().toLowerCase().contains('driver')
              ? 'driver'
              : 'passenger';

      final user = await _authService.signUp(
        _nameCtrl.text,
        _emailCtrl.text,
        _passwordCtrl.text,
        detectedRole, // ✅ Passed dynamically instead of hardcoded string
        phoneNumber: _phoneCtrl.text.trim(),
      );

      if (mounted && user != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;

          // 2️⃣ Routing Switch: Send them to the correct dashboard workspace
          if (detectedRole == 'driver') {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(
                  builder: (context) => DriverDashboardView(user: user)),
              (route) => false,
            );
          } else {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(
                  builder: (context) => RiderDashboardView(user: user)),
              (route) => false,
            );
          }
        });
      }
    } catch (e) {
      setState(() => _errorMsg = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sign Up for AeroRide')),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(labelText: 'Full Name'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _emailCtrl,
              decoration: const InputDecoration(labelText: 'Email'),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _phoneCtrl,
              decoration: const InputDecoration(labelText: 'Phone Number'),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _passwordCtrl,
              decoration: const InputDecoration(labelText: 'Password'),
              obscureText: true,
            ),
            const SizedBox(height: 24),
            if (_errorMsg != null)
              Text(_errorMsg!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 16),
            _isLoading
                ? const CircularProgressIndicator()
                : ElevatedButton(
                    onPressed: _signUp,
                    child: const Text('Sign Up'),
                  ),
          ],
        ),
      ),
    );
  }
}
