import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_database.dart';

/// App-lifetime database. Overridden in tests with an in-memory instance.
final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});
