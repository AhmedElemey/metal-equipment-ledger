import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/database_provider.dart';
import '../../../core/formatters.dart';
import '../../../core/labels.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/total_row.dart';
import '../../accounts/data/accounts_providers.dart';
import '../../accounts/presentation/record_payment_dialog.dart';
import '../../business/data/business_info.dart';
import '../../parties/presentation/contact_launcher.dart';
import '../../voice_notes/presentation/voice_notes_section.dart';
import '../data/order_pdf.dart';
import '../data/orders_providers.dart';

class OrderDetailsScreen extends ConsumerWidget {
  const OrderDetailsScreen({super.key, required this.orderId});

  final int orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(orderProvider(orderId));
    return Scaffold(
      appBar: AppBar(
        title: Text(
          summary.value?.order.status == OrderStatus.quotation
              ? 'عرض سعر رقم $orderId'
              : 'طلب رقم $orderId',
        ),
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
    final isQuotation = order.status == OrderStatus.quotation;
    final items = ref.watch(orderItemsProvider(order.id)).value ?? const [];
    final payments =
        ref.watch(orderPaymentsProvider(order.id)).value ?? const <Payment>[];
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
                    trailing: const Icon(Icons.chevron_right),
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
                  if (!isQuotation) ...[
                    TotalRow('المدفوع', formatMoney(summary.paidPiasters)),
                    TotalRow(
                      'المتبقي',
                      formatMoney(summary.remainingPiasters),
                      bold: true,
                      color: summary.remainingPiasters > 0
                          ? AppColors.danger
                          : null,
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: isQuotation
                            ? FilledButton.icon(
                                style: FilledButton.styleFrom(
                                  backgroundColor: AppColors.sale,
                                ),
                                onPressed: () => _convert(context, ref),
                                icon: const Icon(Icons.check_circle_outline),
                                label: const Text('تحويل لفاتورة بيع'),
                              )
                            : FilledButton.icon(
                                onPressed: () => _addPayment(context, ref),
                                icon: const Icon(Icons.payments_outlined),
                                label: const Text('تسجيل دفعة'),
                              ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _sharePdf(context, ref, items),
                          icon: const Icon(Icons.picture_as_pdf_outlined),
                          label: const Text('مشاركة PDF'),
                        ),
                      ),
                    ],
                  ),
                  TextButton.icon(
                    onPressed: () => _shareOnWhatsApp(ref, items),
                    icon: const Icon(Icons.chat_outlined),
                    label: const Text('إرسال كنص على واتساب'),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (payments.isNotEmpty) ...[
          const SliverToBoxAdapter(child: SectionHeader(title: 'الدفعات')),
          SliverList.builder(
            itemCount: payments.length,
            itemBuilder: (_, i) {
              final p = payments[i];
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.payments_outlined),
                  title: Text(formatMoney(p.amountPiasters)),
                  subtitle: Text([formatDate(p.date), ?p.note].join(' • ')),
                ),
              );
            },
          ),
        ],
        VoiceNotesSliver(partyId: order.partyId, orderId: order.id),
        const SliverToBoxAdapter(child: SizedBox(height: 32)),
      ],
    );
  }

  Future<void> _sharePdf(
    BuildContext context,
    WidgetRef ref,
    List<OrderItem> items,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    try {
      final business = await ref.read(businessInfoProvider.future);
      final party = await ref
          .read(databaseProvider)
          .getParty(summary.order.partyId);
      final bytes = await buildOrderPdf(
        summary: summary,
        items: items,
        party: party,
        business: business,
        font: await loadPdfFont(),
      );
      await Printing.sharePdf(
        bytes: bytes,
        filename: orderPdfFileName(summary),
      );
      if (business.name.isEmpty) {
        messenger.showSnackBar(
          SnackBar(
            content: const Text('أضف اسم النشاط ليظهر أعلى الفاتورة'),
            action: SnackBarAction(
              label: 'الإعدادات',
              onPressed: () => router.go('/settings'),
            ),
          ),
        );
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('تعذر إنشاء ملف PDF: $e')));
    }
  }

  Future<void> _convert(BuildContext context, WidgetRef ref) async {
    final db = ref.read(databaseProvider);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تحويل عرض السعر لفاتورة بيع؟'),
        content: Text(
          'سيصبح طلب بيع بتاريخ اليوم بقيمة '
          '${formatMoney(summary.totalPiasters)} ويُحسب على '
          '${summary.partyName}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('تحويل'),
          ),
        ],
      ),
    );
    if (ok == true) await db.convertQuotation(summary.order.id, DateTime.now());
  }

  Future<void> _addPayment(BuildContext context, WidgetRef ref) async {
    final db = ref.read(databaseProvider);
    final order = summary.order;
    final input = await showRecordPaymentDialog(
      context,
      direction: order.kind == OrderKind.sale
          ? PaymentDirection.received
          : PaymentDirection.paid,
      suggestedAmount: summary.remainingPiasters,
    );
    if (input == null) return;
    await db.addPayment(
      PaymentsCompanion.insert(
        partyId: order.partyId,
        orderId: Value(order.id),
        direction: input.direction,
        amountPiasters: input.amount,
        date: input.date,
        note: Value(input.note),
      ),
    );
  }

  Future<void> _shareOnWhatsApp(WidgetRef ref, List<OrderItem> items) async {
    final order = summary.order;
    final party = await ref.read(databaseProvider).getParty(order.partyId);
    final lines = [
      '${orderDocumentTitle(summary)} رقم ${order.id}',
      'التاريخ: ${formatDate(order.date)}',
      'السادة: ${summary.partyName}',
      '',
      for (final i in items)
        '- ${i.name}: ${formatQuantity(i.quantity)} ${i.unit} × '
            '${formatMoney(i.unitPricePiasters)}',
      '',
      'الإجمالي: ${formatMoney(summary.totalPiasters)}',
      'المدفوع: ${formatMoney(summary.paidPiasters)}',
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
    final chip = Chip(
      avatar: Icon(Icons.circle, size: 12, color: order.status.color),
      label: Text(order.status.label),
    );
    // A quotation only leaves that state through "تحويل لفاتورة بيع".
    if (order.status == OrderStatus.quotation) return chip;
    return PopupMenuButton<OrderStatus>(
      tooltip: 'تغيير الحالة',
      onSelected: (s) =>
          ref.read(databaseProvider).updateOrderStatus(order.id, s),
      itemBuilder: (_) => [
        for (final s in OrderStatus.values)
          if (s != OrderStatus.quotation)
            PopupMenuItem(value: s, child: Text(s.label)),
      ],
      child: chip,
    );
  }
}
