import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/database_provider.dart';
import '../../../core/formatters.dart';
import '../../../core/labels.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/total_row.dart';
import '../../orders/data/orders_providers.dart';
import '../../orders/presentation/order_tile.dart';
import '../../voice_notes/data/voice_notes_providers.dart';
import '../../voice_notes/presentation/voice_notes_section.dart';
import '../data/parties_providers.dart';
import 'contact_launcher.dart';

class PartyDetailsScreen extends ConsumerWidget {
  const PartyDetailsScreen({super.key, required this.partyId});

  final int partyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final party = ref.watch(partyProvider(partyId));
    return Scaffold(
      appBar: AppBar(
        title: Text(party.value?.name ?? ''),
        actions: [
          IconButton(
            tooltip: 'تعديل',
            icon: const Icon(Icons.edit),
            onPressed: () => context.push('/parties/$partyId/edit'),
          ),
          IconButton(
            tooltip: 'حذف',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _delete(context, ref),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/orders/new?partyId=$partyId'),
        icon: const Icon(Icons.add),
        label: const Text('طلب جديد'),
      ),
      body: AsyncValueView(
        value: party,
        data: (p) => _PartyBody(party: p),
      ),
    );
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final db = ref.read(databaseProvider);
    final orders = await db.watchOrderSummaries(partyId: partyId).first;
    if (!context.mounted) return;
    if (orders.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('لا يمكن الحذف: يوجد طلبات مسجلة لهذا الطرف'),
        ),
      );
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف العميل / المورد؟'),
        content: const Text('سيتم حذف البيانات والملاحظات الصوتية.'),
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
    final notes = await db.watchVoiceNotes(partyId: partyId).first;
    if (!context.mounted) return;
    context.pop();
    for (final n in notes) {
      await deleteVoiceNote(db, n);
    }
    await db.deleteParty(partyId);
  }
}

class _PartyBody extends ConsumerWidget {
  const _PartyBody({required this.party});

  final Party party;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balance = ref.watch(partyBalanceProvider(party.id)).value;
    final orders =
        ref
            .watch(ordersProvider((partyId: party.id, kind: null, limit: null)))
            .value ??
        const <OrderSummary>[];
    final phone = party.phone;
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
                  Text(
                    party.kind.label,
                    style: const TextStyle(color: Colors.black54),
                  ),
                  if (party.city != null) Text('📍 ${party.city}'),
                  if (phone != null) ...[
                    Text(phone, textDirection: TextDirection.ltr),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () => callPhone(phone),
                            icon: const Icon(Icons.call),
                            label: const Text('اتصال'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.sale,
                            ),
                            onPressed: () => openWhatsApp(phone),
                            icon: const Icon(Icons.chat),
                            label: const Text('واتساب'),
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (party.notes != null) ...[
                    const SizedBox(height: 8),
                    Text(party.notes!),
                  ],
                ],
              ),
            ),
          ),
        ),
        if (balance != null)
          SliverToBoxAdapter(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    TotalRow(
                      'مستحق لنا عنده',
                      formatMoney(balance.dueFromThem),
                      bold: true,
                      color: balance.dueFromThem > 0 ? AppColors.danger : null,
                    ),
                    TotalRow(
                      'مستحق له علينا',
                      formatMoney(balance.dueToThem),
                      bold: true,
                    ),
                  ],
                ),
              ),
            ),
          ),
        VoiceNotesSliver(partyId: party.id),
        SliverToBoxAdapter(
          child: SectionHeader(title: 'سجل الطلبات (${orders.length})'),
        ),
        SliverList.builder(
          itemCount: orders.length,
          itemBuilder: (_, i) => OrderTile(summary: orders[i]),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 88)),
      ],
    );
  }
}
