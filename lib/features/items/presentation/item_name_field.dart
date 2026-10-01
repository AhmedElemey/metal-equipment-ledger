import 'package:flutter/material.dart';

import '../../../core/arabic_search.dart';
import '../../../core/database/app_database.dart';
import '../../../core/formatters.dart';

/// Item name input that suggests items from past orders as you type.
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
  final Iterable<ItemPrice> items;

  /// This order's client/supplier's last price per item name.
  final Map<String, PartyItemPrice> partyPrices;
  final OrderKind kind;
  final ValueChanged<ItemPrice> onSelected;

  static const _maxOptions = 8;

  @override
  Widget build(BuildContext context) {
    return RawAutocomplete<ItemPrice>(
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
            decoration: const InputDecoration(
              labelText: 'اسم الصنف *',
              hintText: 'مثال: صاج حديد 2 مم',
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

String _pricesLine(ItemPrice item, PartyItemPrice? party, OrderKind kind) => [
  if (party != null)
    '${kind == OrderKind.sale ? 'لهذا العميل' : 'لهذا المورد'} '
        '${formatMoney(party.price)}',
  if (item.lastSale != null) 'بيع ${formatMoney(item.lastSale!)}',
  if (item.lastPurchase != null) 'شراء ${formatMoney(item.lastPurchase!)}',
  item.unit,
].join(' • ');
