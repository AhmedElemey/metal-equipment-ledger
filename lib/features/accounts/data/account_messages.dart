import '../../../core/database/app_database.dart';
import '../../../core/formatters.dart';

/// "عليه 1,500 ج.م" (owes us) / "له 1,500 ج.م" (we owe him) / "خالص".
String balanceLabel(int balance) {
  if (balance == 0) return 'خالص';
  final side = balance > 0 ? 'عليه' : 'له';
  return '$side ${formatMoney(balance.abs())}';
}

String statementEntryTitle(StatementEntry e) {
  if (e.orderKind != null) {
    return e.orderKind == OrderKind.sale
        ? 'فاتورة بيع رقم ${e.refId}'
        : 'فاتورة شراء رقم ${e.refId}';
  }
  final title = e.paymentDirection == PaymentDirection.received
      ? 'دفعة مستلمة'
      : 'دفعة مدفوعة';
  return e.orderId == null ? title : '$title عن طلب رقم ${e.orderId}';
}

/// Polite payment reminder in Egyptian business Arabic.
String paymentReminderMessage({
  required String partyName,
  required int balance,
  required DateTime today,
}) {
  return [
    'السلام عليكم ورحمة الله',
    'أ/ $partyName المحترم،',
    '',
    'نود تذكير حضرتك بأن الرصيد المستحق حتى تاريخ ${formatDate(today)} '
        'هو ${formatMoney(balance)}.',
    'برجاء التكرم بالسداد في أقرب فرصة، ولو في أي استفسار بخصوص الحساب '
        'نبعت لحضرتك كشف الحساب بالتفصيل.',
    '',
    'شكراً لحسن تعاونكم 🙏',
  ].join('\n');
}

/// Full statement of account as plain text, for WhatsApp.
String statementMessage({
  required String partyName,
  required List<StatementEntry> entries,
  required DateTime today,
}) {
  final balance = entries.isEmpty ? 0 : entries.last.balance;
  return [
    'كشف حساب: $partyName',
    'حتى تاريخ: ${formatDate(today)}',
    '',
    for (final e in entries)
      '${formatDate(e.date)} | ${statementEntryTitle(e)} | '
          '${e.increasesBalance ? 'عليه' : 'له'} ${formatMoney(e.amount)} | '
          'الرصيد: ${balanceLabel(e.balance)}',
    '',
    'الرصيد النهائي: ${balanceLabel(balance)}',
  ].join('\n');
}
