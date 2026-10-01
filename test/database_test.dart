import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metal_ledger/core/database/app_database.dart';
import 'package:metal_ledger/features/backup/data/excel_export.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  Future<int> addParty(String name, [PartyKind kind = PartyKind.buyer]) =>
      db.saveParty(
        PartiesCompanion.insert(
          name: name,
          kind: kind,
          phone: const Value('01001234567'),
        ),
      );

  // Every order is 2.5 × 1,000 + 3 × 150.50 = 2,951.50 EGP.
  const orderTotal = 295150;

  Future<int> addOrder(
    int partyId,
    OrderKind kind, {
    int downPayment = 0,
    OrderStatus status = OrderStatus.pending,
    DateTime? date,
  }) => db.saveOrder(
    OrdersCompanion.insert(
      partyId: partyId,
      kind: kind,
      date: date ?? DateTime.now(),
      status: Value(status),
    ),
    [
      OrderItemsCompanion.insert(
        orderId: 0,
        name: 'صاج',
        quantity: 2.5,
        unitPricePiasters: 100000,
      ),
      OrderItemsCompanion.insert(
        orderId: 0,
        name: 'مسامير',
        quantity: 3,
        unitPricePiasters: 15050,
      ),
    ],
    downPayment: downPayment,
  );

  Future<void> pay(
    int partyId,
    int amount, {
    PaymentDirection direction = PaymentDirection.received,
    int? orderId,
    DateTime? date,
  }) => db.addPayment(
    PaymentsCompanion.insert(
      partyId: partyId,
      orderId: Value(orderId),
      direction: direction,
      amountPiasters: amount,
      date: date ?? DateTime.now(),
    ),
  );

  test('order summary sums items and linked payments', () async {
    final party = await addParty('الحاج محمود');
    final id = await addOrder(party, OrderKind.sale, downPayment: 100000);
    await pay(party, 50000, orderId: id);
    await pay(party, 999); // on account — not part of this order

    final s = await db.watchOrderSummary(id).first;
    expect(s.partyName, 'الحاج محمود');
    expect(s.totalPiasters, orderTotal);
    expect(s.paidPiasters, 150000);
    expect(s.remainingPiasters, orderTotal - 150000);
  });

  test('editing an order replaces items and keeps payments', () async {
    final party = await addParty('ورشة النور');
    final id = await addOrder(party, OrderKind.sale, downPayment: 1000);
    final order = await db.getOrder(id);

    await db.saveOrder(order.toCompanion(true), [
      OrderItemsCompanion.insert(
        orderId: 0,
        name: 'زاوية حديد',
        quantity: 1,
        unitPricePiasters: 5000,
      ),
    ]);

    expect((await db.itemsOf(id)).map((i) => i.name), ['زاوية حديد']);
    expect((await db.watchOrderSummary(id).first).paidPiasters, 1000);
  });

  test('party balance nets sales, purchases and payments', () async {
    final party = await addParty('شركة الصلب', PartyKind.both);
    await addOrder(party, OrderKind.sale); // +2951.50
    await addOrder(party, OrderKind.sale, status: OrderStatus.cancelled);
    await pay(party, 95150); // -951.50 → they owe 2000
    expect(await db.watchPartyBalance(party).first, 200000);

    await addOrder(party, OrderKind.purchase); // -2951.50 → we owe 951.50
    expect(await db.watchPartyBalance(party).first, 200000 - orderTotal);

    await pay(party, 95150, direction: PaymentDirection.paid); // settled
    expect(await db.watchPartyBalance(party).first, 0);
  });

  test('statement lists orders and payments with running balance', () async {
    final party = await addParty('عميل');
    final d1 = DateTime(2026, 9, 1);
    final d2 = DateTime(2026, 9, 5);
    final d3 = DateTime(2026, 9, 10);
    final first = await addOrder(party, OrderKind.sale, date: d1);
    await pay(party, 100000, orderId: first, date: d2);
    await addOrder(party, OrderKind.sale, date: d3);
    await addOrder(party, OrderKind.sale, status: OrderStatus.cancelled);

    final s = await db.watchStatement(party).first;
    expect(s.map((e) => e.isPayment), [false, true, false]);
    expect(s.map((e) => e.balance), [
      orderTotal,
      orderTotal - 100000,
      2 * orderTotal - 100000,
    ]);
    expect(s[1].orderId, first);
    expect(s[1].increasesBalance, isFalse);
  });

  test('a down payment on the same day comes after its order', () async {
    final party = await addParty('عميل');
    await addOrder(party, OrderKind.sale, downPayment: orderTotal);
    final s = await db.watchStatement(party).first;
    expect(s.map((e) => e.balance), [orderTotal, 0]);
  });

  test('debtors: only positive balances, biggest first', () async {
    final small = await addParty('صغير');
    final big = await addParty('كبير');
    final settled = await addParty('خالص');
    final supplier = await addParty('مورد', PartyKind.seller);
    await addOrder(small, OrderKind.sale);
    await pay(small, orderTotal - 100);
    await addOrder(big, OrderKind.sale, date: DateTime(2026, 8, 1));
    await addOrder(settled, OrderKind.sale, downPayment: orderTotal);
    await addOrder(supplier, OrderKind.purchase);

    final debtors = await db.watchDebtors().first;
    expect(debtors.map((d) => d.party.name), ['كبير', 'صغير']);
    expect(debtors.first.balance, orderTotal);
    expect(debtors.first.lastPaymentAt, isNull);
    expect(debtors.first.lastActivityAt, DateTime(2026, 8, 1));
    expect(debtors.last.lastPaymentAt, isNotNull);

    await db.markReminded(big, DateTime(2026, 10, 1, 10));
    final again = await db.watchDebtors().first;
    expect(again.first.party.lastRemindedAt, DateTime(2026, 10, 1, 10));
  });

  test('dashboard: today totals and net receivables/payables', () async {
    final client = await addParty('عميل');
    final supplier = await addParty('مورد', PartyKind.seller);
    final now = DateTime(2026, 10, 1, 12);
    await addOrder(client, OrderKind.sale, date: now);
    await addOrder(
      client,
      OrderKind.sale,
      date: now.subtract(const Duration(days: 1)),
      status: OrderStatus.delivered,
    );
    await addOrder(supplier, OrderKind.purchase, date: now);
    await pay(supplier, 100000, direction: PaymentDirection.paid);

    final d = await db.watchDashboard(now).first;
    expect(d.todaySales, orderTotal);
    expect(d.todayPurchases, orderTotal);
    expect(d.receivables, 2 * orderTotal);
    expect(d.payables, orderTotal - 100000);
    expect(d.debtors, 1);
    expect(d.openOrders, 2);
  });

  test('a party with orders or payments cannot be deleted', () async {
    final withOrder = await addParty('عميل');
    await addOrder(withOrder, OrderKind.sale);
    final withPayment = await addParty('عميل 2');
    await pay(withPayment, 100);
    final clean = await addParty('جديد');

    expect(await db.hasHistory(withOrder), isTrue);
    expect(await db.hasHistory(withPayment), isTrue);
    expect(await db.hasHistory(clean), isFalse);
    expect(() => db.deleteParty(withPayment), throwsA(isA<Exception>()));
  });

  test('deleting an order keeps its payments on the account', () async {
    final party = await addParty('عميل');
    final id = await addOrder(party, OrderKind.sale, downPayment: 5000);
    await db.deleteOrder(id);
    expect(await db.watchPartyBalance(party).first, -5000);
  });

  test('quotations never count until converted', () async {
    final party = await addParty('عميل');
    final id = await addOrder(
      party,
      OrderKind.sale,
      status: OrderStatus.quotation,
      date: DateTime(2026, 9, 1),
    );
    final now = DateTime(2026, 10, 1, 12);

    expect(await db.watchPartyBalance(party).first, 0);
    expect(await db.watchStatement(party).first, isEmpty);
    expect(await db.watchDebtors().first, isEmpty);
    final d = await db.watchDashboard(now).first;
    expect((d.receivables, d.openOrders), (0, 0));
    expect(
      (await db.watchOrderSummaries(quotations: true).first).map(
        (o) => o.order.id,
      ),
      [id],
    );
    expect(await db.watchOrderSummaries(quotations: false).first, isEmpty);

    await db.convertQuotation(id, now);

    final order = await db.getOrder(id);
    expect(order.status, OrderStatus.pending);
    expect(order.date, now);
    expect(await db.watchPartyBalance(party).first, orderTotal);
    expect((await db.watchDashboard(now).first).todaySales, orderTotal);
    expect(await db.watchOrderSummaries(quotations: true).first, isEmpty);
  });

  test('item prices: latest sale and purchase, real orders only', () async {
    final client = await addParty('عميل');
    final supplier = await addParty('مورد', PartyKind.seller);
    Future<void> line(
      int party,
      OrderKind kind,
      DateTime date,
      int price, {
      String unit = 'طن',
      OrderStatus status = OrderStatus.pending,
    }) => db.saveOrder(
      OrdersCompanion.insert(
        partyId: party,
        kind: kind,
        date: date,
        status: Value(status),
      ),
      [
        OrderItemsCompanion.insert(
          orderId: 0,
          name: 'صاج',
          quantity: 1,
          unit: Value(unit),
          unitPricePiasters: price,
        ),
      ],
    );
    await line(supplier, OrderKind.purchase, DateTime(2026, 8, 1), 80000);
    await line(supplier, OrderKind.purchase, DateTime(2026, 9, 1), 90000);
    await line(client, OrderKind.sale, DateTime(2026, 9, 5), 100000);
    await line(client, OrderKind.sale, DateTime(2026, 8, 5), 95000);
    await line(
      client,
      OrderKind.sale,
      DateTime(2026, 9, 20),
      1,
      status: OrderStatus.cancelled,
    );
    await line(
      client,
      OrderKind.sale,
      DateTime(2026, 9, 25),
      2,
      status: OrderStatus.quotation,
    );
    await line(
      client,
      OrderKind.sale,
      DateTime(2026, 9, 10),
      99000,
      unit: 'كيلو',
    );
    await addOrder(client, OrderKind.sale, date: DateTime(2026, 7, 1));

    final items = await db.watchItems().first;
    expect(items.map((i) => i.name), ['صاج', 'مسامير']);
    final sheet = items.first;
    expect(sheet.lastSale, 99000);
    expect(sheet.lastSaleAt, DateTime(2026, 9, 10));
    expect(sheet.lastPurchase, 90000);
    expect(sheet.unit, 'كيلو');
    expect(items.last.lastPurchase, isNull);
  });

  test('party item prices: that party, that kind, real orders', () async {
    final a = await addParty('عميل أ');
    final b = await addParty('عميل ب');
    await addOrder(a, OrderKind.sale, date: DateTime(2026, 8, 1));
    final latest = await addOrder(
      a,
      OrderKind.sale,
      date: DateTime(2026, 9, 1),
    );
    await db.saveOrder((await db.getOrder(latest)).toCompanion(true), [
      OrderItemsCompanion.insert(
        orderId: 0,
        name: 'صاج',
        quantity: 1,
        unitPricePiasters: 120000,
      ),
    ]);
    await addOrder(a, OrderKind.purchase, date: DateTime(2026, 9, 2));
    await addOrder(
      a,
      OrderKind.sale,
      date: DateTime(2026, 9, 3),
      status: OrderStatus.quotation,
    );
    await addOrder(b, OrderKind.sale, date: DateTime(2026, 9, 4));

    final prices = await db
        .watchPartyItemPrices(partyId: a, kind: OrderKind.sale)
        .first;
    expect(prices['صاج'], (price: 120000, at: DateTime(2026, 9, 1)));
    expect(prices['مسامير'], (price: 15050, at: DateTime(2026, 8, 1)));

    // Editing the latest order: its own lines don't count.
    final editing = await db
        .watchPartyItemPrices(
          partyId: a,
          kind: OrderKind.sale,
          excludeOrderId: latest,
        )
        .first;
    expect(editing['صاج'], (price: 100000, at: DateTime(2026, 8, 1)));

    expect(
      await db.watchPartyItemPrices(partyId: b, kind: OrderKind.purchase).first,
      isEmpty,
    );
  });

  test('stock: purchases − sales + counts; only tracked items alert', () async {
    final client = await addParty('عميل');
    final supplier = await addParty('مورد', PartyKind.seller);
    // Each order: 2.5 صاج + 3 مسامير.
    await addOrder(supplier, OrderKind.purchase);
    await addOrder(supplier, OrderKind.purchase);
    await addOrder(client, OrderKind.sale);
    await addOrder(client, OrderKind.sale, status: OrderStatus.cancelled);
    await addOrder(client, OrderKind.sale, status: OrderStatus.quotation);

    Future<ItemSummary> item(String name) async =>
        (await db.watchItems().first).singleWhere((i) => i.name == name);

    var sheet = await item('صاج');
    expect(sheet.stock, 2.5);
    expect(sheet.tracked, isFalse);
    expect(sheet.isLow, isFalse);

    // A physical count finds 2 (not 2.5) and sets an alert at 3.
    await db.recordStockCount(
      'صاج',
      current: sheet.stock,
      actual: 2,
      date: DateTime(2026, 10, 1),
    );
    await db.saveItemSettings('صاج', unit: 'طن', minQuantity: 3);
    sheet = await item('صاج');
    expect(sheet.stock, 2);
    expect(sheet.unit, 'طن');
    expect(sheet.tracked, isTrue);
    expect(sheet.isLow, isTrue);

    // An item that exists only as opening stock.
    await db.recordStockCount(
      'زاوية',
      current: 0,
      actual: 40,
      date: DateTime(2026, 10, 1),
    );
    final angle = await item('زاوية');
    expect((angle.stock, angle.unit, angle.lastSale), (40.0, 'قطعة', null));
  });

  test('expenses are listed per month, newest first', () async {
    for (final (day, amount) in [(1, 100), (15, 200), (31, 300)]) {
      await db.addExpense(
        ExpensesCompanion.insert(
          date: DateTime(2026, 10, day),
          category: 'نقل',
          amountPiasters: amount,
        ),
      );
    }
    await db.addExpense(
      ExpensesCompanion.insert(
        date: DateTime(2026, 11, 1),
        category: 'إيجار',
        amountPiasters: 999,
      ),
    );
    final october = await db
        .watchExpenses(DateTime(2026, 10), DateTime(2026, 11))
        .first;
    expect(october.map((e) => e.amountPiasters), [300, 200, 100]);
  });

  group('profit', () {
    Future<int> line(
      int party,
      OrderKind kind,
      String name,
      double qty,
      int price,
      DateTime date, {
      OrderStatus status = OrderStatus.pending,
    }) => db.saveOrder(
      OrdersCompanion.insert(
        partyId: party,
        kind: kind,
        date: date,
        status: Value(status),
      ),
      [
        OrderItemsCompanion.insert(
          orderId: 0,
          name: name,
          quantity: qty,
          unitPricePiasters: price,
        ),
      ],
    );

    test('uses the weighted average purchase cost', () async {
      final supplier = await addParty('مورد', PartyKind.seller);
      final client = await addParty('عميل');
      final d = DateTime(2026, 10, 5);
      // 1 × 800 + 3 × 1,000 → average 950.
      await line(supplier, OrderKind.purchase, 'صاج', 1, 80000, d);
      await line(supplier, OrderKind.purchase, 'صاج', 3, 100000, d);
      await line(
        supplier,
        OrderKind.purchase,
        'صاج',
        5,
        1,
        d,
        status: OrderStatus.cancelled,
      );
      final sale = await db.saveOrder(
        OrdersCompanion.insert(partyId: client, kind: OrderKind.sale, date: d),
        [
          OrderItemsCompanion.insert(
            orderId: 0,
            name: 'صاج',
            quantity: 2,
            unitPricePiasters: 120000,
          ),
          OrderItemsCompanion.insert(
            orderId: 0,
            name: 'صنف جديد', // never bought
            quantity: 1,
            unitPricePiasters: 5000,
          ),
        ],
      );

      final p = await db.watchOrderProfit(sale).first;
      expect(p, (profit: 2 * (120000 - 95000), uncostedLines: 1));
    });

    test('monthly report: totals, profit after expenses, top lists', () async {
      final supplier = await addParty('مورد', PartyKind.seller);
      final big = await addParty('عميل كبير');
      final small = await addParty('عميل صغير');
      final oct = DateTime(2026, 10, 10);
      await line(supplier, OrderKind.purchase, 'صاج', 10, 90000, oct);
      await line(big, OrderKind.sale, 'صاج', 3, 100000, oct);
      await line(small, OrderKind.sale, 'صاج', 1, 110000, oct);
      await line(big, OrderKind.sale, 'صاج', 9, 1, DateTime(2026, 9, 30));
      await line(
        small,
        OrderKind.sale,
        'صاج',
        9,
        1,
        oct,
        status: OrderStatus.quotation,
      );
      await pay(big, 150000, date: oct);
      await pay(supplier, 400000, direction: PaymentDirection.paid, date: oct);
      await db.addExpense(
        ExpensesCompanion.insert(
          date: oct,
          category: 'نقل',
          amountPiasters: 5000,
        ),
      );

      final r = await db
          .watchMonthlyReport(DateTime(2026, 10), DateTime(2026, 11))
          .first;
      expect(r.sales, 410000);
      expect(r.purchases, 900000);
      expect(r.received, 150000);
      expect(r.paidOut, 400000);
      expect(r.expenses, 5000);
      // Sept sale (price 1) is outside; average cost includes all purchases.
      expect(r.grossProfit, 3 * 10000 + 1 * 20000);
      expect(r.netProfit, 50000 - 5000);
      expect(r.uncostedLines, 0);
      expect(r.topClients.map((c) => c.name), ['عميل كبير', 'عميل صغير']);
      expect(r.topItems.single, (name: 'صاج', total: 410000));
    });
  });

  test('excel report has the four Arabic sheets', () async {
    final party = await addParty('الحاج محمود');
    await addOrder(party, OrderKind.sale, downPayment: 1000);

    final excel = Excel.decodeBytes(await buildExcelReport(db));
    expect(
      excel.tables.keys,
      containsAll([
        'الطلبات',
        'الأصناف',
        'الدفعات',
        'العملاء والموردين',
        'المخزون',
        'المصروفات',
      ]),
    );
    expect(excel.tables['الطلبات']!.maxRows, 2);
    expect(excel.tables['الأصناف']!.maxRows, 3);
    expect(excel.tables['الدفعات']!.maxRows, 2);
  });
}
