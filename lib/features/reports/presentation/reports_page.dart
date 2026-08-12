import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../app/di/injection.dart';
import '../../../core/services/reports.dart';
import '../../../core/services/retail_store.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/section_card.dart';

/// Everything the owner and the accountant need out of the till.
class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key});

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  final _store = getIt<RetailStore>();

  DateRange _range = DateRange.thisMonth();
  ReportBundle? _bundle;
  bool _loading = true;
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final bundle = await _store.buildReports(_range);
    if (mounted) {
      setState(() {
        _bundle = bundle;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bundle = _bundle;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _rangeBar(context),
          const SizedBox(height: 16),
          if (_loading || bundle == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 64),
              child: Center(child: CircularProgressIndicator()),
            )
          else ...[
            _headline(context, bundle),
            const SizedBox(height: 16),
            _tabs(context),
            const SizedBox(height: 16),
            switch (_tab) {
              0 => _registerCard(context, bundle),
              1 => _gstCard(context, bundle),
              2 => _hsnCard(context, bundle),
              3 => _productCard(context, bundle),
              _ => _deadStockCard(context, bundle),
            },
          ],
        ],
      ),
    );
  }

  Widget _rangeBar(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      for (final preset in [
        DateRange.today(),
        DateRange.thisWeek(),
        DateRange.thisMonth(),
        DateRange.lastMonth(),
        DateRange.thisFinancialYear(),
      ])
        ChoiceChip(
          label: Text(preset.label),
          selected: _range.label == preset.label,
          onSelected: (_) {
            setState(() => _range = preset);
            _load();
          },
        ),
      OutlinedButton.icon(
        onPressed: _pickCustom,
        icon: const Icon(Icons.date_range),
        label: Text(
          _range.label == 'Custom'
              ? '${AppFormatters.date(_range.from)} – '
                    '${AppFormatters.date(_range.to.subtract(const Duration(days: 1)))}'
              : 'Choose dates',
        ),
      ),
    ],
  );

  Widget _headline(BuildContext context, ReportBundle b) {
    final theme = Theme.of(context);
    return Wrap(
      spacing: 16,
      runSpacing: 16,
      children: [
        _stat(theme, 'Bills', '${b.billCount}'),
        _stat(theme, 'Gross sales', AppFormatters.currency(b.grossSales)),
        _stat(
          theme,
          'Returns',
          '-${AppFormatters.currency(b.returnsTotal)}',
          hint: '${b.returnCount} credit note(s)',
        ),
        _stat(
          theme,
          'Net sales',
          AppFormatters.currency(b.netSales),
          strong: true,
        ),
        _stat(
          theme,
          'Gross profit',
          AppFormatters.currency(b.grossProfit),
          hint: '${b.marginPercent.toStringAsFixed(1)}% margin',
        ),
        _stat(
          theme,
          'GST payable',
          AppFormatters.currency(b.netTax),
          hint: 'after returns',
        ),
        _stat(theme, 'Cash', AppFormatters.currency(b.cashTotal)),
        _stat(theme, 'Card', AppFormatters.currency(b.cardTotal)),
        _stat(theme, 'UPI', AppFormatters.currency(b.upiTotal)),
        _stat(theme, 'Average bill', AppFormatters.currency(b.averageBill)),
      ],
    );
  }

  Widget _stat(
    ThemeData theme,
    String label,
    String value, {
    String? hint,
    bool strong = false,
  }) => SizedBox(
    width: 190,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: strong
                    ? theme.textTheme.headlineSmall
                    : theme.textTheme.titleLarge,
              ),
            ),
            if (hint != null) Text(hint, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    ),
  );

  Widget _tabs(BuildContext context) => SegmentedButton<int>(
    segments: const [
      ButtonSegment(value: 0, label: Text('Sales register')),
      ButtonSegment(value: 1, label: Text('GST summary')),
      ButtonSegment(value: 2, label: Text('HSN summary')),
      ButtonSegment(value: 3, label: Text('Best sellers')),
      ButtonSegment(value: 4, label: Text('Dead stock')),
    ],
    selected: {_tab},
    onSelectionChanged: (s) => setState(() => _tab = s.single),
  );

  Widget _registerCard(BuildContext context, ReportBundle b) => SectionCard(
    title: 'Sales register — ${b.range.label}',
    actions: [_exportButton('sales-register', () => _registerCsv(b))],
    child: b.register.isEmpty
        ? const Text('No bills in this period.')
        : _scrollTable(
            const [
              'Bill',
              'Date',
              'Customer',
              'GSTIN',
              'Taxable',
              'CGST',
              'SGST',
              'IGST',
              'Total',
              'Paid by',
              'Sold by',
            ],
            [
              for (final r in b.register)
                [
                  r.receiptNumber,
                  AppFormatters.dateTime(r.soldAt),
                  r.customerName,
                  r.customerGstin ?? '—',
                  AppFormatters.currency(r.taxableValue),
                  AppFormatters.currency(r.cgst),
                  AppFormatters.currency(r.sgst),
                  AppFormatters.currency(r.igst),
                  AppFormatters.currency(r.grandTotal),
                  r.paymentMethod,
                  r.soldBy,
                ],
            ],
          ),
  );

  Widget _gstCard(BuildContext context, ReportBundle b) => SectionCard(
    title: 'GST by rate — ${b.range.label}',
    actions: [_exportButton('gst-summary', () => _gstCsv(b))],
    child: b.gstByRate.isEmpty
        ? const Text('No taxable sales in this period.')
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Give this to your accountant for the GST return. Figures are '
                'before returns; the credit notes are listed separately.',
                style: TextStyle(fontSize: 12.5),
              ),
              const SizedBox(height: 12),
              _scrollTable(
                const [
                  'Rate',
                  'Lines',
                  'Taxable value',
                  'CGST',
                  'SGST',
                  'IGST',
                  'Total tax',
                  'Invoice value',
                ],
                [
                  for (final g in b.gstByRate)
                    [
                      '${g.ratePercent.toStringAsFixed(0)}%',
                      '${g.lineCount}',
                      AppFormatters.currency(g.taxableValue),
                      AppFormatters.currency(g.cgst),
                      AppFormatters.currency(g.sgst),
                      AppFormatters.currency(g.igst),
                      AppFormatters.currency(g.taxTotal),
                      AppFormatters.currency(g.total),
                    ],
                ],
              ),
            ],
          ),
  );

  Widget _hsnCard(BuildContext context, ReportBundle b) => SectionCard(
    title: 'HSN summary — ${b.range.label}',
    actions: [_exportButton('hsn-summary', () => _hsnCsv(b))],
    child: b.hsn.isEmpty
        ? const Text('Nothing sold in this period.')
        : _scrollTable(
            const [
              'HSN',
              'Description',
              'Quantity',
              'Taxable value',
              'Tax',
              'Total',
            ],
            [
              for (final h in b.hsn)
                [
                  h.hsnCode,
                  h.description,
                  AppFormatters.quantity(h.quantity),
                  AppFormatters.currency(h.taxableValue),
                  AppFormatters.currency(h.taxAmount),
                  AppFormatters.currency(h.total),
                ],
            ],
          ),
  );

  Widget _productCard(BuildContext context, ReportBundle b) => SectionCard(
    title: 'Best sellers — ${b.range.label}',
    actions: [_exportButton('best-sellers', () => _productCsv(b))],
    child: b.topSellers.isEmpty
        ? const Text('Nothing sold in this period.')
        : _scrollTable(
            const [
              'Item',
              'Sold',
              'Revenue',
              'Profit',
              'Margin',
              'Still in stock',
            ],
            [
              for (final p in b.topSellers.take(50))
                [
                  p.description,
                  AppFormatters.quantity(p.quantitySold),
                  AppFormatters.currency(p.revenue),
                  AppFormatters.currency(p.profit),
                  '${p.marginPercent.toStringAsFixed(1)}%',
                  AppFormatters.quantity(p.stockOnHand),
                ],
            ],
          ),
  );

  Widget _deadStockCard(BuildContext context, ReportBundle b) => SectionCard(
    title: 'Dead stock — nothing sold in ${b.range.label.toLowerCase()}',
    actions: [_exportButton('dead-stock', () => _deadStockCsv(b))],
    child: b.deadStock.isEmpty
        ? const Text('Everything in stock sold at least once. Good period.')
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${b.deadStock.length} item(s) sitting on the rail. '
                'Consider marking these down.',
                style: const TextStyle(fontSize: 12.5),
              ),
              const SizedBox(height: 12),
              _scrollTable(
                const ['Item', 'In stock'],
                [
                  for (final p in b.deadStock.take(100))
                    [p.description, AppFormatters.quantity(p.stockOnHand)],
                ],
              ),
            ],
          ),
  );

  Widget _scrollTable(List<String> headers, List<List<String>> rows) =>
      SizedBox(
        width: double.infinity,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columns: [for (final h in headers) DataColumn(label: Text(h))],
            rows: [
              for (final row in rows)
                DataRow(cells: [for (final cell in row) DataCell(Text(cell))]),
            ],
          ),
        ),
      );

  Widget _exportButton(String name, String Function() build) =>
      OutlinedButton.icon(
        onPressed: () => _export(name, build()),
        icon: const Icon(Icons.download),
        label: const Text('Export CSV'),
      );

  // ---------------------------------------------------------------- exports

  String _registerCsv(ReportBundle b) => toCsv(
    const [
      'Invoice number',
      'Date',
      'Customer',
      'Customer GSTIN',
      'Taxable value',
      'CGST',
      'SGST',
      'IGST',
      'Discount',
      'Invoice total',
      'Profit',
      'Payment method',
      'Cash',
      'Card',
      'UPI',
      'Sold by',
    ],
    [
      for (final r in b.register)
        [
          r.receiptNumber,
          r.soldAt.toIso8601String(),
          r.customerName,
          r.customerGstin ?? '',
          r.taxableValue,
          r.cgst,
          r.sgst,
          r.igst,
          r.discount,
          r.grandTotal,
          r.profit,
          r.paymentMethod,
          r.cashAmount,
          r.cardAmount,
          r.upiAmount,
          r.soldBy,
        ],
    ],
  );

  String _gstCsv(ReportBundle b) => toCsv(
    const [
      'Rate %',
      'Lines',
      'Taxable value',
      'CGST',
      'SGST',
      'IGST',
      'Total tax',
      'Invoice value',
    ],
    [
      for (final g in b.gstByRate)
        [
          g.ratePercent,
          g.lineCount,
          g.taxableValue,
          g.cgst,
          g.sgst,
          g.igst,
          g.taxTotal,
          g.total,
        ],
    ],
  );

  String _hsnCsv(ReportBundle b) => toCsv(
    const ['HSN', 'Description', 'Quantity', 'Taxable value', 'Tax', 'Total'],
    [
      for (final h in b.hsn)
        [
          h.hsnCode,
          h.description,
          h.quantity,
          h.taxableValue,
          h.taxAmount,
          h.total,
        ],
    ],
  );

  String _productCsv(ReportBundle b) => toCsv(
    const [
      'Item',
      'Quantity sold',
      'Revenue',
      'Profit',
      'Margin %',
      'In stock',
    ],
    [
      for (final p in b.topSellers)
        [
          p.description,
          p.quantitySold,
          p.revenue,
          p.profit,
          p.marginPercent,
          p.stockOnHand,
        ],
    ],
  );

  String _deadStockCsv(ReportBundle b) => toCsv(
    const ['Item', 'In stock'],
    [
      for (final p in b.deadStock) [p.description, p.stockOnHand],
    ],
  );

  Future<void> _export(String name, String csv) async {
    final range = _range;
    String two(int v) => v.toString().padLeft(2, '0');
    final stamp =
        '${range.from.year}${two(range.from.month)}${two(range.from.day)}';

    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Save report',
      fileName: '$name-$stamp.csv',
      type: FileType.custom,
      allowedExtensions: const ['csv'],
    );
    if (path == null || !mounted) return;

    final target = path.toLowerCase().endsWith('.csv') ? path : '$path.csv';
    // A BOM so Excel opens rupee signs and Indian names as UTF-8 rather than
    // as mojibake.
    await File(target).writeAsString('﻿$csv', encoding: utf8);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Saved to $target')));
  }

  Future<void> _pickCustom() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: DateTimeRange(
        start: _range.from,
        end: _range.to.subtract(const Duration(days: 1)),
      ),
    );
    if (picked == null) return;
    setState(() => _range = DateRange.custom(picked.start, picked.end));
    await _load();
  }
}
