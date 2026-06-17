import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AdminDashboard extends StatelessWidget {
  const AdminDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    final firestore = FirebaseFirestore.instance;

    return DefaultTabController(
      length: 2, 
      child: Scaffold(
        backgroundColor: Colors.grey.shade50,
        appBar: AppBar(
          title: const Text("AeroRide System Panel", style: TextStyle(fontWeight: FontWeight.bold)),
          elevation: 0,
          backgroundColor: Colors.white,
          foregroundColor: Colors.grey.shade900,
          centerTitle: false,
        ),
        body: StreamBuilder<QuerySnapshot>(
          stream: firestore.collection('rides').snapshots(),
          builder: (context, rideSnapshot) {
            if (!rideSnapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            int totalRides = 0;
            int completedRides = 0;
            int cancelledRides = 0;
            double totalRevenue = 0;

            for (var ride in rideSnapshot.data!.docs) {
              final data = ride.data() as Map<String, dynamic>;
              totalRides++;

              if (data['status'] == 'completed') completedRides++;
              if (data['status'] == 'cancelled') cancelledRides++;
              if (data['fare'] != null) {
                totalRevenue += (data['fare'] as num).toDouble();
              }
            }

            return Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 1200),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      // Adjust orientation automatically based on browser window scale
                      if (constraints.maxWidth > 800) {
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 2,
                              child: _buildMetricSidePanel(
                                totalRides: totalRides,
                                completedRides: completedRides,
                                cancelledRides: cancelledRides,
                                totalRevenue: totalRevenue,
                              ),
                            ),
                            const SizedBox(width: 24),
                            Expanded(
                              flex: 3,
                              child: _buildEmergencyTabbedView(firestore),
                            ),
                          ],
                        );
                      } else {
                        // Adaptive rollback for narrower test windows
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildMetricSidePanel(
                              totalRides: totalRides,
                              completedRides: completedRides,
                              cancelledRides: cancelledRides,
                              totalRevenue: totalRevenue,
                            ),
                            const SizedBox(height: 24),
                            _buildEmergencyTabbedView(firestore),
                          ],
                        );
                      }
                    },
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildMetricSidePanel({
    required int totalRides,
    required int completedRides,
    required int cancelledRides,
    required double totalRevenue,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "System Logistics Overview",
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey.shade800),
        ),
        const SizedBox(height: 12),
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.grey.shade200),
          ),
          color: Colors.white,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSummaryLine("Total Dispatched Rides", totalRides.toString(), Icons.local_taxi_rounded, Colors.blue),
                const Divider(height: 24),
                _buildSummaryLine("Completed Trips", completedRides.toString(), Icons.check_circle_outline_rounded, Colors.green),
                const Divider(height: 24),
                _buildSummaryLine("Cancelled Requests", cancelledRides.toString(), Icons.cancel_outlined, Colors.red),
                const Divider(height: 24),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.payments_outlined, color: Colors.green.shade700, size: 28),
                      const SizedBox(width: 16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("Gross Platform Value", style: TextStyle(fontSize: 12, color: Colors.green.shade800, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          Text("KES ${totalRevenue.toStringAsFixed(0)}", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.green.shade900)),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryLine(String title, String value, IconData icon, Color iconColor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Icon(icon, color: iconColor, size: 20),
            const SizedBox(width: 12),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w500, color: Colors.black87)),
          ],
        ),
        Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildEmergencyTabbedView(FirebaseFirestore firestore) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Emergency Management Routing",
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey.shade800),
        ),
        const SizedBox(height: 12),
        Container(
          height: 500,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Container(
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: TabBar(
                    indicatorSize: TabBarIndicatorSize.tab,
                    indicator: BoxDecoration(
                      color: Colors.red.shade600,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    labelColor: Colors.white,
                    unselectedLabelColor: Colors.grey.shade700,
                    tabs: const [
                      Tab(text: "Rider Alerts"),
                      Tab(text: "Driver Alerts"),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    _buildEmergencyList(firestore, 'rider'),
                    _buildEmergencyList(firestore, 'driver'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEmergencyList(FirebaseFirestore firestore, String filterRole) {
    return StreamBuilder<QuerySnapshot>(
      stream: firestore
          .collection('emergencies')
          .where('userRole', isEqualTo: filterRole)
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          // Fall back gracefully if a compound index is still building in Firestore console
          return StreamBuilder<QuerySnapshot>(
            stream: firestore.collection('emergencies').where('userRole', isEqualTo: filterRole).snapshots(),
            builder: (context, fallbackSnapshot) {
              if (!fallbackSnapshot.hasData) return const Center(child: CircularProgressIndicator());
              return _renderList(fallbackSnapshot.data!.docs, filterRole, firestore);
            },
          );
        }

        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        return _renderList(snapshot.data!.docs, filterRole, firestore);
      },
    );
  }

  Widget _renderList(List<QueryDocumentSnapshot> emergencies, String filterRole, FirebaseFirestore firestore) {
    if (emergencies.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.gpp_good_rounded, size: 44, color: Colors.green.shade300),
            const SizedBox(height: 8),
            Text(
              "No active emergencies from ${filterRole}s",
              style: const TextStyle(color: Colors.grey, fontSize: 14),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: emergencies.length,
      itemBuilder: (context, index) {
        final emergency = emergencies[index];
        final data = emergency.data() as Map<String, dynamic>;
        String sosMessage = data['message'] ?? 'No context details updated.';
        bool isActive = data['status'] == 'active';

        return Card(
          elevation: 0,
          color: isActive ? Colors.red.shade50.withOpacity(0.6) : Colors.grey.shade50,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: isActive ? Colors.red.shade100 : Colors.grey.shade200),
          ),
          margin: const EdgeInsets.symmetric(vertical: 6),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            isThreeLine: true,
            leading: CircleAvatar(
              backgroundColor: isActive ? Colors.red.shade100 : Colors.grey.shade200,
              child: Icon(
                isActive ? Icons.warning_amber_rounded : Icons.gpp_good_outlined,
                color: isActive ? Colors.red.shade800 : Colors.grey.shade600,
              ),
            ),
            title: Text(
              "SOS from ${filterRole.toUpperCase()}",
              style: TextStyle(fontWeight: FontWeight.bold, color: isActive ? Colors.red.shade900 : Colors.grey.shade800),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text(
                  "Situation: $sosMessage",
                  style: const TextStyle(color: Colors.black87, fontSize: 13, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 6),
                Text(
                  "System Status: ${data['status'].toString().toUpperCase()}",
                  style: TextStyle(color: isActive ? Colors.red.shade700 : Colors.grey.shade600, fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            trailing: isActive
                ? IconButton(
                    icon: const Icon(Icons.assignment_turned_in_rounded, color: Colors.green),
                    tooltip: "Mark as Resolved",
                    onPressed: () async {
                      await firestore.collection('emergencies').doc(emergency.id).update({'status': 'resolved'});
                    },
                  )
                : const Icon(Icons.check_circle, color: Colors.grey, size: 20),
          ),
        );
      },
    );
  }
}

/*import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AdminDashboard extends StatelessWidget {
  const AdminDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    final firestore = FirebaseFirestore.instance;

    // DefaultTabController organizes our views into tabs automatically
    return DefaultTabController(
      length: 2, // Two channels: Rider and Driver
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Admin Dashboard"),
          centerTitle: true,
        ),
        body: StreamBuilder<QuerySnapshot>(
          stream: firestore.collection('rides').snapshots(),
          builder: (context, rideSnapshot) {
            if (!rideSnapshot.hasData) {
              return const Center(
                child: CircularProgressIndicator(),
              );
            }

            int totalRides = 0;
            int completedRides = 0;
            int cancelledRides = 0;
            double totalRevenue = 0;

            for (var ride in rideSnapshot.data!.docs) {
              final data = ride.data() as Map<String, dynamic>;
              totalRides++;

              if (data['status'] == 'completed') {
                completedRides++;
              }
              if (data['status'] == 'cancelled') {
                cancelledRides++;
              }
              if (data['fare'] != null) {
                totalRevenue += (data['fare'] as num).toDouble();
              }
            }

            return Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Upper Revenue Summary Card
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Total Rides: $totalRides",
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 15),
                        Text(
                          "Completed Rides: $completedRides",
                          style: const TextStyle(fontSize: 18),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          "Cancelled Rides: $cancelledRides",
                          style: const TextStyle(fontSize: 18),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          "Total Revenue: KES ${totalRevenue.toStringAsFixed(0)}",
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 25),
                  
                  const Text(
                    "Emergency Management",
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),

                  // The Tab Selection Bar
                  Container(
                    height: 45,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: TabBar(
                      indicatorSize: TabBarIndicatorSize.tab,
                      indicator: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      labelColor: Colors.white,
                      unselectedLabelColor: Colors.black87,
                      tabs: const [
                        Tab(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.person, size: 18),
                              SizedBox(width: 8),
                              Text("Rider Alerts", style: TextStyle(fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                        Tab(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.time_to_leave, size: 18),
                              SizedBox(width: 8),
                              Text("Driver Alerts", style: TextStyle(fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 15),

                  // Tab Views holding individual streaming filters
                  Expanded(
                    child: TabBarView(
                      children: [
                        // View 1: Riders Stream List
                        _buildEmergencyList(firestore, 'rider'),
                        
                        // View 2: Drivers Stream List
                        _buildEmergencyList(firestore, 'driver'),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  // Reusable component designed to handle segmented queries flawlessly
  Widget _buildEmergencyList(FirebaseFirestore firestore, String filterRole) {
    return StreamBuilder<QuerySnapshot>(
      // We alter the query string to request targeted documents dynamically
      stream: firestore
          .collection('emergencies')
          .where('userRole', isEqualTo: filterRole)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final emergencies = snapshot.data!.docs;

        if (emergencies.isEmpty) {
          return Center(
            child: Text(
              "No active emergencies from ${filterRole}s",
              style: const TextStyle(color: Colors.grey, fontSize: 16),
            ),
          );
        }

        return ListView.builder(
          itemCount: emergencies.length,
          itemBuilder: (context, index) {
            final emergency = emergencies[index];
            final data = emergency.data() as Map<String, dynamic>;
            String sosMessage = data['message'] ?? 'No text description provided.';

            return Card(
              color: Colors.red.shade50,
              margin: const EdgeInsets.symmetric(vertical: 6),
              child: ListTile(
                isThreeLine: true,
                leading: const Icon(
                  Icons.warning,
                  color: Colors.red,
                  size: 28,
                ),
                title: Text(
                  "SOS from ${filterRole.toUpperCase()}",
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 4.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Situation: $sosMessage",
                        style: const TextStyle(
                          color: Colors.black87,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "Status: ${data['status']}",
                        style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
              
            );
          },
        );
      },
    );
  }
}*/

/*import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AdminDashboard extends StatelessWidget {
  const AdminDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    final firestore = FirebaseFirestore.instance;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Admin Dashboard"),
        centerTitle: true,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: firestore.collection('rides').snapshots(),
        builder: (context, rideSnapshot) {
          if (!rideSnapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          int totalRides = 0;
          int completedRides = 0;
          int cancelledRides = 0;
          double totalRevenue = 0;

          for (var ride in rideSnapshot.data!.docs) {
            final data = ride.data() as Map<String, dynamic>;
            totalRides++;

            if (data['status'] == 'completed') {
              completedRides++;
            }
            if (data['status'] == 'cancelled') {
              cancelledRides++;
            }
            if (data['fare'] != null) {
              totalRevenue += (data['fare'] as num).toDouble();
            }
          }

          return Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Total Rides: $totalRides",
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 15),
                      Text(
                        "Completed Rides: $completedRides",
                        style: const TextStyle(fontSize: 18),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        "Cancelled Rides: $cancelledRides",
                        style: const TextStyle(fontSize: 18),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        "Total Revenue: KES ${totalRevenue.toStringAsFixed(0)}",
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 30),
                const Text(
                  "Emergency Alerts",
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 15),
                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: firestore.collection('emergencies').snapshots(),
                    builder: (context, emergencySnapshot) {
                      if (!emergencySnapshot.hasData) {
                        return const SizedBox();
                      }

                      final emergencies = emergencySnapshot.data!.docs;

                      if (emergencies.isEmpty) {
                        return const Center(
                          child: Text("No Emergencies"),
                        );
                      }

                      return ListView.builder(
                        itemCount: emergencies.length,
                        itemBuilder: (context, index) {
                          final emergency = emergencies[index];
                          final data = emergency.data() as Map<String, dynamic>;
                          
                          // Safely retrieve the newly created message field
                          String sosMessage = data['message'] ?? 'No text description provided.';

                          return Card(
                            color: Colors.red.shade50,
                            margin: const EdgeInsets.symmetric(vertical: 6),
                            child: ListTile(
                              isThreeLine: true, // Configures tile to layout multiple rows cleanly
                              leading: const Icon(
                                Icons.warning,
                                color: Colors.red,
                                size: 28,
                              ),
                              title: Text(
                                "SOS from ${data['userRole'].toString().toUpperCase()}",
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 4.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      "Situation: $sosMessage",
                                      style: const TextStyle(
                                        color: Colors.black87,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      "Status: ${data['status']}",
                                      style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}*/

/*import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AdminDashboard extends StatelessWidget {
  const AdminDashboard({super.key});

  @override
  Widget build(BuildContext context) {

    final firestore =
        FirebaseFirestore.instance;

    return Scaffold(

      appBar: AppBar(
        title: const Text(
          "Admin Dashboard",
        ),
        centerTitle: true,
      ),

      body: StreamBuilder<QuerySnapshot>(

        stream: firestore
            .collection('rides')
            .snapshots(),

        builder: (context, rideSnapshot) {

          if (!rideSnapshot.hasData) {

            return const Center(
              child:
                  CircularProgressIndicator(),
            );
          }

          int totalRides = 0;

          int completedRides = 0;

          int cancelledRides = 0;

          double totalRevenue = 0;

          for (var ride
              in rideSnapshot.data!.docs) {

            final data =
                ride.data()
                    as Map<String, dynamic>;

            totalRides++;

            if (data['status'] ==
                'completed') {

              completedRides++;
            }

            if (data['status'] ==
                'cancelled') {

              cancelledRides++;
            }

            if (data['fare'] != null) {

              totalRevenue +=
                  (data['fare']
                          as num)
                      .toDouble();
            }
          }

          return Padding(

            padding:
                const EdgeInsets.all(20),

            child: Column(

              crossAxisAlignment:
                  CrossAxisAlignment.start,

              children: [

                Container(

                  padding:
                      const EdgeInsets.all(20),

                  decoration: BoxDecoration(

                    color:
                        Colors.blue.shade50,

                    borderRadius:
                        BorderRadius.circular(
                      12,
                    ),
                  ),

                  child: Column(

                    crossAxisAlignment:
                        CrossAxisAlignment.start,

                    children: [

                      Text(

                        "Total Rides: "
                        "$totalRides",

                        style:
                            const TextStyle(

                          fontSize: 22,

                          fontWeight:
                              FontWeight.bold,
                        ),
                      ),

                      const SizedBox(
                        height: 15,
                      ),

                      Text(

                        "Completed Rides: "
                        "$completedRides",

                        style:
                            const TextStyle(
                          fontSize: 18,
                        ),
                      ),

                      const SizedBox(
                        height: 10,
                      ),

                      Text(

                        "Cancelled Rides: "
                        "$cancelledRides",

                        style:
                            const TextStyle(
                          fontSize: 18,
                        ),
                      ),

                      const SizedBox(
                        height: 10,
                      ),

                      Text(

                        "Total Revenue: "
                        "KES ${totalRevenue.toStringAsFixed(0)}",

                        style:
                            const TextStyle(

                          fontSize: 20,

                          fontWeight:
                              FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 30),

                const Text(

                  "Emergency Alerts",

                  style: TextStyle(

                    fontSize: 22,

                    fontWeight:
                        FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 15),

                Expanded(

                  child:
                      StreamBuilder<QuerySnapshot>(

                    stream: firestore
                        .collection(
                          'emergencies',
                        )
                        .snapshots(),

                    builder:
                        (context,
                            emergencySnapshot) {

                      if (!emergencySnapshot
                          .hasData) {

                        return const SizedBox();
                      }

                      final emergencies =
                          emergencySnapshot
                              .data!
                              .docs;

                      if (emergencies
                          .isEmpty) {

                        return const Center(

                          child: Text(
                            "No Emergencies",
                          ),
                        );
                      }

                      return ListView.builder(

                        itemCount:
                            emergencies.length,

                        itemBuilder:
                            (context, index) {

                          final emergency =
                              emergencies[index];

                          final data =
                              emergency.data()
                                  as Map<String,
                                      dynamic>;

                          return Card(

                            color:
                                Colors.red.shade50,

                            child: ListTile(

                              leading:
                                  const Icon(
                                Icons.warning,
                                color: Colors.red,
                              ),

                              title: Text(
                                "SOS from ${data['userRole']}",
                              ),

                              subtitle: Text(
                                "Status: ${data['status']}",
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}*/