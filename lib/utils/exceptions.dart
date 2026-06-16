/// Custom exception for when a user is not authenticated for an action.
class NotAuthenticatedException implements Exception {
  final String message;
  NotAuthenticatedException(this.message);

  @override
  String toString() => 'NotAuthenticatedException: $message';
}

/// Custom exception for when a cancellation penalty is applied.
class CancellationPenaltyException implements Exception {
  final String message;
  final double penaltyAmount;
  CancellationPenaltyException(this.message, this.penaltyAmount);

  @override
  String toString() =>
      'CancellationPenaltyException: $message (KSh ${penaltyAmount.toStringAsFixed(0)})';
}
