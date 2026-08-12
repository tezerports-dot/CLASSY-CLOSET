import 'package:flutter/material.dart';

import '../../../app/di/injection.dart';
import '../../../core/services/retail_store.dart';
import '../../../core/services/returns_and_shifts.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/section_card.dart';

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
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            SectionCard(
              title: 'Take goods back',
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
                      const SizedBox(width: 12),
                      FilledButton.icon(
                        onPressed: _searching ? null : _find,
                        icon: _searching
                            ? const SizedBox.square(
                                dimension: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.search),
                        label: const Text('Find bill'),
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
            const SizedBox(height: 16),
            SectionCard(
              title: 'Past returns',
              child: _store.returns.isEmpty
                  ? const Text('Nothing has been returned yet.')
                  : SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        columns: const [
                          DataColumn(label: Text('Credit note')),
                          DataColumn(label: Text('Against bill')),
                          DataColumn(label: Text('Customer')),
                          DataColumn(label: Text('Items')),
                          DataColumn(label: Text('Refunded')),
                          DataColumn(label: Text('How')),
                          DataColumn(label: Text('When')),
                        ],
                        rows: [
                          for (final r in _store.returns.take(50))
                            DataRow(
                              cells: [
                                DataCell(Text(r.returnNumber)),
                                DataCell(Text(r.saleReceipt)),
                                DataCell(Text(r.customerName)),
                                DataCell(Text('${r.lineCount}')),
                                DataCell(
                                  Text(AppFormatters.currency(r.totalAmount)),
                                ),
                                DataCell(Text(r.refundMethod.label)),
                                DataCell(
                                  Text(AppFormatters.dateTime(r.returnedAt)),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _banner(BuildContext context) {
    final theme = Theme.of(context);
    final bg = _messageIsError
        ? theme.colorScheme.errorContainer
        : theme.colorScheme.secondaryContainer;
    final fg = _messageIsError
        ? theme.colorScheme.onErrorContainer
        : theme.colorScheme.onSecondaryContainer;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(
            _messageIsError ? Icons.error_outline : Icons.check_circle,
            color: fg,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(_message!, style: TextStyle(color: fg)),
          ),
        ],
      ),
    );
  }

  Widget _saleHeader(BuildContext context) {
    final sale = _sale!;
    return Wrap(
      spacing: 24,
      runSpacing: 8,
      children: [
        _fact('Bill', sale.receiptNumber),
        _fact('Sold', AppFormatters.dateTime(sale.soldAt)),
        _fact('Customer', sale.customerName),
        _fact('Bill total', AppFormatters.currency(sale.grandTotal)),
      ],
    );
  }

  Widget _fact(String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(label, style: const TextStyle(fontSize: 11.5)),
      Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
    ],
  );

  Widget _lineTable(BuildContext context) {
    final sale = _sale!;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('Item')),
          DataColumn(label: Text('Sold')),
          DataColumn(label: Text('Already back')),
          DataColumn(label: Text('Can take back')),
          DataColumn(label: Text('Taking back')),
          DataColumn(label: Text('Refund')),
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
                      ? const Text('—')
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
                  Text(
                    AppFormatters.currency(
                      line.refundFor(_quantities[line.saleItemId] ?? 0),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _refundPanel(BuildContext context) {
    final theme = Theme.of(context);
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
          const SizedBox(height: 8),
          Text(
            'This bill has no customer on it, so there is no account to credit. '
            'Choose a different refund method.',
            style: TextStyle(color: theme.colorScheme.error, fontSize: 12.5),
          ),
        ],
        const SizedBox(height: 16),
        Row(
          children: [
            Text(
              'Refund ${AppFormatters.currency(_refundTotal)}',
              style: theme.textTheme.headlineMedium,
            ),
            const Spacer(),
            FilledButton.icon(
              onPressed: _canSubmit ? _submit : null,
              icon: _saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.assignment_return),
              label: const Text('Take back and refund'),
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
