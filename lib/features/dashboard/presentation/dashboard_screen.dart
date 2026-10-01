import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/database_provider.dart';
import '../../../core/formatters.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/section_header.dart';
import '../../orders/data/orders_providers.dart';
import '../../orders/presentation/order_tile.dart';

final dashboardProvider = StreamProvider.autoDispose<DashboardStats>(
  (ref) => ref.watch(databaseProvider).watchDashboard(DateTime.now()),
);

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(dashboardProvider).value;
    final recent =
        ref
            .watch(ordersProvider((partyId: null, kind: null, limit: 10)))
            .value ??
        const <OrderSummary>[];
    return Scaffold(
      appBar: AppBar(title: const Text('دفتر المعدات')),
      body: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.all(12),
            sliver: SliverGrid.count(
              crossAxisCount: 2,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 1.6,
              children: [
                _StatCard('مبيعات اليوم', stats?.todaySales, AppColors.sale),
                _StatCard(
                  'مشتريات اليوم',
                  stats?.todayPurchases,
                  AppColors.purchase,
                ),
                _StatCard('مستحقات لنا', stats?.receivables, AppColors.orange),
                _StatCard('مستحقات علينا', stats?.payables, AppColors.danger),
              ],
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.orange,
                        minimumSize: const Size(0, 52),
                      ),
                      onPressed: () => context.push('/orders/new'),
                      icon: const Icon(Icons.add_shopping_cart),
                      label: const Text('طلب جديد'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 52),
                      ),
                      onPressed: () => context.push('/parties/new'),
                      icon: const Icon(Icons.person_add_alt_1),
                      label: const Text('عميل / مورد'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: SectionHeader(
              title:
                  'آخر الطلبات'
                  '${stats == null ? '' : ' • ${stats.openOrders} طلب مفتوح'}',
            ),
          ),
          if (recent.isEmpty)
            const SliverToBoxAdapter(
              child: EmptyState(
                icon: Icons.receipt_long_outlined,
                message: 'ابدأ بإضافة أول طلب بيع أو شراء',
              ),
            ),
          SliverList.builder(
            itemCount: recent.length,
            itemBuilder: (_, i) => OrderTile(summary: recent[i]),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard(this.title, this.piasters, this.color);

  final String title;
  final int? piasters;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Container(
        decoration: BoxDecoration(
          border: BorderDirectional(start: BorderSide(color: color, width: 5)),
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(title, style: const TextStyle(color: Colors.black54)),
            const SizedBox(height: 4),
            FittedBox(
              child: Text(
                piasters == null ? '…' : formatMoney(piasters!),
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
