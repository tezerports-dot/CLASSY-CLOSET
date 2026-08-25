import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../../../app/di/injection.dart';
import '../../../../core/services/printer_service.dart';
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

  /// The rendered picture of one label, exactly as it will print.
  Uint8List? _previewPng;
  int _previewToken = 0;
  late final PrinterService _printerService = getIt<PrinterService>();

  /// The label printer, when the shop has named one under Hardware.
  ///
  /// A counter with two printers — the roll for bills, the label stock for
  /// price tags — should not need the assistant to pick the right one out of
  /// a Windows dialog while a delivery is being tagged. Naming it once sends
  /// every label sheet straight there.
  PrinterSettings get _printer => widget.store.printerSettings;
  bool get _direct =>
      _printer.hasLabelPrinter && _printerService.supportsDirectPrinting;

  @override
  void initState() {
    super.initState();
    for (final variant in widget.style.variants) {
      _copies[variant.id] = TextEditingController(
        text: variant.stock.round().clamp(0, 999).toString(),
      );
    }
    _renderPreview();
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
                onChanged: (v) {
                  setState(() => _sheet = v ?? _sheet);
                  _renderPreview();
                },
              ),
              const SizedBox(height: 16),
              Text('What goes on the label', style: theme.textTheme.titleSmall),
              const SizedBox(height: 2),
              Text(
                'The barcode with its number underneath, and the garment '
                'name with its size. Nothing else — a price label crowded '
                'with the shop name and the MRP leaves the two things '
                'anybody reaches for too small to use.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  _toggle('Product name', _options.showProductName, (v) {
                    setState(
                      () => _options = LabelOptions(
                        showProductName: v,
                        showVariant: _options.showVariant,
                      ),
                    );
                    _renderPreview();
                  }),
                  _toggle('Size / colour', _options.showVariant, (v) {
                    setState(
                      () => _options = LabelOptions(
                        showProductName: _options.showProductName,
                        showVariant: v,
                      ),
                    );
                    _renderPreview();
                  }),
                ],
              ),
              const SizedBox(height: 16),
              _previewPanel(theme),
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
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(
                    _direct ? Icons.local_offer_rounded : Icons.print_outlined,
                    size: 14,
                    color: theme.textTheme.bodySmall?.color,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _direct
                          ? 'Goes straight to ${_printer.labelPrinterName} — '
                                'no dialog.'
                          : 'Opens the Windows print dialog. Name a label '
                                'printer under Hardware to skip it.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
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

  /// A picture of one finished label, at the shape of the chosen stock.
  ///
  /// The dialog used to describe the tag in prose and hide the only true
  /// picture of it behind a Preview button and a second dialog. That is a poor
  /// way to answer "did the label actually change?" — the honest answer is the
  /// label itself, on screen, without a click. It is rendered from the same
  /// builder the printer is handed, so it cannot flatter the print.
  Widget _previewPanel(ThemeData theme) {
    final png = _previewPng;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('What one label looks like', style: theme.textTheme.titleSmall),
        const SizedBox(height: 6),
        Container(
          height: 132,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: theme.dividerColor),
            borderRadius: BorderRadius.circular(6),
          ),
          padding: const EdgeInsets.all(10),
          child: png == null
              ? Text('Rendering the label…', style: theme.textTheme.bodySmall)
              : Image.memory(
                  png,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.medium,
                ),
        ),
        const SizedBox(height: 4),
        Text(
          '${_sheet.widthMm.toStringAsFixed(0)} × '
          '${_sheet.heightMm.toStringAsFixed(0)} mm, shown enlarged. '
          'This is the print, not a drawing of it.',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }

  /// Renders the first unit of the design into [_previewPng].
  ///
  /// Rasterising goes through the platform, so a build without it — a test
  /// harness, a machine with no renderer — simply leaves the panel on its
  /// placeholder rather than taking the dialog down with it. The token guards
  /// against a slow render from an earlier stock size landing after a newer one.
  Future<void> _renderPreview() async {
    final variants = widget.style.variants;
    if (variants.isEmpty) return;
    final token = ++_previewToken;
    try {
      final pdf = await buildLabelPreview(
        product: variants.first,
        sheet: _sheet,
        profile: widget.store.storeProfile,
        options: _options,
      );
      final raster = await Printing.raster(pdf, pages: [0], dpi: 220).first;
      final png = await raster.toPng();
      if (!mounted || token != _previewToken) return;
      setState(() => _previewPng = png);
    } catch (_) {
      if (!mounted || token != _previewToken) return;
      setState(() => _previewPng = null);
    }
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
      final pdf = await buildLabelSheet(
        requests: _requests(),
        sheet: _sheet,
        profile: widget.store.storeProfile,
        options: _options,
      );

      // Straight to the label printer when there is one. A printer that is
      // off or renamed falls through to the dialog rather than losing the job
      // — the labels still have to get printed somehow.
      if (_direct) {
        final sent = await _printerService.sendPdfTo(
          pdf,
          printerName: _printer.labelPrinterName,
        );
        if (sent) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '$_totalLabels label(s) sent to '
                '${_printer.labelPrinterName}.',
              ),
            ),
          );
          return;
        }
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${_printer.labelPrinterName} did not answer, so the print '
              'dialog opened instead.',
            ),
          ),
        );
      }

      await Printing.layoutPdf(
        name: 'labels-${widget.style.styleCode}',
        format: _sheet.pageFormat,
        onLayout: (_) async => pdf,
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
