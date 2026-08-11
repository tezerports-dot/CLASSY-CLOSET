import 'package:flutter/material.dart';

import '../../../../core/services/retail_store.dart';
import '../../../../core/utils/validators.dart';

class CustomerFormDialog extends StatefulWidget {
  const CustomerFormDialog({required this.store, this.customer, super.key});

  final RetailStore store;
  final CustomerRecord? customer;

  @override
  State<CustomerFormDialog> createState() => _CustomerFormDialogState();
}

class _CustomerFormDialogState extends State<CustomerFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _email;
  late final TextEditingController _address;
  late final TextEditingController _creditLimit;
  late final TextEditingController _openingBalance;

  @override
  void initState() {
    super.initState();
    final customer = widget.customer;
    _name = TextEditingController(text: customer?.name ?? '');
    _phone = TextEditingController(text: customer?.phone ?? '');
    _email = TextEditingController(text: customer?.email ?? '');
    _address = TextEditingController(text: customer?.address ?? '');
    _creditLimit = TextEditingController(text: _format(customer?.creditLimit));
    _openingBalance = TextEditingController(
      text: _format(customer?.openingBalance),
    );
  }

  @override
  void dispose() {
    for (final controller in [
      _name,
      _phone,
      _email,
      _address,
      _creditLimit,
      _openingBalance,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.customer == null ? 'Add customer' : 'Edit customer'),
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
                Row(
                  children: [
                    Expanded(
                      child: _field(
                        _creditLimit,
                        'Credit limit',
                        validator: Validators.nonNegativeNumber,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _field(
                        _openingBalance,
                        'Opening balance',
                        validator: Validators.nonNegativeNumber,
                      ),
                    ),
                  ],
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
    final existing = widget.customer;
    await widget.store.saveCustomer(
      CustomerRecord(
        id: existing?.id ?? 0,
        name: _name.text.trim(),
        phone: _phone.text.trim(),
        email: _email.text.trim(),
        address: _address.text.trim(),
        creditLimit: _parse(_creditLimit.text),
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
