import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../../core/services/retail_store.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/brand_theme.dart';
import '../../../../core/widgets/brand_mark.dart';
import '../../../../core/widgets/ui_kit.dart';

/// Everything visual about the shop that is not the bill's own wording.
///
/// The colours a customer sees, the subtitle under the name on the login card,
/// and the image that goes on the sign, the rail and the app tab. All four
/// live together so a second shop can rebrand from one screen — pick a preset,
/// swap two hex values, upload the mark, save.
class BrandLookForm extends StatefulWidget {
  const BrandLookForm({required this.store, required this.onSaved, super.key});

  final RetailStore store;
  final VoidCallback onSaved;

  @override
  State<BrandLookForm> createState() => _BrandLookFormState();
}

class _BrandLookFormState extends State<BrandLookForm> {
  late final TextEditingController _subtitle;
  late final TextEditingController _brandHex;
  late final TextEditingController _accentHex;
  String? _brandImagePath;
  BrandTheme _theme = BrandTheme.classic;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final profile = widget.store.storeProfile ?? StoreProfile.firstRunDefaults;
    _theme = profile.brandTheme;
    _subtitle = TextEditingController(text: profile.subtitle);
    _brandHex = TextEditingController(text: _hex(_theme.brand));
    _accentHex = TextEditingController(text: _hex(_theme.accent));
    _brandImagePath = profile.brandImagePath;
  }

  @override
  void dispose() {
    _subtitle.dispose();
    _brandHex.dispose();
    _accentHex.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionLabel('Brand mark'),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Same widget the rail and the login use, so the preview here is
            // what the app is about to look like — not a mock of it.
            BrandMark(size: 96, path: _brandImagePath),
            const SizedBox(width: AppSpacing.xl),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'The round mark shown on the login panel, the rail and '
                    'the browser tab. A square image works fine — it is '
                    'clipped to a circle.',
                    style: TextStyle(fontSize: 12.5, color: AppColors.inkFaint),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    children: [
                      SecondaryButton(
                        label: _brandImagePath == null
                            ? 'Upload brand image'
                            : 'Change image',
                        icon: Icons.upload_rounded,
                        onPressed: _pickBrandImage,
                      ),
                      if (_brandImagePath != null) ...[
                        const SizedBox(width: AppSpacing.sm),
                        TextButton(
                          onPressed: () =>
                              setState(() => _brandImagePath = null),
                          child: const Text('Use the bundled mark'),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        const Divider(height: 32),
        _sectionLabel('Wordmark subtitle'),
        const Text(
          'The small line under the shop name on the login card. '
          'Leave blank to hide it — the artwork usually says what the shop is.',
          style: TextStyle(fontSize: 12.5, color: AppColors.inkFaint),
        ),
        const SizedBox(height: AppSpacing.sm),
        TextField(
          controller: _subtitle,
          decoration: const InputDecoration(
            labelText: 'Subtitle',
            hintText: 'e.g. MEN\'S FASHION STORE',
          ),
          textCapitalization: TextCapitalization.characters,
        ),
        const Divider(height: 32),
        _sectionLabel('Colours'),
        const Text(
          'Pick a preset combination, or type your own two hex values. '
          'The brand is the rail and the dark buttons; the accent is the '
          'checkout button, the focus ring and the small marks.',
          style: TextStyle(fontSize: 12.5, color: AppColors.inkFaint),
        ),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final preset in BrandTheme.presets) _presetChip(preset),
            _customChip(),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Expanded(child: _hexField('Brand colour', _brandHex, _theme.brand)),
            const SizedBox(width: AppSpacing.base),
            Expanded(
              child: _hexField('Accent colour', _accentHex, _theme.accent),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xl),
        _previewCard(),
        const SizedBox(height: AppSpacing.xl),
        Align(
          alignment: Alignment.centerLeft,
          child: AccentButton(
            label: 'Save brand look',
            icon: Icons.palette_outlined,
            tall: true,
            busy: _saving,
            onPressed: _save,
          ),
        ),
      ],
    );
  }

  Widget _sectionLabel(String label) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
    child: Text(
      label.toUpperCase(),
      style: AppTypography.microLabel.copyWith(color: AppColors.goldDeep),
    ),
  );

  Widget _presetChip(BrandTheme preset) {
    final selected =
        preset.brand.toARGB32() == _theme.brand.toARGB32() &&
        preset.accent.toARGB32() == _theme.accent.toARGB32();
    return FilterChip(
      selected: selected,
      showCheckmark: false,
      onSelected: (_) => _applyTheme(preset),
      avatar: _swatchPair(preset.brand, preset.accent),
      label: Text(preset.name),
    );
  }

  Widget _customChip() {
    final isCustom = !_theme.isPreset;
    return FilterChip(
      selected: isCustom,
      showCheckmark: false,
      onSelected: (_) => _applyTheme(_theme.asCustom()),
      avatar: const Icon(Icons.tune_rounded, size: 15),
      label: const Text('Custom'),
    );
  }

  /// A miniature swatch that mirrors the brand and the accent, so a preset can
  /// be identified at a glance without reading the label.
  Widget _swatchPair(Color brand, Color accent) => SizedBox(
    width: 22,
    height: 14,
    child: Row(
      children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: brand,
              borderRadius: const BorderRadius.horizontal(
                left: Radius.circular(3),
              ),
            ),
          ),
        ),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: accent,
              borderRadius: const BorderRadius.horizontal(
                right: Radius.circular(3),
              ),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _hexField(String label, TextEditingController c, Color live) =>
      TextField(
        controller: c,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Padding(
            padding: const EdgeInsets.only(left: 10, right: 6),
            child: Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: live,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: AppColors.border),
              ),
            ),
          ),
          prefixIconConstraints: const BoxConstraints(minWidth: 44),
          hintText: '#RRGGBB',
        ),
        onChanged: _onHexChanged,
        textCapitalization: TextCapitalization.characters,
      );

  /// A live preview panel that paints itself with the currently-chosen brand
  /// and accent, so the effect of the pick can be seen before saving.
  Widget _previewCard() {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: AppRadii.cardBorder,
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 96,
            padding: const EdgeInsets.all(AppSpacing.xl),
            decoration: BoxDecoration(color: _theme.brand),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [BrandMark(size: 40, path: _brandImagePath)],
            ),
          ),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Preview',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.inkFaint,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    widget.store.storeProfile?.storeName ?? 'Your shop',
                    style: TextStyle(
                      fontFamily: AppTypography.display,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: _theme.brand,
                      letterSpacing: 1.6,
                    ),
                  ),
                  if (_subtitle.text.trim().isNotEmpty)
                    Text(
                      _subtitle.text.trim(),
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: _theme.accent,
                        letterSpacing: 1.4,
                      ),
                    ),
                  const SizedBox(height: AppSpacing.md),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                      vertical: AppSpacing.sm,
                    ),
                    decoration: BoxDecoration(
                      color: _theme.accent,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'Checkout & print',
                      style: TextStyle(
                        color: _theme.brand,
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _applyTheme(BrandTheme theme) {
    setState(() {
      _theme = theme;
      _brandHex.text = _hex(theme.brand);
      _accentHex.text = _hex(theme.accent);
    });
  }

  void _onHexChanged(String _) {
    final brand = _parseHex(_brandHex.text) ?? _theme.brand;
    final accent = _parseHex(_accentHex.text) ?? _theme.accent;
    if (brand.toARGB32() == _theme.brand.toARGB32() &&
        accent.toARGB32() == _theme.accent.toARGB32()) {
      return;
    }
    final matched = BrandTheme.presets.firstWhere(
      (p) =>
          p.brand.toARGB32() == brand.toARGB32() &&
          p.accent.toARGB32() == accent.toARGB32(),
      orElse: () => BrandTheme(name: 'Custom', brand: brand, accent: accent),
    );
    setState(() => _theme = matched);
  }

  static String _hex(Color c) =>
      '#${c.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';

  static Color? _parseHex(String raw) {
    final trimmed = raw.trim().replaceAll('#', '');
    if (trimmed.length != 6) return null;
    final v = int.tryParse(trimmed, radix: 16);
    if (v == null) return null;
    return Color(0xFF000000 | v);
  }

  Future<void> _pickBrandImage() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );
    final path = picked?.files.single.path;
    if (path == null) return;
    final copied = await widget.store.copyBrandImageToAppFolder(path);
    if (mounted) setState(() => _brandImagePath = copied);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final base = widget.store.storeProfile ?? StoreProfile.firstRunDefaults;
    await widget.store.saveStoreProfile(
      base.copyWith(
        brandImagePath: _brandImagePath,
        clearBrandImagePath: _brandImagePath == null,
        subtitle: _subtitle.text.trim(),
        brandTheme: _theme,
      ),
    );
    if (mounted) setState(() => _saving = false);
    widget.onSaved();
  }
}
