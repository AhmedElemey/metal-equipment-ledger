import 'package:flutter/material.dart';

import '../../../core/database/app_database.dart';
import '../../../core/formatters.dart';
import '../../../core/theme.dart';

/// "آخر شراء 900 ج.م • آخر بيع 1,000 ج.م", plus a red warning when a sale
/// price is below the last purchase price.
class ItemPriceHint extends StatelessWidget {
  const ItemPriceHint({
    super.key,
    required this.item,
    required this.kind,
    required this.enteredPrice,
  });

  final ItemPrice item;
  final OrderKind kind;

  /// The unit price typed in the form, in piasters (null if empty/invalid).
  final int? enteredPrice;

  @override
  Widget build(BuildContext context) {
    final lastPurchase = item.lastPurchase;
    final lastSale = item.lastSale;
    final belowCost =
        kind == OrderKind.sale &&
        lastPurchase != null &&
        enteredPrice != null &&
        enteredPrice! < lastPurchase;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          [
            if (lastPurchase != null) 'آخر شراء ${formatMoney(lastPurchase)}',
            if (lastSale != null) 'آخر بيع ${formatMoney(lastSale)}',
          ].join(' • '),
          style: const TextStyle(color: Colors.black54, fontSize: 13),
        ),
        if (belowCost)
          Text(
            '⚠ السعر أقل من آخر سعر شراء',
            style: const TextStyle(
              color: AppColors.danger,
              fontWeight: FontWeight.bold,
            ),
          ),
      ],
    );
  }
}
