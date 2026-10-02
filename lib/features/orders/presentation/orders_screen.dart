import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/database/app_database.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/empty_state.dart';
import '../data/orders_providers.dart';
import 'order_tile.dart';

class OrdersScreen extends ConsumerStatefulWidget {
  const OrdersScreen({super.key});

  @override
  ConsumerState<OrdersScreen> createState() => _OrdersScreenState();
}

enum _Filter { all, sale, purchase, quotations }

class _OrdersScreenState extends ConsumerState<OrdersScreen> {
  _Filter _filter = _Filter.all;

  @override
  Widget build(BuildContext context) {
    final orders = ref.watch(
      ordersProvider((
        partyId: null,
        kind: switch (_filter) {
          _Filter.sale => OrderKind.sale,
          _Filter.purchase => OrderKind.purchase,
          _ => null,
        },
        quotations: _filter == _Filter.quotations,
        limit: null,
      )),
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('طلباتي'),
        actions: [
          IconButton(
            tooltip: 'الأصناف والمخزون',
            icon: const Icon(Icons.inventory_2_outlined),
            onPressed: () => context.push('/items'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'orders-add',
        onPressed: () => context.push(
          _filter == _Filter.quotations
              ? '/orders/new?quotation=1'
              : '/orders/new',
        ),
        icon: const Icon(Icons.add),
        label: Text(
          _filter == _Filter.quotations ? 'عرض سعر جديد' : 'طلب جديد',
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: SegmentedButton<_Filter>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: _Filter.all, label: Text('الكل')),
                ButtonSegment(value: _Filter.sale, label: Text('بيع')),
                ButtonSegment(value: _Filter.purchase, label: Text('شراء')),
                ButtonSegment(
                  value: _Filter.quotations,
                  label: Text('عروض أسعار'),
                ),
              ],
              selected: {_filter},
              onSelectionChanged: (s) => setState(() => _filter = s.first),
            ),
          ),
          Expanded(
            child: AsyncValueView(
              value: orders,
              data: (list) => list.isEmpty
                  ? EmptyState(
                      icon: Icons.receipt_long_outlined,
                      message: _filter == _Filter.quotations
                          ? 'لا توجد عروض أسعار.'
                          : 'لا توجد طلبات بعد.',
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: 88),
                      itemCount: list.length,
                      itemBuilder: (_, i) => OrderTile(summary: list[i]),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
