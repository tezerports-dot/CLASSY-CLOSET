import 'package:flutter/material.dart';

import '../../../../core/services/escpos.dart';
import '../../../../core/services/printer_service.dart';
import '../../../../core/services/retail_store.dart';

/// Picks the till printer and proves it works before the shop opens.
class PrinterSettingsForm extends StatefulWidget {
  const PrinterSettingsForm({
    super.key,
    required this.store,
    required this.service,
  });

  final RetailStore store;
  final PrinterService service;

  @override
  State<PrinterSettingsForm> createState() => _PrinterSettingsFormState();
}

class _PrinterSettingsFormState extends State<PrinterSettingsForm> {
  late PrinterSettings _settings = widget.store.printerSettings;
  final _vpa = TextEditingController();
  final _payee = TextEditingController();
  List<String> _printers = const [];
  bool _loadingPrinters = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _vpa.text = _settings.upiVpa;
    _payee.text = _settings.upiPayeeName;
    _loadPrinters();
  }

  @override
  void dispose() {
    _vpa.dispose();
    _payee.dispose();
    super.dispose();
  }

  Future<void> _loadPrinters() async {
    final printers = await widget.service.availablePrinters();
    if (!mounted) return;
    setState(() {
      _printers = printers;
      _loadingPrinters = false;
    });
  }

  void _update(PrinterSettings next) => setState(() => _settings = next);

  @override
  Widget build(BuildContext context) {
    final supported = widget.service.supportsDirectPrinting;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!supported)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              'Direct printing needs Windows. On this machine bills will go '
              'through the print dialog whatever is selected below.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
        DropdownButtonFormField<ReceiptPrintMode>(
          initialValue: _settings.mode,
          decoration: const InputDecoration(
            labelText: 'How bills print',
            prefixIcon: Icon(Icons.print),
          ),
          items: [
            for (final mode in ReceiptPrintMode.values)
              DropdownMenuItem(value: mode, child: Text(mode.label)),
          ],
          onChanged: (mode) =>
              _update(_settings.copyWith(mode: mode ?? _settings.mode)),
        ),
        const SizedBox(height: 12),
        if (_settings.isThermal) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: DropdownButtonFormField<String?>(
                  initialValue: _printers.contains(_settings.printerName)
                      ? _settings.printerName
                      : null,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Receipt printer',
                    helperText: _loadingPrinters
                        ? 'Looking for printers…'
                        : (_printers.isEmpty
                              ? 'No printers found. Windows must have the '
                                    'printer installed first.'
                              : null),
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Windows default printer'),
                    ),
                    for (final name in _printers)
                      DropdownMenuItem<String?>(value: name, child: Text(name)),
                  ],
                  onChanged: (name) => _update(
                    name == null
                        ? _settings.copyWith(clearPrinterName: true)
                        : _settings.copyWith(printerName: name),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Look for printers again',
                onPressed: _loadingPrinters
                    ? null
                    : () {
                        setState(() => _loadingPrinters = true);
                        _loadPrinters();
                      },
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<ThermalPaper>(
                  initialValue: _settings.paper,
                  decoration: const InputDecoration(labelText: 'Paper width'),
                  items: [
                    for (final paper in ThermalPaper.values)
                      DropdownMenuItem(
                        value: paper,
                        child: Text(
                          '${paper.label} (${paper.columns} characters)',
                        ),
                      ),
                  ],
                  onChanged: (paper) =>
                      _update(_settings.copyWith(paper: paper)),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 140,
                child: DropdownButtonFormField<int>(
                  initialValue: _settings.copies,
                  decoration: const InputDecoration(labelText: 'Copies'),
                  items: [
                    for (var i = 1; i <= 3; i++)
                      DropdownMenuItem(value: i, child: Text('$i')),
                  ],
                  onChanged: (copies) =>
                      _update(_settings.copyWith(copies: copies)),
                ),
              ),
            ],
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _settings.cutAfterPrint,
            title: const Text('Cut the paper after each bill'),
            subtitle: const Text(
              'Turn off for a printer with no cutter — it will just feed.',
            ),
            onChanged: (on) => _update(_settings.copyWith(cutAfterPrint: on)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _settings.openDrawerOnCashSale,
            title: const Text('Open the cash drawer on cash sales'),
            subtitle: const Text(
              'The drawer plugs into the printer, not the PC.',
            ),
            onChanged: (on) =>
                _update(_settings.copyWith(openDrawerOnCashSale: on)),
          ),
          if (_settings.openDrawerOnCashSale)
            DropdownButtonFormField<int>(
              initialValue: _settings.drawerPin,
              decoration: const InputDecoration(
                labelText: 'Drawer socket pin',
                helperText:
                    'Almost every drawer uses pin 2. Try pin 5 only if '
                    'pin 2 does nothing.',
              ),
              items: const [
                DropdownMenuItem(value: 0, child: Text('Pin 2 (usual)')),
                DropdownMenuItem(value: 1, child: Text('Pin 5')),
              ],
              onChanged: (pin) => _update(_settings.copyWith(drawerPin: pin)),
            ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _settings.printLogoOnReceipt,
            title: const Text('Print the shop logo on the bill'),
            subtitle: const Text(
              'Turn off if the logo comes out as a dark block, or to save '
              'roll paper. The shop name prints instead.',
            ),
            onChanged: (on) =>
                _update(_settings.copyWith(printLogoOnReceipt: on)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _settings.printBarcodeOnReceipt,
            title: const Text('Print the bill number as a barcode'),
            subtitle: const Text(
              'Lets the returns desk scan the receipt instead of typing it.',
            ),
            onChanged: (on) =>
                _update(_settings.copyWith(printBarcodeOnReceipt: on)),
          ),
        ],
        const Divider(height: 32),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _settings.printUpiQr,
          title: const Text('Print a UPI QR on the bill'),
          subtitle: const Text(
            'The customer scans the bill and pays into your UPI ID.',
          ),
          onChanged: (on) => _update(_settings.copyWith(printUpiQr: on)),
        ),
        if (_settings.printUpiQr) ...[
          TextField(
            controller: _vpa,
            decoration: const InputDecoration(
              labelText: 'Your UPI ID',
              hintText: 'shopname@okhdfcbank',
            ),
            onChanged: (v) => _update(_settings.copyWith(upiVpa: v)),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _payee,
            decoration: const InputDecoration(
              labelText: 'Name shown in the payment app',
              hintText: 'Leave blank to use the shop name',
            ),
            onChanged: (v) => _update(_settings.copyWith(upiPayeeName: v)),
          ),
          if (_settings.printUpiQr && !_settings.canPrintUpiQr)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'A UPI ID looks like name@bank. Until one is entered the QR '
                'will be left off the bill.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
        ],
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.save),
              label: const Text('Save printing settings'),
            ),
            OutlinedButton.icon(
              onPressed: supported && _settings.isThermal ? _testPrint : null,
              icon: const Icon(Icons.receipt_long),
              label: const Text('Print a test page'),
            ),
            OutlinedButton.icon(
              onPressed: supported && _settings.isThermal ? _testDrawer : null,
              icon: const Icon(Icons.point_of_sale),
              label: const Text('Open the drawer'),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await widget.store.savePrinterSettings(_settings);
    if (!mounted) return;
    setState(() => _saving = false);
    _toast('Printing settings saved.');
  }

  Future<void> _testPrint() async {
    final ok = await widget.service.printTestPage(_settings);
    if (!mounted) return;
    _toast(
      ok
          ? 'Test page sent. Check the paper reaches both edges.'
          : 'The printer did not answer. Check it is on and selected above.',
    );
  }

  Future<void> _testDrawer() async {
    final ok = await widget.service.openDrawer(_settings);
    if (!mounted) return;
    _toast(
      ok
          ? 'Drawer signal sent.'
          : 'The printer did not answer, so the drawer stayed shut.',
    );
  }

  void _toast(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));
}
