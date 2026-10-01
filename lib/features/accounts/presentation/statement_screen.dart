import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/database_provider.dart';
import '../../../core/formatters.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/empty_state.dart';
import '../../parties/data/parties_providers.dart';
import '../../parties/presentation/contact_launcher.dart';
import '../data/account_messages.dart';
import '../data/accounts_providers.dart';
import 'record_payment_dialog.dart';

/// كشف حساب: every order and payment with a running balance.
class StatementScreen extends ConsumerWidget {
  const StatementScreen({super.key, required this.partyId});

  final int partyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final party = ref.watch(partyProvider(partyId)).value;
    final entries = ref.watch(statementProvider(partyId));
    final list = entries.value ?? const <StatementEntry>[];
    final balance = list.isEmpty ? 0 : list.last.balance;
    return Scaffold(
      appBar: AppBar(
        title: Text('كشف حساب ${party?.name ?? ''}'),
        actions: [
          IconButton(
            tooltip: 'إرسال واتساب',
            icon: const Icon(Icons.share),
            onPressed: party == null || list.isEmpty
                ? null
                : () => _share(party, list),
          ),
        ],
      ),
      floatingActionButton: party == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => recordPartyPayment(context, ref, party),
              icon: const Icon(Icons.payments_outlined),
              label: const Text('تسجيل دفعة'),
            ),
      body: AsyncValueView(
        value: entries,
        data: (_) => Column(
          children: [
            _BalanceHeader(balance: balance),
            Expanded(
              child: list.isEmpty
                  ? const EmptyState(
                      icon: Icons.receipt_long_outlined,
                      message: 'لا توجد حركات على هذا الحساب بعد',
                    )
                  // Newest first; the balance column is still chronological.
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: 88),
                      itemCount: list.length,
                      itemBuilder: (_, i) =>
                          _EntryTile(entry: list[list.length - 1 - i]),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _share(Party party, List<StatementEntry> entries) {
    final text = statementMessage(
      partyName: party.name,
      entries: entries,
      today: DateTime.now(),
    );
    final phone = party.phone;
    return launchUrl(
      Uri.https(
        'wa.me',
        phone == null ? '/' : '/${toInternationalEgypt(phone)}',
        {'text': text},
      ),
      mode: LaunchMode.externalApplication,
    );
  }
}

/// Records a payment on the party's account (not tied to one order).
Future<void> recordPartyPayment(
  BuildContext context,
  WidgetRef ref,
  Party party,
) async {
  final db = ref.read(databaseProvider);
  final input = await showRecordPaymentDialog(
    context,
    direction: directionFor(party.kind),
  );
  if (input == null) return;
  await db.addPayment(
    PaymentsCompanion.insert(
      partyId: party.id,
      direction: input.direction,
      amountPiasters: input.amount,
      date: input.date,
      note: Value(input.note),
    ),
  );
}

class _BalanceHeader extends StatelessWidget {
  const _BalanceHeader({required this.balance});

  final int balance;

  @override
  Widget build(BuildContext context) {
    final color = balance > 0
        ? AppColors.danger
        : (balance < 0 ? AppColors.purchase : AppColors.sale);
    return Card(
      margin: const EdgeInsets.all(12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Expanded(
              child: Text('الرصيد الحالي', style: TextStyle(fontSize: 16)),
            ),
            Text(
              balanceLabel(balance),
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EntryTile extends ConsumerWidget {
  const _EntryTile({required this.entry});

  final StatementEntry entry;

  Future<void> _deletePayment(BuildContext context, WidgetRef ref) async {
    final db = ref.read(databaseProvider);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف الدفعة؟'),
        content: Text(
          '${statementEntryTitle(entry)} بمبلغ ${formatMoney(entry.amount)}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (ok == true) await db.deletePayment(entry.refId);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = entry.increasesBalance ? AppColors.danger : AppColors.sale;
    return Card(
      child: ListTile(
        // Payments open a delete confirmation (to fix entry mistakes).
        onTap: entry.isPayment
            ? () => _deletePayment(context, ref)
            : () => context.push('/orders/${entry.refId}'),
        leading: Icon(
          entry.isPayment ? Icons.payments_outlined : Icons.receipt_long,
          color: color,
        ),
        title: Text(statementEntryTitle(entry)),
        subtitle: Text(
          [
            formatDate(entry.date),
            'الرصيد: ${balanceLabel(entry.balance)}',
            ?entry.note,
          ].join('\n'),
        ),
        isThreeLine: true,
        trailing: Text(
          '${entry.increasesBalance ? '+' : '−'} ${formatMoney(entry.amount)}',
          style: TextStyle(color: color, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
