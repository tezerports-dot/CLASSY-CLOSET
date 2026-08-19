import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../app/di/injection.dart';
import '../../../core/services/reports.dart';
import '../../../core/services/retail_store.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/ui_kit.dart';

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
  double _expenses = 0;
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
        _expenses = _store.expensesBetween(_range.from, _range.to);
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bundle = _bundle;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageHeader(
            title: 'Reports',
            subtitle:
                'Everything the owner and the accountant need out of the '
                'till — ${_range.label.toLowerCase()}.',
          ),
          _rangeBar(context),
          const SizedBox(height: AppSpacing.xl),
          if (_loading || bundle == null)
            const SectionCard(child: SkeletonRows(rows: 4, height: 76))
          else ...[
            _headline(context, bundle),
            const SizedBox(height: AppSpacing.xl),
            Align(alignment: Alignment.centerLeft, child: _tabs(context)),
            const SizedBox(height: AppSpacing.xl),
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
    spacing: AppSpacing.sm,
    runSpacing: AppSpacing.sm,
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
          showCheckmark: false,
          selectedColor: AppColors.brand,
          labelStyle: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: _range.label == preset.label
                ? AppColors.brandInk
                : AppColors.inkSoft,
          ),
          onSelected: (_) {
            setState(() => _range = preset);
            _load();
          },
        ),
      SecondaryButton(
        icon: Icons.date_range_rounded,
        label: _range.label == 'Custom'
            ? '${AppFormatters.date(_range.from)} – '
                  '${AppFormatters.date(_range.to.subtract(const Duration(days: 1)))}'
            : 'Choose dates',
        onPressed: _pickCustom,
      ),
    ],
  );

  Widget _headline(BuildContext context, ReportBundle b) {
    final netProfit = b.grossProfit - _expenses;
    return Wrap(
      spacing: AppSpacing.xl,
      runSpacing: AppSpacing.xl,
      children: [
        _stat('Bills', '${b.billCount}', icon: Icons.receipt_long_outlined),
        _stat(
          'Gross sales',
          AppFormatters.currency(b.grossSales),
          icon: Icons.trending_up_rounded,
        ),
        _stat(
          'Returns',
          '-${AppFormatters.currency(b.returnsTotal)}',
          hint:
              '${b.returnCount} credit note'
              '${b.returnCount == 1 ? '' : 's'}',
          icon: Icons.assignment_return_outlined,
          tone: b.returnsTotal > 0 ? AppColors.danger : null,
        ),
        _stat(
          'Net sales',
          AppFormatters.currency(b.netSales),
          strong: true,
          icon: Icons.point_of_sale_outlined,
        ),
        _stat(
          'Gross profit',
          AppFormatters.currency(b.grossProfit),
          hint: '${b.marginPercent.toStringAsFixed(1)}% margin',
          icon: Icons.savings_outlined,
        ),
        _stat(
          'Expenses',
          '-${AppFormatters.currency(_expenses)}',
          hint: 'rent, wages, and so on',
          icon: Icons.payments_outlined,
          tone: _expenses > 0 ? AppColors.danger : null,
        ),
        // The figure that actually answers "was this month worth it".
        _stat(
          'Net profit',
          AppFormatters.currency(netProfit),
          strong: true,
          icon: Icons.account_balance_outlined,
          tone: netProfit < 0 ? AppColors.danger : AppColors.success,
        ),
        _stat(
          'GST payable',
          AppFormatters.currency(b.netTax),
          hint: 'after returns',
          icon: Icons.receipt_outlined,
        ),
        _stat(
          'Cash',
          AppFormatters.currency(b.cashTotal),
          icon: Icons.payments_outlined,
        ),
        _stat(
          'Card',
          AppFormatters.currency(b.cardTotal),
          icon: Icons.credit_card_outlined,
        ),
        _stat(
          'UPI',
          AppFormatters.currency(b.upiTotal),
          icon: Icons.qr_code_2_rounded,
        ),
        _stat(
          'Average bill',
          AppFormatters.currency(b.averageBill),
          icon: Icons.equalizer_rounded,
        ),
      ],
    );
  }

  Widget _stat(
    String label,
    String value, {
    String? hint,
    bool strong = false,
    IconData? icon,
    Color? tone,
  }) => SizedBox(
    width: 196,
    child: KpiCard(
      label: label,
      value: value,
      caption: hint,
      icon: icon,
      tone: tone ?? (strong ? AppColors.goldDeep : null),
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
    showSelectedIcon: false,
    onSelectionChanged: (s) => setState(() => _tab = s.single),
  );

  Widget _registerCard(BuildContext context, ReportBundle b) => SectionCard(
    title: 'Sales register — ${b.range.label}',
    actions: [_exportButton('sales-register', () => _registerCsv(b))],
    child: _scrollTable(
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
      empty: EmptyState(
        icon: Icons.receipt_long_outlined,
        title: 'No bills in ${b.range.label.toLowerCase()}',
        message:
            'Pick a wider date range above, or ring a sale up at the counter.',
      ),
    ),
  );

  Widget _gstCard(BuildContext context, ReportBundle b) => SectionCard(
    title: 'GST by rate — ${b.range.label}',
    actions: [_exportButton('gst-summary', () => _gstCsv(b))],
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (b.gstByRate.isNotEmpty) ...[
          const Text(
            'Give this to your accountant for the GST return. Figures '
            'are before returns; the credit notes are listed separately.',
            style: TextStyle(fontSize: 12.5, color: AppColors.inkFaint),
          ),
          const SizedBox(height: AppSpacing.base),
        ],
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
          empty: EmptyState(
            icon: Icons.percent_rounded,
            title: 'No taxable sales in ${b.range.label.toLowerCase()}',
            message:
                'Once bills carry GST, this is the sheet the accountant '
                'files the return from.',
          ),
        ),
      ],
    ),
  );

  Widget _hsnCard(BuildContext context, ReportBundle b) => SectionCard(
    title: 'HSN summary — ${b.range.label}',
    actions: [_exportButton('hsn-summary', () => _hsnCsv(b))],
    child: _scrollTable(
      const ['HSN', 'Description', 'Quantity', 'Taxable value', 'Tax', 'Total'],
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
      empty: EmptyState(
        icon: Icons.inventory_2_outlined,
        title: 'Nothing sold in ${b.range.label.toLowerCase()}',
        message:
            'The HSN summary groups what was sold by tax code, for the GSTR '
            'filing.',
      ),
    ),
  );

  Widget _productCard(BuildContext context, ReportBundle b) => SectionCard(
    title: 'Best sellers — ${b.range.label}',
    actions: [_exportButton('best-sellers', () => _productCsv(b))],
    child: _scrollTable(
      const ['Item', 'Sold', 'Revenue', 'Profit', 'Margin', 'Still in stock'],
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
      empty: EmptyState(
        icon: Icons.star_outline_rounded,
        title: 'Nothing sold in ${b.range.label.toLowerCase()}',
        message:
            'This ranks what actually moved, with the profit each design '
            'earned — the list worth reordering from.',
      ),
    ),
  );

  Widget _deadStockCard(BuildContext context, ReportBundle b) => SectionCard(
    title: 'Dead stock — nothing sold in ${b.range.label.toLowerCase()}',
    actions: [_exportButton('dead-stock', () => _deadStockCsv(b))],
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (b.deadStock.isNotEmpty) ...[
          Text(
            '${b.deadStock.length} item'
            '${b.deadStock.length == 1 ? '' : 's'} sitting on the rail. '
            'Consider marking these down.',
            style: const TextStyle(fontSize: 12.5, color: AppColors.inkFaint),
          ),
          const SizedBox(height: AppSpacing.base),
        ],
        _scrollTable(
          const ['Item', 'In stock'],
          [
            for (final p in b.deadStock.take(100))
              [p.description, AppFormatters.quantity(p.stockOnHand)],
          ],
          empty: const EmptyState(
            icon: Icons.check_circle_outline_rounded,
            title: 'Nothing is sitting still',
            message:
                'Everything in stock sold at least once in this period. '
                'Good period.',
          ),
        ),
      ],
    ),
  );

  Widget _scrollTable(
    List<String> headers,
    List<List<String>> rows, {
    Widget? empty,
  }) => AppTable(
    minWidth: 120.0 * headers.length,
    empty: empty,
    columns: [
      for (final h in headers)
        DataColumn(label: Text(h.toUpperCase()), numeric: _isNumeric(h)),
    ],
    rows: [
      for (final row in rows)
        DataRow(cells: [for (final cell in row) DataCell(Text(cell))]),
    ],
  );

  /// Money and count columns are right-aligned so the digits line up.
  static bool _isNumeric(String header) => const {
    'Lines',
    'Sold',
    'Quantity',
    'In stock',
    'Still in stock',
    'Margin',
    'Taxable',
    'Taxable value',
    'CGST',
    'SGST',
    'IGST',
    'Total tax',
    'Invoice value',
    'Tax',
    'Total',
    'Revenue',
    'Profit',
  }.contains(header);

  Widget _exportButton(String name, String Function() build) => SecondaryButton(
    label: 'Export CSV',
    icon: Icons.download_rounded,
    onPressed: () => _export(name, build()),
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
