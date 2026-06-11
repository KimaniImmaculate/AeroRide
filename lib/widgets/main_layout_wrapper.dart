import 'package:flutter/material.dart';
import 'package:aeroride/screens/views/rider_dashboard_view.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';

class MainLayoutWrapper extends StatefulWidget {
  final User user;
  const MainLayoutWrapper({super.key, required this.user});

  @override
  State<MainLayoutWrapper> createState() => _MainLayoutWrapperState();
}

class _MainLayoutWrapperState extends State<MainLayoutWrapper> {
  int _selectedIndex = 0;
  static const Color primaryTurquoise = Color(0xFF16a085);

  // Define the screens available in the bottom nav
  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    _pages = [
      RiderDashboardView(user: widget.user),
      const Scaffold(body: Center(child: Text("Your Activity"))),
      const Scaffold(body: Center(child: Text("Profile Settings"))),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: _pages,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 20,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: BottomNavigationBar(
          currentIndex: _selectedIndex,
          onTap: (index) => setState(() => _selectedIndex = index),
          selectedItemColor: primaryTurquoise,
          unselectedItemColor: Colors.grey,
          showUnselectedLabels: true,
          type: BottomNavigationBarType.fixed,
          selectedLabelStyle:
              GoogleFonts.urbanist(fontWeight: FontWeight.w800, fontSize: 12),
          unselectedLabelStyle:
              GoogleFonts.urbanist(fontWeight: FontWeight.w600, fontSize: 12),
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.map_outlined),
              activeIcon: Icon(Icons.map),
              label: 'Ride',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.history_outlined),
              activeIcon: Icon(Icons.history),
              label: 'Activity',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.person_outline),
              activeIcon: Icon(Icons.person),
              label: 'Account',
            ),
          ],
        ),
      ),
    );
  }
}
