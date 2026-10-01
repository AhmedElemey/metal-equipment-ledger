import 'package:flutter/material.dart';

import '../../../core/database/app_database.dart';
import '../../../core/formatters.dart';

typedef PaymentInput = ({
  int amount,
  DateTime date,
  String? note,
  PaymentDirection direction,
});

/// Asks for a payment. Shows the received/paid choice only when
/// [direction] is null (a party who is both client and supplier).
Future<PaymentInput?> showRecordPaymentDialog(
  BuildContext context, {
  PaymentDirection? direction,
  int? suggestedAmount,
}) {
  return showDialog<PaymentInput>(
    context: context,
    builder: (_) => _RecordPaymentDialog(
      direction: direction,
      suggestedAmount: suggestedAmount,
    ),
  );
}

/// Received from a client, paid to a supplier, ask for "both".
PaymentDirection? directionFor(PartyKind kind) => switch (kind) {
  PartyKind.buyer => PaymentDirection.received,
  PartyKind.seller => PaymentDirection.paid,
  PartyKind.both => null,
};

class _RecordPaymentDialog extends StatefulWidget {
  const _RecordPaymentDialog({this.direction, this.suggestedAmount});

  final PaymentDirection? direction;
  final int? suggestedAmount;

  @override
  State<_RecordPaymentDialog> createState() => _RecordPaymentDialogState();
}

class _RecordPaymentDialogState extends State<_RecordPaymentDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _amount = TextEditingController(
    text: (widget.suggestedAmount ?? 0) > 0
        ? piastersToInput(widget.suggestedAmount!)
        : '',
  );
  final _note = TextEditingController();
  late PaymentDirection _direction =
      widget.direction ?? PaymentDirection.received;
  DateTime _date = DateTime.now();

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2015),
      lastDate: DateTime.now(),
    );
    if (picked == null || !mounted) return;
    setState(() => _date = picked);
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final note = _note.text.trim();
    Navigator.pop<PaymentInput>(context, (
      amount: parseMoneyToPiasters(_amount.text)!,
      date: _date,
      note: note.isEmpty ? null : note,
      direction: _direction,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('تسجيل دفعة'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.direction == null) ...[
                SegmentedButton<PaymentDirection>(
                  segments: const [
                    ButtonSegment(
                      value: PaymentDirection.received,
                      label: Text('استلمت منه'),
                    ),
                    ButtonSegment(
                      value: PaymentDirection.paid,
                      label: Text('دفعت له'),
                    ),
                  ],
                  selected: {_direction},
                  onSelectionChanged: (s) =>
                      setState(() => _direction = s.first),
                ),
                const SizedBox(height: 12),
              ],
              TextFormField(
                controller: _amount,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'المبلغ',
                  suffixText: 'ج.م',
                ),
                validator: (v) => (parseMoneyToPiasters(v ?? '') ?? 0) <= 0
                    ? 'أدخل مبلغ صحيح'
                    : null,
              ),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event),
                title: Text(formatDate(_date)),
                onTap: _pickDate,
              ),
              TextFormField(
                controller: _note,
                decoration: const InputDecoration(
                  labelText: 'ملاحظة (اختياري)',
                  hintText: 'مثال: كاش / تحويل بنكي / شيك',
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        FilledButton(onPressed: _submit, child: const Text('تسجيل')),
      ],
    );
  }
}
