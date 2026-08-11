import 'dart:io';

import 'package:flutter/material.dart';

import '../../../app/di/injection.dart';
import '../../../core/services/retail_store.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/section_card.dart';
import 'widgets/product_form_dialog.dart';
import 'widgets/style_matrix_dialog.dart';

class ProductsPage extends StatefulWidget {
  const ProductsPage({super.key});

  @override
  State<ProductsPage> createState() => _ProductsPageState();
}

class _ProductsPageState extends State<ProductsPage> {
  final _store = getIt<RetailStore>();
  final _search = TextEditingController();

  /// Designs first, individual units second. A clothing shop thinks in designs,
  /// so that is the default view; the unit list is there for looking up one
  /// specific size or barcode.
  bool _showUnits = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _store,
      builder: (context, _) {
        return Padding(
          padding: const EdgeInsets.all(24),
          child: SectionCard(
            title: _showUnits ? 'Individual units' : 'Designs',
            actions: [
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(
                    value: false,
                    label: Text('Designs'),
                    icon: Icon(Icons.grid_view),
                  ),
                  ButtonSegment(
                    value: true,
                    label: Text('Units'),
                    icon: Icon(Icons.list),
                  ),
                ],
                selected: {_showUnits},
                onSelectionChanged: (s) =>
                    setState(() => _showUnits = s.single),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: () => _openStyleForm(),
                icon: const Icon(Icons.add),
                label: const Text('Add design'),
              ),
            ],
            child: Column(
              children: [
                TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    labelText:
                        'Search by design code, name, SKU, barcode, size or colour',
                  ),
                ),
                const SizedBox(height: 16),
                if (_showUnits) _unitTable() else _styleGrid(context),
              ],
            ),
          ),
        );
      },
    );
  }

  String get _query => _search.text.trim().toLowerCase();

  Widget _styleGrid(BuildContext context) {
    final styles = _store.styles
        .where(
          (s) => '${s.styleCode} ${s.name} ${s.category} ${s.brand} ${s.season}'
              .toLowerCase()
              .contains(_query),
        )
        .toList();

    if (styles.isEmpty) {
      return _empty(
        context,
        _store.styles.isEmpty
            ? 'No designs yet. Click "Add design" to enter one with its full '
                  'size and colour run.'
            : 'No design matches that search.',
      );
    }

    return Wrap(
      spacing: 16,
      runSpacing: 16,
      children: [
        for (final style in styles)
          SizedBox(
            width: 260,
            child: Card(
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => _openStyleForm(style),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _styleImage(style),
                    Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            style.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          Text(
                            style.styleCode,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              for (final size in style.sizes)
                                Chip(
                                  label: Text(size),
                                  visualDensity: VisualDensity.compact,
                                  padding: EdgeInsets.zero,
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Text(
                                AppFormatters.currency(style.sellingPrice),
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const Spacer(),
                              Text(
                                '${AppFormatters.quantity(style.totalStock)} pcs',
                                style: TextStyle(
                                  color: style.totalStock <= 0
                                      ? Theme.of(context).colorScheme.error
                                      : null,
                                ),
                              ),
                            ],
                          ),
                          Text(
                            '${style.colors.length} colour(s) × '
                            '${style.sizes.length} size(s)',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _styleImage(StyleRecord style) {
    final path = style.variants
        .map((v) => v.imagePath)
        .whereType<String>()
        .where((p) => File(p).existsSync())
        .firstOrNull;
    return Container(
      height: 150,
      color: Colors.grey.shade200,
      child: path == null
          ? Icon(Icons.checkroom, size: 44, color: Colors.grey.shade500)
          : Image.file(File(path), fit: BoxFit.cover),
    );
  }

  Widget _unitTable() {
    final rows = _store.products
        .where(
          (p) =>
              '${p.sku} ${p.name} ${p.category} ${p.brand} ${p.barcode} ${p.size} ${p.color}'
                  .toLowerCase()
                  .contains(_query),
        )
        .toList();

    if (rows.isEmpty) {
      return _empty(context, 'No unit matches that search.');
    }

    return SizedBox(
      width: double.infinity,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: const [
            DataColumn(label: Text('SKU')),
            DataColumn(label: Text('Name')),
            DataColumn(label: Text('Size')),
            DataColumn(label: Text('Colour')),
            DataColumn(label: Text('Barcode')),
            DataColumn(label: Text('HSN')),
            DataColumn(label: Text('Stock')),
            DataColumn(label: Text('Price')),
          ],
          rows: [
            for (final p in rows)
              DataRow(
                color: p.lowStock
                    ? WidgetStateProperty.all(
                        Colors.orange.withValues(alpha: .08),
                      )
                    : null,
                cells: [
                  DataCell(Text(p.sku)),
                  DataCell(
                    InkWell(onTap: () => _openUnitForm(p), child: Text(p.name)),
                  ),
                  DataCell(Text(p.size)),
                  DataCell(Text(p.color)),
                  DataCell(Text(p.barcode)),
                  DataCell(Text(p.hsnCode)),
                  DataCell(Text(AppFormatters.quantity(p.stock))),
                  DataCell(Text(AppFormatters.currency(p.sellingPrice))),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _empty(BuildContext context, String message) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 48),
    child: Column(
      children: [
        Icon(Icons.checkroom, size: 44, color: Theme.of(context).disabledColor),
        const SizedBox(height: 12),
        Text(message, textAlign: TextAlign.center),
      ],
    ),
  );

  Future<void> _openStyleForm([StyleRecord? style]) async {
    await showDialog<void>(
      context: context,
      builder: (_) => StyleMatrixDialog(store: _store, style: style),
    );
  }

  /// Editing a single unit stays available for corrections — a wrong barcode on
  /// one size, say — without reopening the whole design.
  Future<void> _openUnitForm(ProductRecord product) async {
    await showDialog<void>(
      context: context,
      builder: (_) => ProductFormDialog(store: _store, product: product),
    );
  }
}
