import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/database_provider.dart';

typedef OrdersFilter = ({
  int? partyId,
  OrderKind? kind,
  bool? quotations,
  int? limit,
});

final ordersProvider = StreamProvider.autoDispose
    .family<List<OrderSummary>, OrdersFilter>(
      (ref, f) => ref
          .watch(databaseProvider)
          .watchOrderSummaries(
            partyId: f.partyId,
            kind: f.kind,
            quotations: f.quotations,
            limit: f.limit,
          ),
    );

final orderProvider = StreamProvider.autoDispose.family<OrderSummary, int>(
  (ref, id) => ref.watch(databaseProvider).watchOrderSummary(id),
);

final orderItemsProvider = StreamProvider.autoDispose
    .family<List<OrderItem>, int>(
      (ref, id) => ref.watch(databaseProvider).watchItemsOf(id),
    );
