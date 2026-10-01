import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/database_provider.dart';
import '../../../core/formatters.dart';
import '../../../core/widgets/total_row.dart';
import '../../parties/data/parties_providers.dart';

/// The data needed to edit an existing order.
typedef OrderDraft = ({Order order, List<OrderItem> items});

class OrderFormScreen extends ConsumerStatefulWidget {
  const OrderFormScreen({
    super.key,
    this.existing,
    this.initialPartyId,
    this.initialQuotation = false,
  });

  final OrderDraft? existing;
  final int? initialPartyId;
  final bool initialQuotation;

  @override
  ConsumerState<OrderFormScreen> createState() => _OrderFormScreenState();
}

class _ItemControllers {
  _ItemControllers([OrderItem? item])
    : name = TextEditingController(text: item?.name),
      quantity = TextEditingController(
        text: item == null ? '1' : formatQuantity(item.quantity),
      ),
      unit = TextEditingController(text: item?.unit ?? 'قطعة'),
      price = TextEditingController(
        text: item == null ? '' : piastersToInput(item.unitPricePiasters),
      );

  final TextEditingController name;
  final TextEditingController quantity;
  final TextEditingController unit;
  final TextEditingController price;

  int get lineTotal {
    final q = parseNumber(quantity.text) ?? 0;
    final pr = parseMoneyToPiasters(price.text) ?? 0;
    return (q * pr).round();
  }

  void dispose() {
    name.dispose();
    quantity.dispose();
    unit.dispose();
    price.dispose();
  }
}

class _OrderFormScreenState extends ConsumerState<OrderFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late OrderKind _kind = widget.existing?.order.kind ?? OrderKind.sale;
  late int? _partyId = widget.existing?.order.partyId ?? widget.initialPartyId;
  // Only chosen for new orders; converting a quotation is its own action.
  late bool _quotation = widget.initialQuotation;
  late DateTime _date = widget.existing?.order.date ?? DateTime.now();
  late final _items = widget.existing == null
      ? [_ItemControllers()]
      : widget.existing!.items.map(_ItemControllers.new).toList();
  // Down payment — new orders only; later payments go through
  // "تسجيل دفعة" so each one keeps its own date.
  final _paid = TextEditingController();
  late final _notes = TextEditingController(text: widget.existing?.order.notes);
  bool _saving = false;

  @override
  void dispose() {
    for (final i in _items) {
      i.dispose();
    }
    _paid.dispose();
    _notes.dispose();
    super.dispose();
  }

  bool get _isQuotation => widget.existing == null
      ? _quotation && _kind == OrderKind.sale
      : widget.existing!.order.status == OrderStatus.quotation;

  int get _total => _items.fold(0, (sum, i) => sum + i.lineTotal);

  void _addItem() => setState(() => _items.add(_ItemControllers()));

  void _removeItem(int index) {
    final removed = _items.removeAt(index);
    setState(() {});
    // Dispose after the frame so the removed fields stop listening first.
    WidgetsBinding.instance.addPostFrameCallback((_) => removed.dispose());
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2015),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null || !mounted) return;
    setState(() => _date = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_partyId == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('اختر العميل / المورد')));
      return;
    }
    setState(() => _saving = true);
    final existing = widget.existing?.order;
    try {
      final id = await ref.read(databaseProvider).saveOrder(
        OrdersCompanion(
          id: existing == null ? const Value.absent() : Value(existing.id),
          partyId: Value(_partyId!),
          kind: Value(_kind),
          status: Value(
            existing?.status ??
                (_isQuotation ? OrderStatus.quotation : OrderStatus.pending),
          ),
          date: Value(_date),
          notes: Value(_notes.text.trim().isEmpty ? null : _notes.text.trim()),
          createdAt: existing == null
              ? const Value.absent()
              : Value(existing.createdAt),
        ),
        [
          for (final i in _items)
            OrderItemsCompanion.insert(
              orderId: 0, // replaced with the real id in saveOrder
              name: i.name.text.trim(),
              quantity: parseNumber(i.quantity.text)!,
              unit: Value(
                i.unit.text.trim().isEmpty ? 'قطعة' : i.unit.text.trim(),
              ),
              unitPricePiasters: parseMoneyToPiasters(i.price.text)!,
            ),
        ],
        downPayment: existing == null && !_isQuotation
            ? parseMoneyToPiasters(_paid.text) ?? 0
            : 0,
      );
      if (!mounted) return;
      if (existing == null) {
        context.pushReplacement('/orders/$id');
      } else {
        context.pop();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('تعذر الحفظ: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final parties = ref.watch(partiesProvider('')).value ?? const <Party>[];
    final total = _total;
    final isNew = widget.existing == null;
    final quotation = _isQuotation;
    // A down payment only makes sense on a real new order.
    final takesPayment = isNew && !quotation;
    final paid = isNew ? parseMoneyToPiasters(_paid.text) ?? 0 : 0;
    return Scaffold(
      appBar: AppBar(
        title: Text(switch ((isNew, quotation)) {
          (true, true) => 'عرض سعر جديد',
          (true, false) => 'طلب جديد',
          (false, true) => 'تعديل عرض السعر',
          (false, false) => 'تعديل الطلب',
        }),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SegmentedButton<OrderKind>(
              segments: [
                for (final k in OrderKind.values)
                  ButtonSegment(
                    value: k,
                    label: Text(
                      k == OrderKind.sale ? 'بيع لعميل' : 'شراء من مورد',
                    ),
                  ),
              ],
              selected: {_kind},
              // Locked when editing: existing payments depend on the kind.
              onSelectionChanged: widget.existing == null
                  ? (s) => setState(() => _kind = s.first)
                  : null,
            ),
            if (isNew && _kind == OrderKind.sale)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('عرض سعر فقط'),
                subtitle: const Text('لا يُحسب على العميل حتى يتم تأكيده'),
                value: _quotation,
                onChanged: (v) => setState(() => _quotation = v),
              ),
            const SizedBox(height: 16),
            DropdownMenu<int>(
              // Re-key so the menu shows the party once the list has loaded.
              key: ValueKey(parties.length),
              initialSelection: _partyId,
              expandedInsets: EdgeInsets.zero,
              enableFilter: true,
              requestFocusOnTap: true,
              label: const Text('العميل / المورد *'),
              leadingIcon: const Icon(Icons.person_search),
              dropdownMenuEntries: [
                for (final p in parties)
                  DropdownMenuEntry(value: p.id, label: p.name),
              ],
              onSelected: (id) => setState(() => _partyId = id),
            ),
            if (parties.isEmpty)
              TextButton.icon(
                onPressed: () => context.push('/parties/new'),
                icon: const Icon(Icons.person_add_alt_1),
                label: const Text('أضف عميل / مورد أولاً'),
              ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event),
              title: Text('التاريخ: ${formatDate(_date)}'),
              trailing: const Icon(Icons.edit_calendar),
              onTap: _pickDate,
            ),
            const Divider(),
            Text('الأصناف', style: Theme.of(context).textTheme.titleMedium),
            for (var i = 0; i < _items.length; i++)
              _ItemFields(
                key: ObjectKey(_items[i]),
                controllers: _items[i],
                onChanged: () => setState(() {}),
                onRemove: _items.length > 1 ? () => _removeItem(i) : null,
              ),
            TextButton.icon(
              onPressed: _addItem,
              icon: const Icon(Icons.add),
              label: const Text('إضافة صنف'),
            ),
            const Divider(),
            if (takesPayment)
              TextFormField(
                controller: _paid,
                decoration: InputDecoration(
                  labelText: _kind == OrderKind.sale
                      ? 'دفعة مقدمة من العميل (اختياري)'
                      : 'دفعة مقدمة للمورد (اختياري)',
                  suffixText: 'ج.م',
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                onChanged: (_) => setState(() {}),
                validator: (v) =>
                    (v != null &&
                        v.trim().isNotEmpty &&
                        parseMoneyToPiasters(v) == null)
                    ? 'رقم غير صحيح'
                    : null,
              ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _notes,
              decoration: const InputDecoration(labelText: 'ملاحظات'),
              maxLines: 2,
            ),
            const SizedBox(height: 16),
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    TotalRow('الإجمالي', formatMoney(total), bold: true),
                    if (takesPayment) ...[
                      TotalRow('المدفوع', formatMoney(paid)),
                      TotalRow(
                        'المتبقي',
                        formatMoney(total - paid),
                        bold: true,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.save),
              label: Text(quotation ? 'حفظ عرض السعر' : 'حفظ الطلب'),
              style: FilledButton.styleFrom(minimumSize: const Size(0, 52)),
            ),
          ],
        ),
      ),
    );
  }
}

class _ItemFields extends StatelessWidget {
  const _ItemFields({
    super.key,
    required this.controllers,
    required this.onChanged,
    required this.onRemove,
  });

  final _ItemControllers controllers;
  final VoidCallback onChanged;
  final VoidCallback? onRemove;

  String? _requiredNumber(String? v) =>
      parseNumber(v ?? '') == null ? 'مطلوب' : null;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: controllers.name,
                    decoration: const InputDecoration(
                      labelText: 'اسم الصنف *',
                      hintText: 'مثال: صاج حديد 2 مم',
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'مطلوب' : null,
                  ),
                ),
                if (onRemove != null)
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: 'حذف الصنف',
                    onPressed: onRemove,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: controllers.quantity,
                    decoration: const InputDecoration(labelText: 'الكمية'),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: (_) => onChanged(),
                    validator: _requiredNumber,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    controller: controllers.unit,
                    decoration: const InputDecoration(labelText: 'الوحدة'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: controllers.price,
                    decoration: const InputDecoration(
                      labelText: 'سعر الوحدة',
                      suffixText: 'ج.م',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: (_) => onChanged(),
                    validator: _requiredNumber,
                  ),
                ),
              ],
            ),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('الإجمالي: ${formatMoney(controllers.lineTotal)}'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
