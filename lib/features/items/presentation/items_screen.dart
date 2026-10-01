import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/arabic_search.dart';
import '../../../core/database/app_database.dart';
import '../../../core/formatters.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/empty_state.dart';
import '../data/items_providers.dart';

/// الأصناف والأسعار: every item from past orders with its latest prices.
class ItemsScreen extends ConsumerStatefulWidget {
  const ItemsScreen({super.key});

  @override
  ConsumerState<ItemsScreen> createState() => _ItemsScreenState();
}

class _ItemsScreenState extends ConsumerState<ItemsScreen> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(itemPricesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('الأصناف والأسعار')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _search,
              decoration: const InputDecoration(
                hintText: 'بحث عن صنف',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Expanded(
            child: AsyncValueView(
              value: items,
              data: (all) {
                final list = _query.trim().isEmpty
                    ? all
                    : all.where((i) => arabicMatches(i.name, _query)).toList();
                if (list.isEmpty) {
                  return EmptyState(
                    icon: Icons.inventory_2_outlined,
                    message: all.isEmpty
                        ? 'تظهر الأصناف هنا بعد تسجيل أول طلب'
                        : 'لا يوجد صنف بهذا الاسم',
                  );
                }
                return ListView.builder(
                  itemCount: list.length,
                  itemBuilder: (_, i) => _ItemTile(item: list[i]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ItemTile extends StatelessWidget {
  const _ItemTile({required this.item});

  final ItemPrice item;

  @override
  Widget build(BuildContext context) {
    final sale = item.lastSale;
    final purchase = item.lastPurchase;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${item.name} (${item.unit})',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: _PriceCell(
                    label: 'آخر سعر شراء',
                    price: purchase,
                    at: item.lastPurchaseAt,
                    color: AppColors.purchase,
                  ),
                ),
                Expanded(
                  child: _PriceCell(
                    label: 'آخر سعر بيع',
                    price: sale,
                    at: item.lastSaleAt,
                    color: AppColors.sale,
                  ),
                ),
              ],
            ),
            if (sale != null && purchase != null && sale < purchase)
              const Text(
                '⚠ آخر بيع كان أقل من آخر شراء',
                style: TextStyle(color: AppColors.danger),
              ),
          ],
        ),
      ),
    );
  }
}

class _PriceCell extends StatelessWidget {
  const _PriceCell({
    required this.label,
    required this.price,
    required this.at,
    required this.color,
  });

  final String label;
  final int? price;
  final DateTime? at;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.black54)),
        Text(
          price == null ? '—' : formatMoney(price!),
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        if (at != null)
          Text(
            formatDate(at!),
            style: const TextStyle(color: Colors.black45, fontSize: 12),
          ),
      ],
    );
  }
}
