import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/database/app_database.dart';
import '../../../core/formatters.dart';
import '../../../core/labels.dart';
import '../../../core/theme.dart';

class OrderTile extends StatelessWidget {
  const OrderTile({super.key, required this.summary});

  final OrderSummary summary;

  @override
  Widget build(BuildContext context) {
    final order = summary.order;
    final remaining = summary.remainingPiasters;
    return Card(
      child: ListTile(
        onTap: () => context.push('/orders/${order.id}'),
        leading: CircleAvatar(
          backgroundColor: order.kind.color.withValues(alpha: 0.12),
          foregroundColor: order.kind.color,
          child: Icon(
            order.kind == OrderKind.sale ? Icons.north_east : Icons.south_west,
          ),
        ),
        title: Text('${order.kind.label} • ${summary.partyName}'),
        subtitle: Text(
          '#${order.id} • ${formatDate(order.date)} • ${order.status.label}',
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              formatMoney(summary.totalPiasters),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            if (remaining > 0 && order.status != OrderStatus.cancelled)
              Text(
                'متبقي ${formatMoney(remaining)}',
                style: const TextStyle(color: AppColors.danger, fontSize: 12),
              ),
          ],
        ),
      ),
    );
  }
}
