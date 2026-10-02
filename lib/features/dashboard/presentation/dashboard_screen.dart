import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/database_provider.dart';
import '../../../core/formatters.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/section_header.dart';
import '../../cheques/presentation/cheques_screen.dart';
import '../../items/data/items_providers.dart';
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
    final chequesDue = ref.watch(chequesDueSoonProvider).value ?? 0;
    final lowStock = ref.watch(
      itemsProvider.select(
        (items) => items.value?.where((i) => i.isLow).length ?? 0,
      ),
    );
    final recent =
        ref
            .watch(
              ordersProvider((
                partyId: null,
                kind: null,
                quotations: false,
                limit: 10,
              )),
            )
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
                _StatCard(
                  'مستحقات لنا',
                  stats?.receivables,
                  AppColors.orange,
                  onTap: () => context.push('/collections'),
                ),
                _StatCard('مستحقات علينا', stats?.payables, AppColors.danger),
              ],
            ),
          ),
          if ((stats?.debtors ?? 0) > 0)
            SliverToBoxAdapter(
              child: Card(
                color: const Color(0xFFFFF3E0),
                child: ListTile(
                  leading: const Icon(
                    Icons.notifications_active_outlined,
                    color: AppColors.orange,
                  ),
                  title: Text('التحصيل: ${stats!.debtors} عميل عليهم مستحقات'),
                  subtitle: const Text('اضغط لعرض القائمة وإرسال تذكير'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/collections'),
                ),
              ),
            ),
          if (chequesDue > 0)
            SliverToBoxAdapter(
              child: Card(
                color: const Color(0xFFE3F2FD),
                child: ListTile(
                  leading: const Icon(
                    Icons.request_page_outlined,
                    color: AppColors.purchase,
                  ),
                  title: Text(
                    'الشيكات: $chequesDue شيك يستحق خلال '
                    '$chequeWarningDays أيام',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/cheques'),
                ),
              ),
            ),
          if (lowStock > 0)
            SliverToBoxAdapter(
              child: Card(
                color: const Color(0xFFFFEBEE),
                child: ListTile(
                  leading: const Icon(
                    Icons.inventory_2_outlined,
                    color: AppColors.danger,
                  ),
                  title: Text('المخزون: $lowStock صنف أوشك على النفاد'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/items?low=1'),
                ),
              ),
            ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
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
          const SliverToBoxAdapter(child: SectionHeader(title: 'أدوات')),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            sliver: SliverGrid.count(
              crossAxisCount: 3,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 1.15,
              children: const [
                _ToolTile(Icons.inventory_2_outlined, 'المخزون', '/items'),
                _ToolTile(
                  Icons.notifications_active_outlined,
                  'التحصيل',
                  '/collections',
                ),
                _ToolTile(Icons.money_off_outlined, 'المصروفات', '/expenses'),
                _ToolTile(
                  Icons.bar_chart_outlined,
                  'التقرير الشهري',
                  '/report',
                ),
                _ToolTile(Icons.request_page_outlined, 'الشيكات', '/cheques'),
              ],
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

class _ToolTile extends StatelessWidget {
  const _ToolTile(this.icon, this.label, this.route);

  final IconData icon;
  final String label;
  final String route;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push(route),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 32, color: AppColors.steel),
            const SizedBox(height: 6),
            Text(label, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard(this.title, this.piasters, this.color, {this.onTap});

  final String title;
  final int? piasters;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            border: BorderDirectional(
              start: BorderSide(color: color, width: 5),
            ),
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
      ),
    );
  }
}
