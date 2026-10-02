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
    required this.partyPrice,
    required this.enteredPrice,
    required this.enteredQuantity,
  });

  final ItemSummary item;
  final OrderKind kind;

  /// What this order's client/supplier got last time, if ever.
  final PartyItemPrice? partyPrice;

  /// The unit price typed in the form, in piasters (null if empty/invalid).
  final int? enteredPrice;

  /// The quantity typed in the form (null if empty/invalid).
  final double? enteredQuantity;

  @override
  Widget build(BuildContext context) {
    final lastPurchase = item.lastPurchase;
    final lastSale = item.lastSale;
    final belowCost =
        kind == OrderKind.sale &&
        lastPurchase != null &&
        enteredPrice != null &&
        enteredPrice! < lastPurchase;
    final party = partyPrice;
    final showStock = kind == OrderKind.sale && item.tracked;
    final overStock =
        showStock && enteredQuantity != null && enteredQuantity! > item.stock;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (party != null)
          Text(
            '${partyPriceLabel(kind)} ${formatMoney(party.price)} • '
            '${formatDate(party.at)}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        Text(
          [
            if (lastPurchase != null) 'آخر شراء ${formatMoney(lastPurchase)}',
            if (lastSale != null) 'آخر بيع ${formatMoney(lastSale)}',
          ].join(' • '),
          style: const TextStyle(color: Colors.black54, fontSize: 13),
        ),
        if (showStock)
          Text(
            'المتاح في المخزون: ${formatQuantity(item.stock)} ${item.unit}',
            style: TextStyle(color: overStock ? AppColors.danger : null),
          ),
        if (overStock)
          const Text(
            '⚠ الكمية أكبر من المتاح في المخزون',
            style: TextStyle(
              color: AppColors.danger,
              fontWeight: FontWeight.bold,
            ),
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

/// "آخر سعر لهذا العميل:" / "آخر سعر لهذا المورد:"
String partyPriceLabel(OrderKind kind) =>
    kind == OrderKind.sale ? 'آخر سعر لهذا العميل:' : 'آخر سعر لهذا المورد:';
