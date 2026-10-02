import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metal_ledger/core/database/app_database.dart';
import 'package:metal_ledger/core/router.dart';
import 'package:metal_ledger/features/backup/data/drive_backup.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support.dart';

/// Seeds a client with one sale order (2 × 1,500 EGP) and returns the ids.
Future<({int party, int order})> _seedSale(
  WidgetTester tester,
  AppDatabase db, {
  OrderStatus status = OrderStatus.pending,
}) async {
  return (await tester.runAsync(() async {
    final party = await db.saveParty(
      PartiesCompanion.insert(
        name: 'الحاج محمود',
        kind: PartyKind.buyer,
        phone: const Value('01001234567'),
      ),
    );
    final order = await db.saveOrder(
      OrdersCompanion.insert(
        partyId: party,
        kind: OrderKind.sale,
        date: DateTime(2026, 10, 1),
        status: Value(status),
      ),
      [
        OrderItemsCompanion.insert(
          orderId: 0,
          name: 'صاج',
          quantity: 2,
          unitPricePiasters: 150000,
        ),
      ],
    );
    return (party: party, order: order);
  }))!;
}

Future<AppDatabase> _emptyDb(WidgetTester tester) async =>
    AppDatabase(NativeDatabase.memory());

class _FakeDrive implements DriveBackupActions {
  bool connected = false;
  DriveBackupFile? backup;
  Object? backUpError;
  Object? restoreError;
  int restores = 0;
  int backUps = 0;

  @override
  Future<bool> isConnected() async => connected;
  @override
  Future<DateTime?> lastBackupAt() async => null;
  @override
  Future<void> connect() async => connected = true;
  @override
  Future<void> disconnect() async => connected = false;
  @override
  Future<void> backUp(AppDatabase db) async {
    if (backUpError != null) throw backUpError!;
    backUps++;
  }

  @override
  Future<DriveBackupFile?> findBackup() async => backup;
  @override
  Future<DataCounts> restore(AppDatabase db) async {
    if (restoreError != null) throw restoreError!;
    restores++;
    return (parties: 3, orders: 5);
  }
}

void main() {
  setUpAppTests();

  group('editing', () {
    testWidgets('edit an order: type locked, new price saved', (tester) async {
      final db = await _emptyDb(tester);
      final ids = await _seedSale(tester, db);
      await pumpApp(tester, location: '/orders/${ids.order}/edit', db: db);

      expect(find.text('تعديل الطلب'), findsOneWidget);
      final kind = tester.widget<SegmentedButton<OrderKind>>(
        find.byType(SegmentedButton<OrderKind>),
      );
      expect(kind.onSelectionChanged, isNull);
      expect(find.text('عرض سعر فقط'), findsNothing);
      expect(find.textContaining('دفعة مقدمة'), findsNothing);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'سعر الوحدة'),
        '2000',
      );
      await tester.scrollUntilVisible(
        find.text('حفظ الطلب'),
        300,
        scrollable: find
            .descendant(
              of: find.byType(Form),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(find.text('حفظ الطلب'));
      await tester.pumpAndSettle();

      final s = await tester.runAsync(
        () => db.watchOrderSummary(ids.order).first,
      );
      expect(s!.totalPiasters, 400000);
      expect(s.order.status, OrderStatus.pending);
      await unmountApp(tester);
    });

    testWidgets('edit a quotation keeps it a quotation', (tester) async {
      final db = await _emptyDb(tester);
      final ids = await _seedSale(tester, db, status: OrderStatus.quotation);
      await pumpApp(tester, location: '/orders/${ids.order}/edit', db: db);

      expect(find.text('تعديل عرض السعر'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('حفظ عرض السعر'),
        300,
        scrollable: find
            .descendant(
              of: find.byType(Form),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(find.text('حفظ عرض السعر'));
      await tester.pumpAndSettle();

      final order = await tester.runAsync(() => db.getOrder(ids.order));
      expect(order!.status, OrderStatus.quotation);
      await unmountApp(tester);
    });

    testWidgets('edit a client', (tester) async {
      final db = await _emptyDb(tester);
      final ids = await _seedSale(tester, db);
      await pumpApp(tester, location: '/parties/${ids.party}', db: db);

      await tester.tap(find.byTooltip('تعديل'));
      await tester.pumpAndSettle();
      final name = find.widgetWithText(TextFormField, 'الاسم *');
      expect(
        tester.widget<TextFormField>(name).controller!.text,
        'الحاج محمود',
      );
      await tester.enterText(name, 'الحاج محمود السيد');
      await tester.tap(find.widgetWithText(TextFormField, 'المدينة / المنطقة'));
      await tester.enterText(
        find.widgetWithText(TextFormField, 'المدينة / المنطقة'),
        'شبرا',
      );
      await tester.tap(find.text('حفظ'));
      await tester.pumpAndSettle();

      expect(find.text('الحاج محمود السيد'), findsWidgets); // app bar
      final party = await tester.runAsync(() => db.getParty(ids.party));
      expect((party!.name, party.city), ('الحاج محمود السيد', 'شبرا'));
      expect(party.phone, '01001234567'); // untouched fields kept
      await unmountApp(tester);
    });
  });

  group('settings', () {
    testWidgets('business info is saved', (tester) async {
      await pumpApp(tester, location: '/settings');
      await tester.enterText(
        find.widgetWithText(TextField, 'اسم النشاط'),
        'المعدات الحديثة',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'التليفون'),
        '01112223334',
      );
      await tester.tap(find.text('حفظ'));
      await tester.pumpAndSettle();
      expect(find.text('تم حفظ بيانات النشاط'), findsOneWidget);

      final prefs = SharedPreferencesAsync();
      final saved = await tester.runAsync(() async {
        return (
          name: await prefs.getString('business.name'),
          phone: await prefs.getString('business.phone'),
        );
      });
      expect(saved, (name: 'المعدات الحديثة', phone: '01112223334'));
      await unmountApp(tester);
    });

    testWidgets('connecting on an empty phone offers the backup', (
      tester,
    ) async {
      final drive = _FakeDrive()
        ..backup = (id: 'x', modifiedAt: DateTime(2026, 9, 30, 21, 5));
      await pumpApp(
        tester,
        location: '/settings',
        overrides: [driveBackupProvider.overrideWithValue(drive)],
      );
      expect(find.text('جوجل درايف غير متصل'), findsOneWidget);

      await scrollAndTap(tester, find.text('ربط حساب جوجل درايف'));
      expect(
        find.text('هل تريد استعادة بياناتك على هذا التليفون؟'),
        findsOneWidget,
      );
      expect(find.textContaining('تحذير'), findsNothing); // nothing to lose
      await tester.tap(find.text('استعادة'));
      await tester.pumpAndSettle();

      expect(drive.restores, 1);
      expect(find.text('تمت الاستعادة: 3 عميل/مورد و 5 طلب'), findsOneWidget);
      expect(find.text('جوجل درايف متصل'), findsOneWidget);
      await unmountApp(tester);
    });

    testWidgets('restoring over existing data warns and can be cancelled', (
      tester,
    ) async {
      final db = await _emptyDb(tester);
      await _seedSale(tester, db);
      final drive = _FakeDrive()
        ..connected = true
        ..backup = (id: 'x', modifiedAt: DateTime(2026, 9, 30));
      await pumpApp(
        tester,
        location: '/settings',
        db: db,
        overrides: [driveBackupProvider.overrideWithValue(drive)],
      );

      await scrollAndTap(tester, find.text('استعادة من جوجل درايف'));
      expect(find.textContaining('(1 عميل/مورد و 1 طلب)'), findsOneWidget);
      expect(find.text('مسح واستعادة'), findsOneWidget);
      await tester.tap(find.text('إلغاء'));
      await tester.pumpAndSettle();

      expect(drive.restores, 0);
      await unmountApp(tester);
    });

    testWidgets('each backup/restore failure gets a clear message', (
      tester,
    ) async {
      final drive = _FakeDrive()..connected = true;
      await pumpApp(
        tester,
        location: '/settings',
        overrides: [driveBackupProvider.overrideWithValue(drive)],
      );

      Future<void> expectMessage(VoidCallback arrange, String message) async {
        arrange();
        await scrollAndTap(tester, find.text('استعادة من جوجل درايف'));
        if (find.text('استعادة').evaluate().isNotEmpty) {
          await tester.tap(find.text('استعادة'));
          await tester.pumpAndSettle();
        }
        expect(find.text(message), findsOneWidget);
        ScaffoldMessenger.of(tester.element(find.byType(Scaffold).last))
            .removeCurrentSnackBar();
        await tester.pumpAndSettle();
      }

      await expectMessage(
        () => drive.backup = null,
        'لا توجد نسخة احتياطية على جوجل درايف',
      );
      await expectMessage(() {
        drive
          ..backup = (id: 'x', modifiedAt: DateTime(2026, 9, 30))
          ..restoreError = const InvalidBackup();
      }, 'ملف النسخة الاحتياطية تالف — لم يتم تغيير أي بيانات');
      await expectMessage(
        () => drive.restoreError = const BackupTooNew(),
        'النسخة من إصدار أحدث للتطبيق — حدّث التطبيق أولاً',
      );

      drive.backUpError = const NothingToBackUp();
      await scrollAndTap(tester, find.text('نسخ احتياطي الآن'));
      expect(
        find.text('لا توجد بيانات على التليفون لرفعها بعد'),
        findsOneWidget,
      );
      await unmountApp(tester);
    });
  });

  group('order screen', () {
    testWidgets('change status, then delete with its photo', (tester) async {
      final docs = useTempDocuments();
      final db = await _emptyDb(tester);
      final ids = await _seedSale(tester, db);
      final photo = File('${docs.path}/order_photos/photo_1.png');
      await tester.runAsync(() async {
        photo.parent.createSync(recursive: true);
        photo.writeAsBytesSync(tinyPng);
        await db.addOrderPhoto(ids.order, 'photo_1.png');
      });
      // Open the order from its client's page, as in real use.
      await pumpApp(tester, location: '/parties/${ids.party}', db: db);
      router.push('/orders/${ids.order}');
      await tester.pumpAndSettle();

      await tester.tap(find.text('جديد'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('تم التسليم').last);
      await tester.pumpAndSettle();
      expect(find.text('تم التسليم'), findsOneWidget);
      final status = await tester.runAsync(() => db.getOrder(ids.order));
      expect(status!.status, OrderStatus.delivered);

      await tester.tap(find.byTooltip('حذف'));
      await tester.pumpAndSettle();
      expect(
        find.text('سيتم حذف الطلب وأصنافه وصوره نهائياً.'),
        findsOneWidget,
      );
      await tester.tap(find.text('حذف').last);
      await tester.pumpAndSettle();
      await settleIo(tester);

      expect(find.text('سجل الطلبات (0)'), findsOneWidget); // back on client
      expect(photo.existsSync(), isFalse);
      await unmountApp(tester);
    });

    testWidgets('cancelling the quotation conversion changes nothing', (
      tester,
    ) async {
      final db = await _emptyDb(tester);
      final ids = await _seedSale(tester, db, status: OrderStatus.quotation);
      await pumpApp(tester, location: '/orders/${ids.order}', db: db);

      // A quotation's status can't be changed from the chip.
      expect(find.byType(PopupMenuButton<OrderStatus>), findsNothing);
      await tester.tap(find.text('تحويل لفاتورة بيع'));
      await tester.pumpAndSettle();
      expect(find.textContaining('3,000 ج.م'), findsWidgets);
      await tester.tap(find.text('إلغاء'));
      await tester.pumpAndSettle();

      final order = await tester.runAsync(() => db.getOrder(ids.order));
      expect(order!.status, OrderStatus.quotation);
      await unmountApp(tester);
    });

    testWidgets('send the order as WhatsApp text to the client', (
      tester,
    ) async {
      final launched = captureLaunchedUrls();
      final db = await _emptyDb(tester);
      final ids = await _seedSale(tester, db);
      await pumpApp(tester, location: '/orders/${ids.order}', db: db);

      await tester.scrollUntilVisible(find.text('إرسال كنص على واتساب'), 200);
      await tester.tap(find.text('إرسال كنص على واتساب'));
      await settleIo(tester);

      final uri = Uri.parse(launched.single);
      expect(uri.host, 'wa.me');
      expect(uri.path, '/201001234567');
      expect(
        uri.queryParameters['text'],
        contains('فاتورة بيع رقم ${ids.order}'),
      );
      expect(uri.queryParameters['text'], contains('الإجمالي: 3,000 ج.م'));
      await unmountApp(tester);
    });
  });

  group('client screen', () {
    testWidgets('call and WhatsApp open the right links', (tester) async {
      final launched = captureLaunchedUrls();
      final db = await _emptyDb(tester);
      final ids = await _seedSale(tester, db);
      await pumpApp(tester, location: '/parties/${ids.party}', db: db);

      await tester.tap(find.text('اتصال'));
      await tester.tap(find.text('واتساب'));
      await settleIo(tester);
      expect(launched, ['tel:01001234567', 'https://wa.me/201001234567']);
      await unmountApp(tester);
    });

    testWidgets('a client with orders cannot be deleted', (tester) async {
      final db = await _emptyDb(tester);
      final ids = await _seedSale(tester, db);
      await pumpApp(tester, location: '/parties/${ids.party}', db: db);

      await tester.tap(find.byTooltip('حذف'));
      await settleIo(tester);
      expect(
        find.text('لا يمكن الحذف: يوجد طلبات أو دفعات مسجلة لهذا الطرف'),
        findsOneWidget,
      );
      expect(await tester.runAsync(() => db.counts()), (parties: 1, orders: 1));
      await unmountApp(tester);
    });

    testWidgets('a voice note is listed and deleted with its file; '
        'deleting the client removes the rest', (tester) async {
      final docs = useTempDocuments();
      final db = await _emptyDb(tester);
      final party = await tester.runAsync(() async {
        final id = await db.saveParty(
          PartiesCompanion.insert(name: 'مورد جديد', kind: PartyKind.seller),
        );
        Directory('${docs.path}/voice_notes').createSync();
        for (final n in [1, 2]) {
          File('${docs.path}/voice_notes/note_$n.m4a').writeAsStringSync('x');
          await db.addVoiceNote(
            VoiceNotesCompanion.insert(
              partyId: id,
              fileName: 'note_$n.m4a',
              durationMs: 65000,
              createdAt: Value(DateTime(2026, 10, n)),
            ),
          );
        }
        return id;
      });
      await pumpApp(tester, location: '/parties', db: db);
      router.push('/parties/$party');
      await tester.pumpAndSettle();

      expect(find.text('ملاحظات صوتية (2)'), findsOneWidget);
      expect(find.textContaining('المدة 01:05'), findsNWidgets(2));
      // The note's own delete button (the app bar has one for the client).
      await tester.tap(
        find
            .descendant(
              of: find.byType(Card),
              matching: find.byIcon(Icons.delete_outline),
            )
            .first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('حذف').last);
      await settleIo(tester);
      expect(find.text('ملاحظات صوتية (1)'), findsOneWidget);
      expect(Directory('${docs.path}/voice_notes').listSync(), hasLength(1));

      // No orders or payments: the client can be deleted, with the note.
      await tester.tap(find.byTooltip('حذف').first);
      await settleIo(tester);
      await tester.tap(find.text('حذف').last);
      await settleIo(tester);

      expect(await tester.runAsync(() => db.counts()), (parties: 0, orders: 0));
      expect(Directory('${docs.path}/voice_notes').listSync(), isEmpty);
      await unmountApp(tester);
    });
  });
}
