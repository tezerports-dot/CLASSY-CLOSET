import 'package:flutter/material.dart';

import '../../../../core/services/retail_store.dart';
import '../../../../core/utils/validators.dart';

class SupplierFormDialog extends StatefulWidget {
  const SupplierFormDialog({required this.store, this.supplier, super.key});

  final RetailStore store;
  final SupplierRecord? supplier;

  @override
  State<SupplierFormDialog> createState() => _SupplierFormDialogState();
}

class _SupplierFormDialogState extends State<SupplierFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _email;
  late final TextEditingController _address;
  late final TextEditingController _openingBalance;

  @override
  void initState() {
    super.initState();
    final supplier = widget.supplier;
    _name = TextEditingController(text: supplier?.name ?? '');
    _phone = TextEditingController(text: supplier?.phone ?? '');
    _email = TextEditingController(text: supplier?.email ?? '');
    _address = TextEditingController(text: supplier?.address ?? '');
    _openingBalance = TextEditingController(
      text: _format(supplier?.openingBalance),
    );
  }

  @override
  void dispose() {
    for (final controller in [
      _name,
      _phone,
      _email,
      _address,
      _openingBalance,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.supplier == null ? 'Add supplier' : 'Edit supplier'),
      content: SizedBox(
        width: 520,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _field(_name, 'Name', validator: Validators.requiredText),
                _field(_phone, 'Phone'),
                _field(_email, 'Email'),
                _field(_address, 'Address', maxLines: 3),
                _field(
                  _openingBalance,
                  'Opening balance',
                  validator: Validators.nonNegativeNumber,
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

  Widget _field(
    TextEditingController controller,
    String label, {
    String? Function(String?)? validator,
    int maxLines = 1,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextFormField(
      controller: controller,
      decoration: InputDecoration(labelText: label),
      validator: validator,
      maxLines: maxLines,
    ),
  );

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final opening = _parse(_openingBalance.text);
    final existing = widget.supplier;
    await widget.store.saveSupplier(
      SupplierRecord(
        id: existing?.id ?? 0,
        name: _name.text.trim(),
        phone: _phone.text.trim(),
        email: _email.text.trim(),
        address: _address.text.trim(),
        openingBalance: opening,
        balance: existing == null ? opening : existing.balance,
      ),
    );
    if (mounted) Navigator.of(context).pop();
  }

  double _parse(String value) => double.tryParse(value.trim()) ?? 0;
  String _format(double? value) =>
      value == null || value == 0 ? '' : value.toString();
}
