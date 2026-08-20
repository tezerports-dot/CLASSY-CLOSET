import 'package:flutter/material.dart';

import '../../../../core/services/retail_store.dart';
import '../../../../core/utils/validators.dart';

class ProductFormDialog extends StatefulWidget {
  const ProductFormDialog({required this.store, this.product, super.key});

  final RetailStore store;
  final ProductRecord? product;

  @override
  State<ProductFormDialog> createState() => _ProductFormDialogState();
}

class _ProductFormDialogState extends State<ProductFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _sku;
  late final TextEditingController _barcode;
  late final TextEditingController _name;
  late final TextEditingController _description;
  late final TextEditingController _category;
  late final TextEditingController _brand;
  late final TextEditingController _unit;
  late final TextEditingController _supplier;
  late final TextEditingController _purchasePrice;
  late final TextEditingController _sellingPrice;
  late final TextEditingController _wholesalePrice;
  late final TextEditingController _taxRate;
  late final TextEditingController _currentStock;
  late final TextEditingController _minimumStock;
  late final TextEditingController _maximumStock;
  late final TextEditingController _location;
  DateTime? _expiryDate;

  @override
  void initState() {
    super.initState();
    final product = widget.product;
    _sku = TextEditingController(text: product?.sku ?? '');
    _barcode = TextEditingController(text: product?.barcode ?? '');
    _name = TextEditingController(text: product?.name ?? '');
    _description = TextEditingController(text: product?.description ?? '');
    _category = TextEditingController(text: product?.category ?? '');
    _brand = TextEditingController(text: product?.brand ?? '');
    _unit = TextEditingController(
      text:
          product?.unit ??
          (widget.store.unitNames.isEmpty
              ? 'pcs'
              : widget.store.unitNames.first),
    );
    _supplier = TextEditingController(text: product?.supplier ?? '');
    _purchasePrice = TextEditingController(
      text: _format(product?.purchasePrice),
    );
    _sellingPrice = TextEditingController(text: _format(product?.sellingPrice));
    _wholesalePrice = TextEditingController(
      text: _format(product?.wholesalePrice),
    );
    _taxRate = TextEditingController(text: _format(product?.taxRate));
    _currentStock = TextEditingController(text: _format(product?.stock));
    _minimumStock = TextEditingController(text: _format(product?.minimumStock));
    _maximumStock = TextEditingController(text: _format(product?.maximumStock));
    _location = TextEditingController(text: product?.location ?? '');
    _expiryDate = product?.expiryDate;
  }

  @override
  void dispose() {
    for (final controller in [
      _sku,
      _barcode,
      _name,
      _description,
      _category,
      _brand,
      _unit,
      _supplier,
      _purchasePrice,
      _sellingPrice,
      _wholesalePrice,
      _taxRate,
      _currentStock,
      _minimumStock,
      _maximumStock,
      _location,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.product == null ? 'Add product' : 'Edit product'),
      content: SizedBox(
        width: 760,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _text(
                        _sku,
                        'SKU',
                        validator: Validators.requiredText,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: _text(_barcode, 'Barcode (optional)')),
                  ],
                ),
                Row(
                  children: [
                    Expanded(
                      child: _text(
                        _name,
                        'Name',
                        validator: Validators.requiredText,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: _text(_description, 'Description')),
                  ],
                ),
                Row(
                  children: [
                    Expanded(
                      child: _lookup(
                        _category,
                        'Category',
                        widget.store.categoryNames,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _lookup(_brand, 'Brand', widget.store.brandNames),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Expanded(
                      child: _lookup(
                        _unit,
                        'Unit',
                        widget.store.unitNames,
                        required: true,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _supplierPicker(),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Expanded(child: _number(_purchasePrice, 'Purchase price')),
                    const SizedBox(width: 12),
                    Expanded(child: _number(_sellingPrice, 'Selling price')),
                  ],
                ),
                Row(
                  children: [
                    Expanded(
                      child: _number(_wholesalePrice, 'Wholesale price'),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: _number(_taxRate, 'Tax rate %')),
                  ],
                ),
                Row(
                  children: [
                    Expanded(child: _number(_currentStock, 'Current stock')),
                    const SizedBox(width: 12),
                    Expanded(child: _number(_minimumStock, 'Minimum stock')),
                  ],
                ),
                Row(
                  children: [
                    Expanded(
                      child: _number(
                        _maximumStock,
                        'Maximum stock',
                        required: false,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: _text(_location, 'Location')),
                  ],
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    _expiryDate == null
                        ? 'No expiry date'
                        : 'Expiry: ${_expiryDate!.toIso8601String().split('T').first}',
                  ),
                  trailing: Wrap(
                    spacing: 8,
                    children: [
                      TextButton(
                        onPressed: _pickExpiry,
                        child: const Text('Pick date'),
                      ),
                      if (_expiryDate != null)
                        TextButton(
                          onPressed: () => setState(() => _expiryDate = null),
                          child: const Text('Clear'),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }

  Widget _text(
    TextEditingController controller,
    String label, {
    String? Function(String?)? validator,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextFormField(
      controller: controller,
      decoration: InputDecoration(labelText: label),
      validator: validator,
    ),
  );
  Widget _number(
    TextEditingController controller,
    String label, {
    bool required = true,
  }) => _text(
    controller,
    label,
    validator: required
        ? Validators.nonNegativeNumber
        : (value) => (value == null || value.trim().isEmpty)
              ? null
              : Validators.nonNegativeNumber(value),
  );

  Widget _lookup(
    TextEditingController controller,
    String label,
    List<String> options, {
    bool required = false,
  }) {
    final normalized = options.toSet().toList()..sort();
    final value = normalized.contains(controller.text) ? controller.text : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              initialValue: value,
              decoration: InputDecoration(labelText: label),
              items: [
                for (final option in normalized)
                  DropdownMenuItem(value: option, child: Text(option)),
              ],
              onChanged: (value) =>
                  setState(() => controller.text = value ?? controller.text),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextFormField(
              controller: controller,
              decoration: InputDecoration(labelText: 'New/existing $label'),
              validator: required ? Validators.requiredText : null,
            ),
          ),
        ],
      ),
    );
  }

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
          helperText: 'Suppliers are managed on the Supplier page.',
        ),
        items: [
          for (final name in names)
            DropdownMenuItem(value: name, child: Text(name)),
        ],
        onChanged: (value) => setState(() => _supplier.text = value ?? ''),
      ),
    );
  }

  Future<void> _pickExpiry() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _expiryDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _expiryDate = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final product = ProductRecord(
      id: widget.product?.id ?? 0,
      sku: _sku.text.trim(),
      name: _name.text.trim(),
      category: _category.text.trim(),
      brand: _brand.text.trim(),
      unit: _unit.text.trim(),
      stock: _parse(_currentStock.text),
      minimumStock: _parse(_minimumStock.text),
      purchasePrice: _parse(_purchasePrice.text),
      sellingPrice: _parse(_sellingPrice.text),
      barcode: _barcode.text.trim(),
      location: _location.text.trim(),
      description: _description.text.trim(),
      supplier: _supplier.text.trim(),
      wholesalePrice: _parse(_wholesalePrice.text),
      taxRate: _parse(_taxRate.text),
      maximumStock: _maximumStock.text.trim().isEmpty
          ? null
          : _parse(_maximumStock.text),
      expiryDate: _expiryDate,
    );
    await widget.store.saveProduct(product);
    if (mounted) Navigator.of(context).pop();
  }

  double _parse(String value) => double.tryParse(value.trim()) ?? 0;
  String _format(double? value) =>
      value == null || value == 0 ? '' : value.toString();
}
