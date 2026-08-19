import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../../core/services/gst.dart';
import '../../../../core/services/retail_store.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/validators.dart';
import '../../../../core/widgets/ui_kit.dart';

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
  late final TextEditingController _tagline;
  late final TextEditingController _termsText;
  late final TextEditingController _declarationText;
  late final TextEditingController _bankDetails;
  late final TextEditingController _jurisdiction;
  String? _logoPath;
  String? _stateCode;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // A shop that has not been set up yet starts from the packaged defaults;
    // one that has starts from whatever it saved.
    final profile = widget.store.storeProfile ?? StoreProfile.firstRunDefaults;
    _storeName = TextEditingController(text: profile.storeName);
    _address = TextEditingController(text: profile.address ?? '');
    _phone = TextEditingController(text: profile.phone ?? '');
    _email = TextEditingController(text: profile.email ?? '');
    _taxRegistrationNumber = TextEditingController(
      text: profile.taxRegistrationNumber ?? '',
    );
    _currencySymbol = TextEditingController(text: profile.currencySymbol);
    _gstin = TextEditingController(text: profile.gstin ?? '');
    _stateCode = profile.effectiveStateCode;
    _receiptFooterText = TextEditingController(
      text: profile.receiptFooterText ?? '',
    );
    _receiptNumberPrefix = TextEditingController(
      text: profile.receiptNumberPrefix,
    );
    _tagline = TextEditingController(text: profile.tagline);
    _termsText = TextEditingController(text: profile.termsText);
    _declarationText = TextEditingController(text: profile.declarationText);
    _bankDetails = TextEditingController(text: profile.bankDetails);
    _jurisdiction = TextEditingController(text: profile.jurisdiction);
    _logoPath = profile.logoPath;
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
      _tagline,
      _termsText,
      _declarationText,
      _bankDetails,
      _jurisdiction,
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
          _groupLabel('Who you are'),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // The logo sits beside the name it belongs to rather than
              // floating above the form.
              Column(
                children: [
                  Container(
                    width: 92,
                    height: 92,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceAlt,
                      borderRadius: AppRadii.inputBorder,
                      border: Border.all(color: AppColors.border),
                    ),
                    child: logo == null
                        ? const Icon(
                            Icons.storefront_outlined,
                            size: 30,
                            color: AppColors.border,
                          )
                        : Image.file(logo, fit: BoxFit.contain),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextButton(
                    onPressed: _pickLogo,
                    child: Text(_logoPath == null ? 'Add logo' : 'Change'),
                  ),
                ],
              ),
              const SizedBox(width: AppSpacing.xl),
              Expanded(
                child: Column(
                  children: [
                    _field(
                      _storeName,
                      'Shop name',
                      validator: Validators.requiredText,
                    ),
                    _field(_address, 'Address', maxLines: 3),
                  ],
                ),
              ),
            ],
          ),
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
          const Divider(height: 32),
          _groupLabel(
            'GST registration',
            hint:
                'Enter your GSTIN to print bills as a tax invoice. Leave it '
                'blank and bills print as a plain receipt instead.',
          ),
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
          const Divider(height: 32),
          _groupLabel(
            'What prints on the bill',
            hint:
                'The tagline sits under the shop name; the rest print at the '
                'foot of the bill.',
          ),
          _field(_receiptNumberPrefix, 'Invoice number prefix (e.g. CC)'),
          _field(
            _tagline,
            'Tagline under the shop name on the bill',
            maxLines: 2,
          ),
          _field(_receiptFooterText, 'Thank-you line', maxLines: 2),
          _field(
            _termsText,
            'Exchange policy printed on every bill',
            maxLines: 3,
          ),
          _field(
            _jurisdiction,
            'Jurisdiction line (e.g. Subject to Jaipur jurisdiction)',
          ),
          _field(
            _declarationText,
            'Declaration on the full-sheet tax invoice',
            maxLines: 3,
          ),
          _field(
            _bankDetails,
            'Bank details for business buyers (optional)',
            maxLines: 3,
          ),
          const SizedBox(height: AppSpacing.md),
          Align(
            alignment: Alignment.centerLeft,
            child: AccentButton(
              label: 'Save shop profile',
              icon: Icons.save_outlined,
              tall: true,
              busy: _saving,
              onPressed: _save,
            ),
          ),
        ],
      ),
    );
  }

  /// A heading inside the form, so a long profile reads as three short
  /// sections rather than twenty consecutive boxes.
  Widget _groupLabel(String title, {String? hint}) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.base),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title.toUpperCase(),
          style: AppTypography.microLabel.copyWith(color: AppColors.goldDeep),
        ),
        if (hint != null) ...[
          const SizedBox(height: 3),
          Text(
            hint,
            style: const TextStyle(fontSize: 12.5, color: AppColors.inkFaint),
          ),
        ],
      ],
    ),
  );

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
    setState(() => _saving = true);
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
        tagline: _tagline.text.trim(),
        termsText: _termsText.text.trim(),
        declarationText: _declarationText.text.trim(),
        bankDetails: _bankDetails.text.trim(),
        jurisdiction: _jurisdiction.text.trim(),
        gstin: _gstin.text.trim().toUpperCase(),
        stateCode: _stateCode,
      ),
    );
    if (mounted) setState(() => _saving = false);
    widget.onSaved();
  }
}
