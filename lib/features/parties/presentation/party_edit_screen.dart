import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/async_value_view.dart';
import '../data/parties_providers.dart';
import 'party_form_screen.dart';

class PartyEditScreen extends ConsumerWidget {
  const PartyEditScreen({super.key, required this.partyId});

  final int partyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final party = ref.watch(partyProvider(partyId));
    return switch (party) {
      // Built once from the first value; later DB updates don't reset the form.
      AsyncData(:final value) => PartyFormScreen(
        key: ValueKey(partyId),
        existing: value,
      ),
      _ => Scaffold(
        appBar: AppBar(),
        body: AsyncValueView(value: party, data: (_) => const SizedBox()),
      ),
    };
  }
}
