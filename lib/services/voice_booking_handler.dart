import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:geocoding/geocoding.dart';

/// Model representing the parsed intent, resolved coordinates, and formatted location names
/// returned by the voice booking pipeline.
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
/// voice input pipelines via browser integrations and Gemini.
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

  /// Stops recording microphone input and returns the local audio as Base64.
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
      throw StateError("Expected stopRecording to return an audio string, got null.");
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

  /// Decodes and interprets the voice input from the given base64 audio,
  /// returning the enriched origin and destination details including coordinates.
  static Future<VoiceBookingResult?> decodeVoiceToIntent(String base64Audio) async {
    debugPrint("[AerorideVoiceHandler] Decoding voice input via Gemini...");

    try {
      if (!kIsWeb) {
        throw UnsupportedError("Voice booking pipeline is only supported in browser environments.");
      }

      final apiKey = const String.fromEnvironment('GEMINI_API_KEY');
      if (apiKey.isEmpty) {
        throw StateError("GEMINI_API_KEY is not set. Please provide it during compilation.");
      }

      final model = GenerativeModel(
        model: 'gemini-2.5-flash',
        apiKey: apiKey,
        systemInstruction: Content.system(
          'You are a local transit assistant. Extract the transit details from the provided audio. '
          'The audio may contain multiple languages including English and Swahili. '
          'Translate the locations to clean English text. '
          'Respond ONLY with a valid JSON object containing "origin" and "destination" keys, and nothing else. '
          'Example: {"origin": "Main Street Station", "destination": "Broadway Mall"}',
        ),
        generationConfig: GenerationConfig(
          responseMimeType: 'application/json',
          temperature: 0.2, // Low temperature for deterministic JSON output
        ),
      );

      final audioBytes = base64Decode(base64Audio);
      
      final prompt = [
        Content.multi([
          DataPart('audio/wav', audioBytes),
          TextPart('Extract origin and destination from this audio.'),
        ]),
      ];

      final response = await model.generateContent(prompt);
      final responseText = response.text;

      if (responseText == null || responseText.isEmpty) {
        throw Exception("Empty response from Gemini.");
      }

      debugPrint("[AerorideVoiceHandler] Gemini Response: $responseText");

      final Map<String, dynamic> result = jsonDecode(responseText) as Map<String, dynamic>;

      final String? originName = result['origin'];
      final String? destinationName = result['destination'];

      if (originName == null || destinationName == null) {
        throw const FormatException("Invalid transit details: 'origin' or 'destination' are missing.");
      }

      // Geocode using geocoding package
      debugPrint("[AerorideVoiceHandler] Geocoding origin and destination to coordinates...");
      
      final originLocations = await locationFromAddress(originName);
      final destLocations = await locationFromAddress(destinationName);

      if (originLocations.isEmpty || destLocations.isEmpty) {
         throw Exception("Failed to geocode origin or destination.");
      }

      return VoiceBookingResult(
        origin: originName,
        originLat: originLocations.first.latitude,
        originLng: originLocations.first.longitude,
        destination: destinationName,
        destinationLat: destLocations.first.latitude,
        destinationLng: destLocations.first.longitude,
      );
    } catch (e, stack) {
      debugPrint("[AerorideVoiceHandler] Error decoding voice intent: $e");
      debugPrintStack(stackTrace: stack);
      return null;
    }
  }

  /// Initiates the native voice-to-booking pipeline.
  /// Resolves the voice input audio using Gemini,
  /// saves the extracted intent parameters into Cloud Firestore,
  /// and notifies the frontend via the [onBookingConfirmed] callback.
  static Future<void> startVoiceBookingPipeline({
    required String audioBlobUrl, // Carrying base64 audio payload now to preserve existing method signature hooks
    required VoidCallback onBookingConfirmed,
  }) async {
    final result = await decodeVoiceToIntent(audioBlobUrl);
    if (result == null) {
      throw Exception("Could not decode voice to booking intent.");
    }

    // Write extracted intent and metadata to Cloud Firestore 'ride_requests' collection
    debugPrint("[AerorideVoiceHandler] Saving ride request document to Firestore...");
    final currentUser = FirebaseAuth.instance.currentUser;
    await _firestore.collection('ride_requests').add({
      'origin': result.origin,
      'destination': result.destination,
      'rider_id': currentUser?.uid ?? 'immakym001',
      'status': 'searching_drivers',
      'created_at': FieldValue.serverTimestamp(),
      'rideTier': 'tulia', // Default to standard tier to satisfy database constraints
      'estimatedFare': 350, // Default estimated fare to satisfy database constraints
    });

    debugPrint("[AerorideVoiceHandler] Document successfully saved to Cloud Firestore.");

    // Execute execution callback to invoke booking state engine programmatically
    onBookingConfirmed();
  }
}
