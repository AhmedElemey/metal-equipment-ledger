import 'package:intl/intl.dart';

final _money = NumberFormat('#,##0', 'ar');
final _moneyWithPiasters = NumberFormat('#,##0.00', 'ar');
final _qty = NumberFormat('#,##0.###', 'ar');
final _date = DateFormat('d MMMM y', 'ar');
final _shortDate = DateFormat('d/M/y', 'ar');
final _dateTime = DateFormat('d MMM y - h:mm a', 'ar');

/// 150000 → "1,500 ج.م", 150050 → "1,500.50 ج.م"
String formatMoney(int piasters) {
  final f = piasters % 100 == 0 ? _money : _moneyWithPiasters;
  return '${f.format(piasters / 100)} ج.م';
}

String formatQuantity(double qty) => _qty.format(qty);

String formatDate(DateTime d) => _date.format(d);

/// 1/10/2026 — used in PDFs, where month names break the text layout.
String formatShortDate(DateTime d) => _shortDate.format(d);

String formatDateTime(DateTime d) => _dateTime.format(d);

/// Calendar days between [d] and [now] in natural Arabic.
String daysAgo(DateTime d, DateTime now) {
  final days = DateTime(
    now.year,
    now.month,
    now.day,
  ).difference(DateTime(d.year, d.month, d.day)).inDays;
  return switch (days) {
    <= 0 => 'اليوم',
    1 => 'أمس',
    2 => 'منذ يومين',
    <= 10 => 'منذ $days أيام',
    _ => 'منذ $days يوم',
  };
}

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
