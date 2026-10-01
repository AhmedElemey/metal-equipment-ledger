import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:sqlite3/sqlite3.dart' as raw;

part 'app_database.g.dart';

/// نوع الطرف: مشتري (عميل) أو بائع (مورد) أو الاثنين معاً.
enum PartyKind { buyer, seller, both }

/// بيع (للعميل) أو شراء (من المورد).
enum OrderKind { sale, purchase }

/// Stored by index: only ever append new values.
/// A [quotation] (عرض سعر) is a sale not yet agreed — like [cancelled], it
/// never counts towards balances, totals or collections.
enum OrderStatus { pending, inProgress, delivered, cancelled, quotation }

/// [received]: money from the party to us (settles sales).
/// [paid]: money from us to the party (settles purchases).
enum PaymentDirection { received, paid }

class Parties extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 120)();
  TextColumn get phone => text().nullable()();
  TextColumn get city => text().nullable()();
  IntColumn get kind => intEnum<PartyKind>()();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  /// When a payment reminder was last sent, so he doesn't nag twice a day.
  DateTimeColumn get lastRemindedAt => dateTime().nullable()();
}

class Orders extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get partyId =>
      integer().references(Parties, #id, onDelete: KeyAction.restrict)();
  IntColumn get kind => intEnum<OrderKind>()();
  IntColumn get status =>
      intEnum<OrderStatus>().withDefault(const Constant(0))();
  DateTimeColumn get date => dateTime()();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

class OrderItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get orderId =>
      integer().references(Orders, #id, onDelete: KeyAction.cascade)();
  TextColumn get name => text().withLength(min: 1, max: 200)();
  RealColumn get quantity => real()();
  TextColumn get unit => text().withDefault(const Constant('قطعة'))();

  /// Money is stored in piasters (1 EGP = 100) to avoid floating-point drift.
  IntColumn get unitPricePiasters => integer()();
}

class Payments extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get partyId =>
      integer().references(Parties, #id, onDelete: KeyAction.restrict)();

  /// Null for a payment "on account" not tied to one order. Deleting an
  /// order keeps its payments on the party's account — the money was real.
  IntColumn get orderId => integer().nullable().references(
    Orders,
    #id,
    onDelete: KeyAction.setNull,
  )();
  IntColumn get direction => intEnum<PaymentDirection>()();
  IntColumn get amountPiasters => integer()();
  DateTimeColumn get date => dateTime()();
  TextColumn get note => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// Manual stock corrections: an opening count or a physical count (جرد)
/// that differs from what orders imply. Positive adds, negative removes.
class StockAdjustments extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get itemName => text()();
  RealColumn get quantity => real()();
  DateTimeColumn get date => dateTime()();
  TextColumn get note => text().nullable()();
}

/// Per-item settings. An item with a row here (or any adjustment) is
/// "tracked": its stock is shown and its low-stock alert can fire.
class ItemSettings extends Table {
  TextColumn get itemName => text()();
  TextColumn get unit => text().nullable()();

  /// Alert when stock falls to or below this.
  RealColumn get minQuantity => real().nullable()();

  @override
  Set<Column> get primaryKey => {itemName};
}

/// Business costs not tied to an order: transport, loading, rent…
class Expenses extends Table {
  IntColumn get id => integer().autoIncrement()();
  DateTimeColumn get date => dateTime()();
  TextColumn get category => text()();
  IntColumn get amountPiasters => integer()();
  TextColumn get note => text().nullable()();
}

class VoiceNotes extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get partyId =>
      integer().references(Parties, #id, onDelete: KeyAction.cascade)();
  IntColumn get orderId => integer().nullable().references(
    Orders,
    #id,
    onDelete: KeyAction.setNull,
  )();

  /// File name only — the documents directory can move between installs.
  TextColumn get fileName => text()();
  IntColumn get durationMs => integer()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// An order row joined with its party name and computed totals.
class OrderSummary {
  const OrderSummary({
    required this.order,
    required this.partyName,
    required this.totalPiasters,
    required this.paidPiasters,
  });

  final Order order;
  final String partyName;
  final int totalPiasters;

  /// Sum of the payments linked to this order.
  final int paidPiasters;

  int get remainingPiasters => totalPiasters - paidPiasters;
}

class DashboardStats {
  const DashboardStats({
    required this.todaySales,
    required this.todayPurchases,
    required this.receivables,
    required this.payables,
    required this.debtors,
    required this.openOrders,
  });

  final int todaySales;
  final int todayPurchases;
  final int receivables;
  final int payables;

  /// Number of parties that owe us money.
  final int debtors;
  final int openOrders;
}

typedef DataCounts = ({int parties, int orders});

/// The last price one party got for an item, in piasters.
typedef PartyItemPrice = ({int price, DateTime at});

/// An item with its latest prices (in piasters) and stock.
class ItemSummary {
  const ItemSummary({
    required this.name,
    required this.unit,
    required this.lastSale,
    required this.lastSaleAt,
    required this.lastPurchase,
    required this.lastPurchaseAt,
    required this.stock,
    required this.tracked,
    required this.minQuantity,
  });

  final String name;

  /// The unit set for the item, else the one used in its latest order.
  final String unit;
  final int? lastSale;
  final DateTime? lastSaleAt;
  final int? lastPurchase;
  final DateTime? lastPurchaseAt;

  /// Purchases − sales (real orders) + manual adjustments.
  final double stock;

  /// True once he has counted the item or set its settings; only tracked
  /// items show stock and raise alerts, so old history doesn't nag.
  final bool tracked;
  final double? minQuantity;

  bool get isLow => tracked && minQuantity != null && stock <= minQuantity!;
}

/// The file isn't a backup of this app (or is damaged).
class InvalidBackup implements Exception {
  const InvalidBackup();
}

/// The backup was made by a newer app version — update the app first.
class BackupTooNew implements Exception {
  const BackupTooNew();
}

/// A party that owes us money, for the collections list.
class Debtor {
  const Debtor({
    required this.party,
    required this.balance,
    required this.lastPaymentAt,
    required this.firstSaleAt,
  });

  final Party party;
  final int balance;
  final DateTime? lastPaymentAt;
  final DateTime? firstSaleAt;

  /// Last time money came in from them — or, if never, when they first
  /// bought. This is what "how long has this been open" is measured from.
  DateTime? get lastActivityAt => lastPaymentAt ?? firstSaleAt;
}

/// One line of a statement of account (كشف حساب).
class StatementEntry {
  const StatementEntry({
    required this.date,
    required this.orderKind,
    required this.paymentDirection,
    required this.refId,
    required this.orderId,
    required this.amount,
    required this.note,
    required this.balance,
  });

  final DateTime date;

  /// Exactly one of [orderKind] / [paymentDirection] is set.
  final OrderKind? orderKind;
  final PaymentDirection? paymentDirection;

  /// The order id or the payment id.
  final int refId;

  /// For a payment: the order it settles, if any.
  final int? orderId;
  final int amount;
  final String? note;

  /// Running balance after this line; positive means they owe us.
  final int balance;

  bool get isPayment => paymentDirection != null;

  /// True when this line increases what they owe us (عليه), false when it
  /// decreases it (له).
  bool get increasesBalance =>
      orderKind == OrderKind.sale || paymentDirection == PaymentDirection.paid;
}

const _sale = 0; // OrderKind.sale.index
const _received = 0; // PaymentDirection.received.index
const _cancelled = 3; // OrderStatus.cancelled.index
const _quotation = 4; // OrderStatus.quotation.index

/// Orders that are real business: not cancelled and not a quotation.
const _counts = 'o.status NOT IN ($_cancelled, $_quotation)';

const _orderTotalSql =
    'COALESCE((SELECT SUM(CAST(ROUND(i.quantity * i.unit_price_piasters) AS INTEGER)) '
    'FROM order_items i WHERE i.order_id = o.id), 0)';

const _orderPaidSql =
    'COALESCE((SELECT SUM(pay.amount_piasters) FROM payments pay '
    'WHERE pay.order_id = o.id), 0)';

/// Net balance of party `p` — positive means they owe us. Sales and money we
/// paid them count for us; purchases and money they paid us count against.
const _partyBalanceSql =
    '(COALESCE((SELECT SUM(CASE WHEN o.kind = $_sale THEN $_orderTotalSql '
    'ELSE -$_orderTotalSql END) FROM orders o '
    'WHERE o.party_id = p.id AND $_counts), 0) '
    '- COALESCE((SELECT SUM(CASE WHEN pay.direction = $_received '
    'THEN pay.amount_piasters ELSE -pay.amount_piasters END) '
    'FROM payments pay WHERE pay.party_id = p.id), 0))';

@DriftDatabase(
  tables: [
    Parties,
    Orders,
    OrderItems,
    Payments,
    VoiceNotes,
    StockAdjustments,
    ItemSettings,
    Expenses,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _openConnection());

  static const fileName = 'metal_ledger';

  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        // v2: order "paid" amounts become real payment records.
        await m.createTable(payments);
        await m.addColumn(parties, parties.lastRemindedAt);
        await customStatement(
          'INSERT INTO payments '
          '(party_id, order_id, direction, amount_piasters, date, created_at) '
          'SELECT party_id, id, '
          'CASE kind WHEN $_sale THEN $_received ELSE 1 END, '
          'paid_piasters, date, created_at FROM orders WHERE paid_piasters > 0',
        );
        await m.alterTable(TableMigration(orders)); // drops paid_piasters
      }
      if (from < 3) {
        await m.createTable(stockAdjustments);
        await m.createTable(itemSettings);
      }
      if (from < 4) await m.createTable(expenses);
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  // The background backup task opens the same file from another isolate.
  static QueryExecutor _openConnection() => driftDatabase(
    name: fileName,
    native: const DriftNativeOptions(shareAcrossIsolates: true),
  );

  // ---------------------------------------------------------------- parties

  Stream<List<Party>> watchParties({String query = ''}) {
    final q = select(parties)..orderBy([(p) => OrderingTerm.asc(p.name)]);
    final term = query.trim();
    if (term.isNotEmpty) {
      q.where((p) => p.name.contains(term) | p.phone.contains(term));
    }
    return q.watch();
  }

  Stream<Party> watchParty(int id) =>
      (select(parties)..where((p) => p.id.equals(id))).watchSingle();

  Future<Party> getParty(int id) =>
      (select(parties)..where((p) => p.id.equals(id))).getSingle();

  Future<int> saveParty(PartiesCompanion entry) =>
      into(parties).insertOnConflictUpdate(entry);

  /// Fails (foreign key) if the party still has orders or payments — by
  /// design, history must never disappear silently.
  Future<void> deleteParty(int id) =>
      (delete(parties)..where((p) => p.id.equals(id))).go();

  /// True if the party has any order or payment, which blocks deletion.
  Future<bool> hasHistory(int partyId) async {
    final row = await customSelect(
      'SELECT EXISTS(SELECT 1 FROM orders WHERE party_id = ?1) '
      'OR EXISTS(SELECT 1 FROM payments WHERE party_id = ?1) AS has',
      variables: [Variable.withInt(partyId)],
    ).getSingle();
    return row.read<bool>('has');
  }

  Future<void> markReminded(int partyId, DateTime at) =>
      (update(parties)..where((p) => p.id.equals(partyId))).write(
        PartiesCompanion(lastRemindedAt: Value(at)),
      );

  /// Net balance; positive means they owe us, negative means we owe them.
  Stream<int> watchPartyBalance(int partyId) {
    return customSelect(
      'SELECT $_partyBalanceSql AS balance FROM parties p WHERE p.id = ?',
      variables: [Variable.withInt(partyId)],
      readsFrom: {parties, orders, orderItems, payments},
    ).watchSingle().map((row) => row.read<int>('balance'));
  }

  /// Net balance of every party, by id.
  Future<Map<int, int>> partyBalances() async {
    final rows = await customSelect(
      'SELECT p.id AS id, $_partyBalanceSql AS balance FROM parties p',
    ).get();
    return {for (final r in rows) r.read<int>('id'): r.read<int>('balance')};
  }

  /// Parties that owe us, largest balance first.
  Stream<List<Debtor>> watchDebtors() {
    return customSelect(
      'SELECT * FROM (SELECT p.*, $_partyBalanceSql AS balance, '
      '(SELECT MAX(pay.date) FROM payments pay WHERE pay.party_id = p.id '
      'AND pay.direction = $_received) AS last_payment, '
      '(SELECT MIN(o.date) FROM orders o WHERE o.party_id = p.id '
      'AND o.kind = $_sale AND $_counts) AS first_sale '
      'FROM parties p) WHERE balance > 0 ORDER BY balance DESC',
      readsFrom: {parties, orders, orderItems, payments},
    ).watch().map(
      (rows) => [
        for (final row in rows)
          Debtor(
            party: parties.map(row.data),
            balance: row.read<int>('balance'),
            lastPaymentAt: row.readNullable<DateTime>('last_payment'),
            firstSaleAt: row.readNullable<DateTime>('first_sale'),
          ),
      ],
    );
  }

  /// Orders (not cancelled) and payments in date order, with a running
  /// balance. Positive balance means they owe us.
  Stream<List<StatementEntry>> watchStatement(int partyId) {
    return customSelect(
      'SELECT 0 AS is_payment, o.id AS ref_id, o.kind AS kind, '
      'o.date AS date, o.created_at AS created_at, NULL AS order_id, '
      '$_orderTotalSql AS amount, o.notes AS note '
      'FROM orders o WHERE o.party_id = ?1 AND $_counts '
      'UNION ALL '
      'SELECT 1, pay.id, pay.direction, pay.date, pay.created_at, '
      'pay.order_id, pay.amount_piasters, pay.note '
      'FROM payments pay WHERE pay.party_id = ?1 '
      'ORDER BY date, created_at, is_payment',
      variables: [Variable.withInt(partyId)],
      readsFrom: {orders, orderItems, payments},
    ).watch().map((rows) {
      var balance = 0;
      final entries = <StatementEntry>[];
      for (final row in rows) {
        final isPayment = row.read<int>('is_payment') == 1;
        final kind = row.read<int>('kind');
        final amount = row.read<int>('amount');
        final orderKind = isPayment ? null : OrderKind.values[kind];
        final direction = isPayment ? PaymentDirection.values[kind] : null;
        final increases =
            orderKind == OrderKind.sale || direction == PaymentDirection.paid;
        balance += increases ? amount : -amount;
        entries.add(
          StatementEntry(
            date: row.read<DateTime>('date'),
            orderKind: orderKind,
            paymentDirection: direction,
            refId: row.read<int>('ref_id'),
            orderId: row.readNullable<int>('order_id'),
            amount: amount,
            note: row.readNullable<String>('note'),
            balance: balance,
          ),
        );
      }
      return entries;
    });
  }

  // ----------------------------------------------------------------- orders

  /// [quotations]: null = everything, true = only quotations,
  /// false = only real orders.
  Stream<List<OrderSummary>> watchOrderSummaries({
    int? partyId,
    OrderKind? kind,
    bool? quotations,
    int? limit,
  }) {
    final where = <String>[];
    final vars = <Variable>[];
    if (quotations != null) {
      where.add('o.status ${quotations ? '=' : '!='} $_quotation');
    }
    if (partyId != null) {
      where.add('o.party_id = ?');
      vars.add(Variable.withInt(partyId));
    }
    if (kind != null) {
      where.add('o.kind = ${kind.index}');
    }
    final whereSql = where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}';
    final limitSql = limit == null ? '' : 'LIMIT $limit';
    return customSelect(
      'SELECT o.*, p.name AS party_name, $_orderTotalSql AS total, '
      '$_orderPaidSql AS paid '
      'FROM orders o JOIN parties p ON p.id = o.party_id '
      '$whereSql ORDER BY o.date DESC, o.id DESC $limitSql',
      variables: vars,
      readsFrom: {orders, orderItems, parties, payments},
    ).watch().map((rows) => rows.map(_toSummary).toList());
  }

  Stream<OrderSummary> watchOrderSummary(int id) {
    return customSelect(
      'SELECT o.*, p.name AS party_name, $_orderTotalSql AS total, '
      '$_orderPaidSql AS paid '
      'FROM orders o JOIN parties p ON p.id = o.party_id WHERE o.id = ?',
      variables: [Variable.withInt(id)],
      readsFrom: {orders, orderItems, parties, payments},
    ).watchSingle().map(_toSummary);
  }

  OrderSummary _toSummary(QueryRow row) => OrderSummary(
    order: orders.map(row.data),
    partyName: row.read<String>('party_name'),
    totalPiasters: row.read<int>('total'),
    paidPiasters: row.read<int>('paid'),
  );

  Future<Order> getOrder(int id) =>
      (select(orders)..where((o) => o.id.equals(id))).getSingle();

  Future<List<OrderItem>> itemsOf(int orderId) =>
      (select(orderItems)..where((i) => i.orderId.equals(orderId))).get();

  Stream<List<OrderItem>> watchItemsOf(int orderId) =>
      (select(orderItems)..where((i) => i.orderId.equals(orderId))).watch();

  /// Inserts or replaces an order together with its line items atomically.
  /// [downPayment] (new orders only) is recorded as a payment on the order.
  Future<int> saveOrder(
    OrdersCompanion order,
    List<OrderItemsCompanion> items, {
    int downPayment = 0,
  }) {
    return transaction(() async {
      final id = await into(orders).insertOnConflictUpdate(order);
      final orderId = order.id.present ? order.id.value : id;
      await (delete(orderItems)..where((i) => i.orderId.equals(orderId))).go();
      await batch(
        (b) => b.insertAll(
          orderItems,
          items.map((i) => i.copyWith(orderId: Value(orderId))),
        ),
      );
      if (downPayment > 0) {
        await into(payments).insert(
          PaymentsCompanion.insert(
            partyId: order.partyId.value,
            orderId: Value(orderId),
            direction: order.kind.value == OrderKind.sale
                ? PaymentDirection.received
                : PaymentDirection.paid,
            amountPiasters: downPayment,
            date: order.date.value,
          ),
        );
      }
      return orderId;
    });
  }

  Future<void> updateOrderStatus(int id, OrderStatus status) =>
      (update(orders)..where((o) => o.id.equals(id))).write(
        OrdersCompanion(status: Value(status)),
      );

  /// The client accepted the quotation: it becomes a sale dated today.
  Future<void> convertQuotation(int id, DateTime today) =>
      (update(orders)..where((o) => o.id.equals(id))).write(
        OrdersCompanion(
          status: const Value(OrderStatus.pending),
          date: Value(today),
        ),
      );

  Future<void> deleteOrder(int id) =>
      (delete(orders)..where((o) => o.id.equals(id))).go();

  /// Every item (from real orders, stock counts or settings) with its last
  /// sale and purchase price and current stock, most recently used first.
  Stream<List<ItemSummary>> watchItems() {
    return customSelect(
      'WITH lines AS ('
      'SELECT i.name, i.unit, i.quantity, i.unit_price_piasters AS price, '
      'o.kind, o.date, o.id AS oid, i.id AS iid '
      'FROM order_items i JOIN orders o ON o.id = i.order_id WHERE $_counts), '
      'ranked AS (SELECT *, ROW_NUMBER() OVER (PARTITION BY name, kind '
      'ORDER BY date DESC, oid DESC, iid DESC) AS rn FROM lines), '
      'names AS (SELECT name FROM lines '
      'UNION SELECT item_name FROM stock_adjustments '
      'UNION SELECT item_name FROM item_settings) '
      'SELECT n.name, '
      '(SELECT price FROM ranked WHERE name = n.name AND kind = $_sale AND rn = 1) AS last_sale, '
      '(SELECT date FROM ranked WHERE name = n.name AND kind = $_sale AND rn = 1) AS last_sale_at, '
      '(SELECT price FROM ranked WHERE name = n.name AND kind != $_sale AND rn = 1) AS last_purchase, '
      '(SELECT date FROM ranked WHERE name = n.name AND kind != $_sale AND rn = 1) AS last_purchase_at, '
      "COALESCE((SELECT unit FROM item_settings WHERE item_name = n.name), "
      "(SELECT unit FROM ranked WHERE name = n.name AND rn = 1 ORDER BY date DESC LIMIT 1), 'قطعة') AS unit, "
      'COALESCE((SELECT SUM(CASE WHEN kind = $_sale THEN -quantity ELSE quantity END) '
      'FROM lines WHERE name = n.name), 0) + '
      'COALESCE((SELECT SUM(quantity) FROM stock_adjustments WHERE item_name = n.name), 0) AS stock, '
      '(EXISTS(SELECT 1 FROM stock_adjustments WHERE item_name = n.name) OR '
      'EXISTS(SELECT 1 FROM item_settings WHERE item_name = n.name)) AS tracked, '
      '(SELECT min_quantity FROM item_settings WHERE item_name = n.name) AS min_quantity, '
      'MAX(COALESCE((SELECT MAX(date) FROM lines WHERE name = n.name), 0), '
      'COALESCE((SELECT MAX(date) FROM stock_adjustments WHERE item_name = n.name), 0)) AS last_used '
      'FROM names n ORDER BY last_used DESC, n.name',
      readsFrom: {orders, orderItems, stockAdjustments, itemSettings},
    ).watch().map(
      (rows) => [
        for (final r in rows)
          ItemSummary(
            name: r.read<String>('name'),
            unit: r.read<String>('unit'),
            lastSale: r.readNullable<int>('last_sale'),
            lastSaleAt: r.readNullable<DateTime>('last_sale_at'),
            lastPurchase: r.readNullable<int>('last_purchase'),
            lastPurchaseAt: r.readNullable<DateTime>('last_purchase_at'),
            stock: r.read<double>('stock'),
            tracked: r.read<bool>('tracked'),
            minQuantity: r.readNullable<double>('min_quantity'),
          ),
      ],
    );
  }

  /// Records a physical count: adds the difference to reach [actual].
  Future<void> recordStockCount(
    String itemName, {
    required double current,
    required double actual,
    required DateTime date,
    String? note,
  }) => into(stockAdjustments).insert(
    StockAdjustmentsCompanion.insert(
      itemName: itemName,
      quantity: actual - current,
      date: date,
      note: Value(note),
    ),
  );

  Future<void> saveItemSettings(
    String itemName, {
    String? unit,
    double? minQuantity,
  }) => into(itemSettings).insertOnConflictUpdate(
    ItemSettingsCompanion.insert(
      itemName: itemName,
      unit: Value(unit),
      minQuantity: Value(minQuantity),
    ),
  );

  /// The last price [partyId] got for each item in real orders of [kind],
  /// keyed by item name. [excludeOrderId] leaves out the order being edited.
  Stream<Map<String, PartyItemPrice>> watchPartyItemPrices({
    required int partyId,
    required OrderKind kind,
    int? excludeOrderId,
  }) {
    return customSelect(
      'SELECT name, price, date FROM ('
      'SELECT i.name, i.unit_price_piasters AS price, o.date, '
      'ROW_NUMBER() OVER (PARTITION BY i.name '
      'ORDER BY o.date DESC, o.id DESC, i.id DESC) AS rn '
      'FROM order_items i JOIN orders o ON o.id = i.order_id '
      'WHERE o.party_id = ?1 AND o.kind = ?2 AND o.id != ?3 AND $_counts'
      ') WHERE rn = 1',
      variables: [
        Variable.withInt(partyId),
        Variable.withInt(kind.index),
        Variable.withInt(excludeOrderId ?? -1),
      ],
      readsFrom: {orders, orderItems},
    ).watch().map(
      (rows) => {
        for (final r in rows)
          r.read<String>('name'): (
            price: r.read<int>('price'),
            at: r.read<DateTime>('date'),
          ),
      },
    );
  }

  // --------------------------------------------------------------- expenses

  /// Expenses dated within [from, to), newest first.
  Stream<List<Expense>> watchExpenses(DateTime from, DateTime to) =>
      (select(expenses)
            ..where((e) => e.date.isBiggerOrEqualValue(from))
            ..where((e) => e.date.isSmallerThanValue(to))
            ..orderBy([
              (e) => OrderingTerm.desc(e.date),
              (e) => OrderingTerm.desc(e.id),
            ]))
          .watch();

  Future<int> addExpense(ExpensesCompanion entry) =>
      into(expenses).insert(entry);

  Future<void> deleteExpense(int id) =>
      (delete(expenses)..where((e) => e.id.equals(id))).go();

  // --------------------------------------------------------------- payments

  Future<int> addPayment(PaymentsCompanion entry) =>
      into(payments).insert(entry);

  Future<void> deletePayment(int id) =>
      (delete(payments)..where((p) => p.id.equals(id))).go();

  Stream<List<Payment>> watchPaymentsOf(int orderId) =>
      (select(payments)
            ..where((p) => p.orderId.equals(orderId))
            ..orderBy([(p) => OrderingTerm.asc(p.date)]))
          .watch();

  // -------------------------------------------------------------- dashboard

  Stream<DashboardStats> watchDashboard(DateTime now) {
    final dayStart = DateTime(now.year, now.month, now.day);
    final dayEnd = dayStart.add(const Duration(days: 1));
    final delivered = OrderStatus.delivered.index;
    return customSelect(
      'SELECT '
      'COALESCE((SELECT SUM($_orderTotalSql) FROM orders o WHERE o.kind = $_sale '
      'AND $_counts AND o.date >= ?1 AND o.date < ?2), 0) AS today_sales, '
      'COALESCE((SELECT SUM($_orderTotalSql) FROM orders o WHERE o.kind != $_sale '
      'AND $_counts AND o.date >= ?1 AND o.date < ?2), 0) AS today_purchases, '
      'COALESCE((SELECT COUNT(*) FROM orders o WHERE $_counts '
      'AND o.status != $delivered), 0) AS open_orders, '
      'COALESCE(SUM(MAX(b.balance, 0)), 0) AS receivables, '
      'COALESCE(SUM(MAX(-b.balance, 0)), 0) AS payables, '
      'COALESCE(SUM(b.balance > 0), 0) AS debtors '
      'FROM (SELECT $_partyBalanceSql AS balance FROM parties p) b',
      variables: [
        Variable.withDateTime(dayStart),
        Variable.withDateTime(dayEnd),
      ],
      readsFrom: {parties, orders, orderItems, payments},
    ).watchSingle().map(
      (row) => DashboardStats(
        todaySales: row.read<int>('today_sales'),
        todayPurchases: row.read<int>('today_purchases'),
        receivables: row.read<int>('receivables'),
        payables: row.read<int>('payables'),
        debtors: row.read<int>('debtors'),
        openOrders: row.read<int>('open_orders'),
      ),
    );
  }

  // ------------------------------------------------------------ voice notes

  Stream<List<VoiceNote>> watchVoiceNotes({
    required int partyId,
    int? orderId,
  }) {
    final q = select(voiceNotes)
      ..where((v) => v.partyId.equals(partyId))
      ..orderBy([(v) => OrderingTerm.desc(v.createdAt)]);
    if (orderId != null) q.where((v) => v.orderId.equals(orderId));
    return q.watch();
  }

  Future<int> addVoiceNote(VoiceNotesCompanion entry) =>
      into(voiceNotes).insert(entry);

  Future<void> deleteVoiceNote(int id) =>
      (delete(voiceNotes)..where((v) => v.id.equals(id))).go();

  // ----------------------------------------------------------------- backup

  Future<DataCounts> counts() async {
    final row = await customSelect(
      'SELECT (SELECT COUNT(*) FROM parties) AS parties, '
      '(SELECT COUNT(*) FROM orders) AS orders',
    ).getSingle();
    return (parties: row.read<int>('parties'), orders: row.read<int>('orders'));
  }

  /// Replaces every row with the contents of the backup file [backup].
  ///
  /// Works on the live connection (no file swap), so open screens refresh
  /// by themselves. The backup is first brought to the current schema by
  /// opening it with this app's migrations; [backup] is modified by that.
  Future<DataCounts> replaceAllFrom(File backup) async {
    _checkBackup(backup);
    final upgraded = AppDatabase(NativeDatabase(backup));
    try {
      await upgraded.customSelect('SELECT 1').get(); // runs migrations
    } finally {
      await upgraded.close();
    }

    // Children first when deleting, parents first when inserting.
    final ordered = <TableInfo>[
      parties,
      orders,
      orderItems,
      payments,
      voiceNotes,
      stockAdjustments,
      itemSettings,
      expenses,
    ];
    await customStatement('ATTACH DATABASE ? AS backup', [backup.path]);
    try {
      await transaction(() async {
        for (final t in ordered.reversed) {
          await customStatement('DELETE FROM main.${t.actualTableName}');
        }
        for (final t in ordered) {
          final cols = t.$columns.map((c) => '"${c.name}"').join(', ');
          await customStatement(
            'INSERT INTO main.${t.actualTableName} ($cols) '
            'SELECT $cols FROM backup.${t.actualTableName}',
          );
        }
      });
    } finally {
      await customStatement('DETACH DATABASE backup');
    }
    markTablesUpdated(allTables);
    return counts();
  }

  /// Rejects files that aren't a readable backup of this app.
  void _checkBackup(File file) {
    final int version;
    try {
      final db = raw.sqlite3.open(file.path, mode: raw.OpenMode.readOnly);
      try {
        final ok = db.select('PRAGMA quick_check').first.columnAt(0) == 'ok';
        final tables = db
            .select("SELECT name FROM sqlite_master WHERE type = 'table'")
            .map((r) => r.columnAt(0) as String)
            .toSet();
        if (!ok || !tables.containsAll(['parties', 'orders', 'order_items'])) {
          throw const InvalidBackup();
        }
        version = db.userVersion;
      } finally {
        db.close();
      }
    } on raw.SqliteException {
      throw const InvalidBackup();
    }
    if (version < 1) throw const InvalidBackup();
    if (version > schemaVersion) throw const BackupTooNew();
  }

  /// Writes a consistent snapshot of the live database to [target].
  Future<void> snapshotTo(File target) async {
    if (target.existsSync()) target.deleteSync();
    await customStatement('VACUUM INTO ?', [target.path]);
  }
}
