import 'dart:io';

import 'package:flutter/material.dart';

import '../../../app/di/injection.dart';
import '../../../core/services/permissions.dart';
import '../../../core/services/retail_store.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/search.dart';
import '../../../core/widgets/ui_kit.dart';
import 'widgets/label_print_dialog.dart';
import 'widgets/product_form_dialog.dart';
import 'widgets/style_matrix_dialog.dart';

/// The catalogue, seen the way a clothing shop thinks about it.
///
/// A shirt is one design in five sizes and three colours, not fifteen unrelated
/// products — so designs are the default view and the unit list is there for
/// looking up one specific barcode.
class ProductsPage extends StatefulWidget {
  const ProductsPage({super.key});

  @override
  State<ProductsPage> createState() => _ProductsPageState();
}

class _ProductsPageState extends State<ProductsPage> {
  final _store = getIt<RetailStore>();
  final _search = TextEditingController();

  bool _showUnits = false;

  /// Staff without edit rights get a read-only catalogue: they can look a
  /// price or a size up, but not change one.
  bool get _canEdit => _store.can(Permission.editProducts);

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
        final lowStock = _store.products.where((p) => p.lowStock).length;
        return SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PageHeader(
                title: 'Products',
                subtitle:
                    '${_store.styles.length} design'
                    '${_store.styles.length == 1 ? '' : 's'}  ·  '
                    '${_store.products.length} unit'
                    '${_store.products.length == 1 ? '' : 's'} on the rail'
                    '${lowStock > 0 ? '  ·  $lowStock running low' : ''}',
                actions: [
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(
                        value: false,
                        label: Text('Designs'),
                        icon: Icon(Icons.grid_view_rounded, size: 15),
                      ),
                      ButtonSegment(
                        value: true,
                        label: Text('Units'),
                        icon: Icon(
                          Icons.format_list_bulleted_rounded,
                          size: 15,
                        ),
                      ),
                    ],
                    selected: {_showUnits},
                    showSelectedIcon: false,
                    onSelectionChanged: (s) =>
                        setState(() => _showUnits = s.single),
                  ),
                  if (_canEdit)
                    AccentButton(
                      label: 'Add design',
                      icon: Icons.add_rounded,
                      onPressed: () => _openStyleForm(),
                    ),
                ],
              ),
              SectionCard(
                title: _showUnits ? 'Individual units' : 'Designs',
                subtitle: _showUnits
                    ? 'Every piece with its own barcode. Click a name to '
                          'correct one unit.'
                    : 'Each card is a design with its full size and colour run.',
                child: Column(
                  children: [
                    TextField(
                      controller: _search,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search_rounded, size: 18),
                        hintText:
                            'Search design code, name, SKU, barcode, size or '
                            'colour',
                        suffixIcon: _search.text.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Clear',
                                icon: const Icon(Icons.close_rounded, size: 16),
                                onPressed: () => setState(_search.clear),
                              ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    if (_showUnits) _unitTable() else _styleGrid(context),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String get _query => _search.text.trim().toLowerCase();

  // ------------------------------------------------------------------ grid

  Widget _styleGrid(BuildContext context) {
    final styles = _store.styles
        .where(
          (s) => AppSearch.matches(
            '${s.styleCode} ${s.name} ${s.category} ${s.brand} ${s.season}',
            _query,
          ),
        )
        .toList();

    if (styles.isEmpty) {
      return _store.styles.isEmpty
          ? EmptyState(
              icon: Icons.checkroom_rounded,
              title: 'Nothing on the rail yet',
              message:
                  'Add your first design with its full size and colour run, '
                  'and every piece gets its own barcode automatically.',
              action: _canEdit
                  ? AccentButton(
                      label: 'Add design',
                      icon: Icons.add_rounded,
                      onPressed: () => _openStyleForm(),
                    )
                  : null,
            )
          : EmptyState(
              icon: Icons.search_off_rounded,
              title: 'No design matches "${_search.text.trim()}"',
              message:
                  'Try a shorter search, or switch to Units to look a barcode '
                  'up directly.',
              action: SecondaryButton(
                label: 'Clear search',
                onPressed: () => setState(_search.clear),
              ),
            );
    }

    return Wrap(
      spacing: AppSpacing.xl,
      runSpacing: AppSpacing.xl,
      children: [for (final style in styles) _styleCard(context, style)],
    );
  }

  Widget _styleCard(BuildContext context, StyleRecord style) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 256,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: AppRadii.cardBorder,
          border: Border.all(color: AppColors.border),
        ),
        child: InkWell(
          onTap: _canEdit ? () => _openStyleForm(style) : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _styleImage(style),
              Padding(
                padding: const EdgeInsets.all(AppSpacing.base),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      style.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    CodeText(style.styleCode, size: 11, color: AppColors.gold),
                    const SizedBox(height: AppSpacing.md),
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        for (final size in style.sizes)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceAlt,
                              borderRadius: AppRadii.pillBorder,
                              border: Border.all(color: AppColors.borderSoft),
                            ),
                            child: Text(
                              size,
                              style: AppTypography.microLabel.copyWith(
                                color: AppColors.inkSoft,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.base),
                    Row(
                      children: [
                        MoneyText(
                          style.sellingPrice,
                          size: 16,
                          weight: FontWeight.w700,
                        ),
                        const Spacer(),
                        StockPill(stock: style.totalStock),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      '${style.colors.length} colour'
                      '${style.colors.length == 1 ? '' : 's'} × '
                      '${style.sizes.length} size'
                      '${style.sizes.length == 1 ? '' : 's'}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.inkFaint,
                      ),
                    ),
                    if (_canEdit) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Row(
                        children: [
                          TextButton.icon(
                            onPressed: () => _printLabels(style),
                            icon: const Icon(Icons.label_outline, size: 15),
                            label: const Text('Labels'),
                          ),
                          const Spacer(),
                          IconButton(
                            tooltip: 'Delete design',
                            onPressed: () => _confirmDeleteStyle(style),
                            icon: const Icon(
                              Icons.delete_outline,
                              size: 17,
                              color: AppColors.danger,
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () => _openStyleForm(style),
                            icon: const Icon(Icons.edit_outlined, size: 15),
                            label: const Text('Edit'),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _styleImage(StyleRecord style) {
    final path = style.variants
        .map((v) => v.imagePath)
        .whereType<String>()
        .where((p) => File(p).existsSync())
        .firstOrNull;
    return Container(
      height: 148,
      color: AppColors.surfaceAlt,
      child: path == null
          ? const Center(
              child: Icon(
                Icons.checkroom_rounded,
                size: 40,
                color: AppColors.border,
              ),
            )
          : Image.file(
              File(path),
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const Center(
                child: Icon(
                  Icons.broken_image_outlined,
                  size: 32,
                  color: AppColors.border,
                ),
              ),
            ),
    );
  }

  // ----------------------------------------------------------------- units

  Widget _unitTable() {
    final rows = _store.products
        .where(
          (p) => AppSearch.matches(
            '${p.sku} ${p.name} ${p.category} ${p.brand} ${p.barcode} ${p.size} ${p.color}',
            _query,
          ),
        )
        .toList();

    return AppTable(
      minWidth: 860,
      columns: const [
        DataColumn(label: Text('SKU')),
        DataColumn(label: Text('NAME')),
        DataColumn(label: Text('SIZE')),
        DataColumn(label: Text('COLOUR')),
        DataColumn(label: Text('BARCODE')),
        DataColumn(label: Text('HSN')),
        DataColumn(label: Text('STOCK')),
        DataColumn(label: Text('PRICE'), numeric: true),
        DataColumn(label: Text('')),
      ],
      empty: EmptyState(
        icon: _store.products.isEmpty
            ? Icons.qr_code_2_rounded
            : Icons.search_off_rounded,
        title: _store.products.isEmpty
            ? 'No units yet'
            : 'Nothing matches that search',
        message: _store.products.isEmpty
            ? 'Units appear here once a design has been added — one per size '
                  'and colour, each with its own barcode.'
            : 'Check the barcode, or search by design name instead.',
      ),
      rows: [
        for (final p in rows)
          DataRow(
            cells: [
              DataCell(CodeText(p.sku, size: 12)),
              DataCell(
                Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                onTap: _canEdit ? () => _openUnitForm(p) : null,
              ),
              DataCell(Text(p.size)),
              DataCell(Text(p.color)),
              DataCell(CodeText(p.barcode, size: 12)),
              DataCell(CodeText(p.hsnCode, size: 12)),
              DataCell(StockPill(stock: p.stock, minimum: p.minimumStock)),
              DataCell(MoneyText(p.sellingPrice, size: 13)),
              DataCell(
                IconButton(
                  tooltip: 'Delete product',
                  onPressed: _canEdit ? () => _deleteProduct(p) : null,
                  icon: const Icon(Icons.delete_outline, size: 17),
                ),
              ),
            ],
          ),
      ],
    );
  }

  // ---------------------------------------------------------------- actions

  Future<void> _openStyleForm([StyleRecord? style]) async {
    await showDialog<void>(
      context: context,
      builder: (_) => StyleMatrixDialog(store: _store, style: style),
    );
  }

  /// Barcode price labels for a whole design, sized for the label stock the
  /// shop buys.
  Future<void> _printLabels(StyleRecord style) async {
    await showDialog<void>(
      context: context,
      builder: (_) => LabelPrintDialog(store: _store, style: style),
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

  Future<void> _deleteProduct(ProductRecord product) async {
    await _store.deleteProduct(product.id);
  }

  Future<void> _confirmDeleteStyle(StyleRecord style) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete design?'),
        content: Text(
          'This will deactivate ${style.name} and all of its variants, and set '
          'their stock to zero. This cannot be undone automatically.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete design'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _store.deleteStyle(style.id);
    }
  }
}
