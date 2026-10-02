import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:metal_ledger/app.dart';
import 'package:metal_ledger/core/database/app_database.dart';
import 'package:metal_ledger/core/database/database_provider.dart';
import 'package:metal_ledger/core/router.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

/// Shared setup for widget tests that run the whole app.
void setUpAppTests() {
  setUpAll(() async {
    await initializeDateFormatting('ar');
    SharedPreferences.setMockInitialValues({});
  });
  setUp(() {
    // Fresh settings per test, and the app-global router back home so no
    // test depends on which one ran before.
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    router.go('/');
  });
}

/// Runs the app at [location] on a phone-sized screen with [db] (a fresh
/// in-memory database by default). Returns the database.
Future<AppDatabase> pumpApp(
  WidgetTester tester, {
  String location = '/',
  AppDatabase? db,
  List<Override> overrides = const [],
}) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final database = db ?? AppDatabase(NativeDatabase.memory());
  router.go(location);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [databaseProvider.overrideWithValue(database), ...overrides],
      child: const MetalLedgerApp(),
    ),
  );
  await tester.pumpAndSettle();
  return database;
}

/// Scrolls the page until [target] is on screen, then taps it. Advances
/// a fixed half second instead of settling, since a busy spinner may keep
/// animating while a dialog waits for an answer.
Future<void> scrollAndTap(WidgetTester tester, Finder target) async {
  await tester.scrollUntilVisible(
    target,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

/// Unmounts the app so drift's stream-cleanup timers run inside the test.
Future<void> unmountApp(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
}

/// Lets real (non-fake-async) I/O finish, then settles the UI. Repeats a
/// few times because a chain of file operations needs one window each.
Future<void> settleIo(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pumpAndSettle();
  }
}

/// Points the app's documents folder at a temp dir for this test.
Directory useTempDocuments() {
  final docs = Directory.systemTemp.createTempSync('ledger_docs');
  final real = PathProviderPlatform.instance;
  PathProviderPlatform.instance = FakePathProvider(docs.path);
  addTearDown(() {
    PathProviderPlatform.instance = real;
    docs.deleteSync(recursive: true);
  });
  return docs;
}

/// Records launched URLs instead of opening other apps.
List<String> captureLaunchedUrls() {
  final launched = <String>[];
  final real = UrlLauncherPlatform.instance;
  UrlLauncherPlatform.instance = _FakeUrlLauncher(launched);
  addTearDown(() => UrlLauncherPlatform.instance = real);
  return launched;
}

class FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  FakePathProvider(this.root);

  final String root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;

  @override
  Future<String?> getTemporaryPath() async => root;
}

class _FakeUrlLauncher extends UrlLauncherPlatform
    with MockPlatformInterfaceMixin {
  _FakeUrlLauncher(this.launched);

  final List<String> launched;

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> canLaunch(String url) async => true;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launched.add(url);
    return true;
  }
}

/// A valid 1×1 PNG.
final tinyPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);
