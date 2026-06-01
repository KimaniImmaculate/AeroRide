import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

class MpesaService {
  Future<void> payWithMpesa({
    required String phone,
    required double amount,
    BuildContext? context,
  }) async {
    debugPrint('MpesaService: broadcasting STK push request...');

    try {
      final functions = FirebaseFunctions.instance;
      final callable = functions.httpsCallable('initiateStkPush');
      final result = await callable.call(<String, dynamic>{
        'phoneNumber': phone,
        'amount': amount.round().toString(),
      });

      debugPrint('MpesaService: STK push broadcasted: ${result.data}');

      if (context != null && context.mounted) {
        await showDialog<void>(
          context: context,
          builder: (dialogContext) {
            return AlertDialog(
              title: const Text('M-Pesa Payment'),
              content: const Text(
                'An M-Pesa PIN prompt has been sent to your mobile device. Please complete the transaction on your phone.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('OK'),
                ),
              ],
            );
          },
        );
      }
    } on FirebaseFunctionsException catch (error) {
      debugPrint(
        'MpesaService: FirebaseFunctionsException while initiating STK push: ${error.code} ${error.message}',
      );
      if (error.details != null) {
        debugPrint('MpesaService: function details: ${error.details}');
      }
      rethrow;
    } catch (error, stackTrace) {
      debugPrint(
          'MpesaService: unexpected error while initiating STK push: $error');
      debugPrintStack(stackTrace: stackTrace);
      rethrow;
    }
  }
}
