import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/database_provider.dart';

final partyBalanceProvider = StreamProvider.autoDispose.family<int, int>(
  (ref, partyId) => ref.watch(databaseProvider).watchPartyBalance(partyId),
);

final statementProvider = StreamProvider.autoDispose
    .family<List<StatementEntry>, int>(
      (ref, partyId) => ref.watch(databaseProvider).watchStatement(partyId),
    );

final debtorsProvider = StreamProvider.autoDispose<List<Debtor>>(
  (ref) => ref.watch(databaseProvider).watchDebtors(),
);

final orderPaymentsProvider = StreamProvider.autoDispose
    .family<List<Payment>, int>(
      (ref, orderId) => ref.watch(databaseProvider).watchPaymentsOf(orderId),
    );
