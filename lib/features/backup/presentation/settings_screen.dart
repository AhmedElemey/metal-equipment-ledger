import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/database_provider.dart';
import '../../../core/formatters.dart';
import '../../../core/theme.dart';
import '../../business/presentation/business_info_card.dart';
import '../data/backup_schedule.dart';
import '../data/drive_backup.dart';

typedef BackupStatus = ({bool connected, DateTime? lastAt});

final backupStatusProvider = FutureProvider.autoDispose<BackupStatus>((
  ref,
) async {
  final drive = ref.watch(driveBackupProvider);
  return (
    connected: await drive.isConnected(),
    lastAt: await drive.lastBackupAt(),
  );
});

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _busy = false;

  /// Runs [action] with a busy state; shows the message it returns.
  Future<void> _run(Future<String?> Function() action) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    void show(String text) =>
        messenger.showSnackBar(SnackBar(content: Text(text)));
    try {
      final message = await action();
      if (message != null) show(message);
    } on BackupNotConnected {
      show('اربط حساب جوجل درايف أولاً');
    } on NothingToBackUp {
      show('لا توجد بيانات على التليفون لرفعها بعد');
    } on NoBackupFound {
      show('لا توجد نسخة احتياطية على جوجل درايف');
    } on InvalidBackup {
      show('ملف النسخة الاحتياطية تالف — لم يتم تغيير أي بيانات');
    } on BackupTooNew {
      show('النسخة من إصدار أحدث للتطبيق — حدّث التطبيق أولاً');
    } catch (e) {
      show('حدث خطأ: $e');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        ref.invalidate(backupStatusProvider);
      }
    }
  }

  Future<String?> _connect() async {
    await ref.read(driveBackupProvider).connect();
    // A new or reset phone: offer the existing backup before anything else.
    if ((await ref.read(databaseProvider).counts()).parties == 0) {
      final backup = await ref.read(driveBackupProvider).findBackup();
      if (backup != null) return _confirmAndRestore(backup);
    }
    return 'تم الربط بنجاح';
  }

  Future<String?> _restore() async {
    final backup = await ref.read(driveBackupProvider).findBackup();
    if (backup == null) throw const NoBackupFound();
    return _confirmAndRestore(backup);
  }

  Future<String?> _confirmAndRestore(DriveBackupFile backup) async {
    final db = ref.read(databaseProvider);
    final local = await db.counts();
    if (!mounted) return null;
    final hasData = local.parties > 0;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('استعادة البيانات من جوجل درايف'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('آخر نسخة على درايف: ${formatDateTime(backup.modifiedAt)}'),
            const SizedBox(height: 12),
            if (hasData)
              Text(
                'تحذير: سيتم مسح كل البيانات الموجودة على هذا التليفون '
                '(${local.parties} عميل/مورد و ${local.orders} طلب) '
                'واستبدالها بالنسخة الموجودة على درايف.',
                style: const TextStyle(color: AppColors.danger),
              )
            else
              const Text('هل تريد استعادة بياناتك على هذا التليفون؟'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: hasData
                ? FilledButton.styleFrom(backgroundColor: AppColors.danger)
                : null,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(hasData ? 'مسح واستعادة' : 'استعادة'),
          ),
        ],
      ),
    );
    if (ok != true) return null;
    final restored = await ref.read(driveBackupProvider).restore(db);
    return 'تمت الاستعادة: ${restored.parties} عميل/مورد '
        'و ${restored.orders} طلب';
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(backupStatusProvider).value;
    final connected = status?.connected ?? false;
    final lastAt = status?.lastAt;
    return Scaffold(
      appBar: AppBar(title: const Text('الإعدادات')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          const BusinessInfoCard(),
          const SizedBox(height: 12),
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
                    'على جوجل درايف، مع نسخة كاملة من البيانات والملاحظات '
                    'الصوتية. على تليفون جديد: اربط نفس الحساب ثم اضغط '
                    '"استعادة".',
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
                      onPressed: _busy ? null : () => _run(_connect),
                      icon: const Icon(Icons.add_to_drive),
                      label: const Text('ربط حساب جوجل درايف'),
                    )
                  else ...[
                    FilledButton.icon(
                      onPressed: _busy
                          ? null
                          : () => _run(() async {
                              await ref
                                  .read(driveBackupProvider)
                                  .backUp(ref.read(databaseProvider));
                              return 'تم رفع النسخة الاحتياطية';
                            }),
                      icon: _busy
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.backup),
                      label: const Text('نسخ احتياطي الآن'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : () => _run(_restore),
                      icon: const Icon(Icons.settings_backup_restore),
                      label: const Text('استعادة من جوجل درايف'),
                    ),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => _run(() async {
                              await ref.read(driveBackupProvider).disconnect();
                              return 'تم إلغاء الربط';
                            }),
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
