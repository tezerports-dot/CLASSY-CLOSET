import 'package:flutter/material.dart';

import '../../../app/di/injection.dart';
import '../../../core/services/retail_store.dart';
import '../../../core/services/returns_and_shifts.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/ui_kit.dart';

/// Takes goods back against an existing bill.
///
/// The bill is looked up first and quantities come from it, so a refund can
/// never exceed what was actually sold or be given twice on the same garment.
class ReturnsPage extends StatefulWidget {
  const ReturnsPage({super.key});

  @override
  State<ReturnsPage> createState() => _ReturnsPageState();
}

class _ReturnsPageState extends State<ReturnsPage> {
  final _store = getIt<RetailStore>();
  final _receipt = TextEditingController();
  final _receiptFocus = FocusNode();
  final _reason = TextEditingController();

  ReturnableSale? _sale;
  final _quantities = <int, double>{};
  RefundMethod _refundMethod = RefundMethod.cash;
  bool _searching = false;
  bool _saving = false;
  String? _message;
  bool _messageIsError = false;

  @override
  void dispose() {
    _receipt.dispose();
    _receiptFocus.dispose();
    _reason.dispose();
    super.dispose();
  }

  double get _refundTotal {
    final sale = _sale;
    if (sale == null) return 0;
    var total = 0.0;
    for (final line in sale.lines) {
      total += line.refundFor(_quantities[line.saleItemId] ?? 0);
    }
    return total;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _store,
      builder: (context, _) => SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const PageHeader(
              title: 'Returns',
              subtitle:
                  'Goods come back against the bill they went out on, so a '
                  'refund can never exceed what was sold or be given twice.',
            ),
            SectionCard(
              title: 'Take goods back',
              subtitle:
                  'Scan the barcode printed on the bill, or type the bill '
                  'number.',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _receipt,
                          focusNode: _receiptFocus,
                          autofocus: true,
                          decoration: const InputDecoration(
                            labelText: 'Bill number',
                            hintText:
                                'Scan the barcode on the bill, or type it',
                            prefixIcon: Icon(Icons.qr_code_scanner),
                          ),
                          onSubmitted: (_) => _find(),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.base),
                      AccentButton(
                        label: 'Find bill',
                        icon: Icons.search_rounded,
                        tall: true,
                        busy: _searching,
                        onPressed: _find,
                      ),
                    ],
                  ),
                  if (_message != null) ...[
                    const SizedBox(height: 12),
                    _banner(context),
                  ],
                  if (_sale != null) ...[
                    const SizedBox(height: 20),
                    _saleHeader(context),
                    const SizedBox(height: 12),
                    _lineTable(context),
                    const SizedBox(height: 20),
                    _refundPanel(context),
                  ],
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            SectionCard(
              title: 'Past returns',
              subtitle: _store.returns.length > 50
                  ? 'The 50 most recent.'
                  : null,
              child: AppTable(
                minWidth: 900,
                empty: const EmptyState(
                  icon: Icons.assignment_return_outlined,
                  title: 'Nothing has come back yet',
                  message:
                      'Returns you take here put the stock back on the rail '
                      'and produce a credit note against the original bill.',
                ),
                columns: const [
                  DataColumn(label: Text('CREDIT NOTE')),
                  DataColumn(label: Text('AGAINST BILL')),
                  DataColumn(label: Text('CUSTOMER')),
                  DataColumn(label: Text('ITEMS'), numeric: true),
                  DataColumn(label: Text('REFUNDED'), numeric: true),
                  DataColumn(label: Text('HOW')),
                  DataColumn(label: Text('WHEN')),
                ],
                rows: [
                  for (final r in _store.returns.take(50))
                    DataRow(
                      cells: [
                        DataCell(CodeText(r.returnNumber, size: 12)),
                        DataCell(CodeText(r.saleReceipt, size: 12)),
                        DataCell(Text(r.customerName)),
                        DataCell(Text('${r.lineCount}')),
                        DataCell(
                          MoneyText(r.totalAmount, size: 13, signed: true),
                        ),
                        DataCell(StatusPill(r.refundMethod.label)),
                        DataCell(Text(AppFormatters.dateTime(r.returnedAt))),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _banner(BuildContext context) {
    final bg = _messageIsError ? AppColors.dangerWash : AppColors.successWash;
    final fg = _messageIsError ? AppColors.danger : AppColors.success;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.base),
      decoration: BoxDecoration(color: bg, borderRadius: AppRadii.inputBorder),
      child: Row(
        children: [
          Icon(
            _messageIsError
                ? Icons.error_outline_rounded
                : Icons.check_circle_outline_rounded,
            size: 17,
            color: fg,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(_message!, style: TextStyle(color: fg, fontSize: 12.5)),
          ),
        ],
      ),
    );
  }

  Widget _saleHeader(BuildContext context) {
    final sale = _sale!;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: AppRadii.inputBorder,
        border: Border.all(color: AppColors.border),
      ),
      child: Wrap(
        spacing: 40,
        runSpacing: AppSpacing.base,
        children: [
          _fact('BILL', sale.receiptNumber, code: true),
          _fact('SOLD', AppFormatters.dateTime(sale.soldAt)),
          _fact('CUSTOMER', sale.customerName),
          _fact('BILL TOTAL', AppFormatters.currency(sale.grandTotal)),
        ],
      ),
    );
  }

  Widget _fact(String label, String value, {bool code = false}) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        label,
        style: AppTypography.microLabel.copyWith(color: AppColors.inkFaint),
      ),
      const SizedBox(height: 2),
      code
          ? CodeText(value, size: 13)
          : Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
    ],
  );

  Widget _lineTable(BuildContext context) {
    final sale = _sale!;
    return AppTable(
      minWidth: 820,
      columns: const [
        DataColumn(label: Text('ITEM')),
        DataColumn(label: Text('SOLD'), numeric: true),
        DataColumn(label: Text('ALREADY BACK'), numeric: true),
        DataColumn(label: Text('CAN TAKE BACK'), numeric: true),
        DataColumn(label: Text('TAKING BACK')),
        DataColumn(label: Text('REFUND'), numeric: true),
      ],
      rows: [
        for (final line in sale.lines)
          DataRow(
            cells: [
              DataCell(Text(line.description)),
              DataCell(Text(AppFormatters.quantity(line.soldQuantity))),
              DataCell(Text(AppFormatters.quantity(line.alreadyReturned))),
              DataCell(Text(AppFormatters.quantity(line.returnableQuantity))),
              DataCell(
                line.isFullyReturned
                    ? const StatusPill('All back', tone: PillTone.neutral)
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.remove, size: 18),
                            onPressed: () => _bump(line, -1),
                          ),
                          SizedBox(
                            width: 34,
                            child: Text(
                              AppFormatters.quantity(
                                _quantities[line.saleItemId] ?? 0,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.add, size: 18),
                            onPressed: () => _bump(line, 1),
                          ),
                        ],
                      ),
              ),
              DataCell(
                MoneyText(
                  line.refundFor(_quantities[line.saleItemId] ?? 0),
                  size: 13,
                ),
              ),
            ],
          ),
      ],
    );
  }

  Widget _refundPanel(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: DropdownButtonFormField<RefundMethod>(
                initialValue: _refundMethod,
                decoration: const InputDecoration(labelText: 'Refund by'),
                items: [
                  for (final method in RefundMethod.values)
                    DropdownMenuItem(value: method, child: Text(method.label)),
                ],
                onChanged: (v) =>
                    setState(() => _refundMethod = v ?? _refundMethod),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              flex: 2,
              child: TextField(
                controller: _reason,
                decoration: const InputDecoration(
                  labelText: 'Reason (optional)',
                  hintText: 'Wrong size, faulty, changed mind…',
                ),
              ),
            ),
          ],
        ),
        if (_refundMethod == RefundMethod.credit &&
            _sale?.customerId == null) ...[
          const SizedBox(height: AppSpacing.md),
          const Text(
            'This bill has no customer on it, so there is no account to '
            'credit. Choose a different refund method.',
            style: TextStyle(color: AppColors.danger, fontSize: 12.5),
          ),
        ],
        const SizedBox(height: AppSpacing.xl),
        Row(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'REFUNDING',
                  style: AppTypography.microLabel.copyWith(
                    color: AppColors.inkFaint,
                  ),
                ),
                const SizedBox(height: 2),
                MoneyText(_refundTotal, size: 22, weight: FontWeight.w700),
              ],
            ),
            const Spacer(),
            AccentButton(
              label: 'Take back and refund',
              icon: Icons.assignment_return_outlined,
              tall: true,
              busy: _saving,
              onPressed: _canSubmit ? _submit : null,
            ),
          ],
        ),
      ],
    );
  }

  bool get _canSubmit {
    if (_saving || _refundTotal <= 0) return false;
    if (_refundMethod == RefundMethod.credit && _sale?.customerId == null) {
      return false;
    }
    return true;
  }

  void _bump(ReturnableLine line, double delta) {
    setState(() {
      final next = (_quantities[line.saleItemId] ?? 0) + delta;
      _quantities[line.saleItemId] = next.clamp(0, line.returnableQuantity);
    });
  }

  Future<void> _find() async {
    final number = _receipt.text.trim();
    if (number.isEmpty) return;
    setState(() {
      _searching = true;
      _message = null;
    });

    final sale = await _store.findSaleByReceipt(number);
    if (!mounted) return;

    setState(() {
      _searching = false;
      _sale = sale;
      _quantities.clear();
      if (sale == null) {
        _message = 'No bill found with the number "$number".';
        _messageIsError = true;
      } else if (!sale.hasAnythingLeft) {
        _message = 'Everything on this bill has already been returned.';
        _messageIsError = true;
      } else {
        _message = null;
      }
    });
  }

  Future<void> _submit() async {
    final sale = _sale;
    if (sale == null) return;
    setState(() => _saving = true);

    try {
      final record = await _store.processReturn(
        sale: sale,
        selections: [
          for (final line in sale.lines)
            if ((_quantities[line.saleItemId] ?? 0) > 0)
              ReturnSelection(
                line: line,
                quantity: _quantities[line.saleItemId]!,
              ),
        ],
        refundMethod: _refundMethod,
        reason: _reason.text,
      );
      if (!mounted) return;
      setState(() {
        _saving = false;
        _sale = null;
        _quantities.clear();
        _receipt.clear();
        _reason.clear();
        _message =
            'Credit note ${record.returnNumber} created for '
            '${AppFormatters.currency(record.totalAmount)}. '
            'Stock has been put back.';
        _messageIsError = false;
      });
      _receiptFocus.requestFocus();
    } on StateError catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _message = e.message;
        _messageIsError = true;
      });
    }
  }
}
