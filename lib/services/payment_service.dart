import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:convert';
import 'dart:async';

class PaymentService {
  static const String _backendUrl = kIsWeb ? '/api' : 'https://aeroride-665af.web.app/api';

  static Future<String> requestMpesaPrompt({
    required String rawPhone,
    required double amount,
    required BuildContext context,
    String? rideId,
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

        // 2. Start checking the status every 3 seconds (Long polling)
        for (int i = 0; i < 15; i++) { // Check up to 15 times
          await Future.delayed(const Duration(seconds: 2));

          // A. Check Firestore first (fastest and most reliable if webhook succeeds)
          if (rideId != null) {
            try {
              final doc = await FirebaseFirestore.instance.collection('rides').doc(rideId).get();
              if (doc.exists && doc.data()?['paymentStatus'] == 'paid') {
                return 'COMPLETED';
              }
            } catch (_) {}
          }

          // B. Check backend API status
          try {
            final statusCheck = await http
                .get(Uri.parse('$_backendUrl/payment-status/$invoiceId'));
            if (statusCheck.statusCode == 200) {
              final statusData = jsonDecode(statusCheck.body);
              String state = statusData['state']; // 'PENDING', 'PROCESSING', 'COMPLETED', or 'FAILED'

              if (state == 'COMPLETE' || state == 'COMPLETED') {
                return 'COMPLETED';
              }
              if (state == 'FAILED' || state == 'REJECTED') {
                return 'FAILED';
              }
            }
          } catch (_) {}
        }
        return 'TIMEOUT';
      }
      return 'FAILED';
    } catch (e) {
      return 'FAILED';
    }
  }
}
