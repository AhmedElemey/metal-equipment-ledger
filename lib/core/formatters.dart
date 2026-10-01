import 'package:intl/intl.dart';

final _money = NumberFormat('#,##0.##', 'ar');
final _qty = NumberFormat('#,##0.###', 'ar');
final _date = DateFormat('d MMMM y', 'ar');
final _dateTime = DateFormat('d MMM y - h:mm a', 'ar');

/// 150050 piasters → "1,500.5 ج.م"
String formatMoney(int piasters) => '${_money.format(piasters / 100)} ج.م';

String formatQuantity(double qty) => _qty.format(qty);

String formatDate(DateTime d) => _date.format(d);

String formatDateTime(DateTime d) => _dateTime.format(d);

String formatDuration(Duration d) {
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$m:$s';
}

/// Piasters as an editable plain number: 150000 → "1500", 150050 → "1500.50".
String piastersToInput(int piasters) => piasters % 100 == 0
    ? '${piasters ~/ 100}'
    : (piasters / 100).toStringAsFixed(2);

/// Parses user input such as "1,500.50" or "١٥٠٠" into piasters.
/// Returns null for empty or invalid input.
int? parseMoneyToPiasters(String input) {
  final value = parseNumber(input);
  return value == null ? null : (value * 100).round();
}

double? parseNumber(String input) {
  const arabicDigits = '٠١٢٣٤٥٦٧٨٩';
  final buffer = StringBuffer();
  for (final ch in input.trim().split('')) {
    final i = arabicDigits.indexOf(ch);
    if (i >= 0) {
      buffer.write(i);
    } else if (ch == '٫') {
      buffer.write('.');
    } else if (ch != ',' && ch != '٬' && ch != ' ') {
      buffer.write(ch);
    }
  }
  return double.tryParse(buffer.toString());
}
