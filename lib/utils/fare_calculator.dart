class FareCalculator {
  // Static pricing configuration for consistency across the system
  static const Map<String, Map<String, double>> _tierPricing = {
    'tulia': {'base': 150.0, 'km': 45.0},
    'nuru': {'base': 350.0, 'km': 80.0},
    'pamoja': {'base': 500.0, 'km': 110.0},
    'waziri': {'base': 700.0, 'km': 150.0},
  };

  /// Returns the base fare and per km rate for a given tier.
  static Map<String, double> getRates(String? tierId) {
    return _tierPricing[tierId?.toLowerCase()] ?? _tierPricing['tulia']!;
  }

  /// Calculates the total fare for a trip based on distance (km).
  static double calculateFare(String? tierId, double distanceKm) {
    final rates = getRates(tierId);
    return rates['base']! + (distanceKm * rates['km']!);
  }

  /// Calculates the driver's net earnings (85% of total fare).
  static double calculateDriverEarnings(double totalFare) {
    return totalFare * 0.85; // 15% platform commission
  }
}
