import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/services/retail_store.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/validators.dart';

/// Creates or edits one design together with its whole size/colour run.
///
/// The grid is the point: colours run down the rows, sizes across the columns,
/// and each cell holds the stock for that one sellable unit. That is how a
/// clothing shop thinks about a rail, and it means a six-size, four-colour
/// design is entered once rather than as twenty-four separate products.
class StyleMatrixDialog extends StatefulWidget {
  const StyleMatrixDialog({required this.store, this.style, super.key});

  final RetailStore store;
  final StyleRecord? style;

  @override
  State<StyleMatrixDialog> createState() => _StyleMatrixDialogState();
}

class _StyleMatrixDialogState extends State<StyleMatrixDialog> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _styleCode;
  late final TextEditingController _name;
  late final TextEditingController _description;
  late final TextEditingController _category;
  late final TextEditingController _brand;
  late final TextEditingController _supplier;
  late final TextEditingController _hsnCode;
  late final TextEditingController _season;
  late final TextEditingController _purchasePrice;
  late final TextEditingController _sellingPrice;
  late final TextEditingController _location;
  final _sizeInput = TextEditingController();
  final _colorInput = TextEditingController();

  final _sizes = <String>[];
  final _colors = <String>[];

  /// Stock per cell, keyed "colour|size".
  final _stock = <String, TextEditingController>{};

  String? _imagePath;
  bool _saving = false;

  static String _key(String color, String size) => '$color|$size';

  @override
  void initState() {
    super.initState();
    final style = widget.style;
    _styleCode = TextEditingController(text: style?.styleCode ?? '');
    _name = TextEditingController(text: style?.name ?? '');
    _description = TextEditingController(text: style?.description ?? '');
    _category = TextEditingController(text: style?.category ?? '');
    _brand = TextEditingController(text: style?.brand ?? '');
    _supplier = TextEditingController(text: style?.supplier ?? '');
    _hsnCode = TextEditingController(
      text: (style?.hsnCode.isNotEmpty ?? false)
          ? style!.hsnCode
          : widget.store.gstSettings.defaultHsnCode,
    );
    _season = TextEditingController(text: style?.season ?? '');
    _purchasePrice = TextEditingController(text: _money(style?.purchasePrice));
    _sellingPrice = TextEditingController(text: _money(style?.sellingPrice));

    final firstVariant = style == null || style.variants.isEmpty
        ? null
        : style.variants.first;
    _location = TextEditingController(text: firstVariant?.location ?? '');

    if (style != null && style.variants.isNotEmpty) {
      _sizes.addAll(style.sizes);
      _colors.addAll(style.colors.map((c) => c.isEmpty ? 'Default' : c));
      for (final variant in style.variants) {
        final color = variant.color.isEmpty ? 'Default' : variant.color;
        _stock[_key(color, variant.size)] = TextEditingController(
          text: AppFormatters.quantity(variant.stock),
        );
        _imagePath ??= variant.imagePath;
      }
    } else {
      // A sensible starting rail for a new design; rows and columns can both be
      // edited before saving.
      _sizes.addAll(const ['S', 'M', 'L', 'XL']);
      _colors.add('Default');
    }
    _syncCells();
  }

  @override
  void dispose() {
    for (final c in [
      _styleCode,
      _name,
      _description,
      _category,
      _brand,
      _supplier,
      _hsnCode,
      _season,
      _purchasePrice,
      _sellingPrice,
      _location,
      _sizeInput,
      _colorInput,
    ]) {
      c.dispose();
    }
    for (final c in _stock.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// Gives every colour/size intersection a controller and drops the ones whose
  /// row or column has been removed.
  void _syncCells() {
    final wanted = <String>{
      for (final color in _colors)
        for (final size in _sizes) _key(color, size),
    };
    for (final key in wanted) {
      _stock.putIfAbsent(key, () => TextEditingController(text: '0'));
    }
    for (final key in _stock.keys.toList()) {
      if (wanted.contains(key)) continue;
      _stock.remove(key)?.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.grid_view, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(widget.style == null ? 'New design' : 'Edit design'),
          ),
          Text(
            '${_colors.length * _sizes.length} units',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
      content: SizedBox(
        width: 920,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _details(),
                const SizedBox(height: 8),
                _imageSection(theme),
                const SizedBox(height: 20),
                _runEditors(theme),
                const SizedBox(height: 18),
                _matrix(theme),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save),
          label: const Text('Save design'),
        ),
      ],
    );
  }

  Widget _details() => Column(
    children: [
      Row(
        children: [
          Expanded(
            child: _text(
              _styleCode,
              'Design code',
              validator: Validators.requiredText,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: _text(
              _name,
              'Design name',
              validator: Validators.requiredText,
            ),
          ),
        ],
      ),
      Row(
        children: [
          Expanded(child: _text(_category, 'Category')),
          const SizedBox(width: 12),
          Expanded(child: _text(_brand, 'Brand')),
          const SizedBox(width: 12),
          Expanded(child: _supplierPicker()),
        ],
      ),
      Row(
        children: [
          Expanded(
            child: _text(
              _purchasePrice,
              'Cost price',
              validator: Validators.nonNegativeNumber,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _text(
              _sellingPrice,
              'Selling price (MRP)',
              validator: Validators.nonNegativeNumber,
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: _text(_hsnCode, 'HSN code')),
          const SizedBox(width: 12),
          Expanded(child: _text(_season, 'Season')),
        ],
      ),
      Row(
        children: [
          Expanded(flex: 2, child: _text(_description, 'Description')),
          const SizedBox(width: 12),
          Expanded(child: _text(_location, 'Rack / location')),
        ],
      ),
      _gstPreview(),
    ],
  );

  /// Shows which slab the price lands in, so the tax consequence of a price is
  /// visible before it is saved.
  Widget _gstPreview() {
    final price = double.tryParse(_sellingPrice.text.trim()) ?? 0;
    if (price <= 0 || !widget.store.gstSettings.enabled) {
      return const SizedBox.shrink();
    }
    final rate = widget.store.gstSettings.rateFor(unitPrice: price);
    final inclusive = widget.store.gstSettings.pricesIncludeTax;
    return Align(
      alignment: Alignment.centerLeft,
      child: Chip(
        avatar: const Icon(Icons.percent, size: 16),
        label: Text(
          'GST ${rate.toStringAsFixed(0)}% · '
          '${inclusive ? 'included in' : 'added to'} '
          '${AppFormatters.currency(price)}',
        ),
      ),
    );
  }

  Widget _imageSection(ThemeData theme) {
    final file = _imagePath == null || !File(_imagePath!).existsSync()
        ? null
        : File(_imagePath!);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 104,
          height: 104,
          decoration: BoxDecoration(
            border: Border.all(color: theme.dividerColor),
            borderRadius: BorderRadius.circular(10),
          ),
          clipBehavior: Clip.antiAlias,
          child: file == null
              ? Icon(
                  Icons.checkroom,
                  size: 38,
                  color: theme.colorScheme.outline,
                )
              : Image.file(file, fit: BoxFit.cover),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Photo', style: theme.textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(
                'Shown on the POS tile and in the product list. The file is '
                'copied into the app folder, so moving the original later will '
                'not break it.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _pickImage,
                    icon: const Icon(Icons.add_photo_alternate),
                    label: Text(file == null ? 'Add photo' : 'Change photo'),
                  ),
                  if (file != null)
                    TextButton.icon(
                      onPressed: () => setState(() => _imagePath = null),
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Remove'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _runEditors(ThemeData theme) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: _chipEditor(
          theme,
          title: 'Sizes (columns)',
          values: _sizes,
          controller: _sizeInput,
          suggestions: widget.store.sizeNames,
          hint: 'S,M,L,XL — press Enter',
        ),
      ),
      const SizedBox(width: 20),
      Expanded(
        child: _chipEditor(
          theme,
          title: 'Colours (rows)',
          values: _colors,
          controller: _colorInput,
          suggestions: widget.store.colorNames,
          hint: 'Black,Navy — press Enter',
        ),
      ),
    ],
  );

  Widget _chipEditor(
    ThemeData theme, {
    required String title,
    required List<String> values,
    required TextEditingController controller,
    required List<String> suggestions,
    required String hint,
  }) {
    void add(String raw) {
      // Accept a comma-separated run in one go — a size range is normally typed
      // as "S,M,L,XL" rather than one value at a time.
      final added = raw
          .split(',')
          .map((v) => v.trim())
          .where((v) => v.isNotEmpty && !values.contains(v))
          .toList();
      if (added.isEmpty) return;
      setState(() {
        values.addAll(added);
        _syncCells();
      });
      controller.clear();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final value in values)
              InputChip(
                label: Text(value),
                onDeleted: values.length == 1
                    ? null
                    : () => setState(() {
                        values.remove(value);
                        _syncCells();
                      }),
              ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          decoration: InputDecoration(
            isDense: true,
            hintText: hint,
            suffixIcon: IconButton(
              icon: const Icon(Icons.add),
              onPressed: () => add(controller.text),
            ),
          ),
          onSubmitted: add,
        ),
        if (suggestions.isNotEmpty) ...[
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            children: [
              for (final s
                  in suggestions.where((s) => !values.contains(s)).take(8))
                ActionChip(
                  label: Text(s),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => add(s),
                ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _matrix(ThemeData theme) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Text('Stock by colour and size', style: theme.textTheme.titleSmall),
          const Spacer(),
          Text(
            'Total: ${_totalStock().toStringAsFixed(0)} pcs',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
      const SizedBox(height: 8),
      // A long size run makes the grid wider than the dialog, so it scrolls on
      // its own rather than forcing the dialog wider.
      Container(
        decoration: BoxDecoration(
          border: Border.all(color: theme.dividerColor),
          borderRadius: BorderRadius.circular(8),
        ),
        clipBehavior: Clip.antiAlias,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowHeight: 40,
            dataRowMinHeight: 54,
            dataRowMaxHeight: 54,
            columns: [
              const DataColumn(label: Text('Colour')),
              for (final size in _sizes) DataColumn(label: Text(size)),
              const DataColumn(label: Text('Total')),
            ],
            rows: [
              for (final color in _colors)
                DataRow(
                  cells: [
                    DataCell(
                      Text(
                        color,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    for (final size in _sizes)
                      DataCell(
                        SizedBox(
                          width: 64,
                          child: TextFormField(
                            controller: _stock[_key(color, size)],
                            textAlign: TextAlign.center,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            decoration: const InputDecoration(
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(
                                vertical: 8,
                                horizontal: 6,
                              ),
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                      ),
                    DataCell(Text(_rowTotal(color).toStringAsFixed(0))),
                  ],
                ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 6),
      Text(
        'Leave a cell at 0 to stock it later. Each filled cell becomes its own '
        'sellable unit with its own barcode, generated from the design code, '
        'colour and size.',
        style: theme.textTheme.bodySmall,
      ),
    ],
  );

  double _rowTotal(String color) => _sizes.fold(0.0, (sum, size) {
    final text = _stock[_key(color, size)]?.text ?? '';
    return sum + (double.tryParse(text) ?? 0);
  });

  double _totalStock() =>
      _colors.fold(0.0, (sum, color) => sum + _rowTotal(color));

  Widget _text(
    TextEditingController controller,
    String label, {
    String? Function(String?)? validator,
    ValueChanged<String>? onChanged,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextFormField(
      controller: controller,
      decoration: InputDecoration(labelText: label, isDense: true),
      validator: validator,
      onChanged: onChanged,
    ),
  );

  Widget _supplierPicker() {
    final names = widget.store.suppliers.map((s) => s.name).toSet().toList()
      ..sort();
    final value = names.contains(_supplier.text) ? _supplier.text : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<String>(
        initialValue: value,
        isExpanded: true,
        decoration: const InputDecoration(
          labelText: 'Supplier',
          isDense: true,
          helperText: 'Add suppliers on the Supplier page first.',
        ),
        items: [
          const DropdownMenuItem(value: '', child: Text('No supplier')),
          for (final name in names)
            DropdownMenuItem(value: name, child: Text(name)),
        ],
        onChanged: (value) => setState(() => _supplier.text = value ?? ''),
      ),
    );
  }

  Future<void> _pickImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );
    final path = result?.files.single.path;
    if (path == null || !mounted) return;
    setState(() => _imagePath = path);
  }

  String _money(double? value) =>
      value == null || value == 0 ? '' : value.toStringAsFixed(2);

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final code = _styleCode.text.trim();
      final cost = double.tryParse(_purchasePrice.text.trim()) ?? 0;
      final price = double.tryParse(_sellingPrice.text.trim()) ?? 0;

      final variants = <ProductRecord>[];
      for (final color in _colors) {
        for (final size in _sizes) {
          final stock =
              double.tryParse(_stock[_key(color, size)]?.text.trim() ?? '') ??
              0;
          final isDefaultColor = color == 'Default';
          final slug = [
            code,
            if (!isDefaultColor) color,
            size,
          ].join('-').replaceAll(' ', '');

          variants.add(
            ProductRecord(
              id: 0,
              sku: slug,
              name: _name.text.trim(),
              category: _category.text.trim(),
              brand: _brand.text.trim(),
              unit: 'pcs',
              stock: stock,
              minimumStock: 1,
              purchasePrice: cost,
              sellingPrice: price,
              barcode: slug,
              location: _location.text.trim(),
              size: size,
              color: isDefaultColor ? '' : color,
              hsnCode: _hsnCode.text.trim(),
            ),
          );
        }
      }

      final styleId = await widget.store.saveStyle(
        StyleRecord(
          id: widget.style?.id ?? 0,
          styleCode: code,
          name: _name.text.trim(),
          description: _description.text.trim(),
          category: _category.text.trim(),
          brand: _brand.text.trim(),
          supplier: _supplier.text.trim(),
          hsnCode: _hsnCode.text.trim(),
          season: _season.text.trim(),
          purchasePrice: cost,
          sellingPrice: price,
        ),
        variants: variants,
      );

      // The photo belongs to the design, so it is attached to every unit under
      // it and the POS tile for any size shows the same picture.
      final path = _imagePath;
      if (path != null && File(path).existsSync()) {
        final saved = widget.store.styles
            .where((s) => s.id == styleId)
            .expand((s) => s.variants)
            .toList();
        for (final variant in saved) {
          if (variant.imagePath == path) continue;
          await widget.store.saveProductImage(variant.id, path);
        }
      }

      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
