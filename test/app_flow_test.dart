import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:metal_ledger/app.dart';
import 'package:metal_ledger/core/database/app_database.dart';
import 'package:metal_ledger/core/database/database_provider.dart';
import 'package:metal_ledger/core/router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('ar');
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('add a client, then a sale order for them', (tester) async {
    // A typical Android phone screen.
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final db = AppDatabase(NativeDatabase.memory());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const MetalLedgerApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('دفتر المعدات'), findsOneWidget);

    // Add a client from the dashboard.
    await tester.tap(find.text('عميل / مورد'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'الاسم *'),
      'الحاج محمود',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'رقم التليفون'),
      '01001234567',
    );
    await tester.tap(find.text('حفظ'));
    await tester.pumpAndSettle();

    // Open the client and create an order from their page.
    await tester.tap(find.text('العملاء'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('الحاج محمود'));
    await tester.pumpAndSettle();
    expect(find.text('كشف حساب'), findsOneWidget);
    await tester.tap(find.text('طلب جديد'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'اسم الصنف *'),
      'صاج',
    );
    await tester.enterText(find.widgetWithText(TextFormField, 'الكمية'), '2');
    await tester.enterText(
      find.widgetWithText(TextFormField, 'سعر الوحدة'),
      '1500',
    );
    await tester.pump();
    await tester.scrollUntilVisible(
      find.text('حفظ الطلب'),
      300,
      scrollable: find
          .descendant(of: find.byType(Form), matching: find.byType(Scrollable))
          .first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('حفظ الطلب'));
    await tester.pumpAndSettle();

    // Landed on the order details.
    expect(find.text('طلب رقم 1'), findsOneWidget);
    expect(find.textContaining('3,000'), findsWidgets);
    // Real I/O must leave the fake-async zone.
    final summary = (await tester.runAsync(
      () => db.watchOrderSummary(1).first,
    ))!;
    expect(summary.totalPiasters, 300000);
    expect(summary.partyName, 'الحاج محمود');

    // The unpaid client shows up in collections from the dashboard.
    router.go('/');
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('التحصيل: 1 عميل'));
    await tester.pumpAndSettle();
    expect(find.text('الحاج محمود'), findsOneWidget);
    expect(find.text('لم يدفع بعد • أول فاتورة اليوم'), findsOneWidget);

    // Record a payment from the statement; the balance updates.
    await tester.tap(find.byTooltip('كشف الحساب'));
    await tester.pumpAndSettle();
    expect(find.text('فاتورة بيع رقم 1'), findsOneWidget);
    await tester.tap(find.text('تسجيل دفعة'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'المبلغ'),
      '1000',
    );
    await tester.tap(find.text('تسجيل'));
    await tester.pumpAndSettle();
    expect(find.text('دفعة مستلمة'), findsOneWidget);
    expect(find.text('عليه 2,000 ج.م'), findsOneWidget);

    // Unmount so drift's stream-cleanup timers fire inside the test.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}
