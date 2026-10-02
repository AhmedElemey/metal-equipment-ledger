import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/arabic_search.dart';
import '../../../core/database/app_database.dart';
import '../../../core/formatters.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/empty_state.dart';
import '../data/items_providers.dart';
import 'item_stock_sheet.dart';

/// الأصناف والمخزون: every item with its stock and latest prices.
class ItemsScreen extends ConsumerStatefulWidget {
  const ItemsScreen({super.key, this.lowOnly = false});

  /// Start with only the items at or below their alert level.
  final bool lowOnly;

  @override
  ConsumerState<ItemsScreen> createState() => _ItemsScreenState();
}

class _ItemsScreenState extends ConsumerState<ItemsScreen> {
  final _search = TextEditingController();
  String _query = '';
  late bool _lowOnly = widget.lowOnly;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(itemsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('الأصناف والمخزون')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showItemStockSheet(context),
        icon: const Icon(Icons.add),
        label: const Text('صنف جديد'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: TextField(
              controller: _search,
              decoration: const InputDecoration(
                hintText: 'بحث عن صنف',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: FilterChip(
                label: const Text('أوشكت على النفاد'),
                selected: _lowOnly,
                onSelected: (v) => setState(() => _lowOnly = v),
              ),
            ),
          ),
          Expanded(
            child: AsyncValueView(
              value: items,
              data: (all) {
                final list = [
                  for (final i in all)
                    if ((!_lowOnly || i.isLow) &&
                        (_query.trim().isEmpty ||
                            arabicMatches(i.name, _query)))
                      i,
                ];
                if (list.isEmpty) {
                  return EmptyState(
                    icon: Icons.inventory_2_outlined,
                    message: all.isEmpty
                        ? 'أضف أصنافك وكمياتها بزر "صنف جديد"،\n'
                              'أو ستظهر هنا تلقائياً مع أول طلب'
                        : (_lowOnly
                              ? 'لا توجد أصناف أوشكت على النفاد 👍'
                              : 'لا يوجد صنف بهذا الاسم'),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.only(bottom: 88),
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

  final ItemSummary item;

  @override
  Widget build(BuildContext context) {
    final sale = item.lastSale;
    final purchase = item.lastPurchase;
    return Card(
      child: InkWell(
        onTap: () => showItemStockSheet(context, item: item),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      item.name,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  _StockBadge(item: item),
                ],
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
      ),
    );
  }
}

class _StockBadge extends StatelessWidget {
  const _StockBadge({required this.item});

  final ItemSummary item;

  @override
  Widget build(BuildContext context) {
    if (!item.tracked) {
      return const Text(
        'اضغط للجرد',
        style: TextStyle(color: Colors.black45, fontSize: 12),
      );
    }
    final color = item.isLow ? AppColors.danger : AppColors.steel;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '${item.isLow ? '⚠ ' : ''}${formatQuantity(item.stock)} ${item.unit}',
        style: TextStyle(color: color, fontWeight: FontWeight.bold),
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
