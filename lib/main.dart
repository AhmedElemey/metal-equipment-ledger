import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app.dart';
import 'features/backup/data/backup_schedule.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ar');
  if (defaultTargetPlatform == TargetPlatform.android) {
    // iOS needs extra BGTask setup first — see README.
    unawaited(scheduleDailyBackup());
  }
  runApp(const ProviderScope(child: MetalLedgerApp()));
}
