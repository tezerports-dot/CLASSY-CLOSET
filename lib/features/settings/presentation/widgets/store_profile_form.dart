import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../../core/services/retail_store.dart';
import '../../../../core/utils/validators.dart';

class StoreProfileForm extends StatefulWidget {
  const StoreProfileForm({
    required this.store,
    required this.onSaved,
    super.key,
  });

  final RetailStore store;
  final VoidCallback onSaved;
  @override
  State<StoreProfileForm> createState() => _StoreProfileFormState();
}

class _StoreProfileFormState extends State<StoreProfileForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _storeName;
  late final TextEditingController _address;
  late final TextEditingController _phone;
  late final TextEditingController _email;
  late final TextEditingController _taxRegistrationNumber;
  late final TextEditingController _currencySymbol;
  late final TextEditingController _receiptFooterText;
  late final TextEditingController _receiptNumberPrefix;
  String? _logoPath;

  @override
  void initState() {
    super.initState();
    final profile = widget.store.storeProfile;
    _storeName = TextEditingController(text: profile?.storeName ?? '');
    _address = TextEditingController(text: profile?.address ?? '');
    _phone = TextEditingController(text: profile?.phone ?? '');
    _email = TextEditingController(text: profile?.email ?? '');
    _taxRegistrationNumber = TextEditingController(
      text: profile?.taxRegistrationNumber ?? '',
    );
    _currencySymbol = TextEditingController(
      text: profile?.currencySymbol ?? r'$',
    );
    _receiptFooterText = TextEditingController(
      text: profile?.receiptFooterText ?? 'Thank you for shopping with us.',
    );
    _receiptNumberPrefix = TextEditingController(
      text: profile?.receiptNumberPrefix ?? '',
    );
    _logoPath = profile?.logoPath;
  }

  @override
  void dispose() {
    for (final controller in [
      _storeName,
      _address,
      _phone,
      _email,
      _taxRegistrationNumber,
      _currencySymbol,
      _receiptFooterText,
      _receiptNumberPrefix,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final logo = _logoPath == null || !File(_logoPath!).existsSync()
        ? null
        : File(_logoPath!);
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (logo != null) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: Image.file(
                logo,
                width: 96,
                height: 96,
                fit: BoxFit.contain,
              ),
            ),
            const SizedBox(height: 12),
          ],
          _field(_storeName, 'Store name', validator: Validators.requiredText),
          _field(_address, 'Address', maxLines: 3),
          Row(
            children: [
              Expanded(child: _field(_phone, 'Phone')),
              const SizedBox(width: 12),
              Expanded(
                child: _field(
                  _currencySymbol,
                  'Currency symbol',
                  validator: Validators.requiredText,
                ),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(child: _field(_email, 'Email')),
              const SizedBox(width: 12),
              Expanded(
                child: _field(
                  _taxRegistrationNumber,
                  'Tax / registration number',
                ),
              ),
            ],
          ),
          _field(_receiptNumberPrefix, 'Receipt number prefix (optional)'),
          _field(_receiptFooterText, 'Receipt footer text', maxLines: 2),
          OutlinedButton.icon(
            onPressed: _pickLogo,
            icon: const Icon(Icons.image),
            label: Text(_logoPath == null ? 'Choose logo' : 'Change logo'),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save),
            label: const Text('Save store profile'),
          ),
        ],
      ),
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

  Future<void> _pickLogo() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );
    final path = result?.files.single.path;
    if (path == null) return;
    final copied = await widget.store.copyLogoToAppFolder(path);
    if (mounted) setState(() => _logoPath = copied);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    await widget.store.saveStoreProfile(
      StoreProfile(
        storeName: _storeName.text.trim(),
        logoPath: _logoPath,
        address: _address.text.trim(),
        phone: _phone.text.trim(),
        email: _email.text.trim(),
        taxRegistrationNumber: _taxRegistrationNumber.text.trim(),
        currencySymbol: _currencySymbol.text.trim(),
        receiptFooterText: _receiptFooterText.text.trim(),
        receiptNumberPrefix: _receiptNumberPrefix.text.trim(),
      ),
    );
    widget.onSaved();
  }
}
