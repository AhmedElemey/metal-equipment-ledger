import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/database/app_database.dart';
import '../../../core/labels.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/empty_state.dart';
import '../data/parties_providers.dart';

class PartiesScreen extends ConsumerStatefulWidget {
  const PartiesScreen({super.key});

  @override
  ConsumerState<PartiesScreen> createState() => _PartiesScreenState();
}

class _PartiesScreenState extends ConsumerState<PartiesScreen> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final parties = ref.watch(partiesProvider(_query));
    return Scaffold(
      appBar: AppBar(title: const Text('العملاء والموردين')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'parties-add',
        onPressed: () => context.push('/parties/new'),
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('إضافة'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _search,
              decoration: const InputDecoration(
                hintText: 'بحث بالاسم أو رقم التليفون',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Expanded(
            child: AsyncValueView(
              value: parties,
              data: (list) => list.isEmpty
                  ? const EmptyState(
                      icon: Icons.people_outline,
                      message:
                          'لا يوجد عملاء أو موردين بعد.\nاضغط "إضافة" للبدء.',
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: 88),
                      itemCount: list.length,
                      itemBuilder: (_, i) => _PartyTile(party: list[i]),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PartyTile extends StatelessWidget {
  const _PartyTile({required this.party});

  final Party party;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(child: Text(party.name.characters.first)),
        title: Text(party.name),
        subtitle: Text(
          [party.kind.label, ?party.phone, ?party.city].join(' • '),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.push('/parties/${party.id}'),
      ),
    );
  }
}
