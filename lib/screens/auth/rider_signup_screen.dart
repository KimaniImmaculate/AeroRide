import 'package:flutter/material.dart';
import '../../services/auth_service.dart';

class RiderSignupScreen extends StatefulWidget {
  const RiderSignupScreen({super.key});

  @override
  State<RiderSignupScreen> createState() => _RiderSignupScreenState();
}

class _RiderSignupScreenState extends State<RiderSignupScreen> {
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
      final user = await _authService.signUp(
        _nameCtrl.text,
        _emailCtrl.text,
        _passwordCtrl.text,
        'rider',
        phoneNumber: _phoneCtrl.text,
      );
      if (user != null) {
        await _authService.ensureUserProfileForRole(
          user: user,
          role: 'rider',
          name: _nameCtrl.text,
        );
      }
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (e) {
      setState(() => _errorMsg = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Rider Sign Up')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            const Icon(Icons.person_add, size: 60, color: Colors.blue),
            const SizedBox(height: 20),
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Full Name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _emailCtrl,
              decoration: const InputDecoration(
                labelText: 'Email',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _phoneCtrl,
              decoration: const InputDecoration(
                labelText: 'Phone Number',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _passwordCtrl,
              decoration: const InputDecoration(
                labelText: 'Password (min 6 chars)',
                border: OutlineInputBorder(),
              ),
              obscureText: true,
            ),
            const SizedBox(height: 24),
            if (_errorMsg != null)
              Text(
                _errorMsg!,
                style: const TextStyle(color: Colors.red, fontSize: 12),
              ),
            const SizedBox(height: 16),
            _isLoading
                ? const CircularProgressIndicator()
                : ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 50),
                    ),
                    onPressed: _signUp,
                    child: const Text('Create Account'),
                  ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }
}
