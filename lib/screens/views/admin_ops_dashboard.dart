import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AdminOpsDashboard extends StatefulWidget {
  const AdminOpsDashboard({super.key});

  @override
  State<AdminOpsDashboard> createState() => _AdminOpsDashboardState();
}

class _AdminOpsDashboardState extends State<AdminOpsDashboard> {
  // Enterprise Theme Constants
  static const Color deepSpaceBg = Color(0xFF0A0D14);
  static const Color charcoalSlate = Color(0xFF141923);
  static const Color signatureTurquoise = Color(0xFF16A085);
  static const Color neonIndigo = Colors.indigoAccent;

  final List<Map<String, dynamic>> _mockHazards = [
    {
      'type': '[Maandamano Alert]',
      'detail': 'Active disruption logged near CBD. Reroute suggested.',
      'severity': 'Critical',
    },
    {
      'type': '[Flash Flood]',
      'detail': 'High water table at Nairobi West. Trajectory inhibited.',
      'severity': 'Moderate',
    },
    {
      'type': '[Severe Potholes]',
      'detail': 'Localized structural road failure on Enterprise Rd.',
      'severity': 'Caution',
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: deepSpaceBg,
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [
                _buildTopNavigationHeader(),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    physics: const BouncingScrollPhysics(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 20),
                        _buildLiveMetricsGrid(),
                        const SizedBox(height: 32),
                        _buildSectionHeader(
                            "CROWDSOURCED HAZARD FEED", Icons.radar),
                        const SizedBox(height: 16),
                        _buildMonitoringDeck(),
                        const SizedBox(height: 100), // Space for bottom tray
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          _buildGlobalInfrastructureController(),
        ],
      ),
    );
  }

  Widget _buildTopNavigationHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: charcoalSlate,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withOpacity(0.1)),
              ),
              child: const Icon(Icons.arrow_back_ios_new_rounded,
                  color: Colors.white, size: 20),
            ),
          ),
          const SizedBox(width: 16),
          Text(
            "OPERATIONS ADMIN",
            style: GoogleFonts.urbanist(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              letterSpacing: 2,
            ),
          ),
          const Spacer(),
          const CircleAvatar(
            radius: 4,
            backgroundColor: signatureTurquoise,
          ),
          const SizedBox(width: 8),
          Text(
            "LIVE",
            style: GoogleFonts.urbanist(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: signatureTurquoise,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLiveMetricsGrid() {
    return GridView.count(
      shrinkWrap: true,
      crossAxisCount: 2,
      crossAxisSpacing: 16,
      mainAxisSpacing: 16,
      childAspectRatio: 1.5,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        _buildMetricBlock("ACTIVE DRIVERS", "42 CAPS", signatureTurquoise),
        _buildMetricBlock("ONGOING TRIPS", "18 ACTIVE", Colors.blueAccent),
        _buildMetricBlock("SYSTEM HAZARDS", "3 LOGGED", Colors.redAccent),
        _buildMetricBlock("FLEET REVENUE", "KSh 124K", Colors.amberAccent),
      ],
    );
  }

  Widget _buildMetricBlock(String label, String value, Color accentColor) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: charcoalSlate,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: neonIndigo.withOpacity(0.15), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: GoogleFonts.urbanist(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: Colors.grey[400],
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: GoogleFonts.urbanist(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: accentColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: neonIndigo, size: 18),
        const SizedBox(width: 8),
        Text(
          title,
          style: GoogleFonts.urbanist(
            fontSize: 12,
            fontWeight: FontWeight.w900,
            color: Colors.white,
            letterSpacing: 1.5,
          ),
        ),
      ],
    );
  }

  Widget _buildMonitoringDeck() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('live_hazards')
          .orderBy('timestamp', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError ||
            !snapshot.hasData ||
            snapshot.data!.docs.isEmpty) {
          // Elegant Premium Fallback
          return Column(
            children: _mockHazards
                .map((h) => _buildHazardTile(h['type'], h['detail'], true))
                .toList(),
          );
        }

        return Column(
          children: snapshot.data!.docs.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            return _buildHazardTile(data['type'] ?? 'Unknown',
                "Live telemetry logged from grid.", false);
          }).toList(),
        );
      },
    );
  }

  Widget _buildHazardTile(String type, String detail, bool isMock) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: charcoalSlate,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.redAccent.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.warning_amber_rounded,
              color: Colors.redAccent, size: 24),
        ),
        title: Text(
          type,
          style: GoogleFonts.urbanist(
            fontWeight: FontWeight.w900,
            color: Colors.white,
            fontSize: 14,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            detail,
            style: GoogleFonts.urbanist(
              color: Colors.grey[400],
              fontSize: 12,
            ),
          ),
        ),
        trailing: isMock
            ? const Icon(Icons.cloud_off_rounded,
                color: Colors.white24, size: 16)
            : const Icon(Icons.sensors_rounded,
                color: signatureTurquoise, size: 16),
      ),
    );
  }

  Widget _buildGlobalInfrastructureController() {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: charcoalSlate,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.5),
                blurRadius: 40,
                offset: const Offset(0, -10))
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildSectionHeader("GLOBAL INFRASTRUCTURE CONTROLLER",
                Icons.settings_input_component),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                onPressed: () => _purgeExpiredHazards(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white.withOpacity(0.05),
                  side: BorderSide(color: Colors.redAccent.withOpacity(0.3)),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                ),
                child: Text(
                  "PURGE EXPIRED HAZARDS",
                  style: GoogleFonts.urbanist(
                      fontWeight: FontWeight.w900,
                      color: Colors.redAccent,
                      letterSpacing: 1.2),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _purgeExpiredHazards() async {
    final cutoff = DateTime.now().subtract(const Duration(minutes: 30));
    final snapshot = await FirebaseFirestore.instance
        .collection('live_hazards')
        .where('timestamp', isLessThan: cutoff)
        .get();

    final batch = FirebaseFirestore.instance.batch();
    for (var doc in snapshot.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Infrastructure Purge Complete")),
      );
    }
  }
}
