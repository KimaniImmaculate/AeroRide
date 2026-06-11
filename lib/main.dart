import 'dart:async';

import 'package:aeroride/utils/web_helper_stub.dart'
    if (dart.library.html) 'package:aeroride/utils/web_helper_web.dart'
    as web_helper;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// Force absolute package mappings to resolve types cleanly
import 'package:aeroride/controllers/ride_controller.dart';
import 'package:aeroride/firebase_options.dart';
import 'package:aeroride/screens/role_selection_screen.dart';
import 'package:aeroride/widgets/main_layout_wrapper.dart';
import 'package:aeroride/widgets/aero_welcome_view.dart';
import 'package:aeroride/screens/views/driver_dashboard_view.dart'
    as driver_views;
import 'package:aeroride/screens/views/rider_dashboard_view.dart'
    as rider_views;
import 'package:aeroride/services/auth_service.dart';
import 'package:aeroride/services/notification_service.dart';
import 'package:aeroride/theme/aeroride_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  if (kIsWeb) {
    web_helper.registerWebPlatformView();
  }

  // Initialize notifications gracefully
  await _initNotifications();

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
  @override
  Widget build(BuildContext context) {
    final authService = AuthService();

    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // 1. Handle initial connection state
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        // Handle Error States
        if (snapshot.hasError) {
          return Scaffold(
            body: Center(child: Text("Startup Error: ${snapshot.error}")),
          );
        }

        // Always start with the welcome view.
        // The sign-in is handled when they click "LET'S GLIDE".
        return const AeroWelcomeView();
      },
    );
  }
}

// ✅ RETAINED: State key tracker to eliminate multi-swap Web DOM caching crashes
class _StableDashboardMapWrapper extends StatefulWidget {
  final Widget child;
  const _StableDashboardMapWrapper({super.key, required this.child});

  @override
  State<_StableDashboardMapWrapper> createState() =>
      _StableDashboardMapWrapperState();
}

class _StableDashboardMapWrapperState
    extends State<_StableDashboardMapWrapper> {
  bool _isRenderReady = false;
  final Key _domKey = UniqueKey();

  @override
  void initState() {
    super.initState();
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

    return Container(
      key: _domKey,
      child: widget.child,
    );
  }
}
