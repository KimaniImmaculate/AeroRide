import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// Force absolute package mappings to resolve types cleanly
import 'package:aeroride/controllers/ride_controller.dart';
import 'package:aeroride/firebase_options.dart';
import 'package:aeroride/screens/role_selection_screen.dart';
import 'package:aeroride/screens/views/driver_dashboard_view.dart'
    as driver_views;
import 'package:aeroride/screens/views/rider_dashboard_view.dart'
    as rider_views;
import 'package:aeroride/services/auth_service.dart';
import 'package:aeroride/services/notification_service.dart';
import 'package:aeroride/theme/aeroride_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  unawaited(_initNotifications());
  runApp(const AeroRideApp());
}

Future<void> _initNotifications() async {
  try {
    await NotificationService().init().timeout(const Duration(seconds: 5));
  } catch (error) {
    debugPrint('Notification init skipped: $error');
  }
}

class AeroRideApp extends StatelessWidget {
  const AeroRideApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => RideController(),
      child: MaterialApp(
        title: 'AeroRide',
        debugShowCheckedModeBanner: false,
        theme: AeroRideTheme.light(),
        home: const AuthWrapper(),
      ),
    );
  }
}

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  Future<DocumentSnapshot>? _profileFuture;
  String? _cachedUid;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: AuthService().authStateChanges,
      builder: (context, authSnapshot) {
        if (authSnapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (authSnapshot.hasData && authSnapshot.data != null) {
          final user = authSnapshot.data!;

          if (_cachedUid != user.uid) {
            _cachedUid = user.uid;
            _profileFuture = FirebaseFirestore.instance
                .collection('users')
                .doc(user.uid)
                .get()
                .timeout(const Duration(seconds: 10));
          }

          // ✅ The FutureBuilder loads cleanly exactly ONCE here
          return FutureBuilder<DocumentSnapshot>(
            future: _profileFuture,
            builder: (context, userSnapshot) {
              if (userSnapshot.connectionState == ConnectionState.waiting) {
                return const Scaffold(
                  body: Center(child: CircularProgressIndicator()),
                );
              }

              if (userSnapshot.hasError) {
                return Scaffold(
                  body: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        'Could not load profile: ${userSnapshot.error}',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                );
              }

              if (userSnapshot.hasData && userSnapshot.data!.exists) {
                final userData =
                    userSnapshot.data!.data() as Map<String, dynamic>;
                final role = userData['role'] ?? 'rider';

                // ✅ The stable wrappers catch and initialize both maps beautifully
                if (role == 'driver') {
                  return _StableDashboardMapWrapper(
                    child: driver_views.DriverDashboardView(user: user),
                  );
                } else {
                  return _StableDashboardMapWrapper(
                    child: rider_views.RiderDashboardView(user: user),
                  );
                }
              }

              return const RoleSelectionScreen();
            },
          );
        }

        // Fallback if no user data is active in Firebase Auth streams
        return const RoleSelectionScreen();
      },
    );
  }
}

// ✅ UPGRADED: Added a runtime state key tracker to eliminate multi-swap Web DOM caching crashes
class _StableDashboardMapWrapper extends StatefulWidget {
  final Widget child;
  const _StableDashboardMapWrapper({required this.child});

  @override
  State<_StableDashboardMapWrapper> createState() =>
      _StableDashboardMapWrapperState();
}

class _StableDashboardMapWrapperState
    extends State<_StableDashboardMapWrapper> {
  bool _isRenderReady = false;
  // 🔑 Unique state key forces Chrome to cleanly separate instances during portal flips
  final Key _domKey = UniqueKey();

  @override
  void initState() {
    super.initState();
    // ⏳ 450ms gives the Web engine absolute breathing room to dispose of the old layout
    Future.delayed(const Duration(milliseconds: 450), () {
      if (mounted) {
        setState(() => _isRenderReady = true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_isRenderReady) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
          ),
        ),
      );
    }

    // ✅ Wrapping your child view inside a Keyed Container prevents layout reuse collisions
    return Container(
      key: _domKey,
      child: widget.child,
    );
  }
}
