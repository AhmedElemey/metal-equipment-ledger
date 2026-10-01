import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

// Shared look of the app's PDFs (invoices, monthly report).
const pdfSteel = PdfColor.fromInt(0xFF263845);
const pdfOrange = PdfColor.fromInt(0xFFE8772E);
const pdfLightGrey = PdfColor.fromInt(0xFFF1F3F5);

/// Arabic font for PDFs. Note: the PDF engine misplaces spaces around
/// digits inside Arabic sentences, so keep numbers at the end of a label
/// or in their own cell.
Future<pw.Font> loadPdfFont() async =>
    pw.Font.ttf(await rootBundle.load('assets/fonts/Cairo.ttf'));

/// The PDF engine ignores the font's positioning rules, so the long tail of
/// a final ر / ز swallows the next space ("أكبر العملاء" → "أكبرالعملاء").
/// A second space after those letters restores a normal-looking gap.
String fixArabicSpacing(String text) =>
    text.replaceAllMapped(RegExp('([رزژ]) (?! )'), (m) => '${m[1]}  ');

/// [pw.Text] with [fixArabicSpacing] applied — use for all PDF text.
pw.Text pdfText(String text, {pw.TextStyle? style}) =>
    pw.Text(fixArabicSpacing(text), style: style);
