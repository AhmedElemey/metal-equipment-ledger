import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/database/app_database.dart';
import '../../../core/formatters.dart';
import '../../../core/pdf.dart';
import '../../business/data/business_info.dart';

/// A4 monthly summary for the owner (or his accountant).
Future<Uint8List> buildMonthlyReportPdf({
  required MonthlyReport report,
  required DateTime month,
  required BusinessInfo business,
  required pw.Font font,
}) {
  final doc = pw.Document();
  final monthName = DateFormat('MMMM y', 'ar').format(month);

  pw.Widget row(String label, int value, {bool big = false}) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 3),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pdfText(label, style: pw.TextStyle(fontSize: big ? 15 : 12)),
        pdfText(
          formatMoney(value),
          style: pw.TextStyle(fontSize: big ? 15 : 12),
        ),
      ],
    ),
  );

  pw.Widget ranked(String title, List<({String name, int total})> rows) =>
      pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pdfText(
            title,
            style: const pw.TextStyle(fontSize: 14, color: pdfSteel),
          ),
          pw.SizedBox(height: 4),
          if (rows.isEmpty) pdfText('—'),
          for (final r in rows) row(r.name, r.total),
        ],
      );

  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      textDirection: pw.TextDirection.rtl,
      theme: pw.ThemeData.withFont(base: font, bold: font),
      build: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pdfText(
                business.name.isEmpty ? 'تقرير شهري' : business.name,
                style: const pw.TextStyle(fontSize: 20, color: pdfSteel),
              ),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: const pw.BoxDecoration(
                  color: pdfOrange,
                  borderRadius: pw.BorderRadius.all(pw.Radius.circular(6)),
                ),
                child: pdfText(
                  'تقرير $monthName',
                  style: const pw.TextStyle(
                    color: PdfColors.white,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
          pw.Divider(color: pdfSteel, thickness: 2, height: 24),
          row('المبيعات', report.sales),
          row('المشتريات', report.purchases),
          row('التحصيل من العملاء', report.received),
          row('المدفوع للموردين', report.paidOut),
          row('المصروفات', report.expenses),
          pw.Divider(color: PdfColors.grey400),
          row('مجمل الربح', report.grossProfit),
          row('صافي الربح', report.netProfit, big: true),
          if (report.uncostedLines > 0)
            pdfText(
              'ملاحظة: بعض الأصناف المباعة ليس لها سعر شراء ولم تُحسب في الربح',
              style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
            ),
          pw.SizedBox(height: 20),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(child: ranked('أكبر العملاء', report.topClients)),
              pw.SizedBox(width: 24),
              pw.Expanded(
                child: ranked('أكثر الأصناف مبيعاً', report.topItems),
              ),
            ],
          ),
        ],
      ),
    ),
  );
  return doc.save();
}
