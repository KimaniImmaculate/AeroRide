import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Dev-only widget to seed test rides into Firestore.
/// Add this to a debug-only route or only include in debug builds.
class TestRidesSeeder extends StatefulWidget {
  const TestRidesSeeder({super.key});

  @override
  State<TestRidesSeeder> createState() => _TestRidesSeederState();
}

class _TestRidesSeederState extends State<TestRidesSeeder> {
  final TextEditingController _countController = TextEditingController(
    text: '5',
  );
  bool _running = false;
  String _log = '';

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  @override
  void dispose() {
    _countController.dispose();
    super.dispose();
  }

  Future<void> _seed() async {
    final int count = int.tryParse(_countController.text) ?? 5;
    setState(() {
      _running = true;
      _log = '';
    });

    // Example center: Nairobi
    const double centerLat = -1.2921;
    const double centerLng = 36.8219;
    final rnd = Random();

    try {
      for (int i = 0; i < count; i++) {
        final double pLat = centerLat + (rnd.nextDouble() - 0.5) * 0.02;
        final double pLng = centerLng + (rnd.nextDouble() - 0.5) * 0.02;
        final double dLat = centerLat + (rnd.nextDouble() - 0.5) * 0.03;
        final double dLng = centerLng + (rnd.nextDouble() - 0.5) * 0.03;

        final doc = {
          'userId': 'dev-seed-${DateTime.now().millisecondsSinceEpoch}-$i',
          'pickupLocation': GeoPoint(pLat, pLng),
          'destinationLocation': GeoPoint(dLat, dLng),
          'pickupAddress': 'Seeded pickup #${i + 1}',
          'destinationAddress': 'Seeded destination #${i + 1}',
          'status': 'searching',
          'estimatedCost': (rnd.nextDouble() * 100).roundToDouble() / 10.0,
          'createdAt': FieldValue.serverTimestamp(),
        };

        final ref = await _db.collection('rides').add(doc);
        setState(() {
          _log = 'Created ${ref.id}\n' + _log;
        });
      }
    } catch (e) {
      setState(() {
        _log = 'Error: $e\n' + _log;
      });
    } finally {
      setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dev: Seed Test Rides')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _countController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Number of rides to create',
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _running ? null : _seed,
              child: _running
                  ? const CircularProgressIndicator()
                  : const Text('Seed rides'),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: SingleChildScrollView(
                child: Text(_log.isEmpty ? 'No output yet' : _log),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
