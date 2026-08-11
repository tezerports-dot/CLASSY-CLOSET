import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../../core/services/gst.dart';
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
  late final TextEditingController _gstin;
  String? _logoPath;
  String? _stateCode;

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
      text: profile?.currencySymbol ?? '₹',
    );
    _gstin = TextEditingController(text: profile?.gstin ?? '');
    _stateCode = profile?.effectiveStateCode;
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
      _gstin,
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
          const Divider(height: 28),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'GST registration',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 4),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Enter your GSTIN to print bills as a tax invoice. Leave it blank '
              'and bills print as a plain receipt instead.',
              style: TextStyle(fontSize: 12.5),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _field(
                  _gstin,
                  'GSTIN (15 characters)',
                  // Optional, but a value that is present must be well formed:
                  // a malformed GSTIN on an invoice is worse than none at all.
                  validator: (value) {
                    final text = value?.trim() ?? '';
                    if (text.isEmpty) return null;
                    return isValidGstinFormat(text)
                        ? null
                        : 'Not a valid GSTIN';
                  },
                  onChanged: (value) {
                    final derived = stateCodeFromGstin(value);
                    if (derived != null && derived != _stateCode) {
                      setState(() => _stateCode = derived);
                    }
                  },
                  textCapitalization: TextCapitalization.characters,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: DropdownButtonFormField<String>(
                    initialValue: _stateCode,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'State (place of supply)',
                    ),
                    items: [
                      for (final entry in indianStateCodes.entries)
                        DropdownMenuItem(
                          value: entry.key,
                          child: Text(
                            '${entry.key} — ${entry.value}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (value) => setState(() => _stateCode = value),
                  ),
                ),
              ),
            ],
          ),
          const Divider(height: 28),
          _field(_receiptNumberPrefix, 'Invoice number prefix (e.g. CC)'),
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
    ValueChanged<String>? onChanged,
    TextCapitalization textCapitalization = TextCapitalization.none,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextFormField(
      controller: controller,
      decoration: InputDecoration(labelText: label),
      validator: validator,
      maxLines: maxLines,
      onChanged: onChanged,
      textCapitalization: textCapitalization,
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
        gstin: _gstin.text.trim().toUpperCase(),
        stateCode: _stateCode,
      ),
    );
    widget.onSaved();
  }
}
