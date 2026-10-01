import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/database/database_provider.dart';
import 'core/router.dart';
import 'core/theme.dart';
import 'features/backup/data/backup_schedule.dart';

class MetalLedgerApp extends ConsumerStatefulWidget {
  const MetalLedgerApp({super.key});

  @override
  ConsumerState<MetalLedgerApp> createState() => _MetalLedgerAppState();
}

class _MetalLedgerAppState extends ConsumerState<MetalLedgerApp> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // Catch-up for days the OS skipped the background task.
    _lifecycle = AppLifecycleListener(onResume: _backupIfDue);
    _backupIfDue();
  }

  void _backupIfDue() => unawaited(backupIfDue(ref.read(databaseProvider)));

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'دفتر المعدات',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      routerConfig: router,
      locale: const Locale('ar', 'EG'),
      supportedLocales: const [Locale('ar', 'EG')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
    );
  }
}
