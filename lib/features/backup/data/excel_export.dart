import 'package:drift/drift.dart' show OrderingTerm;
import 'package:excel/excel.dart';

import '../../../core/database/app_database.dart';
import '../../../core/labels.dart';

/// Builds a human-readable Excel workbook (RTL, Arabic headers) of all data.
Future<List<int>> buildExcelReport(AppDatabase db) async {
  final parties = await db.select(db.parties).get();
  final orders = await db.watchOrderSummaries().first;
  final items = await db.select(db.orderItems).get();
  final payments = await (db.select(
    db.payments,
  )..orderBy([(p) => OrderingTerm.asc(p.date)])).get();
  final balances = await db.partyBalances();
  final orderInfo = {for (final o in orders) o.order.id: o};

  final excel = Excel.createExcel();
  final defaultSheet = excel.getDefaultSheet()!;

  Sheet sheet(String name, List<String> headers) {
    final s = excel[name]..isRTL = true;
    s.appendRow([for (final h in headers) TextCellValue(h)]);
    return s;
  }

  TextCellValue t(String? v) => TextCellValue(v ?? '');
  DoubleCellValue money(int piasters) => DoubleCellValue(piasters / 100);

  final ordersSheet = sheet('الطلبات', [
    'رقم الطلب',
    'النوع',
    'العميل / المورد',
    'التاريخ',
    'الحالة',
    'الإجمالي',
    'المدفوع',
    'المتبقي',
    'ملاحظات',
  ]);
  for (final s in orders) {
    final o = s.order;
    ordersSheet.appendRow([
      IntCellValue(o.id),
      t(o.kind.label),
      t(s.partyName),
      DateCellValue.fromDateTime(o.date),
      t(o.status.label),
      money(s.totalPiasters),
      money(s.paidPiasters),
      // A quotation isn't owed by anyone yet.
      money(o.status == OrderStatus.quotation ? 0 : s.remainingPiasters),
      t(o.notes),
    ]);
  }

  final itemsSheet = sheet('الأصناف', [
    'رقم الطلب',
    'النوع',
    'العميل / المورد',
    'الصنف',
    'الكمية',
    'الوحدة',
    'سعر الوحدة',
    'الإجمالي',
  ]);
  for (final i in items) {
    final s = orderInfo[i.orderId];
    itemsSheet.appendRow([
      IntCellValue(i.orderId),
      t(s?.order.kind.label),
      t(s?.partyName),
      t(i.name),
      DoubleCellValue(i.quantity),
      t(i.unit),
      money(i.unitPricePiasters),
      money((i.quantity * i.unitPricePiasters).round()),
    ]);
  }

  final paymentsSheet = sheet('الدفعات', [
    'التاريخ',
    'العميل / المورد',
    'النوع',
    'المبلغ',
    'عن طلب رقم',
    'ملاحظة',
  ]);
  final partyNames = {for (final p in parties) p.id: p.name};
  for (final p in payments) {
    paymentsSheet.appendRow([
      DateCellValue.fromDateTime(p.date),
      t(partyNames[p.partyId]),
      t(p.direction == PaymentDirection.received ? 'مستلمة' : 'مدفوعة'),
      money(p.amountPiasters),
      p.orderId == null ? null : IntCellValue(p.orderId!),
      t(p.note),
    ]);
  }

  final partiesSheet = sheet('العملاء والموردين', [
    'الكود',
    'الاسم',
    'النوع',
    'التليفون',
    'المدينة',
    'عليه (مستحق لنا)',
    'له (مستحق علينا)',
    'ملاحظات',
  ]);
  for (final p in parties) {
    final balance = balances[p.id] ?? 0;
    partiesSheet.appendRow([
      IntCellValue(p.id),
      t(p.name),
      t(p.kind.label),
      t(p.phone),
      t(p.city),
      money(balance > 0 ? balance : 0),
      money(balance < 0 ? -balance : 0),
      t(p.notes),
    ]);
  }

  excel.setDefaultSheet('الطلبات');
  excel.delete(defaultSheet);
  return excel.encode()!;
}
