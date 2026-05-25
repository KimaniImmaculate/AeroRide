import 'package:flutter/material.dart';

class WalletView extends StatelessWidget {
  final double currentBalance;
  final bool
      isDriver; // ✅ TRUE = Driver Ledger | FALSE = Rider Consumer Account

  const WalletView({
    super.key,
    required this.currentBalance,
    this.isDriver = false, // Defaults to rider if not specified
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(isDriver ? "Driver Revenue Wallet" : "My Personal Wallet"),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.account_balance_wallet_rounded,
                  size: 90, color: isDriver ? Colors.teal : Colors.green),
              const SizedBox(height: 16),
              Text(
                  isDriver
                      ? "ACCUMULATED REVENUE BALANCE"
                      : "AVAILABLE PAYMENT BALANCE",
                  style: const TextStyle(
                      color: Colors.black45,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5)),
              const SizedBox(height: 4),
              Text(
                "KSh ${currentBalance.toStringAsFixed(2)}",
                style: const TextStyle(
                    fontSize: 38,
                    fontWeight: FontWeight.w900,
                    color: Colors.black),
              ),
              const SizedBox(height: 32),

              // 🔄 DYNAMIC CTAs BASED ON ROLE LAYOUT
              if (isDriver) ...[
                // DRIVER CONTROLS: Cash out money to bank/phone
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal.shade700,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.phone_android_rounded, size: 18),
                  label: const Text("EXPRESS CASH OUT TO M-PESA",
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  onPressed: currentBalance <= 0
                      ? null
                      : () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text(
                                    "💸 Earnings withdrawal request processed via Safaricom gateway.")),
                          );
                        },
                ),
              ] else ...[
                // RIDER CONTROLS: Add money to pay for future trips
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.add_card_rounded, size: 18),
                  label: const Text("TOP UP WALLET VIA M-PESA STK",
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text(
                              "📲 Check your handset phone for the secure M-Pesa PIN prompt overlay.")),
                    );
                  },
                ),
              ],

              const SizedBox(height: 16),
              Text(
                isDriver
                    ? "Standard 20% platform marketplace service fees apply during background calculation routines."
                    : "Use your personal balance for fast checkout workflows on subsequent AeroRide city routes.",
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 11, color: Colors.black38),
              )
            ],
          ),
        ),
      ),
    );
  }
}
