import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/accounts/presentation/collections_screen.dart';
import '../features/accounts/presentation/statement_screen.dart';
import '../features/backup/presentation/settings_screen.dart';
import '../features/expenses/presentation/expenses_screen.dart';
import '../features/items/presentation/items_screen.dart';
import '../features/dashboard/presentation/dashboard_screen.dart';
import '../features/orders/presentation/order_details_screen.dart';
import '../features/orders/presentation/order_edit_screen.dart';
import '../features/orders/presentation/order_form_screen.dart';
import '../features/orders/presentation/orders_screen.dart';
import '../features/parties/presentation/parties_screen.dart';
import '../features/parties/presentation/party_details_screen.dart';
import '../features/parties/presentation/party_edit_screen.dart';
import '../features/parties/presentation/party_form_screen.dart';

int _id(GoRouterState s) => int.parse(s.pathParameters['id']!);

final router = GoRouter(
  routes: [
    // Full-screen pages, listed before the shell so they win the match.
    GoRoute(
      path: '/orders/new',
      builder: (_, s) => OrderFormScreen(
        initialPartyId: int.tryParse(s.uri.queryParameters['partyId'] ?? ''),
        initialQuotation: s.uri.queryParameters['quotation'] == '1',
      ),
    ),
    GoRoute(
      path: '/orders/:id',
      builder: (_, s) => OrderDetailsScreen(orderId: _id(s)),
    ),
    GoRoute(
      path: '/orders/:id/edit',
      builder: (_, s) => OrderEditScreen(orderId: _id(s)),
    ),
    GoRoute(
      path: '/parties/:id/statement',
      builder: (_, s) => StatementScreen(partyId: _id(s)),
    ),
    GoRoute(path: '/collections', builder: (_, _) => const CollectionsScreen()),
    GoRoute(path: '/expenses', builder: (_, _) => const ExpensesScreen()),
    GoRoute(
      path: '/items',
      builder: (_, s) =>
          ItemsScreen(lowOnly: s.uri.queryParameters['low'] == '1'),
    ),
    GoRoute(path: '/parties/new', builder: (_, _) => const PartyFormScreen()),
    GoRoute(
      path: '/parties/:id',
      builder: (_, s) => PartyDetailsScreen(partyId: _id(s)),
    ),
    GoRoute(
      path: '/parties/:id/edit',
      builder: (_, s) => PartyEditScreen(partyId: _id(s)),
    ),
    StatefulShellRoute.indexedStack(
      builder: (_, _, shell) => _HomeShell(shell: shell),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(path: '/', builder: (_, _) => const DashboardScreen()),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(path: '/orders', builder: (_, _) => const OrdersScreen()),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(path: '/parties', builder: (_, _) => const PartiesScreen()),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/settings',
              builder: (_, _) => const SettingsScreen(),
            ),
          ],
        ),
      ],
    ),
  ],
);

class _HomeShell extends StatelessWidget {
  const _HomeShell({required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: shell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: (i) =>
            shell.goBranch(i, initialLocation: i == shell.currentIndex),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard), label: 'الرئيسية'),
          NavigationDestination(
            icon: Icon(Icons.receipt_long),
            label: 'طلباتي',
          ),
          NavigationDestination(icon: Icon(Icons.people), label: 'العملاء'),
          NavigationDestination(icon: Icon(Icons.settings), label: 'الإعدادات'),
        ],
      ),
    );
  }
}
