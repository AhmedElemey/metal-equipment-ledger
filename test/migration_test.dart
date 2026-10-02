import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metal_ledger/core/database/app_database.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test('v1 → v2 turns paid amounts into payments and keeps data', () async {
    final dir = Directory.systemTemp.createTempSync('ledger_migration');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/v1.sqlite');

    // Build a real v1 database from the schema shipped in the first release.
    final raw = sqlite3.open(file.path);
    for (final sql in File('test/schema_v1.sql').readAsLinesSync()) {
      if (sql.trim().isNotEmpty) raw.execute(sql);
    }
    raw.execute('''
      INSERT INTO parties (id, name, kind) VALUES (1, 'عميل', 0), (2, 'مورد', 1);
      INSERT INTO orders (id, party_id, kind, date, paid_piasters)
        VALUES (1, 1, 0, 1767225600, 50000),
               (2, 2, 1, 1767312000, 20000),
               (3, 1, 0, 1767398400, 0);
      INSERT INTO order_items (order_id, name, quantity, unit_price_piasters)
        VALUES (1, 'صاج', 1, 100000), (2, 'حديد', 1, 30000),
               (3, 'زاوية', 2, 10000);
      PRAGMA user_version = 1;
    ''');
    raw.close();

    final db = AppDatabase(NativeDatabase(file));
    addTearDown(db.close);

    final payments = await db.select(db.payments).get();
    expect(payments, hasLength(2));
    final sale = payments.singleWhere((p) => p.orderId == 1);
    expect(sale.direction, PaymentDirection.received);
    expect(sale.amountPiasters, 50000);
    expect(sale.partyId, 1);
    expect(sale.date, DateTime.fromMillisecondsSinceEpoch(1767225600 * 1000));
    final purchase = payments.singleWhere((p) => p.orderId == 2);
    expect(purchase.direction, PaymentDirection.paid);

    // Balances are unchanged by the migration.
    expect((await db.watchOrderSummary(1).first).remainingPiasters, 50000);
    expect(await db.watchPartyBalance(1).first, 50000 + 20000);
    expect(await db.watchPartyBalance(2).first, -10000);
    expect(await db.itemsOf(3), hasLength(1));

    final fkErrors = await db.customSelect('PRAGMA foreign_key_check').get();
    expect(fkErrors, isEmpty);

    // Later versions' tables and indexes exist after upgrading from v1.
    final names =
        (await db
                .customSelect(
                  "SELECT name FROM sqlite_master WHERE type IN ('table', 'index')",
                )
                .get())
            .map((r) => r.read<String>('name'))
            .toSet();
    expect(
      names,
      containsAll([
        'stock_adjustments',
        'item_settings',
        'expenses',
        'orders_party',
        'order_items_order',
        'payments_party',
      ]),
    );
  });
}
