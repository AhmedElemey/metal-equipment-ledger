import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metal_ledger/core/database/app_database.dart';
import 'package:metal_ledger/features/backup/data/excel_export.dart';

/// A large random but reproducible data set, plus an independent in-Dart
/// model of what every query should return.
class _World {
  final parties = <int, PartyKind>{};
  final orders =
      <
        ({
          int id,
          int party,
          OrderKind kind,
          OrderStatus status,
          DateTime date,
          List<({int id, String name, double qty, int price})> lines,
        })
      >[];
  final payments =
      <
        ({
          int party,
          PaymentDirection dir,
          int amount,
          DateTime date,
          int? order,
        })
      >[];
  final expenses = <({int amount, DateTime date})>[];
  final adjustments = <String, double>{};

  static bool counts(OrderStatus s) =>
      s != OrderStatus.cancelled && s != OrderStatus.quotation;

  static int lineTotal(double qty, int price) => (qty * price).round();

  int total(int orderId) => orders
      .firstWhere((o) => o.id == orderId)
      .lines
      .fold(0, (s, l) => s + lineTotal(l.qty, l.price));

  int balance(int party) {
    var b = 0;
    for (final o in orders) {
      if (o.party != party || !counts(o.status)) continue;
      final t = o.lines.fold(0, (s, l) => s + lineTotal(l.qty, l.price));
      b += o.kind == OrderKind.sale ? t : -t;
    }
    for (final p in payments) {
      if (p.party != party) continue;
      b += p.dir == PaymentDirection.received ? -p.amount : p.amount;
    }
    return b;
  }

  double stock(String name) {
    var s = adjustments[name] ?? 0;
    for (final o in orders) {
      if (!counts(o.status)) continue;
      for (final l in o.lines) {
        if (l.name == name) s += o.kind == OrderKind.sale ? -l.qty : l.qty;
      }
    }
    return s;
  }

  double? avgCost(String name) {
    var cost = 0.0;
    var qty = 0.0;
    for (final o in orders) {
      if (o.kind != OrderKind.purchase || !counts(o.status)) continue;
      for (final l in o.lines) {
        if (l.name == name && l.qty > 0) {
          cost += l.qty * l.price;
          qty += l.qty;
        }
      }
    }
    return qty == 0 ? null : cost / qty;
  }
}

const _itemNames = [
  'صاج حديد 2 مم',
  'صاج حديد 3 مم',
  'زاوية 40×40',
  'زاوية 50×50',
  'ماسورة 1 بوصة',
  'ماسورة 2 بوصة',
  'ماسورة 3 بوصة',
  'مربع 20×20',
  'مستطيل 40×20',
  'سيخ تسليح 10',
  'سيخ تسليح 12',
  'سيخ تسليح 16',
  'كمرة I 200',
  'كمرة I 300',
  'شبك ممدد',
  'لوح استانلس',
  'مسامير',
  'صواميل',
  'ماكينة لحام',
  'أسطوانة أكسجين',
  'قطعة غيار A',
  'قطعة غيار B',
  'جنزير',
  'سلك لحام',
  'ألومنيوم 1 مم',
  'ألومنيوم 2 مم',
  'نحاس',
  'خردة حديد',
  'مكبس',
  'منشار صاج',
  'رولمان بلي',
  'عمود دوران',
  'ترس',
  'خوصة 30',
  'خوصة 50',
  'بلوك',
  'طوب',
  'عدة',
  'دهان',
  'حبل سلك',
];

void main() {
  late AppDatabase db;
  late _World world;
  final timings = <String, Duration>{};

  Future<T> timed<T>(String label, Future<T> Function() body) async {
    final sw = Stopwatch()..start();
    final result = await body();
    timings[label] = sw.elapsed;
    return result;
  }

  setUpAll(() async {
    db = AppDatabase(NativeDatabase.memory());
    world = _World();
    final rnd = Random(42);
    DateTime date() => DateTime(
      2025,
      1,
      1,
    ).add(Duration(days: rnd.nextInt(670), minutes: rnd.nextInt(600)));
    final start = DateTime(2025, 1, 1);

    await db.batch((b) {
      for (var id = 1; id <= 500; id++) {
        final kind = PartyKind.values[rnd.nextInt(3)];
        world.parties[id] = kind;
        b.insert(
          db.parties,
          PartiesCompanion.insert(
            id: Value(id),
            name: 'طرف $id',
            kind: kind,
            createdAt: Value(start),
          ),
        );
      }
      var lineId = 0;
      for (var id = 1; id <= 5000; id++) {
        final party = 1 + rnd.nextInt(500);
        final pk = world.parties[party]!;
        final kind = switch (pk) {
          PartyKind.buyer => OrderKind.sale,
          PartyKind.seller => OrderKind.purchase,
          PartyKind.both => OrderKind.values[rnd.nextInt(2)],
        };
        final r = rnd.nextInt(100);
        final status = r < 50
            ? OrderStatus.pending
            : r < 65
            ? OrderStatus.inProgress
            : r < 90
            ? OrderStatus.delivered
            : r < 95
            ? OrderStatus.cancelled
            : (kind == OrderKind.sale
                  ? OrderStatus.quotation
                  : OrderStatus.cancelled);
        final d = date();
        final lines = [
          for (var i = 0; i < 1 + rnd.nextInt(4); i++)
            (
              id: ++lineId,
              name: _itemNames[rnd.nextInt(_itemNames.length)],
              qty: (1 + rnd.nextInt(200)) / 10,
              price: 100 + rnd.nextInt(200000),
            ),
        ];
        world.orders.add((
          id: id,
          party: party,
          kind: kind,
          status: status,
          date: d,
          lines: lines,
        ));
        b.insert(
          db.orders,
          OrdersCompanion.insert(
            id: Value(id),
            partyId: party,
            kind: kind,
            status: Value(status),
            date: d,
            createdAt: Value(start),
          ),
        );
        for (final l in lines) {
          b.insert(
            db.orderItems,
            OrderItemsCompanion.insert(
              id: Value(l.id),
              orderId: id,
              name: l.name,
              quantity: l.qty,
              unitPricePiasters: l.price,
            ),
          );
        }
      }
      for (var i = 0; i < 3000; i++) {
        final party = 1 + rnd.nextInt(500);
        final dir = switch (world.parties[party]!) {
          PartyKind.buyer => PaymentDirection.received,
          PartyKind.seller => PaymentDirection.paid,
          PartyKind.both => PaymentDirection.values[rnd.nextInt(2)],
        };
        final theirs = world.orders.where((o) => o.party == party).toList();
        final order = theirs.isNotEmpty && rnd.nextBool()
            ? theirs[rnd.nextInt(theirs.length)].id
            : null;
        final p = (
          party: party,
          dir: dir,
          amount: 1000 + rnd.nextInt(5000000),
          date: date(),
          order: order,
        );
        world.payments.add(p);
        b.insert(
          db.payments,
          PaymentsCompanion.insert(
            partyId: p.party,
            orderId: Value(p.order),
            direction: p.dir,
            amountPiasters: p.amount,
            date: p.date,
            createdAt: Value(start),
          ),
        );
      }
      for (var i = 0; i < 300; i++) {
        final e = (amount: 100 + rnd.nextInt(500000), date: date());
        world.expenses.add(e);
        b.insert(
          db.expenses,
          ExpensesCompanion.insert(
            date: e.date,
            category: 'نقل',
            amountPiasters: e.amount,
          ),
        );
      }
      for (final name in _itemNames.take(20)) {
        final q = rnd.nextInt(500).toDouble();
        world.adjustments[name] = q;
        b.insert(
          db.stockAdjustments,
          StockAdjustmentsCompanion.insert(
            itemName: name,
            quantity: q,
            date: date(),
          ),
        );
      }
    });
  });

  tearDownAll(() async {
    await db.close();
    // ignore: avoid_print
    print(
      'Query timings on 5,000 orders: '
      '${timings.entries.map((e) => '${e.key}=${e.value.inMilliseconds}ms').join(', ')}',
    );
  });

  // Generous budgets: on a phone expect ~3–5× these desktop timings.
  const budget = Duration(milliseconds: 1500);

  test('every party balance matches the model', () async {
    for (final id in world.parties.keys) {
      expect(
        await db.watchPartyBalance(id).first,
        world.balance(id),
        reason: 'party $id',
      );
    }
  });

  test('dashboard totals equal the sum of party balances', () async {
    final now = DateTime(2026, 10, 1);
    final d = await timed('dashboard', () => db.watchDashboard(now).first);
    final balances = world.parties.keys.map(world.balance).toList();
    expect(
      d.receivables,
      balances.where((b) => b > 0).fold(0, (s, b) => s + b),
    );
    expect(d.payables, balances.where((b) => b < 0).fold(0, (s, b) => s - b));
    expect(d.debtors, balances.where((b) => b > 0).length);
    expect(
      d.openOrders,
      world.orders
          .where((o) => _World.counts(o.status))
          .where((o) => o.status != OrderStatus.delivered)
          .length,
    );
    expect(timings['dashboard']!, lessThan(budget));
  });

  test('collections list = every positive balance, biggest first', () async {
    final debtors = await timed('debtors', () => db.watchDebtors().first);
    final expected = world.parties.keys
        .where((id) => world.balance(id) > 0)
        .toSet();
    expect(debtors.map((d) => d.party.id).toSet(), expected);
    for (var i = 1; i < debtors.length; i++) {
      expect(debtors[i - 1].balance, greaterThanOrEqualTo(debtors[i].balance));
    }
    expect(timings['debtors']!, lessThan(budget));
  });

  test(
    'statements: running balance is consistent and ends on the balance',
    () async {
      for (final id in world.parties.keys.take(60)) {
        final s = await timed('statement', () => db.watchStatement(id).first);
        var running = 0;
        for (final e in s) {
          running += e.increasesBalance ? e.amount : -e.amount;
          expect(e.balance, running);
        }
        expect(running, world.balance(id), reason: 'party $id');
      }
      expect(timings['statement']!, lessThan(budget));
    },
  );

  test('order totals and paid amounts match the model', () async {
    final all = await timed(
      'orders list',
      () => db.watchOrderSummaries().first,
    );
    expect(all, hasLength(5000));
    final paid = <int, int>{};
    for (final p in world.payments) {
      if (p.order != null) paid[p.order!] = (paid[p.order!] ?? 0) + p.amount;
    }
    for (final s in all) {
      expect(s.totalPiasters, world.total(s.order.id));
      expect(s.paidPiasters, paid[s.order.id] ?? 0);
    }
    expect(timings['orders list']!, lessThan(budget));
  });

  test('stock and last prices per item match the model', () async {
    final items = await timed('items', () => db.watchItems().first);
    expect(items.map((i) => i.name).toSet(), _itemNames.toSet());
    for (final i in items) {
      expect(i.stock, closeTo(world.stock(i.name), 1e-6), reason: i.name);
      expect(i.tracked, world.adjustments.containsKey(i.name));
      // Latest counted sale line by (date, order id, line id).
      ({DateTime d, int o, int l, int p})? best;
      for (final o in world.orders) {
        if (o.kind != OrderKind.sale || !_World.counts(o.status)) continue;
        for (final l in o.lines.where((l) => l.name == i.name)) {
          final c = (d: o.date, o: o.id, l: l.id, p: l.price);
          if (best == null ||
              c.d.isAfter(best.d) ||
              (c.d == best.d &&
                  (c.o > best.o || (c.o == best.o && c.l > best.l)))) {
            best = c;
          }
        }
      }
      expect(i.lastSale, best?.p, reason: i.name);
    }
    expect(timings['items']!, lessThan(budget));
  });

  test('monthly reports add up and profit matches the model', () async {
    var sales = 0;
    var expensesSum = 0;
    for (
      var m = DateTime(2025, 1);
      m.isBefore(DateTime(2026, 12));
      m = DateTime(m.year, m.month + 1)
    ) {
      final to = DateTime(m.year, m.month + 1);
      final r = await timed(
        'monthly report',
        () => db.watchMonthlyReport(m, to).first,
      );
      sales += r.sales;
      expensesSum += r.expenses;

      var profit = 0;
      var lines = 0;
      for (final o in world.orders) {
        if (o.kind != OrderKind.sale || !_World.counts(o.status)) continue;
        if (o.date.isBefore(m) || !o.date.isBefore(to)) continue;
        for (final l in o.lines) {
          final c = world.avgCost(l.name);
          if (c == null) continue;
          profit += (l.qty * (l.price - c)).round();
          lines++;
        }
      }
      // Floating-point summation order may differ by a piaster per line.
      expect(r.grossProfit, closeTo(profit, lines), reason: '$m');
    }
    expect(
      sales,
      world.orders
          .where((o) => o.kind == OrderKind.sale && _World.counts(o.status))
          .fold(0, (s, o) => s + world.total(o.id)),
    );
    expect(expensesSum, world.expenses.fold(0, (s, e) => s + e.amount));
    expect(timings['monthly report']!, lessThan(budget));
  });

  test('excel export and backup/restore survive the full data set', () async {
    final excel = await timed('excel export', () => buildExcelReport(db));
    final book = Excel.decodeBytes(excel);
    expect(book.tables['الطلبات']!.maxRows, 5001);

    final dir = Directory.systemTemp.createTempSync('ledger_stress');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/backup.sqlite');
    await timed('snapshot', () => db.snapshotTo(file));
    final phone2 = AppDatabase(NativeDatabase.memory());
    addTearDown(phone2.close);
    final counts = await timed('restore', () => phone2.replaceAllFrom(file));
    expect(counts, (parties: 500, orders: 5000));
    for (final id in [1, 77, 250, 499]) {
      expect(await phone2.watchPartyBalance(id).first, world.balance(id));
    }
    expect(timings['excel export']!, lessThan(const Duration(seconds: 15)));
    expect(timings['restore']!, lessThan(const Duration(seconds: 5)));
  });
}
