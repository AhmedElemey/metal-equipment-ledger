import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

final _monthFormat = DateFormat('MMMM y', 'ar');

DateTime monthStart(DateTime d) => DateTime(d.year, d.month);

/// "‹ أكتوبر 2026 ›" — steps a month back or forward (not into the future).
class MonthSwitcher extends StatelessWidget {
  const MonthSwitcher({
    super.key,
    required this.month,
    required this.onChanged,
  });

  /// First day of the shown month.
  final DateTime month;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    final isCurrent = month == monthStart(DateTime.now());
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          tooltip: 'الشهر السابق',
          // Mirrors in RTL: chevron_left is "back", chevron_right "forward".
          icon: const Icon(Icons.chevron_left),
          onPressed: () => onChanged(DateTime(month.year, month.month - 1)),
        ),
        Text(
          _monthFormat.format(month),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        IconButton(
          tooltip: 'الشهر التالي',
          icon: const Icon(Icons.chevron_right),
          onPressed: isCurrent
              ? null
              : () => onChanged(DateTime(month.year, month.month + 1)),
        ),
      ],
    );
  }
}
