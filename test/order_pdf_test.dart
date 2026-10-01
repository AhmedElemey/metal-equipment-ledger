import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:metal_ledger/core/database/app_database.dart';
import 'package:metal_ledger/features/orders/data/order_pdf.dart';
import 'package:pdf/widgets.dart' as pw;

OrderSummary _summary(OrderStatus status) => OrderSummary(
  order: Order(
    id: 12,
    partyId: 1,
    kind: OrderKind.sale,
    status: status,
    date: DateTime(2026, 10, 1),
    notes: 'التسليم في الورشة',
    createdAt: DateTime(2026, 10, 1),
  ),
  partyName: 'الحاج محمود',
  totalPiasters: 495150,
  paidPiasters: 100000,
);

final _items = [
  const OrderItem(
    id: 1,
    orderId: 12,
    name: 'صاج حديد 2 مم',
    quantity: 2.5,
    unit: 'طن',
    unitPricePiasters: 100000,
  ),
  const OrderItem(
    id: 2,
    orderId: 12,
    name: 'مسامير',
    quantity: 3,
    unit: 'كرتونة',
    unitPricePiasters: 15050,
  ),
];

final _party = Party(
  id: 1,
  name: 'الحاج محمود',
  phone: '01001234567',
  city: 'شبرا الخيمة',
  kind: PartyKind.buyer,
  notes: null,
  createdAt: DateTime(2026, 1, 1),
  lastRemindedAt: null,
);

void main() {
  late pw.Font font;

  setUpAll(() async {
    await initializeDateFormatting('ar');
    font = pw.Font.ttf(
      File('assets/fonts/Cairo.ttf').readAsBytesSync().buffer.asByteData(),
    );
  });

  test('titles and file names', () {
    expect(orderDocumentTitle(_summary(OrderStatus.pending)), 'فاتورة بيع');
    expect(orderDocumentTitle(_summary(OrderStatus.quotation)), 'عرض سعر');
    expect(orderPdfFileName(_summary(OrderStatus.pending)), 'invoice-12.pdf');
    expect(
      orderPdfFileName(_summary(OrderStatus.quotation)),
      'quotation-12.pdf',
    );
  });

  test('builds a PDF for invoices, quotations and long orders', () async {
    for (final (status, items) in [
      (OrderStatus.pending, _items),
      (OrderStatus.quotation, _items),
      (OrderStatus.pending, [for (var i = 0; i < 60; i++) ..._items]),
    ]) {
      final bytes = await buildOrderPdf(
        summary: _summary(status),
        items: items,
        party: _party,
        business: (
          name: 'المعدات الحديثة',
          phone: '01112223334',
          address: 'شارع المعادن - القاهرة',
        ),
        font: font,
      );
      expect(String.fromCharCodes(bytes.take(4)), '%PDF');
      final out = Platform.environment['PDF_OUT'];
      if (out != null) {
        File('$out/${status.name}-${items.length}.pdf').writeAsBytesSync(bytes);
      }
    }
  });
}
