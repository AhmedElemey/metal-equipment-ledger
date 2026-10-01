import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/database_provider.dart';
import '../../../core/labels.dart';

/// Add a new party, or edit [existing].
class PartyFormScreen extends ConsumerStatefulWidget {
  const PartyFormScreen({super.key, this.existing});

  final Party? existing;

  @override
  ConsumerState<PartyFormScreen> createState() => _PartyFormScreenState();
}

class _PartyFormScreenState extends ConsumerState<PartyFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.existing?.name);
  late final _phone = TextEditingController(text: widget.existing?.phone);
  late final _city = TextEditingController(text: widget.existing?.city);
  late final _notes = TextEditingController(text: widget.existing?.notes);
  late PartyKind _kind = widget.existing?.kind ?? PartyKind.buyer;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _city.dispose();
    _notes.dispose();
    super.dispose();
  }

  String? _orNull(TextEditingController c) =>
      c.text.trim().isEmpty ? null : c.text.trim();

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final existing = widget.existing;
    try {
      await ref
          .read(databaseProvider)
          .saveParty(
            PartiesCompanion(
              id: existing == null ? const Value.absent() : Value(existing.id),
              name: Value(_name.text.trim()),
              phone: Value(_orNull(_phone)),
              city: Value(_orNull(_city)),
              kind: Value(_kind),
              notes: Value(_orNull(_notes)),
            ),
          );
      if (!mounted) return;
      context.pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('تعذر الحفظ: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null ? 'إضافة عميل / مورد' : 'تعديل'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SegmentedButton<PartyKind>(
              segments: [
                for (final k in PartyKind.values)
                  ButtonSegment(value: k, label: Text(k.label)),
              ],
              selected: {_kind},
              onSelectionChanged: (s) => setState(() => _kind = s.first),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'الاسم *'),
              textInputAction: TextInputAction.next,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'الاسم مطلوب' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phone,
              decoration: const InputDecoration(labelText: 'رقم التليفون'),
              keyboardType: TextInputType.phone,
              textDirection: TextDirection.ltr,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _city,
              decoration: const InputDecoration(labelText: 'المدينة / المنطقة'),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _notes,
              decoration: const InputDecoration(labelText: 'ملاحظات'),
              maxLines: 3,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.save),
              label: const Text('حفظ'),
              style: FilledButton.styleFrom(minimumSize: const Size(0, 52)),
            ),
          ],
        ),
      ),
    );
  }
}
