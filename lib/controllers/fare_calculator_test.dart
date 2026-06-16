import 'package:flutter_test/flutter_test.dart';
import 'package:aeroride/utils/fare_calculator.dart';

void main() {
  group('FareCalculator Tests', () {
    test('Tulia (Standard) calculation: 10km should be 600', () {
      // Base 150 + (10km * 45) = 600
      final fare = FareCalculator.calculateFare('tulia', 10.0);
      expect(fare, 600.0);
    });

    test('Waziri (Elite) calculation: 5km should be 1450', () {
      // Base 700 + (5km * 150) = 1450
      final fare = FareCalculator.calculateFare('waziri', 5.0);
      expect(fare, 1450.0);
    });

    test('Invalid tier should fallback to Tulia pricing', () {
      final fare = FareCalculator.calculateFare('invalid_tier', 10.0);
      expect(fare, 600.0);
    });

    test('Null tier should fallback to Tulia pricing', () {
      final fare = FareCalculator.calculateFare(null, 10.0);
      expect(fare, 600.0);
    });

    test('Driver earnings should correctly subtract 15% commission', () {
      const totalFare = 1000.0;
      final earnings = FareCalculator.calculateDriverEarnings(totalFare);
      // 1000 * 0.85 = 850
      expect(earnings, 850.0);
    });

    test('GetRates should be case-insensitive', () {
      final ratesLower = FareCalculator.getRates('nuru');
      final ratesUpper = FareCalculator.getRates('NURU');

      expect(ratesLower['base'], 350.0);
      expect(ratesUpper['base'], 350.0);
    });
  });
}
