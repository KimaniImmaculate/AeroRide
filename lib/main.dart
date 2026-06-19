import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart'; // ⚡ ADDED: To expose the state pipeline
import 'firebase_options.dart';
import 'gateway_portal.dart';
import 'screens/auth/auth_gate.dart';
import 'services/ride_service.dart'; // ⚡ ADDED: Imports the RideController you just modified

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // ⚡ UPDATED: Wrapped the app initialization inside a ChangeNotifierProvider
  runApp(
    ChangeNotifierProvider(
      create: (_) => RideController(),
      child: const AeroRideApp(),
    ),
  );
}

class AeroRideApp extends StatelessWidget {
  const AeroRideApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'AeroRide',
      theme: ThemeData(
        primaryColor: const Color(0xFF16A085), // AeroRide Turquoise
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF8F9FA),
        textTheme: GoogleFonts.urbanistTextTheme(Theme.of(context).textTheme),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF16A085),
          primary: const Color(0xFF16A085),
          brightness: Brightness.light,
        ),
      ),
      home: const AuthGate(),
    );
  }
}
