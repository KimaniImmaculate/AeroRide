import 'package:intl/intl.dart';

final NumberFormat _kes = NumberFormat.currency(
  locale: 'en_KE',
  name: 'KES',
  symbol: 'KSh ',
  decimalDigits: 2,
);

String formatKES(double amount) {
  return _kes.format(amount);
}

String formatKESNullable(double? amount) {
  if (amount == null) return 'KSh --';
  return _kes.format(amount);
}
