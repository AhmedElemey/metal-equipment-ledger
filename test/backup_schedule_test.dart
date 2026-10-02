import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metal_ledger/core/database/app_database.dart';
import 'package:metal_ledger/features/backup/data/backup_schedule.dart';
import 'package:metal_ledger/features/backup/data/drive_backup.dart';

class _Drive implements DriveBackupActions {
  _Drive({this.connected = true, this.last, this.error});

  final bool connected;
  final DateTime? last;
  final Object? error;
  int backUps = 0;

  @override
  Future<bool> isConnected() async => connected;
  @override
  Future<DateTime?> lastBackupAt() async => last;
  @override
  Future<void> backUp(AppDatabase db) async {
    backUps++;
    if (error != null) throw error!;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  final evening = DateTime(2026, 10, 1, 22);

  test('not connected: nothing happens, no retry', () async {
    final drive = _Drive(connected: false);
    expect(await backupIfDue(db, drive: drive, now: evening), isTrue);
    expect(drive.backUps, 0);
  });

  test('due: backs up once', () async {
    final drive = _Drive(last: DateTime(2026, 9, 30, 22));
    expect(await backupIfDue(db, drive: drive, now: evening), isTrue);
    expect(drive.backUps, 1);
  });

  test('already done tonight: skipped', () async {
    final drive = _Drive(last: DateTime(2026, 10, 1, 21, 30));
    expect(await backupIfDue(db, drive: drive, now: evening), isTrue);
    expect(drive.backUps, 0);
  });

  test('empty phone: treated as done, so WorkManager does not retry', () async {
    final drive = _Drive(error: const NothingToBackUp());
    expect(await backupIfDue(db, drive: drive, now: evening), isTrue);
  });

  test('network or auth failure: asks WorkManager to retry', () async {
    final drive = _Drive(error: Exception('offline'));
    expect(await backupIfDue(db, drive: drive, now: evening), isFalse);
    final notConnected = _Drive(error: const BackupNotConnected());
    expect(await backupIfDue(db, drive: notConnected, now: evening), isFalse);
  });
}
