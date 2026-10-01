import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:metal_ledger/core/database/app_database.dart';
import 'package:metal_ledger/core/formatters.dart';
import 'package:metal_ledger/features/accounts/data/account_messages.dart';
import 'package:metal_ledger/features/backup/data/backup_schedule.dart';
import 'package:metal_ledger/features/parties/presentation/contact_launcher.dart';

void main() {
  setUpAll(() => initializeDateFormatting('ar'));

  test('parseMoneyToPiasters handles separators and Arabic digits', () {
    expect(parseMoneyToPiasters('1,500.50'), 150050);
    expect(parseMoneyToPiasters('١٥٠٠'), 150000);
    expect(parseMoneyToPiasters('١٢٫٥'), 1250);
    expect(parseMoneyToPiasters(''), isNull);
    expect(parseMoneyToPiasters('abc'), isNull);
  });

  test('piastersToInput round-trips', () {
    expect(piastersToInput(150000), '1500');
    expect(piastersToInput(150050), '1500.50');
    expect(parseMoneyToPiasters(piastersToInput(150050)), 150050);
  });

  test('Egyptian numbers become international for WhatsApp', () {
    expect(toInternationalEgypt('0100 123 4567'), '201001234567');
    expect(toInternationalEgypt('+201001234567'), '201001234567');
    expect(toInternationalEgypt('00201001234567'), '201001234567');
  });

  group('isBackupDue', () {
    final evening = DateTime(2026, 10, 1, 22);
    final morning = DateTime(2026, 10, 2, 9);

    test('never backed up', () => expect(isBackupDue(null, evening), isTrue));

    test('due after 21:00 if not yet done today', () {
      expect(isBackupDue(DateTime(2026, 10, 1, 8), evening), isTrue);
      expect(isBackupDue(DateTime(2026, 10, 1, 21, 5), evening), isFalse);
    });

    test('missed evening is caught up next morning', () {
      expect(isBackupDue(DateTime(2026, 9, 30, 23), morning), isTrue);
      expect(isBackupDue(DateTime(2026, 10, 1, 23), morning), isFalse);
    });
  });

  test('daysAgo uses calendar days', () {
    final now = DateTime(2026, 10, 10, 9);
    expect(daysAgo(DateTime(2026, 10, 10, 23), now), 'اليوم');
    expect(daysAgo(DateTime(2026, 10, 9, 23), now), 'أمس');
    expect(daysAgo(DateTime(2026, 10, 8), now), 'منذ يومين');
    expect(daysAgo(DateTime(2026, 10, 5), now), 'منذ 5 أيام');
    expect(daysAgo(DateTime(2026, 9, 10), now), 'منذ 30 يوم');
  });

  test('balanceLabel says who owes whom', () {
    expect(balanceLabel(150000), startsWith('عليه 1,500'));
    expect(balanceLabel(-2500), startsWith('له 25'));
    expect(balanceLabel(0), 'خالص');
  });

  test('statement message ends with the final balance', () {
    final entries = [
      StatementEntry(
        date: DateTime(2026, 9, 1),
        orderKind: OrderKind.sale,
        paymentDirection: null,
        refId: 7,
        orderId: null,
        amount: 300000,
        note: null,
        balance: 300000,
      ),
      StatementEntry(
        date: DateTime(2026, 9, 2),
        orderKind: null,
        paymentDirection: PaymentDirection.received,
        refId: 1,
        orderId: 7,
        amount: 100000,
        note: null,
        balance: 200000,
      ),
    ];
    final text = statementMessage(
      partyName: 'الحاج محمود',
      entries: entries,
      today: DateTime(2026, 10, 1),
    );
    expect(text, contains('كشف حساب: الحاج محمود'));
    expect(text, contains('فاتورة بيع رقم 7'));
    expect(text, contains('دفعة مستلمة عن طلب رقم 7'));
    expect(text.split('\n').last, 'الرصيد النهائي: عليه 2,000 ج.م');
  });

  test('reminder message names the client and the amount', () {
    final text = paymentReminderMessage(
      partyName: 'الحاج محمود',
      balance: 250000,
      today: DateTime(2026, 10, 1),
    );
    expect(text, contains('أ/ الحاج محمود'));
    expect(text, contains('2,500 ج.م'));
  });
}
