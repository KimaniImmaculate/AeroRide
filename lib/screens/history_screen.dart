import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  static const Color primaryTurquoise = Color(0xFF16A085);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1715),
      appBar: AppBar(
        title: Text("Ride History",
            style: GoogleFonts.urbanist(
                fontWeight: FontWeight.bold, color: Colors.white)),
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        centerTitle: true,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('rides')
            .where('status', isEqualTo: 'completed')
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final rides = snapshot.data!.docs;

          if (rides.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.history_toggle_off_rounded,
                      size: 64, color: Colors.white.withValues(alpha: 0.2)),
                  const SizedBox(height: 16),
                  Text(
                    "No completed trips found",
                    style: GoogleFonts.urbanist(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 16,
                        fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            );
          }

          return Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 1200),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    // Create a responsive grid layout depending on the browser width
                    int crossAxisCount = constraints.maxWidth > 900
                        ? 3
                        : (constraints.maxWidth > 600 ? 2 : 1);

                    return GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 16,
                        mainAxisExtent: 200,
                      ),
                      itemCount: rides.length,
                      itemBuilder: (context, index) {
                        final ride = rides[index];
                        final data = ride.data() as Map<String, dynamic>;

                        return Card(
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: BorderSide(color: Colors.grey.shade200),
                          ),
                          color: Colors.white,
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.green.shade50,
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Text(
                                        "Completed",
                                        style: TextStyle(
                                            color: Colors.green.shade700,
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                    if (data['rating'] != null)
                                      Row(
                                        children: [
                                          const Icon(Icons.star_rounded,
                                              color: Colors.amber, size: 18),
                                          const SizedBox(width: 4),
                                          Text(
                                            "${data['rating']}/5",
                                            style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 13),
                                          ),
                                        ],
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 14),
                                // Simplified Route representation
                                Row(
                                  children: [
                                    Icon(Icons.trip_origin_rounded,
                                        color: Colors.blue.shade600, size: 14),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        data['pickup'] ?? 'Unknown Location',
                                        style: const TextStyle(
                                            fontSize: 13,
                                            overflow: TextOverflow.ellipsis),
                                      ),
                                    ),
                                  ],
                                ),
                                Padding(
                                  padding: const EdgeInsets.only(left: 6),
                                  child: Container(
                                      width: 1.5,
                                      height: 16,
                                      color: Colors.grey.shade300),
                                ),
                                Row(
                                  children: [
                                    const Icon(Icons.location_on_rounded,
                                        color: Colors.red, size: 14),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        data['destination'] ??
                                            'Unknown Destination',
                                        style: const TextStyle(
                                            fontSize: 13,
                                            overflow: TextOverflow.ellipsis,
                                            fontWeight: FontWeight.w500),
                                      ),
                                    ),
                                  ],
                                ),
                                const Spacer(),
                                const Divider(height: 12),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Text("DRIVER",
                                              style: TextStyle(
                                                  fontSize: 10,
                                                  color: Colors.grey,
                                                  fontWeight: FontWeight.bold)),
                                          Text(
                                            data['driverEmail'] ?? 'N/A',
                                            style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey.shade700,
                                                overflow:
                                                    TextOverflow.ellipsis),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Text(
                                      "KES ${data['fare'] ?? '0'}",
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                          color: Colors.black87),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
/*import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {

    return Scaffold(

      appBar: AppBar(
        title: const Text(
          "Ride History",
        ),
        centerTitle: true,
      ),

      body: StreamBuilder<QuerySnapshot>(

        stream: FirebaseFirestore.instance
            .collection('rides')
            .where(
              'status',
              isEqualTo: 'completed',
            )
            .snapshots(),

        builder: (context, snapshot) {

          if (!snapshot.hasData) {

            return const Center(
              child:
                  CircularProgressIndicator(),
            );
          }

          final rides =
              snapshot.data!.docs;

          if (rides.isEmpty) {

            return const Center(
              child: Text(
                "No Completed Rides",
              ),
            );
          }

          return ListView.builder(

            itemCount: rides.length,

            itemBuilder: (context, index) {

              final ride =
                  rides[index];

              final data =
                  ride.data()
                      as Map<String, dynamic>;

              return Card(

                margin:
                    const EdgeInsets.all(10),

                child: ListTile(

                  leading: const Icon(
                    Icons.history,
                  ),

                  title: Text(
                    "${data['pickup']} → ${data['destination']}",
                  ),

                  subtitle: Column(

                    crossAxisAlignment:
                        CrossAxisAlignment.start,

                    children: [

                      Text(
                        "Driver: ${data['driverEmail'] ?? 'N/A'}",
                      ),

                      Text(
                        "Status: ${data['status']}",
                      ),
                      if (data['status'] == 'cancelled')

  Text(
    "Cancelled By: ${data['cancelledBy']}",
  ),

                      if (data['status'] == 'cancelled')

  Text(
    "Reason: ${data['cancelReason']}",
  ),
                      Text(
                        "Fare: KES ${data['fare']}",
),
            if (data['rating'] != null)

  Text(
    "Rating: ${data['rating']}/5",
  ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}*/
