import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../gateway_portal.dart';
import '../rider/rider_home_screen.dart';
import '../driver/driver_home_screen.dart';
import '../admin/admin_dashboard.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // User is not signed in
        if (!snapshot.hasData) {
          return const AeroRideGatewayPortal();
        }

        // User is signed in, determine their role
        return FutureBuilder<DocumentSnapshot>(
          future: FirebaseFirestore.instance
              .collection('users')
              .doc(snapshot.data!.uid)
              .get(),
          builder: (context, userSnapshot) {
            // While fetching user data, show a loading screen
            if (userSnapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(
                  child: CircularProgressIndicator(),
                ),
              );
            }

            // If user data exists, check the role
            if (userSnapshot.hasData && userSnapshot.data!.exists) {
              final data = userSnapshot.data!.data() as Map<String, dynamic>;
              if (data['role'] == 'driver') {
                return const DriverHomeScreen();
              } else if (data['role'] == 'admin') {
                return const AdminDashboard();
              }
            }

            // Default to RiderHomeScreen if role is not 'driver' or not specified
            return const RiderHomeScreen();
          },
        );
      },
    );
  }
}
