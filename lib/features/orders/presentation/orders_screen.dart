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

class _OrdersScreenState extends ConsumerState<OrdersScreen> {
  OrderKind? _kind;

  @override
  Widget build(BuildContext context) {
    final orders = ref.watch(
      ordersProvider((partyId: null, kind: _kind, limit: null)),
    );
    return Scaffold(
      appBar: AppBar(title: const Text('طلباتي')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/orders/new'),
        icon: const Icon(Icons.add),
        label: const Text('طلب جديد'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: SegmentedButton<OrderKind?>(
              segments: const [
                ButtonSegment(value: null, label: Text('الكل')),
                ButtonSegment(value: OrderKind.sale, label: Text('مبيعات')),
                ButtonSegment(
                  value: OrderKind.purchase,
                  label: Text('مشتريات'),
                ),
              ],
              selected: {_kind},
              onSelectionChanged: (s) => setState(() => _kind = s.first),
            ),
          ),
          Expanded(
            child: AsyncValueView(
              value: orders,
              data: (list) => list.isEmpty
                  ? const EmptyState(
                      icon: Icons.receipt_long_outlined,
                      message: 'لا توجد طلبات بعد.',
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
