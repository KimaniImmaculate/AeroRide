import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class DriverProfileScreen extends StatelessWidget {
  final User user;
  const DriverProfileScreen({super.key, required this.user});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Your Profile")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: CircleAvatar(
                radius: 50,
                backgroundColor: Colors.green,
                child: Text(
                  user.email?.substring(0, 1).toUpperCase() ?? "U",
                  style: const TextStyle(fontSize: 32, color: Colors.white),
                ),
              ),
            ),
            const SizedBox(height: 24),
            _ProfileField(label: "Name", value: user.displayName ?? "Not set"),
            _ProfileField(label: "Email", value: user.email ?? "Not set"),
            _ProfileField(label: "Role", value: "Driver"),
            _ProfileField(
              label: "Account Created",
              value: user.metadata.creationTime?.toString().split('.')[0] ??
                  "Unknown",
            ),
            const SizedBox(height: 30),
            const Text(
              "Driver Statistics",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('rides')
                  .where('driverId', isEqualTo: user.uid)
                  .where('status', isEqualTo: 'completed')
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                double totalEarnings = 0.0;
                final totalTrips = snapshot.data!.docs.length;

                for (final doc in snapshot.data!.docs) {
                  final data = doc.data() as Map<String, dynamic>;
                  // Prefer driverEarningsLog if present, fallback to legacy fareAmountKsh
                  final earning = (data['driverEarningsLog'] ??
                          data['fareAmountKsh'] ??
                          0.0)
                      .toDouble();
                  totalEarnings += earning;
                }

                return Row(
                  children: [
                    Expanded(
                      child: _buildMetricTile(
                        "Total Earnings",
                        "KSh ${totalEarnings.toStringAsFixed(0)}",
                        Icons.account_balance_wallet,
                        Colors.green,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildMetricTile(
                        "Completed Trips",
                        "$totalTrips",
                        Icons.check_circle,
                        Colors.blue,
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 24),
            const Text(
              "Ride History",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('rides')
                  .where('driverId', isEqualTo: user.uid)
                  .where('status', isEqualTo: 'completed')
                  .orderBy('completedAt', descending: true)
                  .limit(5)
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.data!.docs.isEmpty) {
                  return const Text('No completed rides yet.');
                }

                return Column(
                  children: snapshot.data!.docs.map((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    final rideLabel = (data['destinationName'] ??
                            data['dropoffAddress'] ??
                            'Trip')
                        .toString();

                    final double finalFare = (data['finalFareCharged'] ??
                            data['fareAmountKsh'] ??
                            0.0)
                        .toDouble();

                    return Card(
                      child: ListTile(
                        leading: const Icon(Icons.route, color: Colors.green),
                        title: Text(rideLabel),
                        subtitle: Text(
                            'Completed ride • KSh ${finalFare.toStringAsFixed(0)}'),
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileField extends StatelessWidget {
  final String label;
  final String value;

  const _ProfileField({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
          ),
          const Divider(),
        ],
      ),
    );
  }
}

class _StatBox extends StatelessWidget {
  final String label;
  final String value;

  const _StatBox({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green, width: 1),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.green,
            ),
          ),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        ],
      ),
    );
  }
}

Widget _buildMetricTile(
  String title,
  String value,
  IconData icon,
  Color color,
) {
  return Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: color.withValues(alpha: 0.25)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color),
        const SizedBox(height: 12),
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 4),
        Text(title, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    ),
  );
}
