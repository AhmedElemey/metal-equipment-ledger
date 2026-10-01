import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'app_database.g.dart';

/// نوع الطرف: مشتري (عميل) أو بائع (مورد) أو الاثنين معاً.
enum PartyKind { buyer, seller, both }

/// بيع (للعميل) أو شراء (من المورد).
enum OrderKind { sale, purchase }

enum OrderStatus { pending, inProgress, delivered, cancelled }

class Parties extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 120)();
  TextColumn get phone => text().nullable()();
  TextColumn get city => text().nullable()();
  IntColumn get kind => intEnum<PartyKind>()();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

class Orders extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get partyId =>
      integer().references(Parties, #id, onDelete: KeyAction.restrict)();
  IntColumn get kind => intEnum<OrderKind>()();
  IntColumn get status =>
      intEnum<OrderStatus>().withDefault(const Constant(0))();
  DateTimeColumn get date => dateTime()();

  /// Money is stored in piasters (1 EGP = 100) to avoid floating-point drift.
  IntColumn get paidPiasters => integer().withDefault(const Constant(0))();
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
  IntColumn get unitPricePiasters => integer()();
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
  });

  final Order order;
  final String partyName;
  final int totalPiasters;

  int get remainingPiasters => totalPiasters - order.paidPiasters;
}

/// What a party owes us (sales) and what we owe them (purchases).
class PartyBalance {
  const PartyBalance({required this.dueFromThem, required this.dueToThem});

  final int dueFromThem;
  final int dueToThem;
}

class DashboardStats {
  const DashboardStats({
    required this.todaySales,
    required this.todayPurchases,
    required this.receivables,
    required this.payables,
    required this.openOrders,
  });

  final int todaySales;
  final int todayPurchases;
  final int receivables;
  final int payables;
  final int openOrders;
}

const _orderTotalSql =
    'COALESCE((SELECT SUM(CAST(ROUND(i.quantity * i.unit_price_piasters) AS INTEGER)) '
    'FROM order_items i WHERE i.order_id = o.id), 0)';

@DriftDatabase(tables: [Parties, Orders, OrderItems, VoiceNotes])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _openConnection());

  static const fileName = 'metal_ledger';

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
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

  /// Fails (foreign key) if the party still has orders — by design, history
  /// must never disappear silently.
  Future<void> deleteParty(int id) =>
      (delete(parties)..where((p) => p.id.equals(id))).go();

  Stream<PartyBalance> watchPartyBalance(int partyId) {
    return customSelect(
      'SELECT '
      'COALESCE(SUM(CASE WHEN o.kind = ${OrderKind.sale.index} THEN $_orderTotalSql - o.paid_piasters END), 0) AS due_from, '
      'COALESCE(SUM(CASE WHEN o.kind = ${OrderKind.purchase.index} THEN $_orderTotalSql - o.paid_piasters END), 0) AS due_to '
      'FROM orders o WHERE o.party_id = ? AND o.status != ${OrderStatus.cancelled.index}',
      variables: [Variable.withInt(partyId)],
      readsFrom: {orders, orderItems},
    ).watchSingle().map(
      (row) => PartyBalance(
        dueFromThem: row.read<int>('due_from'),
        dueToThem: row.read<int>('due_to'),
      ),
    );
  }

  // ----------------------------------------------------------------- orders

  Stream<List<OrderSummary>> watchOrderSummaries({
    int? partyId,
    OrderKind? kind,
    int? limit,
  }) {
    final where = <String>[];
    final vars = <Variable>[];
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
      'SELECT o.*, p.name AS party_name, $_orderTotalSql AS total '
      'FROM orders o JOIN parties p ON p.id = o.party_id '
      '$whereSql ORDER BY o.date DESC, o.id DESC $limitSql',
      variables: vars,
      readsFrom: {orders, orderItems, parties},
    ).watch().map((rows) => rows.map(_toSummary).toList());
  }

  Stream<OrderSummary> watchOrderSummary(int id) {
    return customSelect(
      'SELECT o.*, p.name AS party_name, $_orderTotalSql AS total '
      'FROM orders o JOIN parties p ON p.id = o.party_id WHERE o.id = ?',
      variables: [Variable.withInt(id)],
      readsFrom: {orders, orderItems, parties},
    ).watchSingle().map(_toSummary);
  }

  OrderSummary _toSummary(QueryRow row) => OrderSummary(
    order: orders.map(row.data),
    partyName: row.read<String>('party_name'),
    totalPiasters: row.read<int>('total'),
  );

  Future<Order> getOrder(int id) =>
      (select(orders)..where((o) => o.id.equals(id))).getSingle();

  Future<List<OrderItem>> itemsOf(int orderId) =>
      (select(orderItems)..where((i) => i.orderId.equals(orderId))).get();

  Stream<List<OrderItem>> watchItemsOf(int orderId) =>
      (select(orderItems)..where((i) => i.orderId.equals(orderId))).watch();

  /// Inserts or replaces an order together with its line items atomically.
  Future<int> saveOrder(
    OrdersCompanion order,
    List<OrderItemsCompanion> items,
  ) {
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
      return orderId;
    });
  }

  Future<void> updateOrderStatus(int id, OrderStatus status) =>
      (update(orders)..where((o) => o.id.equals(id))).write(
        OrdersCompanion(status: Value(status)),
      );

  Future<void> updatePaid(int id, int paidPiasters) =>
      (update(orders)..where((o) => o.id.equals(id))).write(
        OrdersCompanion(paidPiasters: Value(paidPiasters)),
      );

  Future<void> deleteOrder(int id) =>
      (delete(orders)..where((o) => o.id.equals(id))).go();

  // -------------------------------------------------------------- dashboard

  Stream<DashboardStats> watchDashboard(DateTime now) {
    final dayStart = DateTime(now.year, now.month, now.day);
    final dayEnd = dayStart.add(const Duration(days: 1));
    const sale = 0;
    const purchase = 1;
    final cancelled = OrderStatus.cancelled.index;
    final delivered = OrderStatus.delivered.index;
    return customSelect(
      'SELECT '
      'COALESCE(SUM(CASE WHEN o.kind = $sale AND o.date >= ?1 AND o.date < ?2 THEN $_orderTotalSql END), 0) AS today_sales, '
      'COALESCE(SUM(CASE WHEN o.kind = $purchase AND o.date >= ?1 AND o.date < ?2 THEN $_orderTotalSql END), 0) AS today_purchases, '
      'COALESCE(SUM(CASE WHEN o.kind = $sale THEN $_orderTotalSql - o.paid_piasters END), 0) AS receivables, '
      'COALESCE(SUM(CASE WHEN o.kind = $purchase THEN $_orderTotalSql - o.paid_piasters END), 0) AS payables, '
      'COALESCE(SUM(CASE WHEN o.status != $delivered THEN 1 END), 0) AS open_orders '
      'FROM orders o WHERE o.status != $cancelled',
      variables: [
        Variable.withDateTime(dayStart),
        Variable.withDateTime(dayEnd),
      ],
      readsFrom: {orders, orderItems},
    ).watchSingle().map(
      (row) => DashboardStats(
        todaySales: row.read<int>('today_sales'),
        todayPurchases: row.read<int>('today_purchases'),
        receivables: row.read<int>('receivables'),
        payables: row.read<int>('payables'),
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

  /// Writes a consistent snapshot of the live database to [target].
  Future<void> snapshotTo(File target) async {
    if (target.existsSync()) target.deleteSync();
    await customStatement('VACUUM INTO ?', [target.path]);
  }
}
