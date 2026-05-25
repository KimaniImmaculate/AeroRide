import 'package:flutter/material.dart';

class SupportView extends StatelessWidget {
  final bool isDriver; // ✅ TRUE = Driver Support | FALSE = Rider Support

  const SupportView({super.key, this.isDriver = false});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title:
            Text(isDriver ? "Partner Help Center" : "AeroRide Guest Support"),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // RED ALERT: EMERGENCY CALLS (Both roles)
          Card(
            color: Colors.red.shade50,
            elevation: 0,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.red.shade100)),
            child: ListTile(
              leading: Icon(Icons.gpp_maybe_rounded,
                  color: Colors.red.shade700, size: 28),
              title: const Text("Call Emergency Dispatch",
                  style: TextStyle(
                      fontWeight: FontWeight.bold, color: Colors.black87)),
              subtitle: Text(isDriver
                  ? "Report route anomalies or vehicular distress"
                  : "Live 24/7 security & incident intervention response unit"),
              onTap: () {},
            ),
          ),
          const SizedBox(height: 16),

          const Text("STANDARD SUPPORT CHANNELS",
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Colors.black45,
                  letterSpacing: 0.8)),
          const SizedBox(height: 8),

          ListTile(
            leading: const Icon(Icons.forum_rounded, color: Colors.black87),
            title: const Text("Chat with Live Assistant",
                style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: const Text(
                "Connect to Nakuru hub customer care agents. Response time ~3 mins."),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () {},
          ),
          const Divider(),

          // DYNAMIC METRIC ROWS BASED ON REGISTRATION ACCOUNT TYPE
          if (isDriver) ...[
            ListTile(
              leading: const Icon(Icons.account_balance_rounded,
                  color: Colors.black87),
              title: const Text("Dispute Payment or Platform Fee"),
              subtitle: const Text(
                  "Submit manual audit ticket reviews for trip split processing variances"),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () {},
            ),
          ] else ...[
            ListTile(
              leading: const Icon(Icons.card_giftcard_rounded,
                  color: Colors.black87),
              title: const Text("Promo Code & Referral Queries"),
              subtitle: const Text(
                  "Resolve validation failures regarding voucher codes"),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () {},
            ),
          ],
          const Divider(),

          ListTile(
            leading: const Icon(Icons.history_toggle_off_rounded,
                color: Colors.black87),
            title: Text(isDriver
                ? "Report App Performance Bug"
                : "Review Past Trip History Issues"),
            subtitle: const Text(
                "Open archival database logs to link with core tech operations"),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () {},
          ),
        ],
      ),
    );
  }
}
