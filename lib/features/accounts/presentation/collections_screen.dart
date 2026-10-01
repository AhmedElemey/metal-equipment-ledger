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
import '../../parties/presentation/contact_launcher.dart';
import '../data/account_messages.dart';
import '../data/accounts_providers.dart';

/// No payment for this long and the balance is flagged as late.
const overdueAfter = Duration(days: 30);

/// التحصيل: everyone who owes us, with one-tap WhatsApp reminders.
class CollectionsScreen extends ConsumerWidget {
  const CollectionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final debtors = ref.watch(debtorsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('التحصيل')),
      body: AsyncValueView(
        value: debtors,
        data: (list) {
          if (list.isEmpty) {
            return const EmptyState(
              icon: Icons.verified_outlined,
              message: 'لا توجد مستحقات لدى العملاء 👍',
            );
          }
          final total = list.fold(0, (sum, d) => sum + d.balance);
          final now = DateTime.now();
          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Card(
                  margin: const EdgeInsets.all(12),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'إجمالي المستحق لنا (${list.length} عميل)',
                            style: const TextStyle(fontSize: 16),
                          ),
                        ),
                        Text(
                          formatMoney(total),
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: AppColors.danger,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              SliverList.builder(
                itemCount: list.length,
                itemBuilder: (_, i) => _DebtorCard(debtor: list[i], now: now),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _DebtorCard extends ConsumerWidget {
  const _DebtorCard({required this.debtor, required this.now});

  final Debtor debtor;
  final DateTime now;

  Future<void> _remind(WidgetRef ref, String phone) async {
    final db = ref.read(databaseProvider);
    final party = debtor.party;
    final text = paymentReminderMessage(
      partyName: party.name,
      balance: debtor.balance,
      today: now,
    );
    final opened = await launchUrl(
      Uri.https('wa.me', '/${toInternationalEgypt(phone)}', {'text': text}),
      mode: LaunchMode.externalApplication,
    );
    if (opened) await db.markReminded(party.id, DateTime.now());
  }

  String _activityText() {
    final lastPayment = debtor.lastPaymentAt;
    final firstSale = debtor.firstSaleAt;
    if (lastPayment != null) return 'آخر دفعة ${daysAgo(lastPayment, now)}';
    if (firstSale != null) {
      return 'لم يدفع بعد • أول فاتورة ${daysAgo(firstSale, now)}';
    }
    return 'لم يدفع بعد';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final party = debtor.party;
    final phone = party.phone;
    final lastActivity = debtor.lastActivityAt;
    final overdue =
        lastActivity != null && now.difference(lastActivity) > overdueAfter;
    final remindedAt = party.lastRemindedAt;
    return Card(
      child: InkWell(
        onTap: () => context.push('/parties/${party.id}/statement'),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      party.name,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  Text(
                    formatMoney(debtor.balance),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.danger,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    _activityText(),
                    style: const TextStyle(color: Colors.black54),
                  ),
                  if (overdue)
                    const Chip(
                      label: Text('متأخر'),
                      visualDensity: VisualDensity.compact,
                      backgroundColor: Color(0x22C62828),
                    ),
                  if (remindedAt != null)
                    Text(
                      'تم التذكير ${daysAgo(remindedAt, now)}',
                      style: const TextStyle(color: AppColors.purchase),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.sale,
                      ),
                      onPressed: phone == null
                          ? null
                          : () => _remind(ref, phone),
                      icon: const Icon(Icons.chat),
                      label: const Text('تذكير واتساب'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.outlined(
                    tooltip: 'اتصال',
                    onPressed: phone == null ? null : () => callPhone(phone),
                    icon: const Icon(Icons.call),
                  ),
                  const SizedBox(width: 4),
                  IconButton.outlined(
                    tooltip: 'كشف الحساب',
                    onPressed: () =>
                        context.push('/parties/${party.id}/statement'),
                    icon: const Icon(Icons.receipt_long),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
