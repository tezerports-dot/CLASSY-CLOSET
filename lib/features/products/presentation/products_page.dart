import 'package:flutter/material.dart';

import '../../../app/di/injection.dart';
import '../../../core/services/retail_store.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/section_card.dart';

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
            actions: [FilledButton.icon(onPressed: _addSample, icon: const Icon(Icons.add), label: const Text('Add sample'))],
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
                        DataRow(color: p.lowStock ? MaterialStateProperty.all(Colors.orange.withOpacity(.08)) : null, cells: [
                          DataCell(Text(p.sku)),
                          DataCell(Text(p.name)),
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

  void _addSample() {
    final id = _store.products.length + 1;
    _store.addProduct(ProductRecord(id: id, sku: 'SKU-${1000 + id}', name: 'New Product $id', category: 'General', brand: 'Classy', unit: 'pcs', stock: 10, minimumStock: 3, purchasePrice: 10, sellingPrice: 18, barcode: '89010000$id', location: 'NEW'));
  }
}
