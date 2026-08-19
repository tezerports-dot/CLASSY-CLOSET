import 'package:flutter/material.dart';

import '../../../app/di/injection.dart';
import '../../../core/services/reports.dart';
import '../../../core/services/retail_store.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/ui_kit.dart';

/// Rent, wages, electricity — everything that is not stock.
///
/// Without this the app can only show gross margin, which is not the number
/// that tells a shopkeeper whether the month was worth opening for.
class ExpensesPage extends StatefulWidget {
  const ExpensesPage({super.key});

  @override
  State<ExpensesPage> createState() => _ExpensesPageState();
}

class _ExpensesPageState extends State<ExpensesPage> {
  final _store = getIt<RetailStore>();
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _amount = TextEditingController();
  final _category = TextEditingController();
  final _notes = TextEditingController();
  DateTime _spentAt = DateTime.now();
  bool _saving = false;
  String? _error;

  /// Categories a clothing shop actually has, offered as one-tap chips so the
  /// list stays consistent instead of accumulating spelling variants.
  static const _suggested = [
    'Rent',
    'Wages',
    'Electricity',
    'Transport',
    'Packaging',
    'Marketing',
    'Repairs',
    'Tea & refreshments',
    'Bank charges',
    'Other',
  ];

  @override
  void dispose() {
    _title.dispose();
    _amount.dispose();
    _category.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _store,
      builder: (context, _) {
        final month = DateRange.thisMonth();
        final spentThisMonth = _store.expensesBetween(month.from, month.to);
        final today = DateTime.now();
        final spentToday = _store.expensesBetween(
          DateTime(today.year, today.month, today.day),
          DateTime(today.year, today.month, today.day + 1),
        );
        return SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const PageHeader(
                title: 'Expenses',
                subtitle:
                    'Rent, wages, electricity — everything that is not stock. '
                    'These are what turn gross margin into real profit.',
              ),
              Row(
                children: [
                  Expanded(
                    child: KpiCard(
                      label: 'Spent this month',
                      value: AppFormatters.currency(spentThisMonth),
                      caption: 'Since ${AppFormatters.date(month.from)}',
                      icon: Icons.calendar_month_outlined,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xl),
                  Expanded(
                    child: KpiCard(
                      label: 'Spent today',
                      value: AppFormatters.currency(spentToday),
                      caption: AppFormatters.date(today),
                      icon: Icons.today_outlined,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xl),
                  Expanded(
                    child: KpiCard(
                      label: 'Entries recorded',
                      value: '${_store.expenses.length}',
                      caption: 'All time',
                      icon: Icons.receipt_outlined,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xl),
              SectionCard(
                title: 'Record what you spent',
                subtitle:
                    'One line per payment. Pick a category so the report can '
                    'group them.',
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 2,
                            child: TextFormField(
                              controller: _title,
                              decoration: const InputDecoration(
                                labelText: 'What was it for',
                                hintText: 'March shop rent',
                              ),
                              validator: (v) => (v ?? '').trim().isEmpty
                                  ? 'Enter what it was for'
                                  : null,
                            ),
                          ),
                          const SizedBox(width: 12),
                          SizedBox(
                            width: 170,
                            child: TextFormField(
                              controller: _amount,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: InputDecoration(
                                labelText: 'Amount',
                                prefixText: '${AppFormatters.symbol} ',
                              ),
                              validator: (v) {
                                final parsed = double.tryParse(
                                  (v ?? '').trim(),
                                );
                                if (parsed == null || parsed <= 0) {
                                  return 'Enter an amount';
                                }
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          SizedBox(
                            width: 190,
                            child: InkWell(
                              onTap: _pickDate,
                              child: InputDecorator(
                                decoration: const InputDecoration(
                                  labelText: 'When',
                                ),
                                child: Text(AppFormatters.date(_spentAt)),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _category,
                              decoration: const InputDecoration(
                                labelText: 'Category',
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: TextFormField(
                              controller: _notes,
                              decoration: const InputDecoration(
                                labelText: 'Notes (optional)',
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final name in {
                            ..._store.expenseCategoryNames,
                            ..._suggested,
                          })
                            ActionChip(
                              label: Text(name),
                              visualDensity: VisualDensity.compact,
                              onPressed: () =>
                                  setState(() => _category.text = name),
                            ),
                        ],
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: AppSpacing.md),
                        Row(
                          children: [
                            const Icon(
                              Icons.error_outline_rounded,
                              size: 15,
                              color: AppColors.danger,
                            ),
                            const SizedBox(width: AppSpacing.xs),
                            Text(
                              _error!,
                              style: const TextStyle(color: AppColors.danger),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: AppSpacing.xl),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: AccentButton(
                          label: 'Record expense',
                          icon: Icons.add_rounded,
                          busy: _saving,
                          onPressed: _save,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              SectionCard(
                title: 'What you have spent',
                subtitle: _store.expenses.length > 100
                    ? 'The 100 most recent. Older entries stay in the reports.'
                    : null,
                child: AppTable(
                  minWidth: 820,
                  empty: const EmptyState(
                    icon: Icons.savings_outlined,
                    title: 'Nothing recorded yet',
                    message:
                        'Record the shop rent, the electricity bill and the '
                        'wages as you pay them, and the profit figure in '
                        'Reports becomes the real one.',
                  ),
                  columns: const [
                    DataColumn(label: Text('DATE')),
                    DataColumn(label: Text('CATEGORY')),
                    DataColumn(label: Text('WHAT FOR')),
                    DataColumn(label: Text('AMOUNT'), numeric: true),
                    DataColumn(label: Text('NOTES')),
                    DataColumn(label: Text('')),
                  ],
                  rows: [
                    for (final e in _store.expenses.take(100))
                      DataRow(
                        cells: [
                          DataCell(Text(AppFormatters.date(e.spentAt))),
                          DataCell(
                            e.category.isEmpty
                                ? const Text('—')
                                : StatusPill(e.category),
                          ),
                          DataCell(Text(e.title)),
                          DataCell(MoneyText(e.amount, size: 13)),
                          DataCell(
                            Text(
                              (e.notes ?? '').isEmpty ? '—' : e.notes!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          DataCell(
                            IconButton(
                              tooltip: 'Remove',
                              icon: const Icon(Icons.delete_outline, size: 18),
                              color: AppColors.danger,
                              onPressed: () => _confirmDelete(e),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _spentAt,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _spentAt = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _store.saveExpense(
        category: _category.text,
        title: _title.text,
        amount: double.tryParse(_amount.text.trim()) ?? 0,
        notes: _notes.text,
        spentAt: _spentAt,
      );
      if (!mounted) return;
      _title.clear();
      _amount.clear();
      _notes.clear();
      setState(() => _saving = false);
    } on StateError catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.message;
      });
    }
  }

  Future<void> _confirmDelete(ExpenseRecord expense) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove this expense?'),
        content: Text(
          '${expense.title} — ${AppFormatters.currency(expense.amount)}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed == true) await _store.deleteExpense(expense.id);
  }
}
