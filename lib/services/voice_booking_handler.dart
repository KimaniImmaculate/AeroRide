import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// Model representing the parsed intent, resolved coordinates, and formatted location names
/// returned by the Puter.js and Google Maps geocoder pipeline.
class VoiceBookingResult {
  final String origin;
  final double originLat;
  final double originLng;
  final String destination;
  final double destinationLat;
  final double destinationLng;

  VoiceBookingResult({
    required this.origin,
    required this.originLat,
    required this.originLng,
    required this.destination,
    required this.destinationLat,
    required this.destinationLng,
  });
}

/// A reusable, headless service handler for managing hands-free ride booking
/// voice input pipelines via browser integrations.
class AerorideVoiceHandler {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Starts recording microphone input in the browser.
  static Future<void> startRecording() async {
    if (!kIsWeb) return;
    if (!globalContext.has('aerorideStartRecording')) {
      throw StateError("JavaScript helper 'aerorideStartRecording' is not defined.");
    }
    globalContext.callMethod('aerorideStartRecording'.toJS);
  }

  /// Stops recording microphone input and returns the local audio Blob URL.
  static Future<String> stopRecording() async {
    if (!kIsWeb) return "";
    if (!globalContext.has('aerorideStopRecording')) {
      throw StateError("JavaScript helper 'aerorideStopRecording' is not defined.");
    }
    final JSAny? jsPromise = globalContext.callMethod('aerorideStopRecording'.toJS);
    if (jsPromise == null) {
      throw StateError("aerorideStopRecording returned null.");
    }
    final JSAny? resolvedAny = await (jsPromise as JSPromise).toDart;
    if (resolvedAny == null) {
      throw StateError("Expected stopRecording to return an audio URL, got null.");
    }
    return (resolvedAny as JSString).toDart;
  }

  /// Plays text using the browser's speechSynthesis API for accessibility notifications.
  static void speak(String text, {String languageCode = 'en-US'}) {
    if (!kIsWeb) return;
    if (globalContext.has('aerorideSpeak')) {
      globalContext.callMethod('aerorideSpeak'.toJS, text.toJS, languageCode.toJS);
    } else {
      debugPrint("[AerorideVoiceHandler speak fallback] $text");
    }
  }

  /// Decodes and interprets the voice input from the given audio blob URL,
  /// returning the enriched origin and destination details including coordinates.
  static Future<VoiceBookingResult?> decodeVoiceToIntent(String audioBlobUrl) async {
    debugPrint("[AerorideVoiceHandler] Decoding voice input from URL: $audioBlobUrl");

    try {
      if (!kIsWeb) {
        throw UnsupportedError("Voice booking pipeline is only supported in browser environments.");
      }

      // Check if our processVoiceToIntent JavaScript wrapper function is available on the window object
      if (!globalContext.has('processVoiceToIntent')) {
        throw StateError("JavaScript interop wrapper 'processVoiceToIntent' is not defined.");
      }

      // Call the JS function and capture the returned promise
      final JSAny? jsPromise = globalContext.callMethod(
        'processVoiceToIntent'.toJS,
        audioBlobUrl.toJS,
      );

      if (jsPromise == null) {
        throw StateError("Failed to call JavaScript processVoiceToIntent (returned null).");
      }

      // Await the JS Promise in Dart using toDart
      debugPrint("[AerorideVoiceHandler] Awaiting JS Promise resolution...");
      final JSAny? resolvedAny = await (jsPromise as JSPromise).toDart;

      if (resolvedAny == null) {
        throw StateError("Expected JS wrapper to return a result, got null.");
      }

      final String rawResult = (resolvedAny as JSString).toDart;
      debugPrint("[AerorideVoiceHandler] Received raw JSON response: $rawResult");

      // Parse the JSON payload safely in Dart
      final Map<String, dynamic> result = jsonDecode(rawResult) as Map<String, dynamic>;

      // Check if an error was captured on the JS side
      if (result.containsKey('error')) {
        throw Exception("Pipeline failed in JS context: ${result['error']}");
      }

      final String? origin = result['origin'];
      final double? originLat = double.tryParse(result['origin_lat'].toString());
      final double? originLng = double.tryParse(result['origin_lng'].toString());
      final String? destination = result['destination'];
      final double? destinationLat = double.tryParse(result['destination_lat'].toString());
      final double? destinationLng = double.tryParse(result['destination_lng'].toString());

      if (origin == null || origin.trim().isEmpty || originLat == null || originLng == null) {
        throw const FormatException("Invalid transit details: 'origin' or coordinates are missing.");
      }
      if (destination == null || destination.trim().isEmpty || destinationLat == null || destinationLng == null) {
        throw const FormatException("Invalid transit details: 'destination' or coordinates are missing.");
      }

      return VoiceBookingResult(
        origin: origin.trim(),
        originLat: originLat,
        originLng: originLng,
        destination: destination.trim(),
        destinationLat: destinationLat,
        destinationLng: destinationLng,
      );
    } catch (e, stack) {
      debugPrint("[AerorideVoiceHandler] Error decoding voice intent: $e");
      debugPrintStack(stackTrace: stack);
      return null;
    }
  }

  /// Initiates the legacy parallel voice-to-booking pipeline.
  /// Resolves the voice input audio blob URL using Whisper-1 and Gemini 2.5 Flash-lite via Puter.js,
  /// saves the extracted intent parameters into Cloud Firestore,
  /// and notifies the frontend via the [onBookingConfirmed] callback.
  static Future<void> startVoiceBookingPipeline({
    required String audioBlobUrl,
    required VoidCallback onBookingConfirmed,
  }) async {
    final result = await decodeVoiceToIntent(audioBlobUrl);
    if (result == null) {
      throw Exception("Could not decode voice to booking intent.");
    }

    // Write extracted intent and metadata to Cloud Firestore 'ride_requests' collection
    debugPrint("[AerorideVoiceHandler] Saving ride request document to Firestore...");
    await _firestore.collection('ride_requests').add({
      'origin': result.origin,
      'destination': result.destination,
      'rider_id': 'immakym001',
      'status': 'searching_drivers',
      'created_at': FieldValue.serverTimestamp(),
    });

    debugPrint("[AerorideVoiceHandler] Document successfully saved to Cloud Firestore.");

    // Execute execution callback to invoke booking state engine programmatically
    onBookingConfirmed();
  }
}
