import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/database_provider.dart';
import '../../../core/formatters.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/month_switcher.dart';

const expenseCategories = [
  'نقل',
  'تحميل وتنزيل',
  'إيجار',
  'كهرباء ومياه',
  'أجور',
  'صيانة',
  'أخرى',
];

/// Expenses of the month starting at the key date.
final monthExpensesProvider = StreamProvider.autoDispose
    .family<List<Expense>, DateTime>(
      (ref, month) => ref
          .watch(databaseProvider)
          .watchExpenses(month, DateTime(month.year, month.month + 1)),
    );

class ExpensesScreen extends ConsumerStatefulWidget {
  const ExpensesScreen({super.key});

  @override
  ConsumerState<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends ConsumerState<ExpensesScreen> {
  DateTime _month = monthStart(DateTime.now());

  @override
  Widget build(BuildContext context) {
    final expenses = ref.watch(monthExpensesProvider(_month));
    return Scaffold(
      appBar: AppBar(title: const Text('المصروفات')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showAddExpenseSheet(context),
        icon: const Icon(Icons.add),
        label: const Text('مصروف جديد'),
      ),
      body: Column(
        children: [
          MonthSwitcher(
            month: _month,
            onChanged: (m) => setState(() => _month = m),
          ),
          Expanded(
            child: AsyncValueView(
              value: expenses,
              data: (list) {
                if (list.isEmpty) {
                  return const EmptyState(
                    icon: Icons.money_off_outlined,
                    message: 'لا توجد مصروفات في هذا الشهر',
                  );
                }
                final total = list.fold(0, (s, e) => s + e.amountPiasters);
                return CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(
                      child: Card(
                        margin: const EdgeInsets.all(12),
                        child: ListTile(
                          title: const Text('إجمالي مصروفات الشهر'),
                          trailing: Text(
                            formatMoney(total),
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppColors.danger,
                            ),
                          ),
                        ),
                      ),
                    ),
                    SliverList.builder(
                      itemCount: list.length,
                      itemBuilder: (_, i) => _ExpenseTile(expense: list[i]),
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: 88)),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ExpenseTile extends ConsumerWidget {
  const _ExpenseTile({required this.expense});

  final Expense expense;

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final db = ref.read(databaseProvider);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف المصروف؟'),
        content: Text(
          '${expense.category} — ${formatMoney(expense.amountPiasters)}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (ok == true) await db.deleteExpense(expense.id);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: ListTile(
        onTap: () => _delete(context, ref),
        leading: const Icon(Icons.receipt_outlined),
        title: Text(expense.category),
        subtitle: Text([formatDate(expense.date), ?expense.note].join(' • ')),
        trailing: Text(
          formatMoney(expense.amountPiasters),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}

Future<void> showAddExpenseSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
      ),
      child: const _AddExpenseSheet(),
    ),
  );
}

class _AddExpenseSheet extends ConsumerStatefulWidget {
  const _AddExpenseSheet();

  @override
  ConsumerState<_AddExpenseSheet> createState() => _AddExpenseSheetState();
}

class _AddExpenseSheetState extends ConsumerState<_AddExpenseSheet> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _note = TextEditingController();
  String _category = expenseCategories.first;
  DateTime _date = DateTime.now();
  bool _saving = false;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2015),
      lastDate: DateTime.now(),
    );
    if (picked == null || !mounted) return;
    setState(() => _date = picked);
  }

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final note = _note.text.trim();
    await ref
        .read(databaseProvider)
        .addExpense(
          ExpensesCompanion.insert(
            date: _date,
            category: _category,
            amountPiasters: parseMoneyToPiasters(_amount.text)!,
            note: Value(note.isEmpty ? null : note),
          ),
        );
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('مصروف جديد', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final c in expenseCategories)
                    ChoiceChip(
                      label: Text(c),
                      selected: _category == c,
                      onSelected: (_) => setState(() => _category = c),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _amount,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'المبلغ',
                  suffixText: 'ج.م',
                ),
                validator: (v) => (parseMoneyToPiasters(v ?? '') ?? 0) <= 0
                    ? 'أدخل مبلغ صحيح'
                    : null,
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event),
                title: Text(formatDate(_date)),
                onTap: _pickDate,
              ),
              TextFormField(
                controller: _note,
                decoration: const InputDecoration(
                  labelText: 'ملاحظة (اختياري)',
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: const Icon(Icons.save),
                label: const Text('حفظ'),
                style: FilledButton.styleFrom(minimumSize: const Size(0, 52)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
