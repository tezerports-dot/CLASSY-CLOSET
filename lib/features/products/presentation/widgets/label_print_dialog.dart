import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../../../core/services/retail_store.dart';
import '../../../../core/utils/formatters.dart';
import '../../data/label_document.dart';

/// Prints barcode price labels for a design's whole size/colour run.
///
/// Copies default to the stock on hand for each unit, because the usual reason
/// to print labels is that a delivery has just arrived and every piece needs
/// one.
class LabelPrintDialog extends StatefulWidget {
  const LabelPrintDialog({required this.store, required this.style, super.key});

  final RetailStore store;
  final StyleRecord style;

  @override
  State<LabelPrintDialog> createState() => _LabelPrintDialogState();
}

class _LabelPrintDialogState extends State<LabelPrintDialog> {
  LabelSheet _sheet = LabelSheet.a4_65;
  LabelOptions _options = const LabelOptions();
  final _copies = <int, TextEditingController>{};
  bool _printing = false;

  @override
  void initState() {
    super.initState();
    for (final variant in widget.style.variants) {
      _copies[variant.id] = TextEditingController(
        text: variant.stock.round().clamp(0, 999).toString(),
      );
    }
  }

  @override
  void dispose() {
    for (final c in _copies.values) {
      c.dispose();
    }
    super.dispose();
  }

  int get _totalLabels => _copies.values.fold(
    0,
    (sum, c) => sum + (int.tryParse(c.text.trim()) ?? 0),
  );

  int get _sheetsNeeded =>
      _sheet.isRoll ? _totalLabels : (_totalLabels / _sheet.perPage).ceil();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.label),
          const SizedBox(width: 10),
          Expanded(child: Text('Print labels — ${widget.style.name}')),
        ],
      ),
      content: SizedBox(
        width: 720,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<LabelSheet>(
                initialValue: _sheet,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Label stock'),
                items: [
                  for (final sheet in LabelSheet.values)
                    DropdownMenuItem(value: sheet, child: Text(sheet.label)),
                ],
                onChanged: (v) => setState(() => _sheet = v ?? _sheet),
              ),
              const SizedBox(height: 16),
              Text('What goes on the label', style: theme.textTheme.titleSmall),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                children: [
                  _toggle('Shop name', _options.showStoreName, (v) {
                    setState(
                      () => _options = LabelOptions(
                        showStoreName: v,
                        showProductName: _options.showProductName,
                        showVariant: _options.showVariant,
                        showPrice: _options.showPrice,
                      ),
                    );
                  }),
                  _toggle('Product name', _options.showProductName, (v) {
                    setState(
                      () => _options = LabelOptions(
                        showStoreName: _options.showStoreName,
                        showProductName: v,
                        showVariant: _options.showVariant,
                        showPrice: _options.showPrice,
                      ),
                    );
                  }),
                  _toggle('Size / colour', _options.showVariant, (v) {
                    setState(
                      () => _options = LabelOptions(
                        showStoreName: _options.showStoreName,
                        showProductName: _options.showProductName,
                        showVariant: v,
                        showPrice: _options.showPrice,
                      ),
                    );
                  }),
                  _toggle('MRP', _options.showPrice, (v) {
                    setState(
                      () => _options = LabelOptions(
                        showStoreName: _options.showStoreName,
                        showProductName: _options.showProductName,
                        showVariant: _options.showVariant,
                        showPrice: v,
                      ),
                    );
                  }),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Text('How many of each', style: theme.textTheme.titleSmall),
                  const Spacer(),
                  TextButton(
                    onPressed: () => _setAll(useStock: true),
                    child: const Text('Match stock'),
                  ),
                  TextButton(
                    onPressed: () => _setAll(useStock: false),
                    child: const Text('Clear'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text('Size / colour')),
                      DataColumn(label: Text('Barcode')),
                      DataColumn(label: Text('MRP')),
                      DataColumn(label: Text('In stock')),
                      DataColumn(label: Text('Labels')),
                    ],
                    rows: [
                      for (final v in widget.style.variants)
                        DataRow(
                          cells: [
                            DataCell(
                              Text(
                                v.variantLabel.isEmpty ? '—' : v.variantLabel,
                              ),
                            ),
                            DataCell(
                              Text(
                                v.barcode.isEmpty ? v.sku : v.barcode,
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                            DataCell(
                              Text(AppFormatters.currency(v.sellingPrice)),
                            ),
                            DataCell(Text(AppFormatters.quantity(v.stock))),
                            DataCell(
                              SizedBox(
                                width: 68,
                                child: TextField(
                                  controller: _copies[v.id],
                                  keyboardType: TextInputType.number,
                                  textAlign: TextAlign.center,
                                  decoration: const InputDecoration(
                                    isDense: true,
                                  ),
                                  onChanged: (_) => setState(() {}),
                                ),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                _totalLabels == 0
                    ? 'Nothing to print yet.'
                    : '$_totalLabels label(s) — '
                          '${_sheet.isRoll ? '$_sheetsNeeded on the roll' : '$_sheetsNeeded sheet(s)'}',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _printing ? null : () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
        OutlinedButton.icon(
          onPressed: _totalLabels == 0 || _printing ? null : _preview,
          icon: const Icon(Icons.visibility),
          label: const Text('Preview'),
        ),
        FilledButton.icon(
          onPressed: _totalLabels == 0 || _printing ? null : _print,
          icon: _printing
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.print),
          label: const Text('Print labels'),
        ),
      ],
    );
  }

  Widget _toggle(String label, bool value, ValueChanged<bool> onChanged) =>
      FilterChip(label: Text(label), selected: value, onSelected: onChanged);

  void _setAll({required bool useStock}) {
    setState(() {
      for (final variant in widget.style.variants) {
        _copies[variant.id]?.text = useStock
            ? variant.stock.round().clamp(0, 999).toString()
            : '0';
      }
    });
  }

  List<LabelRequest> _requests() => [
    for (final variant in widget.style.variants)
      if ((int.tryParse(_copies[variant.id]?.text.trim() ?? '') ?? 0) > 0)
        LabelRequest(
          product: variant,
          copies: int.parse(_copies[variant.id]!.text.trim()),
        ),
  ];

  Future<void> _print() async {
    setState(() => _printing = true);
    try {
      await Printing.layoutPdf(
        name: 'labels-${widget.style.styleCode}',
        format: _sheet.pageFormat,
        onLayout: (_) => buildLabelSheet(
          requests: _requests(),
          sheet: _sheet,
          profile: widget.store.storeProfile,
          options: _options,
        ),
      );
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  Future<void> _preview() async {
    setState(() => _printing = true);
    try {
      final bytes = await buildLabelSheet(
        requests: _requests(),
        sheet: _sheet,
        profile: widget.store.storeProfile,
        options: _options,
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => Dialog(
          child: SizedBox(
            width: 700,
            height: 720,
            child: PdfPreview(
              build: (_) => bytes,
              canChangePageFormat: false,
              canDebug: false,
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }
}
