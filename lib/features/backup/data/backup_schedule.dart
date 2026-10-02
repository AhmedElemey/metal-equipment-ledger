import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';

import '../../../core/database/app_database.dart';
import 'drive_backup.dart';

/// "End of the working day" — the daily backup runs after this hour.
const backupHour = 21;

const _taskName = 'daily-drive-backup';

/// The backup is due when the last one happened before the most recent
/// end-of-day boundary (today 21:00 if that has passed, else yesterday 21:00).
bool isBackupDue(DateTime? lastBackup, DateTime now) {
  if (lastBackup == null) return true;
  var boundary = DateTime(now.year, now.month, now.day, backupHour);
  if (now.isBefore(boundary)) {
    boundary = boundary.subtract(const Duration(days: 1));
  }
  return lastBackup.isBefore(boundary);
}

/// Runs the backup if it's due and Drive is connected. Never throws.
///
/// Returns false only when WorkManager should retry later. [drive] and
/// [now] are replaceable for tests.
Future<bool> backupIfDue(
  AppDatabase db, {
  DriveBackupActions drive = const DriveBackupActions(),
  DateTime? now,
}) async {
  try {
    if (!await drive.isConnected()) return true;
    if (!isBackupDue(await drive.lastBackupAt(), now ?? DateTime.now())) {
      return true;
    }
    await drive.backUp(db);
    return true;
  } on NothingToBackUp {
    return true; // nothing to do — don't make WorkManager retry
  } catch (e, st) {
    debugPrint('Daily backup failed: $e\n$st');
    return false;
  }
}

@pragma('vm:entry-point')
void backupCallbackDispatcher() {
  Workmanager().executeTask((task, _) async {
    WidgetsFlutterBinding.ensureInitialized();
    final db = AppDatabase();
    try {
      // false → WorkManager retries with backoff (e.g. no network yet).
      return await backupIfDue(db);
    } finally {
      await db.close();
    }
  });
}

/// Registers a periodic OS task that wakes up roughly every few hours; each
/// run only uploads when [isBackupDue]. Phones with aggressive battery
/// savers may skip runs, so the app also checks on open/resume.
Future<void> scheduleDailyBackup() async {
  await Workmanager().initialize(backupCallbackDispatcher);
  await Workmanager().registerPeriodicTask(
    _taskName,
    _taskName,
    frequency: const Duration(hours: 3),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    constraints: Constraints(networkType: NetworkType.connected),
  );
}
