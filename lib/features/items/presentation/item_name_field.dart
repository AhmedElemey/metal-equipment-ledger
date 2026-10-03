import 'package:flutter/material.dart';

import '../../../core/arabic_search.dart';
import '../../../core/database/app_database.dart';
import '../../../core/formatters.dart';

/// Item name input that suggests saved items as you type, with a button
/// to pick one from the full list.
class ItemNameField extends StatelessWidget {
  const ItemNameField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.items,
    required this.partyPrices,
    required this.kind,
    required this.onSelected,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final Iterable<ItemSummary> items;

  /// This order's client/supplier's last price per item name.
  final Map<String, PartyItemPrice> partyPrices;
  final OrderKind kind;
  final ValueChanged<ItemSummary> onSelected;

  static const _maxOptions = 8;

  @override
  Widget build(BuildContext context) {
    return RawAutocomplete<ItemSummary>(
      textEditingController: controller,
      focusNode: focusNode,
      displayStringForOption: (item) => item.name,
      optionsBuilder: (value) {
        final query = value.text.trim();
        if (query.isEmpty) return const [];
        return items
            .where((i) => arabicMatches(i.name, query))
            // Hide the suggestion once the exact name is typed.
            .where((i) => i.name != query)
            .take(_maxOptions);
      },
      onSelected: onSelected,
      fieldViewBuilder: (context, controller, focusNode, onSubmitted) =>
          TextFormField(
            controller: controller,
            focusNode: focusNode,
            decoration: InputDecoration(
              labelText: 'اسم الصنف *',
              hintText: 'مثال: صاج حديد 2 مم',
              suffixIcon: items.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.inventory_2_outlined),
                      tooltip: 'اختر من الأصناف',
                      onPressed: () => _pick(context),
                    ),
            ),
            validator: (v) => (v == null || v.trim().isEmpty) ? 'مطلوب' : null,
            onFieldSubmitted: (_) => onSubmitted(),
          ),
      optionsViewBuilder: (context, onSelected, options) => Align(
        alignment: AlignmentDirectional.topStart,
        child: Material(
          elevation: 4,
          borderRadius: BorderRadius.circular(8),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 280, maxWidth: 360),
            child: ListView.builder(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              itemCount: options.length,
              itemBuilder: (_, i) {
                final item = options.elementAt(i);
                return ListTile(
                  dense: true,
                  title: Text(item.name),
                  subtitle: Text(
                    _pricesLine(item, partyPrices[item.name], kind),
                  ),
                  onTap: () => onSelected(item),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

extension on ItemNameField {
  Future<void> _pick(BuildContext context) async {
    focusNode.unfocus();
    final item = await showModalBottomSheet<ItemSummary>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ItemPicker(
        items: items.toList(),
        partyPrices: partyPrices,
        kind: kind,
      ),
    );
    if (item == null) return;
    controller.text = item.name;
    onSelected(item);
  }
}

/// Every saved item, searchable; pops with the one tapped.
class _ItemPicker extends StatefulWidget {
  const _ItemPicker({
    required this.items,
    required this.partyPrices,
    required this.kind,
  });

  final List<ItemSummary> items;
  final Map<String, PartyItemPrice> partyPrices;
  final OrderKind kind;

  @override
  State<_ItemPicker> createState() => _ItemPickerState();
}

class _ItemPickerState extends State<_ItemPicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final query = _query.trim();
    final list = [
      for (final i in widget.items)
        if (query.isEmpty || arabicMatches(i.name, query)) i,
    ];
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.7,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: TextField(
                  decoration: const InputDecoration(
                    hintText: 'بحث عن صنف',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              Expanded(
                child: list.isEmpty
                    ? const Center(child: Text('لا يوجد صنف بهذا الاسم'))
                    : ListView.builder(
                        itemCount: list.length,
                        itemBuilder: (_, i) {
                          final item = list[i];
                          return ListTile(
                            title: Text(item.name),
                            subtitle: Text(
                              _pricesLine(
                                item,
                                widget.partyPrices[item.name],
                                widget.kind,
                              ),
                            ),
                            onTap: () => Navigator.of(context).pop(item),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _pricesLine(ItemSummary item, PartyItemPrice? party, OrderKind kind) => [
  if (party != null)
    '${kind == OrderKind.sale ? 'لهذا العميل' : 'لهذا المورد'} '
        '${formatMoney(party.price)}',
  if (item.lastSale != null) 'بيع ${formatMoney(item.lastSale!)}',
  if (item.lastPurchase != null) 'شراء ${formatMoney(item.lastPurchase!)}',
  item.unit,
].join(' • ');
