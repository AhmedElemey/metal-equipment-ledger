import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/database_provider.dart';
import '../../../core/formatters.dart';

/// Stock count (جرد), unit, low-stock limit and last prices for one item —
/// or, with [item] null, a new item with its opening stock.
Future<void> showItemStockSheet(BuildContext context, {ItemSummary? item}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    // The sheet's own context: it sees the keyboard as it opens.
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
      ),
      child: _ItemStockSheet(item: item),
    ),
  );
}

class _ItemStockSheet extends ConsumerStatefulWidget {
  const _ItemStockSheet({this.item});

  final ItemSummary? item;

  @override
  ConsumerState<_ItemStockSheet> createState() => _ItemStockSheetState();
}

class _ItemStockSheetState extends ConsumerState<_ItemStockSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.item?.name);
  late final _unit = TextEditingController(text: widget.item?.unit ?? 'قطعة');
  late final _actual = TextEditingController(
    text: widget.item?.tracked ?? false
        ? formatQuantity(widget.item!.stock)
        : '',
  );
  late final _min = TextEditingController(
    text: widget.item?.minQuantity == null
        ? ''
        : formatQuantity(widget.item!.minQuantity!),
  );
  late final _purchase = TextEditingController(
    text: _priceText(widget.item?.lastPurchase),
  );
  late final _sale = TextEditingController(
    text: _priceText(widget.item?.lastSale),
  );
  bool _saving = false;

  static String _priceText(int? piasters) =>
      piasters == null ? '' : piastersToInput(piasters);

  /// The price typed in [field], or null if it is empty or unchanged from
  /// [current] — so saving untouched fields doesn't restamp their date.
  static int? _changedPrice(TextEditingController field, int? current) {
    final price = parseMoneyToPiasters(field.text);
    return price == current ? null : price;
  }

  @override
  void dispose() {
    _name.dispose();
    _unit.dispose();
    _actual.dispose();
    _min.dispose();
    _purchase.dispose();
    _sale.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final db = ref.read(databaseProvider);
    final name = _name.text.trim();
    final unit = _unit.text.trim();
    final actual = parseNumber(_actual.text);
    final min = parseNumber(_min.text);
    try {
      await db.transaction(() async {
        await db.saveItemSettings(
          name,
          unit: unit.isEmpty ? null : unit,
          minQuantity: min,
          purchasePrice: _changedPrice(_purchase, widget.item?.lastPurchase),
          salePrice: _changedPrice(_sale, widget.item?.lastSale),
        );
        final current = widget.item?.stock ?? 0;
        if (actual != null && actual != current) {
          await db.recordStockCount(
            name,
            current: current,
            actual: actual,
            date: DateTime.now(),
            note: widget.item == null ? 'رصيد افتتاحي' : 'جرد',
          );
        }
      });
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('تعذر الحفظ: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    String? number(String? v) =>
        (v != null && v.trim().isNotEmpty && parseNumber(v) == null)
        ? 'رقم غير صحيح'
        : null;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                item == null ? 'صنف جديد في المخزون' : item.name,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              if (item != null && item.tracked)
                Text(
                  'المخزون حسب الدفتر: ${formatQuantity(item.stock)} ${item.unit}',
                  style: const TextStyle(color: Colors.black54),
                ),
              const SizedBox(height: 12),
              if (item == null) ...[
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'اسم الصنف *'),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'مطلوب' : null,
                ),
                const SizedBox(height: 8),
              ],
              TextFormField(
                controller: _unit,
                decoration: const InputDecoration(labelText: 'الوحدة'),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _actual,
                decoration: InputDecoration(
                  labelText: item == null
                      ? 'الكمية الموجودة الآن'
                      : 'الكمية الفعلية بعد الجرد',
                  helperText: item == null
                      ? null
                      : 'اتركها كما هي إن لم تقم بالجرد',
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                validator: number,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _min,
                decoration: const InputDecoration(
                  labelText: 'نبهني لما توصل الكمية إلى (اختياري)',
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                validator: number,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _purchase,
                      decoration: const InputDecoration(
                        labelText: 'آخر سعر شراء',
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      validator: number,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _sale,
                      decoration: const InputDecoration(
                        labelText: 'آخر سعر بيع',
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      validator: number,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: const Icon(Icons.save),
                label: const Text('حفظ'),
                style: FilledButton.styleFrom(minimumSize: const Size(0, 52)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
