import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';

class PaymentService {
  static const String _backendUrl = 'http://localhost:5000/api';

  static Future<String> requestMpesaPrompt({
    required String rawPhone,
    required double amount,
    required BuildContext context,
  }) async {
    String formattedPhone = rawPhone.trim();
    if (formattedPhone.startsWith('0')) {
      formattedPhone = '254${formattedPhone.substring(1)}';
    }

    try {
      // 1. Dispatch prompt request
      final response = await http.post(
        Uri.parse('$_backendUrl/stkpush'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"phone": formattedPhone, "amount": amount.toInt()}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        String invoiceId = data['invoice']['invoice_id'];

        // 2. Start checking the status every 4 seconds (Long polling)
        for (int i = 0; i < 10; i++) {
          await Future.delayed(const Duration(seconds: 3));

          final statusCheck = await http
              .get(Uri.parse('$_backendUrl/payment-status/$invoiceId'));
          if (statusCheck.statusCode == 200) {
            final statusData = jsonDecode(statusCheck.body);
            String state = statusData[
                'state']; // 'PENDING', 'PROCESSING', 'COMPLETED', or 'FAILED'

            if (state == 'COMPLETE' || state == 'COMPLETED') {
              return 'COMPLETED';
            }
            if (state == 'FAILED' || state == 'REJECTED') {
              return 'FAILED';
            }
          }
        }
        return 'TIMEOUT';
      }
      return 'FAILED';
    } catch (e) {
      return 'FAILED';
    }
  }
}
