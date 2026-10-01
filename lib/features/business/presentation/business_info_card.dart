import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/business_info.dart';

/// Settings card for the details printed on invoices and quotations.
class BusinessInfoCard extends ConsumerWidget {
  const BusinessInfoCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = ref.watch(businessInfoProvider).value;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: info == null
            ? const Center(child: CircularProgressIndicator())
            : _BusinessInfoForm(initial: info),
      ),
    );
  }
}

class _BusinessInfoForm extends ConsumerStatefulWidget {
  const _BusinessInfoForm({required this.initial});

  final BusinessInfo initial;

  @override
  ConsumerState<_BusinessInfoForm> createState() => _BusinessInfoFormState();
}

class _BusinessInfoFormState extends ConsumerState<_BusinessInfoForm> {
  late final _name = TextEditingController(text: widget.initial.name);
  late final _phone = TextEditingController(text: widget.initial.phone);
  late final _address = TextEditingController(text: widget.initial.address);
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _address.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    await saveBusinessInfo((
      name: _name.text,
      phone: _phone.text,
      address: _address.text,
    ));
    if (!mounted) return;
    setState(() => _saving = false);
    FocusScope.of(context).unfocus();
    messenger.showSnackBar(
      const SnackBar(content: Text('تم حفظ بيانات النشاط')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'بيانات النشاط (تظهر في الفواتير وعروض الأسعار)',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _name,
          decoration: const InputDecoration(labelText: 'اسم النشاط'),
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _phone,
          decoration: const InputDecoration(labelText: 'التليفون'),
          keyboardType: TextInputType.phone,
          textDirection: TextDirection.ltr,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _address,
          decoration: const InputDecoration(labelText: 'العنوان'),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: const Icon(Icons.save),
          label: const Text('حفظ'),
        ),
      ],
    );
  }
}
