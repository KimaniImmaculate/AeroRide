import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

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

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Processing payment... returning to map'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );

        // ✅ THE FIX: Execute state cleanup routine to reset the UI component layout
        onSuccess();
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
