import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:convert';
import 'dart:async';

class MpesaPaymentResult {
  final String status; // 'COMPLETED', 'FAILED', 'TIMEOUT'
  final String? transactionCode;

  MpesaPaymentResult({required this.status, this.transactionCode});
}

class PaymentService {
  static const String _backendUrl = kIsWeb ? '/api' : 'https://aeroride-665af.web.app/api';

  static Future<MpesaPaymentResult> requestMpesaPrompt({
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

        // 2. Start checking the status every 2 seconds (Long polling)
        for (int i = 0; i < 5; i++) { // Check up to 5 times (10 seconds max)
          await Future.delayed(const Duration(seconds: 2));

          // A. Check Firestore first (fastest and most reliable if webhook succeeds)
          if (rideId != null) {
            try {
              final doc = await FirebaseFirestore.instance.collection('rides').doc(rideId).get();
              if (doc.exists && doc.data()?['paymentStatus'] == 'paid') {
                return MpesaPaymentResult(
                  status: 'COMPLETED',
                  transactionCode: doc.data()?['mpesaReference'] as String?,
                );
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
              String? mpesaReference = statusData['mpesaReference'];

              if (state == 'COMPLETE' || state == 'COMPLETED') {
                return MpesaPaymentResult(status: 'COMPLETED', transactionCode: mpesaReference);
              }
              if (state == 'FAILED' || state == 'REJECTED') {
                return MpesaPaymentResult(status: 'FAILED');
              }
            }
          } catch (_) {}
        }
        return MpesaPaymentResult(status: 'TIMEOUT');
      }
      return MpesaPaymentResult(status: 'FAILED');
    } catch (e) {
      return MpesaPaymentResult(status: 'FAILED');
    }
  }
}

