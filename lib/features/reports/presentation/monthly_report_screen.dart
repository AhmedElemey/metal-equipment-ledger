import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import '../../../core/database/app_database.dart';
import '../../../core/formatters.dart';
import '../../../core/pdf.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/month_switcher.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/total_row.dart';
import '../../business/data/business_info.dart';
import '../data/report_pdf.dart';
import '../data/report_providers.dart';

class MonthlyReportScreen extends ConsumerStatefulWidget {
  const MonthlyReportScreen({super.key});

  @override
  ConsumerState<MonthlyReportScreen> createState() =>
      _MonthlyReportScreenState();
}

class _MonthlyReportScreenState extends ConsumerState<MonthlyReportScreen> {
  DateTime _month = monthStart(DateTime.now());

  Future<void> _share(MonthlyReport report) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final bytes = await buildMonthlyReportPdf(
        report: report,
        month: _month,
        business: await ref.read(businessInfoProvider.future),
        font: await loadPdfFont(),
      );
      await Printing.sharePdf(
        bytes: bytes,
        filename: 'report-${_month.year}-${_month.month}.pdf',
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('تعذر إنشاء التقرير: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final report = ref.watch(monthlyReportProvider(_month));
    final data = report.value;
    return Scaffold(
      appBar: AppBar(
        title: const Text('التقرير الشهري'),
        actions: [
          IconButton(
            tooltip: 'مشاركة PDF',
            icon: const Icon(Icons.picture_as_pdf_outlined),
            onPressed: data == null ? null : () => _share(data),
          ),
        ],
      ),
      body: Column(
        children: [
          MonthSwitcher(
            month: _month,
            onChanged: (m) => setState(() => _month = m),
          ),
          Expanded(
            child: AsyncValueView(
              value: report,
              data: (r) => ListView(
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  _NetProfitCard(report: r),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          TotalRow('المبيعات', formatMoney(r.sales)),
                          TotalRow('المشتريات', formatMoney(r.purchases)),
                          TotalRow(
                            'التحصيل من العملاء',
                            formatMoney(r.received),
                          ),
                          TotalRow('المدفوع للموردين', formatMoney(r.paidOut)),
                          TotalRow('المصروفات', formatMoney(r.expenses)),
                          const Divider(),
                          TotalRow(
                            'مجمل الربح',
                            formatMoney(r.grossProfit),
                            bold: true,
                          ),
                        ],
                      ),
                    ),
                  ),
                  _Ranked(title: 'أكبر العملاء', rows: r.topClients),
                  _Ranked(title: 'أكثر الأصناف مبيعاً', rows: r.topItems),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NetProfitCard extends StatelessWidget {
  const _NetProfitCard({required this.report});

  final MonthlyReport report;

  @override
  Widget build(BuildContext context) {
    final net = report.netProfit;
    return Card(
      margin: const EdgeInsets.all(12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Text('صافي الربح', style: TextStyle(fontSize: 16)),
            Text(
              formatMoney(net),
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: net >= 0 ? AppColors.sale : AppColors.danger,
              ),
            ),
            const Text(
              'الربح التقريبي من المبيعات بعد خصم المصروفات',
              style: TextStyle(color: Colors.black54, fontSize: 12),
            ),
            if (report.uncostedLines > 0)
              Text(
                '${report.uncostedLines} صنف مُباع بدون سعر شراء لم يُحسب',
                style: const TextStyle(color: AppColors.orange, fontSize: 12),
              ),
          ],
        ),
      ),
    );
  }
}

class _Ranked extends StatelessWidget {
  const _Ranked({required this.title, required this.rows});

  final String title;
  final List<({String name, int total})> rows;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(title: title),
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: rows.isEmpty
                ? const Text('لا توجد مبيعات في هذا الشهر')
                : Column(
                    children: [
                      for (final r in rows)
                        TotalRow(r.name, formatMoney(r.total)),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}
