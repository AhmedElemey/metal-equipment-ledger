import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/database_provider.dart';
import '../../../core/formatters.dart';
import '../../../core/labels.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/empty_state.dart';
import '../../accounts/presentation/record_payment_dialog.dart';
import '../../parties/data/parties_providers.dart';

/// Warn about pending cheques due within this many days.
const chequeWarningDays = 7;

final chequesProvider =
    StreamProvider.autoDispose<List<({Cheque cheque, String partyName})>>(
      (ref) => ref.watch(databaseProvider).watchCheques(),
    );

final chequesDueSoonProvider = StreamProvider.autoDispose<int>((ref) {
  final now = DateTime.now();
  final until = DateTime(now.year, now.month, now.day + chequeWarningDays + 1);
  return ref.watch(databaseProvider).watchChequesDueCount(until);
});

class ChequesScreen extends ConsumerStatefulWidget {
  const ChequesScreen({super.key});

  @override
  ConsumerState<ChequesScreen> createState() => _ChequesScreenState();
}

class _ChequesScreenState extends ConsumerState<ChequesScreen> {
  bool _pendingOnly = true;

  @override
  Widget build(BuildContext context) {
    final cheques = ref.watch(chequesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('الشيكات')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showAddChequeSheet(context),
        icon: const Icon(Icons.add),
        label: const Text('شيك جديد'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: true, label: Text('قيد التحصيل')),
                ButtonSegment(value: false, label: Text('الكل')),
              ],
              selected: {_pendingOnly},
              onSelectionChanged: (s) => setState(() => _pendingOnly = s.first),
            ),
          ),
          Expanded(
            child: AsyncValueView(
              value: cheques,
              data: (all) {
                final list = _pendingOnly
                    ? all
                          .where((c) => c.cheque.status == ChequeStatus.pending)
                          .toList()
                    : all;
                if (list.isEmpty) {
                  return const EmptyState(
                    icon: Icons.request_page_outlined,
                    message: 'لا توجد شيكات',
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.only(bottom: 88),
                  itemCount: list.length,
                  itemBuilder: (_, i) => _ChequeTile(
                    cheque: list[i].cheque,
                    partyName: list[i].partyName,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ChequeTile extends ConsumerWidget {
  const _ChequeTile({required this.cheque, required this.partyName});

  final Cheque cheque;
  final String partyName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.read(databaseProvider);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final daysLeft = cheque.dueDate.difference(today).inDays;
    final pending = cheque.status == ChequeStatus.pending;
    final received = cheque.direction == PaymentDirection.received;
    return Card(
      child: ListTile(
        leading: Icon(
          received ? Icons.call_received : Icons.call_made,
          color: received ? AppColors.sale : AppColors.purchase,
        ),
        title: Text(
          '${received ? 'من' : 'إلى'} $partyName • ${formatMoney(cheque.amountPiasters)}',
        ),
        subtitle: Text(
          [
            'يستحق ${formatDate(cheque.dueDate)}',
            if (pending && daysLeft < 0) 'متأخر',
            if (pending && daysLeft >= 0 && daysLeft <= chequeWarningDays)
              daysLeft == 0 ? 'اليوم' : 'بعد $daysLeft يوم',
            if (cheque.number != null) 'رقم ${cheque.number}',
            ?cheque.bank,
          ].join(' • '),
          style: TextStyle(
            color: pending && daysLeft <= chequeWarningDays
                ? AppColors.danger
                : null,
          ),
        ),
        trailing: PopupMenuButton<Object>(
          tooltip: 'تغيير الحالة',
          onSelected: (v) async {
            if (v is ChequeStatus) {
              await db.setChequeStatus(cheque.id, v, DateTime.now());
            } else if (await _confirmDelete(context)) {
              await db.deleteCheque(cheque.id);
            }
          },
          itemBuilder: (_) => [
            for (final s in ChequeStatus.values)
              if (s != cheque.status)
                PopupMenuItem(value: s, child: Text(s.label)),
            const PopupMenuItem(value: 'delete', child: Text('حذف')),
          ],
          child: Chip(
            label: Text(cheque.status.label),
            backgroundColor: cheque.status.color.withValues(alpha: 0.12),
          ),
        ),
      ),
    );
  }

  Future<bool> _confirmDelete(BuildContext context) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('حذف الشيك؟'),
          content: const Text('لو كان مصروفاً سيتم حذف الدفعة المسجلة له.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text(
                'حذف',
                style: TextStyle(color: AppColors.danger),
              ),
            ),
          ],
        ),
      ) ??
      false;
}

Future<void> showAddChequeSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
      ),
      child: const _AddChequeSheet(),
    ),
  );
}

class _AddChequeSheet extends ConsumerStatefulWidget {
  const _AddChequeSheet();

  @override
  ConsumerState<_AddChequeSheet> createState() => _AddChequeSheetState();
}

class _AddChequeSheetState extends ConsumerState<_AddChequeSheet> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _number = TextEditingController();
  final _bank = TextEditingController();
  Party? _party;
  PaymentDirection _direction = PaymentDirection.received;
  DateTime _due = DateTime.now();
  bool _saving = false;

  @override
  void dispose() {
    _amount.dispose();
    _number.dispose();
    _bank.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _due,
      firstDate: DateTime(2015),
      lastDate: DateTime.now().add(const Duration(days: 3 * 365)),
    );
    if (picked == null || !mounted) return;
    setState(() => _due = picked);
  }

  String? _orNull(TextEditingController c) =>
      c.text.trim().isEmpty ? null : c.text.trim();

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    final party = _party;
    if (party == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('اختر العميل / المورد')));
      return;
    }
    setState(() => _saving = true);
    await ref
        .read(databaseProvider)
        .addCheque(
          ChequesCompanion.insert(
            partyId: party.id,
            direction: _direction,
            amountPiasters: parseMoneyToPiasters(_amount.text)!,
            number: Value(_orNull(_number)),
            bank: Value(_orNull(_bank)),
            dueDate: _due,
          ),
        );
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final parties = ref.watch(partiesProvider('')).value ?? const <Party>[];
    final askDirection = _party == null || _party!.kind == PartyKind.both;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('شيك جديد', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              DropdownMenu<Party>(
                key: ValueKey(parties.length),
                expandedInsets: EdgeInsets.zero,
                enableFilter: true,
                requestFocusOnTap: true,
                label: const Text('العميل / المورد *'),
                dropdownMenuEntries: [
                  for (final p in parties)
                    DropdownMenuEntry(value: p, label: p.name),
                ],
                onSelected: (p) => setState(() {
                  _party = p;
                  _direction = p == null
                      ? _direction
                      : directionFor(p.kind) ?? _direction;
                }),
              ),
              if (askDirection) ...[
                const SizedBox(height: 8),
                SegmentedButton<PaymentDirection>(
                  segments: const [
                    ButtonSegment(
                      value: PaymentDirection.received,
                      label: Text('استلمته منه'),
                    ),
                    ButtonSegment(
                      value: PaymentDirection.paid,
                      label: Text('كتبته له'),
                    ),
                  ],
                  selected: {_direction},
                  onSelectionChanged: (s) =>
                      setState(() => _direction = s.first),
                ),
              ],
              const SizedBox(height: 8),
              TextFormField(
                controller: _amount,
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
                title: Text('تاريخ الاستحقاق: ${formatDate(_due)}'),
                onTap: _pickDate,
              ),
              TextFormField(
                controller: _number,
                decoration: const InputDecoration(
                  labelText: 'رقم الشيك (اختياري)',
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _bank,
                decoration: const InputDecoration(labelText: 'البنك (اختياري)'),
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
