import 'package:drift/drift.dart' hide isNull;
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

  Future<int> addOrder(
    int partyId,
    OrderKind kind, {
    int paid = 0,
    OrderStatus status = OrderStatus.pending,
    DateTime? date,
  }) => db.saveOrder(
    OrdersCompanion.insert(
      partyId: partyId,
      kind: kind,
      date: date ?? DateTime.now(),
      paidPiasters: Value(paid),
      status: Value(status),
    ),
    [
      // 2.5 ton × 1,000 EGP + 3 × 150.50 EGP = 2,951.50 EGP
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
  );

  test('order summary totals items and remaining', () async {
    final party = await addParty('الحاج محمود');
    final id = await addOrder(party, OrderKind.sale, paid: 100000);

    final s = await db.watchOrderSummary(id).first;
    expect(s.partyName, 'الحاج محمود');
    expect(s.totalPiasters, 295150);
    expect(s.remainingPiasters, 195150);
  });

  test('editing an order replaces its items', () async {
    final party = await addParty('ورشة النور');
    final id = await addOrder(party, OrderKind.sale);
    final order = await db.getOrder(id);

    await db.saveOrder(order.toCompanion(true), [
      OrderItemsCompanion.insert(
        orderId: 0,
        name: 'زاوية حديد',
        quantity: 1,
        unitPricePiasters: 5000,
      ),
    ]);

    final items = await db.itemsOf(id);
    expect(items.map((i) => i.name), ['زاوية حديد']);
  });

  test('party balance splits sales and purchases, ignores cancelled', () async {
    final party = await addParty('شركة الصلب', PartyKind.both);
    await addOrder(party, OrderKind.sale, paid: 95150); // 2000 due from
    await addOrder(party, OrderKind.purchase); // 2951.50 due to
    await addOrder(party, OrderKind.sale, status: OrderStatus.cancelled);

    final b = await db.watchPartyBalance(party).first;
    expect(b.dueFromThem, 200000);
    expect(b.dueToThem, 295150);
  });

  test('dashboard counts today only for daily totals', () async {
    final party = await addParty('عميل');
    final now = DateTime(2026, 10, 1, 12);
    await addOrder(party, OrderKind.sale, date: now);
    await addOrder(
      party,
      OrderKind.sale,
      date: now.subtract(const Duration(days: 1)),
      status: OrderStatus.delivered,
    );
    await addOrder(party, OrderKind.purchase, date: now, paid: 295150);

    final d = await db.watchDashboard(now).first;
    expect(d.todaySales, 295150);
    expect(d.todayPurchases, 295150);
    expect(d.receivables, 295150 * 2);
    expect(d.payables, 0);
    expect(d.openOrders, 2);
  });

  test('a party with orders cannot be deleted', () async {
    final party = await addParty('عميل');
    await addOrder(party, OrderKind.sale);
    expect(() => db.deleteParty(party), throwsA(isA<Exception>()));
  });

  test('excel report has the three Arabic sheets', () async {
    final party = await addParty('الحاج محمود');
    await addOrder(party, OrderKind.sale);

    final excel = Excel.decodeBytes(await buildExcelReport(db));
    expect(
      excel.tables.keys,
      containsAll(['الطلبات', 'الأصناف', 'العملاء والموردين']),
    );
    expect(excel.tables['الطلبات']!.maxRows, 2);
    expect(excel.tables['الأصناف']!.maxRows, 3);
  });
}
