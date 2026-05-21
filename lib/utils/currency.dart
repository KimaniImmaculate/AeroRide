import 'package:intl/intl.dart';

final NumberFormat _kes = NumberFormat.currency(
  locale: 'en_KE',
  name: 'KES',
  decimalDigits: 2,
);

String formatKES(double? amount) {
  if (amount == null) return _kes.format(0);
  return _kes.format(amount);
}
