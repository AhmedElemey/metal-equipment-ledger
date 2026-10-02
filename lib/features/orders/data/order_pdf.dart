import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/database/app_database.dart';
import '../../../core/formatters.dart';
import '../../../core/pdf.dart';
import '../../business/data/business_info.dart';

String orderDocumentTitle(OrderSummary s) {
  if (s.order.status == OrderStatus.quotation) return 'عرض سعر';
  return s.order.kind == OrderKind.sale ? 'فاتورة بيع' : 'فاتورة شراء';
}

/// File name for sharing — ASCII so every app accepts it.
String orderPdfFileName(OrderSummary s) {
  final prefix = s.order.status == OrderStatus.quotation
      ? 'quotation'
      : 'invoice';
  return '$prefix-${s.order.id}.pdf';
}

/// A4, right-to-left invoice or quotation. Long item lists flow onto more
/// pages with the table header repeated.
Future<Uint8List> buildOrderPdf({
  required OrderSummary summary,
  required List<OrderItem> items,
  required Party party,
  required BusinessInfo business,
  required pw.Font font,
}) {
  final order = summary.order;
  final isQuotation = order.status == OrderStatus.quotation;
  final doc = pw.Document(title: '${orderDocumentTitle(summary)} ${order.id}');

  pw.Widget small(String text) => pdfText(
    text,
    style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
  );

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      textDirection: pw.TextDirection.rtl,
      theme: pw.ThemeData.withFont(base: font, bold: font),
      header: (context) => context.pageNumber == 1
          ? pw.SizedBox()
          : pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 8),
              child: small('${orderDocumentTitle(summary)} رقم ${order.id}'),
            ),
      footer: (context) => pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          small(
            isQuotation
                // Kept free of digits: the PDF engine misplaces spaces around
                // numbers inside Arabic sentences.
                ? 'هذا العرض صالح لمدة أسبوع من تاريخه'
                : 'شكراً لتعاملكم معنا',
          ),
          small('${context.pageNumber} / ${context.pagesCount}'),
        ],
      ),
      build: (context) => [
        // Business (right) and document title (left).
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  if (business.name.isNotEmpty)
                    pdfText(
                      business.name,
                      style: const pw.TextStyle(fontSize: 22, color: pdfSteel),
                    ),
                  if (business.phone.isNotEmpty) small('ت: ${business.phone}'),
                  if (business.address.isNotEmpty) small(business.address),
                ],
              ),
            ),
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
              decoration: const pw.BoxDecoration(
                color: pdfOrange,
                borderRadius: pw.BorderRadius.all(pw.Radius.circular(6)),
              ),
              child: pw.Column(
                children: [
                  pdfText(
                    orderDocumentTitle(summary),
                    style: const pw.TextStyle(
                      fontSize: 18,
                      color: PdfColors.white,
                    ),
                  ),
                  pdfText(
                    'رقم ${order.id}',
                    style: const pw.TextStyle(color: PdfColors.white),
                  ),
                ],
              ),
            ),
          ],
        ),
        pw.Divider(color: pdfSteel, thickness: 2, height: 24),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pdfText(
                  '${order.kind == OrderKind.sale ? 'السادة' : 'المورد'}: '
                  '${party.name}',
                  style: const pw.TextStyle(fontSize: 14),
                ),
                if (party.phone != null) small('ت: ${party.phone}'),
                if (party.city != null) small(party.city!),
              ],
            ),
            pdfText('التاريخ: ${formatShortDate(order.date)}'),
          ],
        ),
        pw.SizedBox(height: 16),
        // pw.Table lays columns out left-to-right even in RTL pages, so the
        // columns are listed last-to-first to read right-to-left.
        pw.TableHelper.fromTextArray(
          headers: _rtl([
            'م',
            'الصنف',
            'الكمية',
            'الوحدة',
            'السعر',
            'الإجمالي',
          ]),
          data: [
            for (var i = 0; i < items.length; i++)
              _rtl([
                '${i + 1}',
                items[i].name,
                formatQuantity(items[i].quantity),
                items[i].unit,
                formatMoney(items[i].unitPricePiasters),
                formatMoney(
                  (items[i].quantity * items[i].unitPricePiasters).round(),
                ),
              ]),
          ],
          headerStyle: const pw.TextStyle(color: PdfColors.white),
          cellStyle: const pw.TextStyle(fontSize: 10),
          cellPadding: const pw.EdgeInsets.symmetric(
            horizontal: 6,
            vertical: 1,
          ),
          headerDecoration: const pw.BoxDecoration(color: pdfSteel),
          rowDecoration: const pw.BoxDecoration(
            border: pw.Border(
              bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.5),
            ),
          ),
          oddRowDecoration: const pw.BoxDecoration(color: pdfLightGrey),
          border: null,
          cellAlignment: pw.Alignment.centerRight,
          headerAlignment: pw.Alignment.centerRight,
          columnWidths: const {
            0: pw.FlexColumnWidth(1.5),
            1: pw.FlexColumnWidth(1.5),
            2: pw.FlexColumnWidth(1),
            3: pw.FlexColumnWidth(1),
            4: pw.FlexColumnWidth(3),
            5: pw.FixedColumnWidth(24),
          },
        ),
        pw.SizedBox(height: 16),
        pw.Align(
          alignment: pw.Alignment.centerLeft,
          child: pw.Container(
            width: 220,
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: pdfSteel),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
            ),
            child: pw.Column(
              children: [
                _totalRow('الإجمالي', formatMoney(summary.totalPiasters), 14),
                if (!isQuotation) ...[
                  _totalRow('المدفوع', formatMoney(summary.paidPiasters), 11),
                  _totalRow(
                    'المتبقي',
                    formatMoney(summary.remainingPiasters),
                    14,
                  ),
                ],
              ],
            ),
          ),
        ),
        if (order.notes != null) ...[
          pw.SizedBox(height: 16),
          pdfText('ملاحظات: ${order.notes}'),
        ],
      ],
    ),
  );
  return doc.save();
}

List<String> _rtl(List<String> cells) =>
    cells.reversed.map(fixArabicSpacing).toList();

pw.Widget _totalRow(String label, String value, double size) => pw.Padding(
  padding: const pw.EdgeInsets.symmetric(vertical: 2),
  child: pw.Row(
    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
    children: [
      pdfText(label, style: pw.TextStyle(fontSize: size)),
      pdfText(value, style: pw.TextStyle(fontSize: size)),
    ],
  ),
);
