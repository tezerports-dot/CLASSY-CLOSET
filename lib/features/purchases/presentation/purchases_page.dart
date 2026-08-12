import 'package:flutter/material.dart';

import '../../../app/di/injection.dart';
import '../../../core/services/retail_store.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/section_card.dart';

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
    final active = _store.products.where((p) => p.active);
    if (query.isEmpty) return active.take(40).toList();
    return active
        .where(
          (p) => '${p.name} ${p.sku} ${p.barcode} ${p.size} ${p.color}'
              .toLowerCase()
              .contains(query),
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
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            SectionCard(
              title: 'Receive a delivery',
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
                  TextField(
                    controller: _search,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      labelText: 'Find the items that arrived',
                      hintText: 'Scan a barcode, or type a name or size',
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 12),
                  if (_store.products.isEmpty)
                    const Text(
                      'Add some designs first, then you can receive stock '
                      'against them.',
                    )
                  else
                    _grid(context),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Text(
                        'Delivery total ${AppFormatters.currency(_total)}',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(width: 16),
                      if (_total > 0)
                        Text(
                          'Owing after payment: '
                          '${AppFormatters.currency(_total - (double.tryParse(_paid.text.trim()) ?? 0))}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      const Spacer(),
                      FilledButton.icon(
                        onPressed: _saving || _total <= 0 || _supplierId == null
                            ? null
                            : _receive,
                        icon: _saving
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.inventory),
                        label: const Text('Add to stock'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SectionCard(
              title: 'Past deliveries',
              child: _store.purchases.isEmpty
                  ? const Text('No deliveries recorded yet.')
                  : SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        columns: const [
                          DataColumn(label: Text('Invoice')),
                          DataColumn(label: Text('Supplier')),
                          DataColumn(label: Text('Items')),
                          DataColumn(label: Text('Total')),
                          DataColumn(label: Text('Paid')),
                          DataColumn(label: Text('Still owing')),
                          DataColumn(label: Text('When')),
                        ],
                        rows: [
                          for (final p in _store.purchases.take(50))
                            DataRow(
                              cells: [
                                DataCell(Text(p.invoiceNumber)),
                                DataCell(Text(p.supplierName)),
                                DataCell(Text('${p.lineCount}')),
                                DataCell(Text(AppFormatters.currency(p.total))),
                                DataCell(Text(AppFormatters.currency(p.paid))),
                                DataCell(
                                  Text(
                                    AppFormatters.currency(p.outstanding),
                                    style: TextStyle(
                                      color: p.outstanding > 0
                                          ? Theme.of(context).colorScheme.error
                                          : null,
                                    ),
                                  ),
                                ),
                                DataCell(
                                  Text(AppFormatters.date(p.purchasedAt)),
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

  Widget _grid(BuildContext context) => SizedBox(
    width: double.infinity,
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('Item')),
          DataColumn(label: Text('Size / colour')),
          DataColumn(label: Text('In stock')),
          DataColumn(label: Text('Arrived')),
          DataColumn(label: Text('Cost each')),
          DataColumn(label: Text('Line total')),
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
                  Text(
                    AppFormatters.currency(
                      (double.tryParse(_qty(p).text.trim()) ?? 0) *
                          (double.tryParse(_cost(p).text.trim()) ?? 0),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    ),
  );

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
      );

      if (!mounted) return;
      for (final c in _quantities.values) {
        c.text = '0';
      }
      _invoice.clear();
      _paid.text = '0';
      setState(() => _saving = false);
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
