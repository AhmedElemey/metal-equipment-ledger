import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metal_ledger/core/database/app_database.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('ledger_restore'));
  tearDown(() => dir.deleteSync(recursive: true));

  Future<void> seed(AppDatabase db, String name, {int price = 100000}) async {
    final party = await db.saveParty(
      PartiesCompanion.insert(name: name, kind: PartyKind.buyer),
    );
    final order = await db.saveOrder(
      OrdersCompanion.insert(
        partyId: party,
        kind: OrderKind.sale,
        date: DateTime(2026, 9, 1),
      ),
      [
        OrderItemsCompanion.insert(
          orderId: 0,
          name: 'صاج',
          quantity: 1,
          unitPricePiasters: price,
        ),
      ],
      downPayment: 40000,
    );
    await db.addVoiceNote(
      VoiceNotesCompanion.insert(
        partyId: party,
        orderId: Value(order),
        fileName: 'note_1.m4a',
        durationMs: 3000,
      ),
    );
  }

  test('restore replaces everything and refreshes open streams', () async {
    final phone1 = AppDatabase(NativeDatabase.memory());
    await seed(phone1, 'الحاج محمود');
    await seed(phone1, 'ورشة النور', price: 250000);
    final backup = File('${dir.path}/backup.sqlite');
    await phone1.snapshotTo(backup);
    await phone1.close();

    final phone2 = AppDatabase(NativeDatabase.memory());
    addTearDown(phone2.close);
    await seed(phone2, 'بيانات قديمة'); // will be replaced
    final names = phone2.watchParties().map((l) => l.map((p) => p.name));
    final emitted = expectLater(
      names,
      emitsThrough(unorderedEquals(['الحاج محمود', 'ورشة النور'])),
    );

    final counts = await phone2.replaceAllFrom(backup);

    expect(counts, (parties: 2, orders: 2));
    await emitted;
    final debtors = await phone2.watchDebtors().first;
    expect(debtors.map((d) => d.balance), [210000, 60000]);
    expect(await phone2.select(phone2.voiceNotes).get(), hasLength(2));
    expect(
      await phone2.customSelect('PRAGMA foreign_key_check').get(),
      isEmpty,
    );

    // New rows after a restore don't collide with restored ids.
    await seed(phone2, 'عميل جديد');
    expect((await phone2.counts()).parties, 3);
  });

  test('a v1 backup is upgraded while restoring', () async {
    final backup = File('${dir.path}/v1.sqlite');
    final v1 = sqlite3.open(backup.path);
    for (final sql in File('test/schema_v1.sql').readAsLinesSync()) {
      if (sql.trim().isNotEmpty) v1.execute(sql);
    }
    v1.execute('''
      INSERT INTO parties (id, name, kind) VALUES (1, 'عميل', 0);
      INSERT INTO orders (id, party_id, kind, date, paid_piasters)
        VALUES (1, 1, 0, 1767225600, 30000);
      INSERT INTO order_items (order_id, name, quantity, unit_price_piasters)
        VALUES (1, 'صاج', 1, 100000);
      PRAGMA user_version = 1;
    ''');
    v1.close();

    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.replaceAllFrom(backup);

    expect(await db.watchPartyBalance(1).first, 70000);
    expect(await db.select(db.payments).get(), hasLength(1));
  });

  test('rejects files that are not a backup, keeping current data', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await seed(db, 'الحاج محمود');

    final junk = File('${dir.path}/junk.sqlite')
      ..writeAsBytesSync(List.filled(4096, 7));
    await expectLater(db.replaceAllFrom(junk), throwsA(isA<InvalidBackup>()));

    final other = File('${dir.path}/other.sqlite');
    sqlite3.open(other.path)
      ..execute('CREATE TABLE notes (id INTEGER); PRAGMA user_version = 1;')
      ..close();
    await expectLater(db.replaceAllFrom(other), throwsA(isA<InvalidBackup>()));

    expect((await db.counts()).parties, 1);
  });

  test('rejects a backup from a newer app version', () async {
    final source = AppDatabase(NativeDatabase.memory());
    await seed(source, 'عميل');
    final backup = File('${dir.path}/new.sqlite');
    await source.snapshotTo(backup);
    await source.close();
    sqlite3.open(backup.path)
      ..execute('PRAGMA user_version = 99')
      ..close();

    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await expectLater(db.replaceAllFrom(backup), throwsA(isA<BackupTooNew>()));
  });
}
