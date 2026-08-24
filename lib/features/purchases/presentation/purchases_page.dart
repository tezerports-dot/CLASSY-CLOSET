import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/di/injection.dart';
import '../../../core/services/retail_store.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/search.dart';
import '../../../core/widgets/ui_kit.dart';

/// Receiving a delivery: stock in, cost updated, supplier balance adjusted.
class PurchasesPage extends StatefulWidget {
  const PurchasesPage({super.key});

  @override
  State<PurchasesPage> createState() => _PurchasesPageState();
}

class _PurchasesPageState extends State<PurchasesPage> {
  final _store = getIt<RetailStore>();
  final _invoice = TextEditingController();
  final _search = TextEditingController();
  final _paid = TextEditingController(text: '0');

  int? _supplierId;
  final _quantities = <int, TextEditingController>{};
  final _costs = <int, TextEditingController>{};
  bool _saving = false;
  String? _error;

  /// The supplier's own invoice, picked before the delivery is booked. An
  /// invoice number on its own settles no argument three months later; the
  /// paper does.
  String? _invoiceFilePath;

  @override
  void dispose() {
    _invoice.dispose();
    _search.dispose();
    _paid.dispose();
    for (final c in [..._quantities.values, ..._costs.values]) {
      c.dispose();
    }
    super.dispose();
  }

  List<ProductRecord> get _visible {
    final query = _search.text.trim().toLowerCase();
    final active = _store.products.where(
      (p) => p.active && (_supplierId == null || p.supplierId == _supplierId),
    );
    if (query.isEmpty) return active.take(40).toList();
    return active
        .where(
          (p) => AppSearch.matches(
            '${p.name} ${p.sku} ${p.barcode} ${p.size} ${p.color}',
            query,
          ),
        )
        .toList();
  }

  TextEditingController _qty(ProductRecord p) =>
      _quantities.putIfAbsent(p.id, () => TextEditingController(text: '0'));

  TextEditingController _cost(ProductRecord p) => _costs.putIfAbsent(
    p.id,
    () => TextEditingController(text: p.purchasePrice.toStringAsFixed(2)),
  );

  double get _total {
    var total = 0.0;
    for (final entry in _quantities.entries) {
      final qty = double.tryParse(entry.value.text.trim()) ?? 0;
      final cost = double.tryParse(_costs[entry.key]?.text.trim() ?? '') ?? 0;
      total += qty * cost;
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
            PageHeader(
              title: 'Purchases',
              subtitle:
                  'Receiving a delivery: stock in, cost updated, supplier '
                  'balance adjusted — in one action.',
              actions: [
                if (_store.purchases.isNotEmpty)
                  StatusPill(
                    '${_store.purchases.length} delivery'
                    '${_store.purchases.length == 1 ? '' : ' records'}',
                  ),
              ],
            ),
            if (_store.suppliers.isEmpty)
              SectionCard(
                child: EmptyState(
                  icon: Icons.local_shipping_outlined,
                  title: 'Add a supplier first',
                  message:
                      'A delivery has to be booked against someone, so that '
                      'what you owe them stays correct. Add the wholesaler, '
                      'then come back here.',
                  action: SecondaryButton(
                    label: 'Go to Suppliers',
                    icon: Icons.arrow_forward_rounded,
                    onPressed: () => context.go('/suppliers'),
                  ),
                ),
              )
            else
              SectionCard(
                title: 'Receive a delivery',
                subtitle:
                    'Pick the supplier, type in what arrived, and the stock, '
                    'the cost price and their account all move together.',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            initialValue: _supplierId,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Supplier',
                            ),
                            items: [
                              for (final s in _store.suppliers)
                                DropdownMenuItem(
                                  value: s.id,
                                  child: Text(s.name),
                                ),
                            ],
                            onChanged: (v) => setState(() => _supplierId = v),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _invoice,
                            decoration: const InputDecoration(
                              labelText: "Supplier's invoice number",
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 180,
                          child: TextField(
                            controller: _paid,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: InputDecoration(
                              labelText: 'Paid now',
                              prefixText: '${AppFormatters.symbol} ',
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _invoiceFileRow(context),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _search,
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search),
                        labelText: 'Find the items that arrived',
                        hintText: 'Scan a barcode, or type a name or size',
                        helperText: _supplierId == null
                            ? 'Pick the supplier first and only their items '
                                  'are listed.'
                            : 'Showing only what this supplier stocks.',
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 12),
                    if (_store.products.isEmpty)
                      EmptyState(
                        icon: Icons.checkroom_rounded,
                        title: 'Nothing to receive against',
                        message:
                            'Add your designs first — a delivery is booked '
                            'against the units it contains.',
                        action: SecondaryButton(
                          label: 'Go to Products',
                          icon: Icons.arrow_forward_rounded,
                          onPressed: () => context.go('/products'),
                        ),
                      )
                    else
                      _grid(context),
                    if (_error != null) ...[
                      const SizedBox(height: AppSpacing.base),
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
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceAlt,
                        borderRadius: AppRadii.inputBorder,
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'DELIVERY TOTAL',
                                style: AppTypography.microLabel.copyWith(
                                  color: AppColors.inkFaint,
                                ),
                              ),
                              const SizedBox(height: 2),
                              MoneyText(
                                _total,
                                size: 22,
                                weight: FontWeight.w700,
                              ),
                            ],
                          ),
                          if (_total > 0) ...[
                            const SizedBox(width: 40),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'OWING AFTER PAYMENT',
                                  style: AppTypography.microLabel.copyWith(
                                    color: AppColors.inkFaint,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                MoneyText(
                                  _total -
                                      (double.tryParse(_paid.text.trim()) ?? 0),
                                  size: 16,
                                  weight: FontWeight.w600,
                                  tone: AppColors.inkSoft,
                                ),
                              ],
                            ),
                          ],
                          const Spacer(),
                          AccentButton(
                            label: 'Add to stock',
                            icon: Icons.inventory_2_outlined,
                            tall: true,
                            busy: _saving,
                            onPressed: _total <= 0 || _supplierId == null
                                ? null
                                : _receive,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: AppSpacing.xl),
            SectionCard(
              title: 'Past deliveries',
              subtitle: _store.purchases.length > 50
                  ? 'The 50 most recent.'
                  : null,
              child: AppTable(
                minWidth: 900,
                empty: const EmptyState(
                  icon: Icons.inventory_2_outlined,
                  title: 'No deliveries recorded yet',
                  message:
                      'Every delivery you book here adds the stock, updates '
                      'your cost price and adjusts what you owe the supplier.',
                ),
                columns: const [
                  DataColumn(label: Text('INVOICE')),
                  DataColumn(label: Text('SUPPLIER')),
                  DataColumn(label: Text('ITEMS'), numeric: true),
                  DataColumn(label: Text('TOTAL'), numeric: true),
                  DataColumn(label: Text('PAID'), numeric: true),
                  DataColumn(label: Text('STILL OWING'), numeric: true),
                  DataColumn(label: Text('WHEN')),
                  DataColumn(label: Text('BILL COPY')),
                ],
                rows: [
                  for (final p in _store.purchases.take(50))
                    DataRow(
                      cells: [
                        DataCell(CodeText(p.invoiceNumber, size: 12)),
                        DataCell(Text(p.supplierName)),
                        DataCell(Text('${p.lineCount}')),
                        DataCell(MoneyText(p.total, size: 13)),
                        // Everything that has reached the supplier for this
                        // delivery, whether it was handed over on the day or
                        // settled later on the Suppliers screen. Paying a
                        // balance off there now shows here too.
                        DataCell(
                          Tooltip(
                            message: p.settled > 0
                                ? '${AppFormatters.currency(p.paid)} on '
                                      'delivery, '
                                      '${AppFormatters.currency(p.settled)} '
                                      'settled since'
                                : 'Paid on delivery',
                            child: MoneyText(p.totalPaid, size: 13),
                          ),
                        ),
                        DataCell(
                          p.outstanding <= 0
                              ? const StatusPill('Paid', tone: PillTone.good)
                              : MoneyText(
                                  p.outstanding,
                                  size: 13,
                                  weight: FontWeight.w600,
                                  tone: AppColors.danger,
                                ),
                        ),
                        DataCell(Text(AppFormatters.date(p.purchasedAt))),
                        DataCell(_invoiceFileCell(p)),
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

  Widget _grid(BuildContext context) => AppTable(
    minWidth: 780,
    empty: EmptyState(
      icon: Icons.search_off_rounded,
      title: 'Nothing matches that search',
      message:
          'Scan the barcode on the delivery, or search by design name '
          'instead.',
      action: SecondaryButton(
        label: 'Clear search',
        onPressed: () => setState(_search.clear),
      ),
    ),
    columns: const [
      DataColumn(label: Text('ITEM')),
      DataColumn(label: Text('SIZE / COLOUR')),
      DataColumn(label: Text('IN STOCK'), numeric: true),
      DataColumn(label: Text('ARRIVED'), numeric: true),
      DataColumn(label: Text('COST EACH'), numeric: true),
      DataColumn(label: Text('LINE TOTAL'), numeric: true),
    ],
    rows: [
      for (final p in _visible)
        DataRow(
          cells: [
            DataCell(Text(p.name)),
            DataCell(Text(p.variantLabel.isEmpty ? '—' : p.variantLabel)),
            DataCell(Text(AppFormatters.quantity(p.stock))),
            DataCell(
              SizedBox(
                width: 68,
                child: TextField(
                  controller: _qty(p),
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  decoration: const InputDecoration(isDense: true),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ),
            DataCell(
              SizedBox(
                width: 90,
                child: TextField(
                  controller: _cost(p),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  textAlign: TextAlign.right,
                  decoration: const InputDecoration(isDense: true),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ),
            DataCell(
              MoneyText(
                (double.tryParse(_qty(p).text.trim()) ?? 0) *
                    (double.tryParse(_cost(p).text.trim()) ?? 0),
                size: 13,
              ),
            ),
          ],
        ),
    ],
  );

  /// Pick or clear the supplier's own invoice for the delivery being booked.
  Widget _invoiceFileRow(BuildContext context) {
    final theme = Theme.of(context);
    final picked = _invoiceFilePath;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.base,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        border: Border.all(color: AppColors.border),
        borderRadius: AppRadii.inputBorder,
      ),
      child: Row(
        children: [
          Icon(
            picked == null
                ? Icons.attach_file_rounded
                : Icons.check_circle_rounded,
            size: 16,
            color: picked == null ? AppColors.inkSoft : AppColors.success,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              picked == null
                  ? "Attach the supplier's bill — a PDF, or a photo of the "
                        'paper. Optional, but it is the proof.'
                  : _fileName(picked),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: picked == null ? AppColors.inkSoft : AppColors.ink,
              ),
            ),
          ),
          if (picked != null)
            IconButton(
              tooltip: 'Remove',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.close_rounded, size: 16),
              onPressed: () => setState(() => _invoiceFilePath = null),
            ),
          SecondaryButton(
            label: picked == null ? 'Attach bill' : 'Change',
            icon: Icons.upload_file_rounded,
            onPressed: _pickInvoiceFile,
          ),
        ],
      ),
    );
  }

  /// The proof on a delivery already recorded: open it, or attach one that
  /// turned up after the stock did.
  Widget _invoiceFileCell(PurchaseRecord purchase) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (purchase.hasInvoiceFile)
        IconButton(
          tooltip: 'Show the bill copy',
          visualDensity: VisualDensity.compact,
          icon: const Icon(
            Icons.description_rounded,
            size: 17,
            color: AppColors.success,
          ),
          onPressed: () => _showInvoiceFile(purchase),
        ),
      IconButton(
        tooltip: purchase.hasInvoiceFile
            ? 'Replace the bill copy'
            : 'Attach the bill copy',
        visualDensity: VisualDensity.compact,
        icon: Icon(
          purchase.hasInvoiceFile
              ? Icons.sync_rounded
              : Icons.upload_file_rounded,
          size: 17,
        ),
        onPressed: () => _attachInvoiceFile(purchase),
      ),
    ],
  );

  String _fileName(String path) => path.split(RegExp(r'[/\\]')).last;

  Future<String?> _chooseFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: RetailStore.purchaseInvoiceExtensions,
      dialogTitle: "Choose the supplier's bill",
    );
    return result?.files.single.path;
  }

  Future<void> _pickInvoiceFile() async {
    final path = await _chooseFile();
    if (path == null || !mounted) return;
    setState(() => _invoiceFilePath = path);
  }

  Future<void> _attachInvoiceFile(PurchaseRecord purchase) async {
    final path = await _chooseFile();
    if (path == null) return;
    try {
      await _store.setPurchaseInvoiceFile(purchase.id, path);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Bill copy attached to ${purchase.invoiceNumber}.'),
        ),
      );
    } on StateError catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  /// Shows the stored copy. Images render in place; a PDF is shown as its
  /// location, because a counter PC opens PDFs perfectly well on its own and
  /// bundling a viewer to avoid one double-click is not worth the weight.
  Future<void> _showInvoiceFile(PurchaseRecord purchase) async {
    final path = purchase.invoicePath!;
    final isImage = !path.toLowerCase().endsWith('.pdf');
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Bill copy — ${purchase.invoiceNumber}'),
        content: SizedBox(
          width: 560,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isImage && File(path).existsSync())
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 460),
                  child: Image.file(File(path), fit: BoxFit.contain),
                )
              else
                Text(
                  File(path).existsSync()
                      ? 'Saved as ${_fileName(path)}. Open it from:'
                      : 'The file is missing from:',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              const SizedBox(height: AppSpacing.sm),
              SelectableText(path, style: AppTypography.code),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _receive() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final lines = <int, PurchaseLine>{};
      for (final entry in _quantities.entries) {
        final qty = double.tryParse(entry.value.text.trim()) ?? 0;
        if (qty <= 0) continue;
        lines[entry.key] = PurchaseLine(
          quantity: qty,
          unitCost: double.tryParse(_costs[entry.key]?.text.trim() ?? '') ?? 0,
        );
      }

      await _store.receiveStock(
        supplierId: _supplierId!,
        invoiceNumber: _invoice.text,
        lines: lines,
        paidAmount: double.tryParse(_paid.text.trim()) ?? 0,
        invoiceFilePath: _invoiceFilePath,
      );

      if (!mounted) return;
      for (final c in _quantities.values) {
        c.text = '0';
      }
      _invoice.clear();
      _paid.text = '0';
      setState(() {
        _saving = false;
        _invoiceFilePath = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Stock added and supplier updated.')),
      );
    } on StateError catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.message;
      });
    }
  }
}
