import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/database_provider.dart';

final itemPricesProvider = StreamProvider.autoDispose<List<ItemPrice>>(
  (ref) => ref.watch(databaseProvider).watchItemPrices(),
);

typedef PartyPricesKey = ({int partyId, OrderKind kind, int? excludeOrderId});

final partyItemPricesProvider = StreamProvider.autoDispose
    .family<Map<String, PartyItemPrice>, PartyPricesKey>(
      (ref, key) => ref
          .watch(databaseProvider)
          .watchPartyItemPrices(
            partyId: key.partyId,
            kind: key.kind,
            excludeOrderId: key.excludeOrderId,
          ),
    );
