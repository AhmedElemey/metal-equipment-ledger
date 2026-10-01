import 'package:flutter_test/flutter_test.dart';
import 'package:metal_ledger/core/formatters.dart';
import 'package:metal_ledger/features/backup/data/backup_schedule.dart';
import 'package:metal_ledger/features/parties/presentation/contact_launcher.dart';

void main() {
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
}
