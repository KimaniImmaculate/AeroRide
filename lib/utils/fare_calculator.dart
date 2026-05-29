class FareResult {
  final double passengerFare;
  final double driverEarnings;

  FareResult(this.passengerFare, this.driverEarnings);
}

// Pricing constants (restored original model)
const double kBaseFare = 100.0;
const double kPerKm = 90.0;
const double kPerMin = 3.0;
const double kCommissionPct = 0.80; // driver receives 80% of passenger fare
const double kMinFare = 200.0;

FareResult computeFareAndEarnings(double distanceKm, double durationMin) {
  final double rawFare =
      kBaseFare + (distanceKm * kPerKm) + (durationMin * kPerMin);
  final double passengerFare = rawFare < kMinFare ? kMinFare : rawFare;
  final double driverEarnings = passengerFare * kCommissionPct;
  return FareResult(passengerFare, driverEarnings);
}
