import 'package:flutter/material.dart';

import '../../theme/aeroride_theme.dart';
import '../../services/auth_service.dart';
import '../../widgets/aeroride_components.dart';

enum AeroRideUserRole { rider, driver }

class AuthScreen extends StatefulWidget {
  final AeroRideUserRole role;

  const AuthScreen({super.key, required this.role});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final AuthService _authService = AuthService();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _identifierController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isLogin = true;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _nameController.dispose();
    _identifierController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.aeroTokens;
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.white, tokens.softSurface, const Color(0xFFF8FAFC)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: AeroRidePanelCard(
                  padding: const EdgeInsets.all(24),
                  radius: 28,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              gradient: tokens.tealGradient,
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: const Icon(
                              Icons.local_taxi_rounded,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _headline,
                                  style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w900,
                                    color: Color(0xFF0D2B52),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _subheadline,
                                  style: TextStyle(
                                    color: Colors.grey.shade600,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      _LoginSignupToggle(
                        isLogin: _isLogin,
                        onChanged: (value) {
                          setState(() {
                            _isLogin = value;
                            _errorMessage = null;
                          });
                        },
                      ),
                      if (!_isLogin) ...[
                        const SizedBox(height: 14),
                        AeroRideTextField(
                          hint: 'Full Name',
                          icon: Icons.badge_outlined,
                          controller: _nameController,
                        ),
                      ],
                      const SizedBox(height: 22),
                      AeroRideTextField(
                        hint: 'Email or Phone',
                        icon: Icons.mail_outline_rounded,
                        controller: _identifierController,
                      ),
                      const SizedBox(height: 14),
                      AeroRideTextField(
                        hint: 'Password',
                        icon: Icons.lock_outline_rounded,
                        controller: _passwordController,
                        obscureText: true,
                      ),
                      const SizedBox(height: 20),
                      AeroRidePrimaryButton(
                        label: _isLogin ? 'Sign In' : 'Create Account',
                        trailing: const Icon(
                          Icons.arrow_forward_rounded,
                          size: 18,
                        ),
                        onPressed: _isSubmitting ? null : _submit,
                      ),
                      if (_errorMessage != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _errorMessage!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.red,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(child: Divider(color: tokens.mutedBorder)),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Text(
                              'Or continue with',
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Expanded(child: Divider(color: tokens.mutedBorder)),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: _SocialButton(
                              label: 'Google',
                              icon: Icons.g_mobiledata_rounded,
                              onTap: () {
                                // TODO: Hook up Google sign-in flow.
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _SocialButton(
                              label: 'Apple',
                              icon: Icons.apple_rounded,
                              onTap: () {
                                // TODO: Hook up Apple sign-in flow.
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        widget.role == AeroRideUserRole.rider
                            ? 'Rider access'
                            : 'Driver access',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.w600,
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

  String get _headline => widget.role == AeroRideUserRole.rider
      ? 'Welcome Rider'
      : 'Welcome Driver';

  String get _subheadline => widget.role == AeroRideUserRole.rider
      ? 'Book a clean, fast ride in seconds'
      : 'Start earning on your schedule';

  String get _roleValue =>
      widget.role == AeroRideUserRole.rider ? 'rider' : 'driver';

  Future<void> _submit() async {
    final email = _identifierController.text.trim();
    final password = _passwordController.text.trim();
    final name = _nameController.text.trim();

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      if (_isLogin) {
        final user = await _authService.login(email, password);
        if (user != null) {
          await _authService.ensureUserProfileForRole(
            user: user,
            role: _roleValue,
            name: name.isEmpty ? null : name,
          );
        }
      } else {
        final user = await _authService.signUp(
          name,
          email,
          password,
          _roleValue,
        );
        if (user != null) {
          await _authService.ensureUserProfileForRole(
            user: user,
            role: _roleValue,
            name: name,
          );
        }
      }

      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }
}

class _LoginSignupToggle extends StatelessWidget {
  final bool isLogin;
  final ValueChanged<bool> onChanged;

  const _LoginSignupToggle({required this.isLogin, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final tokens = context.aeroTokens;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: tokens.softSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: tokens.mutedBorder),
      ),
      child: Row(
        children: [
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              decoration: BoxDecoration(
                color: isLogin ? Colors.white : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
              ),
              child: TextButton(
                onPressed: () => onChanged(true),
                child: Text(
                  'Login',
                  style: TextStyle(
                    color: isLogin
                        ? tokens.primaryDarkBlue
                        : Colors.grey.shade600,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              decoration: BoxDecoration(
                color: !isLogin ? Colors.white : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
              ),
              child: TextButton(
                onPressed: () => onChanged(false),
                child: Text(
                  'Sign Up',
                  style: TextStyle(
                    color: !isLogin
                        ? tokens.primaryDarkBlue
                        : Colors.grey.shade600,
                    fontWeight: FontWeight.w800,
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

class _SocialButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _SocialButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.aeroTokens;
    return Material(
      color: tokens.softSurface,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: tokens.mutedBorder),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 22, color: tokens.primaryDarkBlue),
              const SizedBox(width: 10),
              Text(
                label,
                style: TextStyle(
                  color: tokens.primaryDarkBlue,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
