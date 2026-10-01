import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database_provider.dart';
import '../../../core/formatters.dart';
import '../../../core/theme.dart';
import '../data/backup_schedule.dart';
import '../data/drive_backup.dart';

typedef BackupStatus = ({bool connected, DateTime? lastAt});

final backupStatusProvider = FutureProvider.autoDispose<BackupStatus>(
  (ref) async => (
    connected: await DriveBackup.isConnected(),
    lastAt: await DriveBackup.lastBackupAt(),
  ),
);

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action, String success) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
      messenger.showSnackBar(SnackBar(content: Text(success)));
    } on BackupNotConnected {
      messenger.showSnackBar(
        const SnackBar(content: Text('اربط حساب جوجل درايف أولاً')),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('حدث خطأ: $e')));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        ref.invalidate(backupStatusProvider);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(backupStatusProvider).value;
    final connected = status?.connected ?? false;
    final lastAt = status?.lastAt;
    return Scaffold(
      appBar: AppBar(title: const Text('الإعدادات والنسخ الاحتياطي')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        connected ? Icons.cloud_done : Icons.cloud_off,
                        color: connected ? AppColors.sale : Colors.grey,
                        size: 32,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          connected ? 'جوجل درايف متصل' : 'جوجل درايف غير متصل',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'كل يوم بعد الساعة $backupHour:00 يتم تحديث ملف Excel '
                    'بكل البيانات في مجلد "${DriveBackup.folderName}" '
                    'على جوجل درايف، مع نسخة كاملة من قاعدة البيانات.',
                    style: const TextStyle(color: Colors.black54),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    lastAt == null
                        ? 'لم يتم عمل نسخة احتياطية بعد'
                        : 'آخر نسخة: ${formatDateTime(lastAt)}',
                  ),
                  const SizedBox(height: 16),
                  if (!connected)
                    FilledButton.icon(
                      onPressed: _busy
                          ? null
                          : () => _run(DriveBackup.connect, 'تم الربط بنجاح'),
                      icon: const Icon(Icons.add_to_drive),
                      label: const Text('ربط حساب جوجل درايف'),
                    )
                  else ...[
                    FilledButton.icon(
                      onPressed: _busy
                          ? null
                          : () => _run(
                              () => DriveBackup.run(ref.read(databaseProvider)),
                              'تم رفع النسخة الاحتياطية',
                            ),
                      icon: _busy
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.backup),
                      label: const Text('نسخ احتياطي الآن'),
                    ),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () =>
                                _run(DriveBackup.disconnect, 'تم إلغاء الربط'),
                      child: const Text('إلغاء ربط الحساب'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
