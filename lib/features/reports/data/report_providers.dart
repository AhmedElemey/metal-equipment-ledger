import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/database_provider.dart';

final orderProfitProvider = StreamProvider.autoDispose.family<Profit, int>(
  (ref, orderId) => ref.watch(databaseProvider).watchOrderProfit(orderId),
);

/// Report for the month starting at the key date.
final monthlyReportProvider = StreamProvider.autoDispose
    .family<MonthlyReport, DateTime>(
      (ref, month) => ref
          .watch(databaseProvider)
          .watchMonthlyReport(month, DateTime(month.year, month.month + 1)),
    );
