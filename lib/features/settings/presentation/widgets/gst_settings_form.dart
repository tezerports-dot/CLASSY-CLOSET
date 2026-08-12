import 'package:flutter/material.dart';

import '../../../../core/services/gst.dart';
import '../../../../core/services/retail_store.dart';
import '../../../../core/utils/formatters.dart';

/// Lets the shop set its own GST rate bands.
///
/// Rates are entered by hand rather than shipped as constants: the apparel
/// threshold has already moved once (Rs 1,000 to Rs 2,500) and a shop must be
/// able to correct a rate the day its accountant says so, without waiting for
/// a new build.
class GstSettingsForm extends StatefulWidget {
  const GstSettingsForm({
    required this.store,
    required this.onSaved,
    super.key,
  });

  final RetailStore store;
  final VoidCallback onSaved;

  @override
  State<GstSettingsForm> createState() => _GstSettingsFormState();
}

class _GstSettingsFormState extends State<GstSettingsForm> {
  final _formKey = GlobalKey<FormState>();
  late bool _enabled;
  late bool _pricesIncludeTax;
  late final TextEditingController _defaultHsn;

  /// One editable row per band: the price ceiling and the rate.
  final _bands = <_BandControllers>[];

  @override
  void initState() {
    super.initState();
    final settings = widget.store.gstSettings;
    _enabled = settings.enabled;
    _pricesIncludeTax = settings.pricesIncludeTax;
    _defaultHsn = TextEditingController(text: settings.defaultHsnCode);
    for (final slab in settings.slabs) {
      _bands.add(
        _BandControllers(
          upTo: TextEditingController(
            text: slab.upToPrice == null
                ? ''
                : slab.upToPrice!.toStringAsFixed(0),
          ),
          rate: TextEditingController(
            text: slab.ratePercent.toStringAsFixed(0),
          ),
        ),
      );
    }
    if (_bands.isEmpty) _addBand();
  }

  @override
  void dispose() {
    _defaultHsn.dispose();
    for (final band in _bands) {
      band.dispose();
    }
    super.dispose();
  }

  void _addBand() {
    _bands.add(
      _BandControllers(
        upTo: TextEditingController(),
        rate: TextEditingController(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _enabled,
            onChanged: (v) => setState(() => _enabled = v),
            title: const Text('Charge GST on sales'),
            subtitle: const Text(
              'Turn off if the shop is not GST registered. Bills then print '
              'as a plain receipt with no tax lines.',
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _pricesIncludeTax,
            onChanged: _enabled
                ? (v) => setState(() => _pricesIncludeTax = v)
                : null,
            title: const Text('Selling prices already include GST'),
            subtitle: Text(
              _pricesIncludeTax
                  ? 'The tag price is what the customer pays. Tax is worked '
                        'backwards out of it. This is the usual Indian retail way.'
                  : 'Tax is added on top of the tag price at billing, so the '
                        'customer pays more than the label.',
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _defaultHsn,
            decoration: const InputDecoration(
              labelText: 'Default HSN code',
              helperText:
                  'Used when a design has no HSN of its own. 6109 knitted '
                  '(t-shirts), 6203/6204 woven (shirts, trousers).',
            ),
          ),
          const SizedBox(height: 24),
          Text('Rate bands', style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            'The rate is chosen by the price of ONE piece, not the bill total. '
            'Leave the last band\'s price limit empty so it catches everything '
            'above the one before it.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < _bands.length; i++) _bandRow(i, theme),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(_addBand),
              icon: const Icon(Icons.add),
              label: const Text('Add a band'),
            ),
          ),
          const Divider(height: 28),
          _preview(theme),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save),
            label: const Text('Save GST settings'),
          ),
        ],
      ),
    );
  }

  Widget _bandRow(int index, ThemeData theme) {
    final band = _bands[index];
    final isLast = index == _bands.length - 1;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 3,
            child: TextFormField(
              controller: band.upTo,
              enabled: _enabled,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: isLast
                    ? 'Up to price per piece (leave empty for "and above")'
                    : 'Up to price per piece',
                prefixText: '${AppFormatters.symbol} ',
              ),
              onChanged: (_) => setState(() {}),
              validator: (value) {
                final text = value?.trim() ?? '';
                if (text.isEmpty) {
                  // Only the final band may be open-ended, otherwise the bands
                  // below it could never be reached.
                  return isLast ? null : 'Only the last band can be empty';
                }
                final parsed = double.tryParse(text);
                if (parsed == null || parsed <= 0) return 'Enter an amount';
                return null;
              },
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: TextFormField(
              controller: band.rate,
              enabled: _enabled,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'GST rate',
                suffixText: '%',
              ),
              onChanged: (_) => setState(() {}),
              validator: (value) {
                final parsed = double.tryParse(value?.trim() ?? '');
                if (parsed == null) return 'Enter a rate';
                if (parsed < 0 || parsed > 100) return '0 to 100';
                return null;
              },
            ),
          ),
          IconButton(
            tooltip: 'Remove this band',
            onPressed: _bands.length == 1
                ? null
                : () => setState(() => _bands.removeAt(index).dispose()),
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
    );
  }

  /// Worked examples against the bands as currently typed, so the effect of a
  /// change is visible before it is saved.
  Widget _preview(ThemeData theme) {
    final settings = _build();
    if (!settings.enabled) {
      return Text(
        'GST is off. Bills will show no tax.',
        style: theme.textTheme.bodySmall,
      );
    }
    const samples = [499.0, 1499.0, 2500.0, 3200.0];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('How that works out', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final price in samples)
              Chip(
                label: Text(
                  '${AppFormatters.currency(price)} → '
                  '${settings.rateFor(unitPrice: price).toStringAsFixed(0)}%',
                ),
              ),
          ],
        ),
      ],
    );
  }

  GstSettings _build() {
    final slabs = <GstSlab>[];
    for (var i = 0; i < _bands.length; i++) {
      final band = _bands[i];
      final rate = double.tryParse(band.rate.text.trim()) ?? 0;
      final upTo = double.tryParse(band.upTo.text.trim());
      slabs.add(
        GstSlab(
          upToPrice: i == _bands.length - 1 ? upTo : (upTo ?? double.infinity),
          ratePercent: rate,
        ),
      );
    }
    // Bands are matched in order, so a shop that types them out of sequence
    // still gets the right answer.
    slabs.sort((a, b) {
      final left = a.upToPrice ?? double.infinity;
      final right = b.upToPrice ?? double.infinity;
      return left.compareTo(right);
    });
    return GstSettings(
      enabled: _enabled,
      pricesIncludeTax: _pricesIncludeTax,
      slabs: slabs,
      defaultHsnCode: _defaultHsn.text.trim().isEmpty
          ? '6109'
          : _defaultHsn.text.trim(),
    );
  }

  Future<void> _save() async {
    if (_enabled && !_formKey.currentState!.validate()) return;
    await widget.store.saveGstSettings(_build());
    widget.onSaved();
  }
}

class _BandControllers {
  _BandControllers({required this.upTo, required this.rate});
  final TextEditingController upTo;
  final TextEditingController rate;

  void dispose() {
    upTo.dispose();
    rate.dispose();
  }
}
