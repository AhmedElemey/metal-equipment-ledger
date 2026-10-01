import 'package:excel/excel.dart';

import '../../../core/database/app_database.dart';
import '../../../core/labels.dart';

/// Builds a human-readable Excel workbook (RTL, Arabic headers) of all data.
Future<List<int>> buildExcelReport(AppDatabase db) async {
  final parties = await db.select(db.parties).get();
  final orders = await db.watchOrderSummaries().first;
  final items = await db.select(db.orderItems).get();
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
      money(o.paidPiasters),
      money(s.remainingPiasters),
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

  final partiesSheet = sheet('العملاء والموردين', [
    'الكود',
    'الاسم',
    'النوع',
    'التليفون',
    'المدينة',
    'مستحق لنا',
    'مستحق علينا',
    'ملاحظات',
  ]);
  final dueFrom = <int, int>{};
  final dueTo = <int, int>{};
  for (final s in orders) {
    if (s.order.status == OrderStatus.cancelled) continue;
    final map = s.order.kind == OrderKind.sale ? dueFrom : dueTo;
    map.update(
      s.order.partyId,
      (v) => v + s.remainingPiasters,
      ifAbsent: () => s.remainingPiasters,
    );
  }
  for (final p in parties) {
    partiesSheet.appendRow([
      IntCellValue(p.id),
      t(p.name),
      t(p.kind.label),
      t(p.phone),
      t(p.city),
      money(dueFrom[p.id] ?? 0),
      money(dueTo[p.id] ?? 0),
      t(p.notes),
    ]);
  }

  excel.setDefaultSheet('الطلبات');
  excel.delete(defaultSheet);
  return excel.encode()!;
}
