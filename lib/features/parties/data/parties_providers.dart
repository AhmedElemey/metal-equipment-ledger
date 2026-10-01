import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/database_provider.dart';

final partiesProvider = StreamProvider.autoDispose.family<List<Party>, String>(
  (ref, query) => ref.watch(databaseProvider).watchParties(query: query),
);

final partyProvider = StreamProvider.autoDispose.family<Party, int>(
  (ref, id) => ref.watch(databaseProvider).watchParty(id),
);
