import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/database_provider.dart';
import '../../../core/formatters.dart';
import '../../../core/labels.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/total_row.dart';
import '../../parties/presentation/contact_launcher.dart';
import '../../voice_notes/presentation/voice_notes_section.dart';
import '../data/orders_providers.dart';

class OrderDetailsScreen extends ConsumerWidget {
  const OrderDetailsScreen({super.key, required this.orderId});

  final int orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(orderProvider(orderId));
    return Scaffold(
      appBar: AppBar(
        title: Text('طلب رقم $orderId'),
        actions: [
          IconButton(
            tooltip: 'تعديل',
            icon: const Icon(Icons.edit),
            onPressed: () => context.push('/orders/$orderId/edit'),
          ),
          IconButton(
            tooltip: 'حذف',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _confirmDelete(context, ref),
          ),
        ],
      ),
      body: AsyncValueView(
        value: summary,
        data: (s) => _OrderBody(summary: s),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final db = ref.read(databaseProvider);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف الطلب؟'),
        content: const Text('سيتم حذف الطلب وأصنافه نهائياً.'),
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
    if (ok != true || !context.mounted) return;
    // Leave first so this screen's stream never sees the missing row.
    context.pop();
    await db.deleteOrder(orderId);
  }
}

class _OrderBody extends ConsumerWidget {
  const _OrderBody({required this.summary});

  final OrderSummary summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final order = summary.order;
    final items = ref.watch(orderItemsProvider(order.id)).value ?? const [];
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Card(
            margin: const EdgeInsets.all(12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Chip(
                        label: Text(order.kind.label),
                        backgroundColor: order.kind.color.withValues(
                          alpha: 0.12,
                        ),
                      ),
                      const SizedBox(width: 8),
                      _StatusMenu(order: order),
                    ],
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.person),
                    title: Text(summary.partyName),
                    subtitle: Text(formatDate(order.date)),
                    trailing: const Icon(Icons.chevron_left),
                    onTap: () => context.push('/parties/${order.partyId}'),
                  ),
                  if (order.notes != null) Text(order.notes!),
                ],
              ),
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SectionHeader(title: 'الأصناف')),
        SliverList.builder(
          itemCount: items.length,
          itemBuilder: (_, i) {
            final item = items[i];
            return Card(
              child: ListTile(
                title: Text(item.name),
                subtitle: Text(
                  '${formatQuantity(item.quantity)} ${item.unit} × '
                  '${formatMoney(item.unitPricePiasters)}',
                ),
                trailing: Text(
                  formatMoney((item.quantity * item.unitPricePiasters).round()),
                ),
              ),
            );
          },
        ),
        SliverToBoxAdapter(
          child: Card(
            margin: const EdgeInsets.all(12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  TotalRow(
                    'الإجمالي',
                    formatMoney(summary.totalPiasters),
                    bold: true,
                  ),
                  TotalRow('المدفوع', formatMoney(order.paidPiasters)),
                  TotalRow(
                    'المتبقي',
                    formatMoney(summary.remainingPiasters),
                    bold: true,
                    color: summary.remainingPiasters > 0
                        ? AppColors.danger
                        : null,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () => _addPayment(context, ref),
                          icon: const Icon(Icons.payments_outlined),
                          label: const Text('تسجيل دفعة'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _shareOnWhatsApp(ref, items),
                          icon: const Icon(Icons.share),
                          label: const Text('إرسال واتساب'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        VoiceNotesSliver(partyId: order.partyId, orderId: order.id),
        const SliverToBoxAdapter(child: SizedBox(height: 32)),
      ],
    );
  }

  Future<void> _addPayment(BuildContext context, WidgetRef ref) async {
    final db = ref.read(databaseProvider);
    final amount = await showDialog<int>(
      context: context,
      builder: (_) => _PaymentDialog(remaining: summary.remainingPiasters),
    );
    if (amount == null || amount == 0) return;
    await db.updatePaid(summary.order.id, summary.order.paidPiasters + amount);
  }

  Future<void> _shareOnWhatsApp(WidgetRef ref, List<OrderItem> items) async {
    final order = summary.order;
    final party = await ref.read(databaseProvider).getParty(order.partyId);
    final lines = [
      '${order.kind == OrderKind.sale ? 'فاتورة بيع' : 'أمر شراء'} رقم ${order.id}',
      'التاريخ: ${formatDate(order.date)}',
      'السادة: ${summary.partyName}',
      '',
      for (final i in items)
        '- ${i.name}: ${formatQuantity(i.quantity)} ${i.unit} × '
            '${formatMoney(i.unitPricePiasters)}',
      '',
      'الإجمالي: ${formatMoney(summary.totalPiasters)}',
      'المدفوع: ${formatMoney(order.paidPiasters)}',
      'المتبقي: ${formatMoney(summary.remainingPiasters)}',
    ];
    final phone = party.phone;
    final uri = Uri.https(
      'wa.me',
      phone == null ? '/' : '/${toInternationalEgypt(phone)}',
      {'text': lines.join('\n')},
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

class _StatusMenu extends ConsumerWidget {
  const _StatusMenu({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<OrderStatus>(
      tooltip: 'تغيير الحالة',
      onSelected: (s) =>
          ref.read(databaseProvider).updateOrderStatus(order.id, s),
      itemBuilder: (_) => [
        for (final s in OrderStatus.values)
          PopupMenuItem(value: s, child: Text(s.label)),
      ],
      child: Chip(
        avatar: Icon(Icons.circle, size: 12, color: order.status.color),
        label: Text(order.status.label),
        deleteIcon: const Icon(Icons.arrow_drop_down),
        onDeleted: null,
      ),
    );
  }
}

class _PaymentDialog extends StatefulWidget {
  const _PaymentDialog({required this.remaining});

  final int remaining;

  @override
  State<_PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<_PaymentDialog> {
  late final _amount = TextEditingController(
    text: widget.remaining > 0 ? piastersToInput(widget.remaining) : '',
  );

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('تسجيل دفعة'),
      content: TextField(
        controller: _amount,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(
          labelText: 'المبلغ',
          suffixText: 'ج.م',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.pop(context, parseMoneyToPiasters(_amount.text)),
          child: const Text('تسجيل'),
        ),
      ],
    );
  }
}
