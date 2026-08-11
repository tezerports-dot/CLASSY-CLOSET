import 'package:flutter/material.dart';

import '../../../app/di/injection.dart';
import '../../../core/services/retail_store.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/section_card.dart';
import 'widgets/product_form_dialog.dart';

class ProductsPage extends StatefulWidget {
  const ProductsPage({super.key});

  @override
  State<ProductsPage> createState() => _ProductsPageState();
}

class _ProductsPageState extends State<ProductsPage> {
  final _store = getIt<RetailStore>();
  final _search = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _store,
      builder: (context, _) {
        final query = _search.text.toLowerCase();
        final rows = _store.products.where((p) => '${p.sku} ${p.name} ${p.category} ${p.brand} ${p.barcode}'.toLowerCase().contains(query)).toList();
        return Padding(
          padding: const EdgeInsets.all(24),
          child: SectionCard(
            title: 'Products',
            actions: [FilledButton.icon(onPressed: () => _openForm(), icon: const Icon(Icons.add), label: const Text('Add product'))],
            child: Column(
              children: [
                TextField(controller: _search, onChanged: (_) => setState(() {}), decoration: const InputDecoration(prefixIcon: Icon(Icons.search), labelText: 'Search by SKU, barcode, name, category or brand')),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text('SKU')),
                      DataColumn(label: Text('Name')),
                      DataColumn(label: Text('Category')),
                      DataColumn(label: Text('Stock')),
                      DataColumn(label: Text('Min')),
                      DataColumn(label: Text('Price')),
                      DataColumn(label: Text('Location')),
                    ],
                    rows: [
                      for (final p in rows)
                        DataRow(color: p.lowStock ? WidgetStateProperty.all(Colors.orange.withValues(alpha: .08)) : null, cells: [
                          DataCell(Text(p.sku)),
                          DataCell(InkWell(onTap: () => _openForm(p), child: Text(p.name))),
                          DataCell(Text('${p.category} / ${p.brand}')),
                          DataCell(Text('${p.stock.toStringAsFixed(0)} ${p.unit}')),
                          DataCell(Text(p.minimumStock.toStringAsFixed(0))),
                          DataCell(Text(AppFormatters.currency(p.sellingPrice))),
                          DataCell(Text(p.location)),
                        ]),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openForm([ProductRecord? product]) async {
    await showDialog<void>(context: context, builder: (_) => ProductFormDialog(store: _store, product: product));
  }
}
