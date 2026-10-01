import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/database_provider.dart';

final itemPricesProvider = StreamProvider.autoDispose<List<ItemPrice>>(
  (ref) => ref.watch(databaseProvider).watchItemPrices(),
);
