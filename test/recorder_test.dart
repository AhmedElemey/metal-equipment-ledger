import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metal_ledger/core/database/app_database.dart';
import 'package:metal_ledger/core/router.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:record_platform_interface/record_platform_interface.dart';

import 'support.dart';

/// A microphone that "records" by writing a small file at the given path.
class _FakeRecorder extends RecordPlatform with MockPlatformInterfaceMixin {
  _FakeRecorder({this.allowed = true});

  final bool allowed;
  String? _path;

  @override
  Future<void> create(String recorderId) async {}
  @override
  Future<bool> hasPermission(String recorderId, {bool request = true}) async =>
      allowed;
  @override
  Future<void> start(
    String recorderId,
    RecordConfig config, {
    required String path,
  }) async {
    _path = path;
    File(path).writeAsStringSync('audio');
  }

  @override
  Future<String?> stop(String recorderId) async => _path;
  @override
  Future<bool> isRecording(String recorderId) async => false;
  @override
  Future<void> dispose(String recorderId) async {}
  @override
  Stream<RecordState> onStateChanged(String recorderId) => const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void _useRecorder(_FakeRecorder fake) {
  final real = RecordPlatform.instance;
  RecordPlatform.instance = fake;
  addTearDown(() => RecordPlatform.instance = real);
}

Future<int> _openClient(WidgetTester tester, AppDatabase db) async {
  final id = await tester.runAsync(
    () => db.saveParty(
      PartiesCompanion.insert(name: 'عميل', kind: PartyKind.buyer),
    ),
  );
  await pumpApp(tester, location: '/parties', db: db);
  router.push('/parties/$id');
  await tester.pumpAndSettle();
  return id!;
}

Directory _notesDir(Directory docs) => Directory('${docs.path}/voice_notes');

void main() {
  setUpAppTests();

  testWidgets('record, stop and save a voice note', (tester) async {
    final docs = useTempDocuments();
    _useRecorder(_FakeRecorder());
    final db = AppDatabase(NativeDatabase.memory());
    final party = await _openClient(tester, db);

    await tester.tap(find.text('تسجيل'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.mic).last); // the sheet's big button
    await settleIo(tester);
    expect(find.text('جاري التسجيل…'), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
    expect(find.text('00:03'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.stop));
    await settleIo(tester);
    await tester.tap(find.text('حفظ'));
    await settleIo(tester);

    final notes = await tester.runAsync(
      () => db.watchVoiceNotes(partyId: party).first,
    );
    expect(notes, hasLength(1));
    expect(notes!.single.durationMs, 3000);
    expect(
      File('${_notesDir(docs).path}/${notes.single.fileName}').existsSync(),
      isTrue,
    );
    expect(find.text('ملاحظات صوتية (1)'), findsOneWidget);
    await unmountApp(tester);
  });

  testWidgets('cancelling a recording leaves no file behind', (tester) async {
    final docs = useTempDocuments();
    _useRecorder(_FakeRecorder());
    final db = AppDatabase(NativeDatabase.memory());
    await _openClient(tester, db);

    await tester.tap(find.text('تسجيل'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.mic).last); // the sheet's big button
    await settleIo(tester);
    await tester.pump(const Duration(seconds: 2));
    await tester.tap(find.byIcon(Icons.stop));
    await settleIo(tester);
    expect(_notesDir(docs).listSync(), hasLength(1));

    await tester.tap(find.text('إلغاء'));
    await settleIo(tester);

    expect(_notesDir(docs).listSync(), isEmpty);
    expect(
      await tester.runAsync(() => db.select(db.voiceNotes).get()),
      isEmpty,
    );
    await unmountApp(tester);
  });

  testWidgets('no microphone permission: a clear message, nothing recorded', (
    tester,
  ) async {
    final docs = useTempDocuments();
    _useRecorder(_FakeRecorder(allowed: false));
    final db = AppDatabase(NativeDatabase.memory());
    await _openClient(tester, db);

    await tester.tap(find.text('تسجيل'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.mic).last); // the sheet's big button
    await settleIo(tester);

    expect(find.text('يجب السماح باستخدام الميكروفون'), findsOneWidget);
    expect(find.text('جاري التسجيل…'), findsNothing);
    expect(
      !_notesDir(docs).existsSync() || _notesDir(docs).listSync().isEmpty,
      isTrue,
    );
    await unmountApp(tester);
  });
}
