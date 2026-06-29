import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'dart:convert';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  final TextEditingController driverNameController = TextEditingController();
  final TextEditingController driverEmailController = TextEditingController();
  final TextEditingController driverPasswordController = TextEditingController();
  final TextEditingController driverPhoneController = TextEditingController();
  final TextEditingController driverLicenseController = TextEditingController();
  final TextEditingController driverBioController = TextEditingController();
  final TextEditingController driverDocsController = TextEditingController();
  final TextEditingController driverPassportPhotoController = TextEditingController();

  bool isRegistering = false;
  String selectedCarTier = 'tulia';

  @override
  void dispose() {
    driverNameController.dispose();
    driverEmailController.dispose();
    driverPasswordController.dispose();
    driverPhoneController.dispose();
    driverLicenseController.dispose();
    driverBioController.dispose();
    driverDocsController.dispose();
    driverPassportPhotoController.dispose();
    super.dispose();
  }

  Future<void> _registerDriver() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      isRegistering = true;
    });

    final String name = driverNameController.text.trim();
    final String email = driverEmailController.text.trim();
    final String password = driverPasswordController.text.trim();
    final String phone = driverPhoneController.text.trim();
    final String license = driverLicenseController.text.trim();
    final String bio = driverBioController.text.trim();
    final String documents = driverDocsController.text.trim();
    final String passport = driverPassportPhotoController.text.trim();

    try {
      final appName = 'driver_creator_${DateTime.now().millisecondsSinceEpoch}';
      FirebaseApp tempApp = await Firebase.initializeApp(
        name: appName,
        options: Firebase.app().options,
      );

      UserCredential creds = await FirebaseAuth.instanceFor(app: tempApp)
          .createUserWithEmailAndPassword(email: email, password: password);

      await FirebaseFirestore.instance.collection('users').doc(creds.user!.uid).set({
        'name': name,
        'email': email,
        'phone': phone,
        'role': 'driver',
        'licenseNumber': license,
        'bio': bio,
        'documents': documents,
        'passportPhotoUrl': passport,
        'carTier': selectedCarTier,
        'isOnline': false,
        'isFlagged': false,
        'createdAt': FieldValue.serverTimestamp(),
      });

      await tempApp.delete();

      driverNameController.clear();
      driverEmailController.clear();
      driverPasswordController.clear();
      driverPhoneController.clear();
      driverLicenseController.clear();
      driverBioController.clear();
      driverDocsController.clear();
      driverPassportPhotoController.clear();
      setState(() {
        selectedCarTier = 'tulia';
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Driver Registered Successfully! 🎉"),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Failed to register driver: $e"),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          isRegistering = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final firestore = FirebaseFirestore.instance;

    return DefaultTabController(
      length: 5,
      child: Scaffold(
        backgroundColor: Colors.grey.shade50,
        appBar: AppBar(
          title: const Text("AeroRide System Panel", style: TextStyle(fontWeight: FontWeight.bold)),
          elevation: 0,
          backgroundColor: Colors.white,
          foregroundColor: Colors.grey.shade900,
          centerTitle: false,
          bottom: const TabBar(
            isScrollable: true,
            labelColor: Colors.blue,
            unselectedLabelColor: Colors.grey,
            indicatorColor: Colors.blue,
            tabs: [
              Tab(icon: Icon(Icons.analytics_rounded), text: "Logistics"),
              Tab(icon: Icon(Icons.warning_rounded), text: "Emergencies"),
              Tab(icon: Icon(Icons.people_rounded), text: "Users"),
              Tab(icon: Icon(Icons.person_add_rounded), text: "Register Driver"),
              Tab(icon: Icon(Icons.mark_email_unread_rounded), text: "Requests"),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildLogisticsTab(firestore),
            _buildEmergenciesTab(firestore),
            _buildUsersTab(firestore),
            _buildRegisterDriverTab(context),
            _buildRequestsTab(firestore),
          ],
        ),
      ),
    );
  }

  Widget _buildLogisticsTab(FirebaseFirestore firestore) {
    return StreamBuilder<QuerySnapshot>(
      stream: firestore.collection('rides').snapshots(),
      builder: (context, rideSnapshot) {
        if (!rideSnapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        int totalRides = 0;
        int completedRides = 0;
        int cancelledRides = 0;
        double grossRevenue = 0;
        double platformRevenue = 0;
        double driverPayouts = 0;
        double cancellationRevenue = 0;

        for (var ride in rideSnapshot.data!.docs) {
          final data = ride.data() as Map<String, dynamic>;
          totalRides++;

          if (data['status'] == 'completed') {
            completedRides++;
            if (data['fare'] != null) {
              final fare = (data['fare'] as num).toDouble();
              grossRevenue += fare;
              final driverEarnings = (data['driverEarnings'] as num?)?.toDouble() ?? (fare * 0.75);
              final platformFee = (data['platformFee'] as num?)?.toDouble() ?? (fare * 0.25);
              platformRevenue += platformFee;
              driverPayouts += driverEarnings;
            }
          } else if (data['status'] == 'cancelled') {
            cancelledRides++;
            // Count paid cancellation fees — 100% goes to driver, 0% to platform
            if (data['paymentStatus'] == 'paid' && data['fare'] != null) {
              final fee = (data['fare'] as num).toDouble();
              grossRevenue += fee;
              driverPayouts += fee; // 100% to driver
              cancellationRevenue += fee;
              // platformRevenue += 0 (platform takes nothing on cancellations)
            }
          }

        }

        final allRides = rideSnapshot.data!.docs.toList();
        allRides.sort((a, b) {
          final aData = a.data() as Map<String, dynamic>;
          final bData = b.data() as Map<String, dynamic>;
          final aTime = (aData['createdAt'] as Timestamp?)?.toDate() ?? DateTime.fromMillisecondsSinceEpoch(0);
          final bTime = (bData['createdAt'] as Timestamp?)?.toDate() ?? DateTime.fromMillisecondsSinceEpoch(0);
          return bTime.compareTo(aTime);
        });

        final double screenWidth = MediaQuery.of(context).size.width;
        final bool isMobile = screenWidth < 600;

        return SingleChildScrollView(
          padding: EdgeInsets.all(isMobile ? 12 : 24),
          child: Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 1200),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildMetricSidePanel(
                    totalRides: totalRides,
                    completedRides: completedRides,
                    cancelledRides: cancelledRides,
                    grossRevenue: grossRevenue,
                    platformRevenue: platformRevenue,
                    driverPayouts: driverPayouts,
                    cancellationRevenue: cancellationRevenue,
                    isMobile: isMobile,
                  ),
                  const SizedBox(height: 32),
                  _buildAdminRideHistoryList(allRides),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildAdminRideHistoryList(List<QueryDocumentSnapshot> rides) {
    if (rides.isEmpty) {
      return const Center(child: Text("No rides recorded yet."));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "All Rides History",
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey.shade800),
        ),
        const SizedBox(height: 12),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: rides.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final data = rides[index].data() as Map<String, dynamic>;
            final status = data['status'] ?? 'unknown';
            final pickup = data['pickup'] ?? 'Unknown';
            final dropoff = data['dropoff'] ?? 'Unknown';
            final fare = data['fare'] != null ? 'KES ${data['fare']}' : 'N/A';
            
            String dateStr = "Date Unknown";
            if (data['createdAt'] != null) {
              final dt = (data['createdAt'] as Timestamp).toDate();
              dateStr = DateFormat('MMM d, yyyy • h:mm a').format(dt);
            }
            
            Color statusColor = Colors.grey;
            if (status == 'completed') {
              statusColor = Colors.green;
            } else if (status == 'cancelled') {
              statusColor = Colors.red;
            } else {
              statusColor = Colors.orange;
            }

            return Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.grey.shade200),
              ),
              color: Colors.white,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      runAlignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        Wrap(
                          spacing: 8,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: statusColor.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                status.toString().toUpperCase(),
                                style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                            ),
                            if (data['rideTier'] != null)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF16a085).withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  data['rideTier'].toString().toUpperCase(),
                                  style: const TextStyle(color: Color(0xFF16a085), fontSize: 10, fontWeight: FontWeight.bold),
                                ),
                              ),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              "Fare: $fare",
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              dateStr,
                              style: TextStyle(color: Colors.grey.shade600, fontSize: 11, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Icon(Icons.trip_origin_rounded, color: Colors.blue.shade600, size: 14),
                        const SizedBox(width: 8),
                        Expanded(child: Text(pickup, style: const TextStyle(fontSize: 13, overflow: TextOverflow.ellipsis))),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: Container(width: 1.5, height: 16, color: Colors.grey.shade300),
                    ),
                    Row(
                      children: [
                        Icon(Icons.location_on_rounded, color: Colors.red.shade500, size: 14),
                        const SizedBox(width: 8),
                        Expanded(child: Text(dropoff, style: const TextStyle(fontSize: 13, overflow: TextOverflow.ellipsis))),
                      ],
                    ),
                    const SizedBox(height: 14),
                    const Divider(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          "Rider: ${data['riderEmail'] ?? 'Unknown'}",
                          style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                        ),
                        Text(
                          "Driver: ${data['driverEmail'] ?? 'Unassigned'}",
                          style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                        ),
                      ],
                    ),
                    if (status == 'completed' && data['fare'] != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Text(
                          "Driver Payout: KES ${(data['driverEarnings'] ?? ((data['fare'] as num).toDouble() * 0.75)).toStringAsFixed(0)} (75%) | Platform Fee: KES ${(data['platformFee'] ?? ((data['fare'] as num).toDouble() * 0.25)).toStringAsFixed(0)} (25%)",
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.blueGrey),
                        ),
                      ),
                    if (status == 'cancelled' && data['paymentStatus'] == 'paid' && data['fare'] != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.orange.shade200),
                          ),
                          child: Text(
                            "Cancellation Fee: KES ${data['fare']} → Driver Payout: 100% | Platform: 0%",
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.orange.shade800),
                          ),
                        ),
                      ),
                    if (data['paymentStatus'] != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Row(
                          children: [
                            Text(
                              "Payment: ",
                              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                            ),
                            Text(
                              data['paymentStatus'].toString().toUpperCase(),
                              style: TextStyle(
                                color: data['paymentStatus'] == 'paid' ? Colors.green : Colors.red,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                            if (data['mpesaReference'] != null) ...[
                              const SizedBox(width: 12),
                              Text(
                                "M-Pesa Ref: ${data['mpesaReference']}",
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Colors.blueGrey),
                              ),
                            ]
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildEmergenciesTab(FirebaseFirestore firestore) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: _buildEmergencyTabbedView(firestore),
        ),
      ),
    );
  }

  Widget _buildUsersTab(FirebaseFirestore firestore) {
    return StreamBuilder<QuerySnapshot>(
      stream: firestore.collection('users').snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final users = snapshot.data!.docs;

        return Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 1000),
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: users.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final userDoc = users[index];
                final data = userDoc.data() as Map<String, dynamic>;
                final String email = data['email'] ?? 'Unknown User';
                final String role = data['role'] ?? 'rider';
                final String phone = data['phone'] ?? 'N/A';
                final bool isFlagged = data['isFlagged'] ?? false;

                return Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: Colors.grey.shade200),
                  ),
                  color: isFlagged ? Colors.red.shade50 : Colors.white,
                  child: ListTile(
                    title: Text(
                      email,
                      style: GoogleFonts.urbanist(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("Role: ${role.toUpperCase()} | Phone: $phone"),
                        if (role == 'driver' && data['carTier'] != null)
                          Text("Tier: ${(data['carTier'] as String).toUpperCase()}", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                        if (role == 'driver' && data['vehicleImageUrl'] != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: GestureDetector(
                              onTap: () {
                                final bool isVerified = data['vehicleVerified'] == true;
                                showDialog(
                                  context: context,
                                  builder: (dialogCtx) => Dialog(
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                    child: Padding(
                                      padding: const EdgeInsets.all(16),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            "Vehicle Verification",
                                            style: GoogleFonts.urbanist(fontSize: 18, fontWeight: FontWeight.bold),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            "${data['name'] ?? email} — Tier: ${(data['carTier'] ?? 'tulia').toUpperCase()}",
                                            style: GoogleFonts.urbanist(color: Colors.grey),
                                          ),
                                          const SizedBox(height: 12),
                                          ClipRRect(
                                            borderRadius: BorderRadius.circular(12),
                                            child: data['vehicleImageUrl'].toString().startsWith('data:image')
                                                ? Image.memory(
                                                    base64Decode(data['vehicleImageUrl'].toString().split(',').last),
                                                    fit: BoxFit.contain,
                                                    width: double.infinity,
                                                  )
                                                : Image.network(
                                                    data['vehicleImageUrl'],
                                                    fit: BoxFit.contain,
                                                    width: double.infinity,
                                                  ),
                                          ),
                                          const SizedBox(height: 16),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                            decoration: BoxDecoration(
                                              color: isVerified ? Colors.green.shade50 : Colors.orange.shade50,
                                              borderRadius: BorderRadius.circular(8),
                                              border: Border.all(color: isVerified ? Colors.green.shade300 : Colors.orange.shade300),
                                            ),
                                            child: Text(
                                              isVerified ? "✅ Approved" : "⏳ Pending Approval",
                                              style: TextStyle(
                                                color: isVerified ? Colors.green.shade800 : Colors.orange.shade800,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 16),
                                          Row(
                                            children: [
                                              Expanded(
                                                child: OutlinedButton.icon(
                                                  icon: const Icon(Icons.close, color: Colors.red),
                                                  label: const Text("Reject", style: TextStyle(color: Colors.red)),
                                                  style: OutlinedButton.styleFrom(
                                                    side: const BorderSide(color: Colors.red),
                                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                                  ),
                                                  onPressed: () async {
                                                    await firestore.collection('users').doc(userDoc.id).update({
                                                      'vehicleVerified': false,
                                                      'vehicleImageUrl': FieldValue.delete(),
                                                    });
                                                    if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                                                    if (context.mounted) {
                                                      ScaffoldMessenger.of(context).showSnackBar(
                                                        const SnackBar(content: Text("❌ Vehicle photo rejected & cleared."), backgroundColor: Colors.red),
                                                      );
                                                    }
                                                  },
                                                ),
                                              ),
                                              const SizedBox(width: 12),
                                              Expanded(
                                                child: ElevatedButton.icon(
                                                  icon: const Icon(Icons.check, color: Colors.white),
                                                  label: const Text("Approve", style: TextStyle(color: Colors.white)),
                                                  style: ElevatedButton.styleFrom(
                                                    backgroundColor: Colors.green.shade700,
                                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                                  ),
                                                  onPressed: () async {
                                                    await firestore.collection('users').doc(userDoc.id).update({
                                                      'vehicleVerified': true,
                                                    });
                                                    if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                                                    if (context.mounted) {
                                                      ScaffoldMessenger.of(context).showSnackBar(
                                                        const SnackBar(content: Text("✅ Vehicle approved successfully!"), backgroundColor: Colors.green),
                                                      );
                                                    }
                                                  },
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          TextButton(
                                            onPressed: () => Navigator.pop(dialogCtx),
                                            child: const Text("Close"),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                              child: Row(
                                children: [
                                  Icon(
                                    data['vehicleVerified'] == true ? Icons.verified_rounded : Icons.image_rounded,
                                    size: 16,
                                    color: data['vehicleVerified'] == true ? Colors.green : Colors.orange,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    data['vehicleVerified'] == true ? "Vehicle Approved ✅" : "Review Vehicle Photo ⏳",
                                    style: GoogleFonts.urbanist(
                                      color: data['vehicleVerified'] == true ? Colors.green : Colors.orange,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isFlagged)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.red.shade100,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              "Suspended",
                              style: GoogleFonts.urbanist(
                                color: Colors.red.shade800,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isFlagged ? Colors.green : Colors.red,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          onPressed: () async {
                            await firestore.collection('users').doc(userDoc.id).update({
                              'isFlagged': !isFlagged,
                            });
                          },
                          child: Text(isFlagged ? "Unflag" : "Flag"),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildRegisterDriverTab(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: Colors.grey.shade200),
            ),
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      "Register Service Driver",
                      style: GoogleFonts.urbanist(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "Create driver credentials and bio details manually.",
                      style: GoogleFonts.urbanist(
                        fontSize: 13,
                        color: Colors.grey,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    TextFormField(
                      controller: driverNameController,
                      decoration: const InputDecoration(
                        labelText: "Full Name",
                        prefixIcon: Icon(Icons.person_rounded),
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) => v!.isEmpty ? "Enter name" : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: driverEmailController,
                      decoration: const InputDecoration(
                        labelText: "Email Address",
                        prefixIcon: Icon(Icons.email_rounded),
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) => v!.isEmpty ? "Enter email" : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: driverPasswordController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: "Password",
                        prefixIcon: Icon(Icons.lock_rounded),
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) => v!.isEmpty ? "Enter password" : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: driverPhoneController,
                      decoration: const InputDecoration(
                        labelText: "Phone Number",
                        prefixIcon: Icon(Icons.phone_rounded),
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) => v!.isEmpty ? "Enter phone" : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: driverLicenseController,
                      decoration: const InputDecoration(
                        labelText: "Driver's License Number",
                        prefixIcon: Icon(Icons.card_membership_rounded),
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) => v!.isEmpty ? "Enter license" : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: driverBioController,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: "Bio / Description",
                        prefixIcon: Icon(Icons.description_rounded),
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) => v!.isEmpty ? "Enter bio" : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: driverDocsController,
                      decoration: const InputDecoration(
                        labelText: "Documents Reference / Link",
                        prefixIcon: Icon(Icons.folder_open_rounded),
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) => v!.isEmpty ? "Enter document links" : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: driverPassportPhotoController,
                      decoration: const InputDecoration(
                        labelText: "Passport Photo URL",
                        prefixIcon: Icon(Icons.image_rounded),
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) => v!.isEmpty ? "Enter passport photo URL" : null,
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: selectedCarTier,
                      decoration: const InputDecoration(
                        labelText: "Car Tier",
                        prefixIcon: Icon(Icons.drive_eta_rounded),
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'tulia', child: Text('Tulia (Economy)')),
                        DropdownMenuItem(value: 'nuru', child: Text('Nuru (Comfort)')),
                        DropdownMenuItem(value: 'pamoja', child: Text('Pamoja (XL/Group)')),
                        DropdownMenuItem(value: 'waziri', child: Text('Waziri (Premium/VIP)')),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          setState(() {
                            selectedCarTier = val;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue.shade600,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: isRegistering ? null : _registerDriver,
                      child: isRegistering
                          ? const Center(child: CircularProgressIndicator(color: Colors.white))
                          : Text(
                              "Register Driver",
                              style: GoogleFonts.urbanist(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRequestsTab(FirebaseFirestore firestore) {
    return StreamBuilder<QuerySnapshot>(
      stream: firestore
          .collection('driver_change_requests')
          .orderBy('requestedAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final requests = snapshot.data!.docs;

        if (requests.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.mark_email_read_rounded, size: 48, color: Colors.grey.shade400),
                const SizedBox(height: 12),
                Text(
                  "No pending update requests",
                  style: GoogleFonts.urbanist(color: Colors.grey),
                ),
              ],
            ),
          );
        }

        return Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 900),
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: requests.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final doc = requests[index];
                final data = doc.data() as Map<String, dynamic>;
                final String email = data['driverEmail'] ?? 'Unknown Driver';
                final String reason = data['reason'] ?? 'No reason';
                final String details = data['details'] ?? 'No details';
                final String status = data['status'] ?? 'pending';
                final bool isPending = status == 'pending';

                return Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: Colors.grey.shade200),
                  ),
                  color: isPending ? Colors.amber.shade50.withValues(alpha: 0.3) : Colors.grey.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              email,
                              style: GoogleFonts.urbanist(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: isPending ? Colors.amber.shade100 : Colors.grey.shade200,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                status.toUpperCase(),
                                style: GoogleFonts.urbanist(
                                  color: isPending ? Colors.amber.shade800 : Colors.grey.shade600,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          "Reason: $reason",
                          style: GoogleFonts.urbanist(fontWeight: FontWeight.w600, fontSize: 14),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          "Requested Changes: $details",
                          style: GoogleFonts.urbanist(fontSize: 13, color: Colors.grey.shade700),
                        ),
                        if (isPending) ...[
                          const SizedBox(height: 12),
                          Align(
                            alignment: Alignment.centerRight,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                                elevation: 0,
                              ),
                              onPressed: () async {
                                await firestore.collection('driver_change_requests').doc(doc.id).update({
                                  'status': 'resolved',
                                });
                              },
                              icon: const Icon(Icons.check_rounded, size: 16),
                              label: const Text("Mark as Handled"),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildMetricSidePanel({
    required int totalRides,
    required int completedRides,
    required int cancelledRides,
    required double grossRevenue,
    required double platformRevenue,
    required double driverPayouts,
    required double cancellationRevenue,
    required bool isMobile,
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
            padding: EdgeInsets.all(isMobile ? 14 : 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSummaryLine("Total Dispatched", totalRides.toString(), Icons.local_taxi_rounded, Colors.blue, isMobile),
                const Divider(height: 20),
                _buildSummaryLine("Completed Trips", completedRides.toString(), Icons.check_circle_outline_rounded, Colors.green, isMobile),
                const Divider(height: 20),
                _buildSummaryLine("Cancelled Requests", cancelledRides.toString(), Icons.cancel_outlined, Colors.red, isMobile),
                const Divider(height: 20),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header: icon + title + gross revenue
                      Row(
                        children: [
                          Icon(Icons.payments_outlined, color: Colors.green.shade700, size: isMobile ? 20 : 24),
                          const SizedBox(width: 8),
                          Text(
                            "Gross Revenue",
                            style: TextStyle(fontSize: isMobile ? 12 : 13, color: Colors.green.shade800, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "KES ${grossRevenue.toStringAsFixed(0)}",
                        style: TextStyle(fontSize: isMobile ? 22 : 26, fontWeight: FontWeight.w900, color: Colors.green.shade900),
                      ),
                      const Divider(height: 20, color: Colors.green),

                      // Platform Revenue row
                      _buildRevenueRow(
                        label: "Platform Revenue",
                        sublabel: "(trips, 25%)",
                        value: "KES ${platformRevenue.toStringAsFixed(0)}",
                        color: Colors.green.shade900,
                      ),
                      const SizedBox(height: 10),

                      // Driver Payouts row
                      _buildRevenueRow(
                        label: "Driver Payouts",
                        sublabel: "(trips + cancellations)",
                        value: "KES ${driverPayouts.toStringAsFixed(0)}",
                        color: Colors.green.shade900,
                      ),

                      // Cancellation sub-line
                      if (cancellationRevenue > 0) ...[
                        const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: Row(
                            children: [
                              Icon(Icons.subdirectory_arrow_right_rounded, size: 14, color: Colors.orange.shade700),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  "Cancellation fees",
                                  style: TextStyle(fontSize: 12, color: Colors.orange.shade800, fontWeight: FontWeight.w500),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                "KES ${cancellationRevenue.toStringAsFixed(0)}",
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.orange.shade800),
                              ),
                            ],
                          ),
                        ),
                      ],
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

  Widget _buildSummaryLine(String title, String value, IconData icon, Color iconColor, bool isMobile) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Row(
            children: [
              Icon(icon, color: iconColor, size: isMobile ? 16 : 20),
              SizedBox(width: isMobile ? 8 : 12),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    color: Colors.black87,
                    fontSize: isMobile ? 13 : 14,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: isMobile ? 16 : 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildRevenueRow({
    required String label,
    required String sublabel,
    required String value,
    required Color color,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontSize: 13, color: color, fontWeight: FontWeight.w600)),
              Text(sublabel, style: TextStyle(fontSize: 11, color: color.withValues(alpha: 0.7))),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }

  Widget _buildEmergencyTabbedView(FirebaseFirestore firestore) {
    return DefaultTabController(
      length: 2,
      child: Column(
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
    ),
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

        final String? userId = data['userId'];

        return FutureBuilder<DocumentSnapshot?>(
          future: userId != null ? firestore.collection('users').doc(userId).get() : Future.value(null),
          builder: (context, userSnapshot) {
            String senderIdentifier = "UNKNOWN ${filterRole.toUpperCase()}";
            if (userSnapshot.connectionState == ConnectionState.waiting) {
              senderIdentifier = "Loading...";
            } else if (userSnapshot.hasData && userSnapshot.data != null && userSnapshot.data!.exists) {
              final userData = userSnapshot.data!.data() as Map<String, dynamic>?;
              if (userData != null) {
                final name = userData['name'] ?? 'Unknown';
                final contact = userData['email'] ?? userData['phone'] ?? 'No Contact';
                senderIdentifier = "$name ($contact)";
              }
            }

            return Card(
              elevation: 0,
              color: isActive ? Colors.red.shade50.withValues(alpha: 0.6) : Colors.grey.shade50,
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
                  "SOS from $senderIdentifier",
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