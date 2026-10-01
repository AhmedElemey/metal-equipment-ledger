import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database_provider.dart';
import '../../../core/widgets/async_value_view.dart';
import 'order_form_screen.dart';

/// Loads an order + its items once, then shows the form for editing.
final _orderDraftProvider = FutureProvider.autoDispose.family<OrderDraft, int>((
  ref,
  id,
) async {
  final db = ref.watch(databaseProvider);
  return (order: await db.getOrder(id), items: await db.itemsOf(id));
});

class OrderEditScreen extends ConsumerWidget {
  const OrderEditScreen({super.key, required this.orderId});

  final int orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(_orderDraftProvider(orderId));
    return switch (draft) {
      AsyncData(:final value) => OrderFormScreen(existing: value),
      _ => Scaffold(
        appBar: AppBar(),
        body: AsyncValueView(value: draft, data: (_) => const SizedBox()),
      ),
    };
  }
}
