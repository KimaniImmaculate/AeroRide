import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';

class MpesaService {
  Future<void> payWithMpesa({
    required String phone,
    required double amount,
    required BuildContext context,
    required VoidCallback onSuccess, // Added callback function hook 🎯
  }) async {
    debugPrint('MpesaService: broadcasting STK push request...');

    final url = Uri.parse(
        'https://us-central1-aeroride-1.cloudfunctions.net/initiateStkPush');

    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(<String, dynamic>{
          'data': {
            'phoneNumber': phone,
            'amount': amount.round(),
          }
        }),
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> responseBody = jsonDecode(response.body);
        debugPrint(
            'MpesaService: STK push broadcasted: ${responseBody['data']}');

        final checkoutRequestId = responseBody['data']?['CheckoutRequestID'];

        if (!context.mounted) return;

        // 1. Show the success alert prompt to the user
        await showDialog<void>(
          context: context,
          barrierDismissible:
              false, // Force them to tap the button so execution order stays perfect
          builder: (dialogContext) {
            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green),
                  SizedBox(width: 10),
                  Text('Payment Initiated'),
                ],
              ),
              content: const Text(
                'An M-Pesa PIN prompt has been sent to your phone.\n\nOnce you enter your PIN, the ride will update automatically.',
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    // Pop the AlertDialog off the screen safely
                    Navigator.of(dialogContext).pop();
                  },
                  child: const Text('OK'),
                ),
              ],
            );
          },
        );

        if (!context.mounted) return;

        // 2. Start checking for payment confirmation (Wait for the user)
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (loadingContext) => const Center(
            child: Card(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Verifying payment...'),
                  ],
                ),
              ),
            ),
          ),
        );

        try {
          final paymentDoc = FirebaseFirestore.instance
              .collection('payments')
              .doc(checkoutRequestId);
          final snapshot = await paymentDoc
              .snapshots()
              .firstWhere((s) => s.exists && s.data()?['status'] != 'PENDING')
              .timeout(const Duration(seconds: 60));

          if (!context.mounted) return;
          Navigator.of(context).pop(); // Dismiss loading indicator

          final status = snapshot.data()?['status'];
          if (status == 'SUCCESSFUL') {
            final receipt = snapshot.data()?['receiptNumber'] ?? 'N/A';
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Payment Successful! Receipt: $receipt'),
                  backgroundColor: Colors.green,
                ),
              );
            }
            onSuccess();
          } else {
            final desc = snapshot.data()?['resultDesc'] ?? 'Payment failed.';
            throw Exception(desc);
          }
        } catch (e) {
          if (context.mounted)
            Navigator.of(context).pop(); // Dismiss loading indicator
          throw Exception(
              'Verification failed or timed out. Please check your M-Pesa.');
        }
      } else {
        final Map<String, dynamic> errorBody = jsonDecode(response.body);
        final errorMessage =
            errorBody['data']?['error'] ?? 'STK push request failed.';
        throw Exception(errorMessage);
      }
    } catch (error, stackTrace) {
      debugPrint('MpesaService: error while initiating STK: $error');

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Payment Error: $error'),
            backgroundColor: Colors.red,
          ),
        );
      }
      rethrow;
    }
  }
}
