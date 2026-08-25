import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../app/di/injection.dart';
import '../../../core/services/escpos.dart';
import '../../../core/services/printer_service.dart';
import '../../../core/services/retail_store.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/ui_kit.dart';

/// Everything plugged into the counter, in one place.
///
/// The hardware was configurable before but buried in a settings pane, so a
/// shopkeeper had no way to answer "is the scanner working?" without ringing
/// up a real sale. Each device here says whether it is there and gives one
/// button that proves it.
class HardwarePage extends StatefulWidget {
  const HardwarePage({super.key});

  @override
  State<HardwarePage> createState() => _HardwarePageState();
}

class _HardwarePageState extends State<HardwarePage> {
  final _store = getIt<RetailStore>();
  final _printer = getIt<PrinterService>();

  final _scanField = TextEditingController();
  final _scanFocus = FocusNode();

  List<String> _printers = const [];
  bool _looking = true;

  /// What the scanner last sent, and whether it matched a garment.
  String? _lastScan;
  ProductRecord? _lastScanMatch;
  DateTime? _lastScanAt;

  @override
  void initState() {
    super.initState();
    _findPrinters();
  }

  @override
  void dispose() {
    _scanField.dispose();
    _scanFocus.dispose();
    super.dispose();
  }

  Future<void> _findPrinters() async {
    final found = await _printer.availablePrinters();
    if (!mounted) return;
    setState(() {
      _printers = found;
      _looking = false;
    });
  }

  PrinterSettings get _settings => _store.printerSettings;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _store,
      builder: (context, _) => LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < AppBreakpoints.laptop;
          return SingleChildScrollView(
            padding: EdgeInsets.all(narrow ? AppSpacing.xl : AppSpacing.xxl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const PageHeader(
                  title: 'Hardware',
                  subtitle:
                      'What is plugged into this counter, and whether it '
                      'is answering.',
                ),
                // A one-glance summary of what is assigned to what. The
                // detail cards below still hold the picker and the tester —
                // this row is what the shopkeeper looks at to know the
                // counter is ready to open, without scrolling five cards.
                _assignmentSummary(context),
                const SizedBox(height: AppSpacing.xl),
                if (!_printer.supportsDirectPrinting)
                  const Padding(
                    padding: EdgeInsets.only(bottom: AppSpacing.xl),
                    child: OfflineNotice(
                      message:
                          'Direct printing needs Windows. On this machine '
                          'bills go through the print dialog instead, and the '
                          'drawer cannot be opened.',
                    ),
                  ),
                _scannerCard(context),
                const SizedBox(height: AppSpacing.base),
                _receiptPrinterCard(context),
                const SizedBox(height: AppSpacing.base),
                _drawerCard(context),
                const SizedBox(height: AppSpacing.base),
                _labelPrinterCard(context),
              ],
            ),
          );
        },
      ),
    );
  }

  // -------------------------------------------------- device assignments

  /// A compact panel that names every device slot and the connected device
  /// currently filling it, with a coloured pill for each. Nothing here writes
  /// anything back — the pickers and testers live in the per-device cards
  /// below — but the assistant sees at a glance whether every slot is set.
  Widget _assignmentSummary(BuildContext context) {
    final printer = _settings;
    final billName = (printer.printerName ?? '').trim();
    final labelName = (printer.labelPrinterName ?? '').trim();
    return SectionCard(
      title: 'Connected devices',
      subtitle:
          'Plug each device in over USB, LAN or Bluetooth once, pick which '
          'slot it fills below, and the till uses it automatically from then '
          'on — no more picking a printer at every sale.',
      child: Column(
        children: [
          _assignmentRow(
            icon: Icons.receipt_long_outlined,
            role: 'Bill printer',
            value: printer.isThermal
                ? (billName.isEmpty ? 'Windows default' : billName)
                : 'Print dialog (no direct printer)',
            ok: printer.isThermal && billName.isNotEmpty,
            hint: printer.isThermal
                ? 'Bills go straight to the roll — no dialog.'
                : 'Bills open the Windows dialog. Switch to a thermal '
                      'printer under "Receipt printer" to skip it.',
          ),
          _assignmentRow(
            icon: Icons.qr_code_2_outlined,
            role: 'Label printer',
            value: labelName.isEmpty ? 'Same as bill printer' : labelName,
            ok: labelName.isNotEmpty,
            hint: labelName.isEmpty
                ? 'Barcode labels share the bill printer. Pick a dedicated '
                      'label printer under "Barcode label printer" if the '
                      'shop has two.'
                : 'Labels route straight to it from Products → Labels.',
          ),
          _assignmentRow(
            icon: Icons.qr_code_scanner_rounded,
            role: 'Barcode scanner',
            value: _lastScanAt == null
                ? 'Waiting for a scan'
                : 'Answering (last scan '
                      '${AppFormatters.time(_lastScanAt!)})',
            ok: _lastScanAt != null,
            hint:
                'Any USB or Bluetooth scanner works — it behaves as a '
                'keyboard. Test one below.',
          ),
          if (printer.openDrawerOnCashSale)
            _assignmentRow(
              icon: Icons.point_of_sale_outlined,
              role: 'Cash drawer',
              value:
                  'Kicks pin ${printer.drawerPin == 1 ? '5' : '2'} on the bill printer',
              ok: printer.isThermal,
              hint: printer.isThermal
                  ? 'The drawer opens on every cash sale.'
                  : 'The drawer needs the thermal printer — plug it in and '
                        'pick it above.',
            ),
        ],
      ),
    );
  }

  Widget _assignmentRow({
    required IconData icon,
    required String role,
    required String value,
    required bool ok,
    required String hint,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: ok ? AppColors.successWash : AppColors.warnWash,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              size: 17,
              color: ok ? AppColors.success : AppColors.warn,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      role,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    StatusPill(
                      ok ? 'Ready' : 'Not set',
                      tone: ok ? PillTone.good : PillTone.caution,
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.inkSoft,
                  ),
                ),
                if (hint.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    hint,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.inkFaint,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------- the scanner

  Widget _scannerCard(BuildContext context) {
    final theme = Theme.of(context);
    final match = _lastScanMatch;
    return SectionCard(
      title: 'Barcode scanner',
      icon: Icons.qr_code_scanner_rounded,
      subtitle:
          'Any USB scanner works. It behaves as a keyboard — nothing to '
          'install, nothing to select.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Click the box, then scan any garment tag. If the code appears '
            'and the item is named underneath, the scanner is working and '
            'billing will pick it up the same way.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppColors.inkSoft,
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          TextField(
            controller: _scanField,
            focusNode: _scanFocus,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'Scan test',
              hintText: 'Scan a tag here…',
              prefixIcon: const Icon(Icons.barcode_reader),
              suffixIcon: _scanField.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () => setState(_scanField.clear),
                    ),
            ),
            onChanged: (_) => setState(() {}),
            onSubmitted: _onScanned,
          ),
          if (_lastScan != null) ...[
            const SizedBox(height: AppSpacing.xl),
            Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: match != null
                    ? AppColors.successWash
                    : AppColors.warnWash,
                borderRadius: AppRadii.inputBorder,
              ),
              child: Row(
                children: [
                  Icon(
                    match != null
                        ? Icons.check_circle_rounded
                        : Icons.help_outline_rounded,
                    size: 20,
                    color: match != null
                        ? AppColors.success
                        : AppColors.goldDeep,
                  ),
                  const SizedBox(width: AppSpacing.base),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          match != null
                              ? 'Scanner works — and this tag is in your catalogue.'
                              : 'Scanner works, but nothing in the catalogue '
                                    'carries that code.',
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: match != null
                                ? AppColors.success
                                : AppColors.goldDeep,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            CodeText(_lastScan!),
                            if (match != null) ...[
                              const Text('  ·  '),
                              Flexible(
                                child: Text(
                                  match.displayName,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall,
                                ),
                              ),
                            ],
                            if (_lastScanAt != null) ...[
                              const Text('  ·  '),
                              Text(
                                'read at ${AppFormatters.time(_lastScanAt!)}',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: AppColors.inkFaint,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _onScanned(String value) {
    final code = value.trim();
    if (code.isEmpty) return;
    final lower = code.toLowerCase();
    setState(() {
      _lastScan = code;
      _lastScanAt = DateTime.now();
      _lastScanMatch = _store.products
          .where(
            (p) =>
                p.barcode.toLowerCase() == lower ||
                p.sku.toLowerCase() == lower,
          )
          .firstOrNull;
      _scanField.clear();
    });
    // Put the caret straight back, exactly as billing does.
    _scanFocus.requestFocus();
  }

  // --------------------------------------------------- the receipt printer

  Widget _receiptPrinterCard(BuildContext context) {
    final theme = Theme.of(context);
    final settings = _settings;
    final selected = settings.printerName;
    final known = selected == null || _printers.contains(selected);

    return SectionCard(
      title: 'Receipt printer',
      icon: Icons.receipt_long_rounded,
      subtitle: settings.isThermal
          ? 'Bills print straight to the roll — no dialog.'
          : 'Bills currently go through the Windows print dialog.',
      actions: [
        IconButton(
          tooltip: 'Look again',
          onPressed: _looking
              ? null
              : () {
                  setState(() => _looking = true);
                  _findPrinters();
                },
          icon: const Icon(Icons.refresh),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _statusRow(
            context,
            ok: _printer.supportsDirectPrinting && settings.isThermal && known,
            okText:
                'Ready — ${selected ?? 'Windows default printer'} · '
                '${settings.paper.label}',
            badText: !_printer.supportsDirectPrinting
                ? 'Direct printing is unavailable on this machine.'
                : (!settings.isThermal
                      ? 'Set to the print dialog. Switch to direct printing below.'
                      : 'The chosen printer "$selected" is not installed on '
                            'this PC any more.'),
          ),
          const SizedBox(height: AppSpacing.xl),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 2,
                child: DropdownButtonFormField<ReceiptPrintMode>(
                  initialValue: settings.mode,
                  decoration: const InputDecoration(
                    labelText: 'How bills print',
                  ),
                  items: [
                    for (final m in ReceiptPrintMode.values)
                      DropdownMenuItem(value: m, child: Text(m.label)),
                  ],
                  onChanged: (m) => _save((s) => s.copyWith(mode: m)),
                ),
              ),
              const SizedBox(width: AppSpacing.base),
              Expanded(
                flex: 2,
                child: DropdownButtonFormField<String?>(
                  initialValue: known ? selected : null,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Printer',
                    helperText: _looking
                        ? 'Looking…'
                        : (_printers.isEmpty
                              ? 'None found — install it in Windows first'
                              : '${_printers.length} found'),
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Windows default'),
                    ),
                    for (final n in _printers)
                      DropdownMenuItem<String?>(value: n, child: Text(n)),
                  ],
                  onChanged: (n) => _save(
                    (s) => n == null
                        ? s.copyWith(clearPrinterName: true)
                        : s.copyWith(printerName: n),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.base),
              Expanded(
                child: DropdownButtonFormField<ThermalPaper>(
                  initialValue: settings.paper,
                  decoration: const InputDecoration(labelText: 'Roll'),
                  items: [
                    for (final p in ThermalPaper.values)
                      DropdownMenuItem(value: p, child: Text(p.label)),
                  ],
                  onChanged: (p) => _save((s) => s.copyWith(paper: p)),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.base),
          Wrap(
            spacing: AppSpacing.xl,
            runSpacing: AppSpacing.xxs,
            children: [
              _toggle(
                'Cut after each bill',
                settings.cutAfterPrint,
                (v) => _save((s) => s.copyWith(cutAfterPrint: v)),
              ),
              _toggle(
                'Print the shop logo',
                settings.printLogoOnReceipt,
                (v) => _save((s) => s.copyWith(printLogoOnReceipt: v)),
              ),
              _toggle(
                'Print the bill barcode',
                settings.printBarcodeOnReceipt,
                (v) => _save((s) => s.copyWith(printBarcodeOnReceipt: v)),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          Row(
            children: [
              AccentButton(
                label: 'Print a test page',
                icon: Icons.print_rounded,
                onPressed: _printer.supportsDirectPrinting && settings.isThermal
                    ? _testPrint
                    : null,
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                'Check the rule reaches both edges of the roll.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.inkFaint,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------ the drawer

  Widget _drawerCard(BuildContext context) {
    final settings = _settings;
    return SectionCard(
      title: 'Cash drawer',
      icon: Icons.point_of_sale_rounded,
      subtitle: 'The drawer plugs into the printer, not into the PC.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _statusRow(
            context,
            ok: _printer.supportsDirectPrinting && settings.isThermal,
            okText: settings.openDrawerOnCashSale
                ? 'Opens automatically on a cash sale, on pin '
                      '${settings.drawerPin == 1 ? '5' : '2'}.'
                : 'Ready, but set to stay shut on a cash sale.',
            badText:
                'The drawer opens through the thermal printer, so direct '
                'printing has to be on first.',
          ),
          const SizedBox(height: AppSpacing.xl),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _toggle(
                  'Open on every cash sale',
                  settings.openDrawerOnCashSale,
                  (v) => _save((s) => s.copyWith(openDrawerOnCashSale: v)),
                ),
              ),
              SizedBox(
                width: 240,
                child: DropdownButtonFormField<int>(
                  initialValue: settings.drawerPin,
                  decoration: const InputDecoration(
                    labelText: 'Socket pin',
                    helperText: 'Try pin 5 only if pin 2 does nothing',
                  ),
                  items: const [
                    DropdownMenuItem(value: 0, child: Text('Pin 2 (usual)')),
                    DropdownMenuItem(value: 1, child: Text('Pin 5')),
                  ],
                  onChanged: (p) => _save((s) => s.copyWith(drawerPin: p)),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          SecondaryButton(
            label: 'Open the drawer now',
            icon: Icons.lock_open_rounded,
            onPressed: _printer.supportsDirectPrinting && settings.isThermal
                ? _testDrawer
                : null,
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------- the label printer

  Widget _labelPrinterCard(BuildContext context) {
    final theme = Theme.of(context);
    final named = _settings.labelPrinterName;
    final direct = _settings.hasLabelPrinter && _printer.supportsDirectPrinting;
    return SectionCard(
      title: 'Barcode label printer',
      icon: Icons.local_offer_rounded,
      subtitle:
          'The second printer: the one with the label stock in it, kept '
          'separate from the roll the bills come off.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _statusRow(
            context,
            ok: direct,
            okText: 'Labels go straight to $named.',
            badText: named == null
                ? 'No label printer chosen — labels open the Windows dialog.'
                : 'Direct label printing is off; labels open the Windows '
                      'dialog.',
          ),
          const SizedBox(height: AppSpacing.xl),
          DropdownButtonFormField<String?>(
            initialValue: _printers.contains(named) ? named : null,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: 'Which printer has the labels in it',
              helperText: _looking
                  ? 'Looking for printers…'
                  : (_printers.isEmpty
                        ? 'Windows reported no printers on this machine.'
                        : 'Pick the label printer, not the bill printer.'),
            ),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('Ask every time (Windows dialog)'),
              ),
              for (final name in _printers)
                DropdownMenuItem<String?>(value: name, child: Text(name)),
            ],
            onChanged: (name) => _save(
              (current) => name == null
                  ? current.copyWith(
                      clearLabelPrinterName: true,
                      sendLabelsToLabelPrinter: false,
                    )
                  : current.copyWith(
                      labelPrinterName: name,
                      sendLabelsToLabelPrinter: true,
                    ),
            ),
          ),
          const SizedBox(height: AppSpacing.base),
          _toggle(
            'Send labels straight to it',
            _settings.sendLabelsToLabelPrinter,
            named == null
                ? null
                : (v) => _save((c) => c.copyWith(sendLabelsToLabelPrinter: v)),
          ),
          const SizedBox(height: AppSpacing.base),
          Text(
            'Labels are laid out per design, so they are printed from '
            'Products: open a design and choose the label stock.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppColors.inkSoft,
            ),
          ),
          const SizedBox(height: AppSpacing.base),
          SecondaryButton(
            label: _store.products.isEmpty
                ? 'Add a garment first'
                : 'Go to Products to print labels',
            icon: Icons.qr_code_rounded,
            onPressed: () => context.go('/products'),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------- the card machine

  // ------------------------------------------------------------- fragments

  Widget _statusRow(
    BuildContext context, {
    required bool ok,
    required String okText,
    required String badText,
  }) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: ok ? AppColors.successWash : AppColors.warnWash,
        borderRadius: AppRadii.inputBorder,
      ),
      child: Row(
        children: [
          Icon(
            ok ? Icons.check_circle_rounded : Icons.warning_amber_rounded,
            size: 19,
            color: ok ? AppColors.success : AppColors.goldDeep,
          ),
          const SizedBox(width: AppSpacing.base),
          Expanded(
            child: Text(
              ok ? okText : badText,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: ok ? AppColors.success : AppColors.goldDeep,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// [onChanged] is nullable so a switch with nothing to act on — "send
  /// labels straight to it" before a printer has been chosen — is greyed out
  /// rather than silently doing nothing.
  Widget _toggle(String label, bool value, ValueChanged<bool>? onChanged) =>
      SizedBox(
        width: 300,
        child: SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          value: value,
          title: Text(label, style: Theme.of(context).textTheme.bodyMedium),
          onChanged: onChanged,
        ),
      );

  /// The write in flight, if any. Settings changes are chained onto it so two
  /// quick taps cannot race.
  Future<void> _pendingSave = Future.value();

  /// Applies one change to the *current* settings and persists it.
  ///
  /// The store only refreshes its in-memory copy once the database write has
  /// finished, so building the update from the snapshot this build captured
  /// would lose the previous change if the counter flicked two switches in
  /// quick succession. Reading inside the closure, after the previous write has
  /// settled, means each change is applied to what is actually stored.
  Future<void> _save(PrinterSettings Function(PrinterSettings current) change) {
    final next = _pendingSave.then(
      (_) => _store.savePrinterSettings(change(_store.printerSettings)),
    );
    // Keep the chain alive even if one write fails, or every later change
    // would be dropped along with it.
    _pendingSave = next.catchError((_) {});
    return next;
  }

  Future<void> _testPrint() async {
    final ok = await _printer.printTestPage(_settings);
    _toast(
      ok
          ? 'Test page sent.'
          : 'The printer did not answer. Check it is on and has paper.',
      ok,
    );
  }

  Future<void> _testDrawer() async {
    final ok = await _printer.openDrawer(_settings);
    _toast(
      ok
          ? 'Signal sent — the drawer should have opened.'
          : 'The printer did not answer, so the drawer stayed shut.',
      ok,
    );
  }

  void _toast(String message, bool ok) {
    if (!mounted) return;
    HapticFeedback.selectionClick();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: ok ? AppColors.success : AppColors.danger,
      ),
    );
  }
}
