import 'dart:io';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../../app/di/injection.dart';
import '../../../core/services/permissions.dart';
import '../../../core/services/printer_service.dart';
import '../../../core/services/retail_store.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/section_card.dart';
import '../data/invoice_document.dart';
import '../data/repositories/pos_repository.dart';
import '../data/thermal_receipt.dart';

enum _PaymentMode { cash, card, upi, split }

class PosPage extends StatefulWidget {
  const PosPage({super.key});

  @override
  State<PosPage> createState() => _PosPageState();
}

class _PosPageState extends State<PosPage> {
  late final RetailStore _store;
  late final PosRepository _posRepository;
  late final PrinterService _printerService;
  final _customerSearch = TextEditingController();
  final _productSearch = TextEditingController();

  /// Held so focus can be pushed straight back after a scan.
  final _productSearchFocus = FocusNode();
  final _cashTendered = TextEditingController();
  final _splitCash = TextEditingController();
  final _splitCard = TextEditingController();
  CustomerRecord? _selectedCustomer;
  _PaymentMode _paymentMode = _PaymentMode.cash;

  /// Which paper the invoice is laid out for. 80 mm is the common counter
  /// thermal roll, so it is the default.
  InvoicePaper _paper = InvoicePaper.roll80;
  bool _checkingOut = false;

  /// Kept so the counter can reprint the bill it just handed over without
  /// re-ringing the sale.
  InvoiceData? _lastInvoice;

  /// What the cashier typed into the bill-discount box.
  final _billDiscount = TextEditingController();

  /// The card machine's or UPI app's own reference for this payment.
  final _paymentReference = TextEditingController();

  @override
  void initState() {
    super.initState();
    _store = getIt<RetailStore>();
    _posRepository = getIt<PosRepository>();
    _printerService = getIt<PrinterService>();
    _cashTendered.addListener(_onPaymentChanged);
    _splitCash.addListener(_onPaymentChanged);
    _splitCard.addListener(_onPaymentChanged);
  }

  @override
  void dispose() {
    _customerSearch.dispose();
    _productSearch.dispose();
    _productSearchFocus.dispose();
    _cashTendered.dispose();
    _splitCash.dispose();
    _splitCard.dispose();
    _billDiscount.dispose();
    _paymentReference.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _store,
      builder: (context, _) {
        final total = _cartTotal;
        final walkIn = _walkInCustomer;
        _selectedCustomer = _resolveSelectedCustomer(_selectedCustomer, walkIn);
        _syncPaymentDefaults(total);
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: SectionCard(
                  title: 'Sell Products',
                  actions: [
                    SizedBox(
                      width: 320,
                      child: TextField(
                        controller: _productSearch,
                        focusNode: _productSearchFocus,
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: 'Scan barcode or search name / SKU',
                          prefixIcon: const Icon(Icons.qr_code_scanner),
                          suffixIcon: _productSearch.text.isEmpty
                              ? null
                              : IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: () {
                                    _productSearch.clear();
                                    setState(() {});
                                  },
                                ),
                        ),
                        onChanged: (_) => setState(() {}),
                        onSubmitted: _onSearchSubmitted,
                      ),
                    ),
                  ],
                  child: SingleChildScrollView(
                    child: Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        for (final p in _visibleProducts)
                          SizedBox(
                            width: 210,
                            child: Card(
                              clipBehavior: Clip.antiAlias,
                              color: Colors.grey.shade50,
                              child: InkWell(
                                onTap: p.stock > 0
                                    ? () => _posRepository.addToCart(p)
                                    : null,
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    _productImage(p),
                                    Padding(
                                      padding: const EdgeInsets.all(14),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            p.name,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: Theme.of(
                                              context,
                                            ).textTheme.titleMedium,
                                          ),
                                          // Without this every size and colour
                                          // of a design looks identical on the
                                          // counter screen.
                                          if (p.variantLabel.isNotEmpty)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                top: 4,
                                              ),
                                              child: Chip(
                                                label: Text(p.variantLabel),
                                                visualDensity:
                                                    VisualDensity.compact,
                                                padding: EdgeInsets.zero,
                                              ),
                                            ),
                                          const SizedBox(height: 6),
                                          Text(
                                            p.sku,
                                            style: Theme.of(
                                              context,
                                            ).textTheme.bodySmall,
                                          ),
                                          Text(
                                            'Stock: ${AppFormatters.quantity(p.stock)}',
                                            style: TextStyle(
                                              color: p.lowStock
                                                  ? Theme.of(
                                                      context,
                                                    ).colorScheme.error
                                                  : null,
                                            ),
                                          ),
                                          Text(
                                            AppFormatters.currency(
                                              p.sellingPrice,
                                            ),
                                            style: Theme.of(
                                              context,
                                            ).textTheme.titleLarge,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 2,
                child: SectionCard(
                  title: 'Cart',
                  actions: [
                    Text(
                      AppFormatters.currency(total),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ],
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _customerPicker(),
                        const SizedBox(height: 16),
                        for (final line in _store.cart)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(line.product.displayName),
                            subtitle: Text(
                              '${line.quantity} × ${AppFormatters.currency(line.product.sellingPrice)}',
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () =>
                                  _posRepository.removeFromCart(line),
                            ),
                          ),
                        if (_store.cart.isEmpty)
                          const Text('Add products to start a sale.'),
                        const Divider(height: 28),
                        _totalsPanel(total),
                        const SizedBox(height: 16),
                        _paymentPanel(total),
                        const SizedBox(height: 16),
                        if (_store.printerSettings.isThermal)
                          // The roll is whatever the printer is loaded with, so
                          // in direct mode the choice belongs in Settings, not
                          // in front of the cashier on every sale.
                          Row(
                            children: [
                              const Icon(Icons.print, size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Printing direct to '
                                  '${_store.printerSettings.printerName ?? 'the default printer'}'
                                  ' (${_store.printerSettings.paper.label})',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ),
                            ],
                          )
                        else
                          DropdownButtonFormField<InvoicePaper>(
                            initialValue: _paper,
                            decoration: const InputDecoration(
                              labelText: 'Print on',
                              prefixIcon: Icon(Icons.receipt_long),
                            ),
                            items: [
                              for (final paper in InvoicePaper.values)
                                DropdownMenuItem(
                                  value: paper,
                                  child: Text(paper.label),
                                ),
                            ],
                            onChanged: (paper) =>
                                setState(() => _paper = paper ?? _paper),
                          ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _canCheckout(total)
                                ? () => _checkout(context)
                                : null,
                            icon: _checkingOut
                                ? const SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.receipt),
                            label: const Text('Checkout and print receipt'),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _lastInvoice == null
                                    ? null
                                    : _reprintLast,
                                icon: const Icon(Icons.print_outlined),
                                label: const Text('Reprint last'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _openDrawerWithoutSale,
                                icon: const Icon(Icons.point_of_sale),
                                label: const Text('Open drawer'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _customerPicker() {
    final filtered = _store.customers
        .where(
          (customer) => customer.name.toLowerCase().contains(
            _customerSearch.text.trim().toLowerCase(),
          ),
        )
        .toList();
    if (_selectedCustomer != null &&
        !filtered.any((customer) => customer.id == _selectedCustomer!.id)) {
      filtered.insert(0, _selectedCustomer!);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _customerSearch,
          decoration: const InputDecoration(
            labelText: 'Search customer',
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<CustomerRecord>(
          initialValue: _selectedCustomer,
          decoration: const InputDecoration(labelText: 'Customer'),
          items: filtered
              .map(
                (customer) => DropdownMenuItem(
                  value: customer,
                  child: Text(customer.name),
                ),
              )
              .toList(),
          onChanged: (customer) => setState(() => _selectedCustomer = customer),
        ),
      ],
    );
  }

  Widget _totalsPanel(double total) {
    // Taxes come from the store so the panel always agrees with what the sale
    // will actually record — including the CGST/SGST versus IGST split.
    var taxable = 0.0, cgst = 0.0, sgst = 0.0, igst = 0.0, discount = 0.0;
    for (final line in _store.cart) {
      final tax = _store.lineTaxFor(line, customer: _selectedCustomer);
      taxable += tax.taxableValue;
      cgst += tax.cgst;
      sgst += tax.sgst;
      igst += tax.igst;
      discount += line.discount;
    }
    return Column(
      children: [
        _amountRow('Items', _store.cartGrossTotal),
        if (_store.can(Permission.giveDiscount)) _discountRow(discount),
        if (discount > 0 && !_store.can(Permission.giveDiscount))
          _amountRow('Discount', discount),
        _amountRow('Taxable value', taxable),
        if (cgst > 0) _amountRow('CGST', cgst),
        if (sgst > 0) _amountRow('SGST', sgst),
        if (igst > 0) _amountRow('IGST', igst),
        const Divider(),
        _amountRow('Total', total, prominent: true),
      ],
    );
  }

  /// A rupee amount off the whole bill, which is how a shopkeeper actually
  /// gives a discount — "call it 1,800" rather than "give them 10%".
  ///
  /// The store spreads it across the lines so the GST on the printed invoice
  /// still adds up.
  Widget _discountRow(double discount) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        const Expanded(child: Text('Discount on the bill')),
        SizedBox(
          width: 130,
          child: TextField(
            controller: _billDiscount,
            enabled: _store.cart.isNotEmpty,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textAlign: TextAlign.right,
            decoration: InputDecoration(
              isDense: true,
              prefixText: '${AppFormatters.symbol} ',
              hintText: '0',
              suffixIcon: discount > 0
                  ? IconButton(
                      tooltip: 'Remove the discount',
                      icon: const Icon(Icons.clear, size: 16),
                      onPressed: () {
                        _billDiscount.clear();
                        _store.clearDiscounts();
                      },
                    )
                  : null,
            ),
            onChanged: (value) =>
                _store.applyBillDiscount(double.tryParse(value.trim()) ?? 0),
          ),
        ),
      ],
    ),
  );

  Widget _paymentPanel(double total) {
    final paid = _paidAmount;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SegmentedButton<_PaymentMode>(
          segments: const [
            ButtonSegment(
              value: _PaymentMode.cash,
              label: Text('Cash'),
              icon: Icon(Icons.payments),
            ),
            ButtonSegment(
              value: _PaymentMode.card,
              label: Text('Card'),
              icon: Icon(Icons.credit_card),
            ),
            ButtonSegment(
              value: _PaymentMode.upi,
              label: Text('UPI'),
              icon: Icon(Icons.qr_code_2),
            ),
            ButtonSegment(
              value: _PaymentMode.split,
              label: Text('Split'),
              icon: Icon(Icons.call_split),
            ),
          ],
          selected: {_paymentMode},
          onSelectionChanged: (selection) =>
              setState(() => _paymentMode = selection.single),
        ),
        const SizedBox(height: 12),
        if (_paymentMode == _PaymentMode.cash)
          TextField(
            controller: _cashTendered,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Cash tendered'),
          ),
        if (_paymentMode == _PaymentMode.card)
          const Text('Card payment will charge the full grand total.'),
        if (_paymentMode == _PaymentMode.upi)
          const Text('UPI payment will charge the full grand total.'),
        if (_paymentMode != _PaymentMode.cash) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _paymentReference,
            decoration: const InputDecoration(
              labelText: 'Transaction reference',
              helperText:
                  'The number on the card machine slip or the UPI app. '
                  'Printed on the bill so a disputed charge can be traced.',
              prefixIcon: Icon(Icons.tag),
            ),
          ),
        ],
        if (_paymentMode == _PaymentMode.split) ...[
          TextField(
            controller: _splitCash,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Cash amount'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _splitCard,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Card amount'),
          ),
        ],
        const SizedBox(height: 10),
        _amountRow('Paid', paid),
        _amountRow('Change due', _changeDue(total)),
      ],
    );
  }

  Widget _amountRow(
    String label,
    double amount, {
    bool prominent = false,
  }) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(
        label,
        style: prominent ? const TextStyle(fontWeight: FontWeight.bold) : null,
      ),
      Text(
        AppFormatters.currency(amount),
        style: prominent ? const TextStyle(fontWeight: FontWeight.bold) : null,
      ),
    ],
  );

  /// Products matching the search box, across name, SKU, barcode, size and
  /// colour so a scanned code and a typed name both land here.
  List<ProductRecord> get _visibleProducts {
    final query = _productSearch.text.trim().toLowerCase();
    final active = _store.products.where((p) => p.active);
    if (query.isEmpty) return active.toList();
    return active
        .where(
          (p) =>
              '${p.name} ${p.sku} ${p.barcode} ${p.size} ${p.color} ${p.category} ${p.brand}'
                  .toLowerCase()
                  .contains(query),
        )
        .toList();
  }

  /// A barcode scanner in keyboard-wedge mode types the code then sends Enter,
  /// which arrives here. An exact barcode or SKU match is added to the cart
  /// straight away and the box clears, ready for the next scan.
  void _onSearchSubmitted(String value) {
    final code = value.trim().toLowerCase();
    if (code.isEmpty) return;

    final exact = _store.products
        .where(
          (p) =>
              p.active &&
              (p.barcode.toLowerCase() == code || p.sku.toLowerCase() == code),
        )
        .cast<ProductRecord?>()
        .firstOrNull;

    // A single search hit is unambiguous, so treat it the same as a scan.
    final matches = _visibleProducts;
    final target = exact ?? (matches.length == 1 ? matches.single : null);

    if (target == null) return;
    if (target.stock <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${target.displayName} is out of stock')),
      );
      return;
    }
    _posRepository.addToCart(target);
    _productSearch.clear();
    setState(() {});
    // Keep the caret in the box so the next scan needs no click.
    _productSearchFocus.requestFocus();
  }

  Widget _productImage(ProductRecord product) {
    final path = product.imagePath;
    final file = path == null || !File(path).existsSync() ? null : File(path);
    return Container(
      height: 108,
      width: double.infinity,
      color: Colors.grey.shade200,
      child: file == null
          ? Icon(Icons.checkroom, size: 34, color: Colors.grey.shade500)
          : Image.file(file, fit: BoxFit.cover),
    );
  }

  /// Grand total as the store will record it, so the button, the totals panel
  /// and the saved sale can never disagree.
  double get _cartTotal => _store.cartGrandTotal(customer: _selectedCustomer);

  double get _paidAmount => switch (_paymentMode) {
    _PaymentMode.cash => _parse(_cashTendered.text),
    _PaymentMode.card || _PaymentMode.upi => _cartTotal,
    _PaymentMode.split => _parse(_splitCash.text) + _parse(_splitCard.text),
  };
  String get _paymentLabel => switch (_paymentMode) {
    _PaymentMode.cash => 'Paid by cash',
    _PaymentMode.card => 'Paid by card',
    _PaymentMode.upi => 'Paid by UPI',
    _PaymentMode.split =>
      'Split: cash ${AppFormatters.currency(_parse(_splitCash.text))}, card ${AppFormatters.currency(_parse(_splitCard.text))}',
  };
  String get _paymentMethodValue => switch (_paymentMode) {
    _PaymentMode.cash => 'cash',
    _PaymentMode.card => 'card',
    _PaymentMode.upi => 'upi',
    _PaymentMode.split => 'split',
  };
  double get _cashAmountForSale => switch (_paymentMode) {
    _PaymentMode.cash => _cartTotal,
    _PaymentMode.card || _PaymentMode.upi => 0,
    _PaymentMode.split => _parse(_splitCash.text),
  };
  double get _cardAmountForSale => switch (_paymentMode) {
    _PaymentMode.cash || _PaymentMode.upi => 0,
    _PaymentMode.card => _cartTotal,
    _PaymentMode.split => _parse(_splitCard.text),
  };
  double get _upiAmountForSale =>
      _paymentMode == _PaymentMode.upi ? _cartTotal : 0;

  CustomerRecord? get _walkInCustomer {
    for (final customer in _store.customers) {
      if (customer.name.toLowerCase().contains('walk-in')) return customer;
    }
    return _store.customers.isEmpty ? null : _store.customers.first;
  }

  /// [RetailStore.refresh] rebuilds [RetailStore.customers] with new instances, so the previous
  /// selection is matched by id and swapped for the live record. Returning the stale instance
  /// would leave the dropdown holding a value that is not identical to any of its items, which
  /// trips the `DropdownButtonFormField` "exactly one item with value" assertion on the next build.
  CustomerRecord? _resolveSelectedCustomer(
    CustomerRecord? selected,
    CustomerRecord? walkIn,
  ) {
    if (selected == null) return walkIn;
    for (final customer in _store.customers) {
      if (customer.id == selected.id) return customer;
    }
    return walkIn;
  }

  /// Called from [build], so the controller writes are deferred to the end of the frame: the
  /// controllers have listeners that call [setState], which cannot run while the tree is building.
  void _syncPaymentDefaults(double total) {
    if (total <= 0) return;
    final needsCash =
        _paymentMode == _PaymentMode.cash && _cashTendered.text.isEmpty;
    final needsSplit =
        _paymentMode == _PaymentMode.split &&
        _splitCard.text.isEmpty &&
        _splitCash.text.isEmpty;
    if (!needsCash && !needsSplit) return;
    final formattedTotal = total.toStringAsFixed(2);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (needsCash && _cashTendered.text.isEmpty) {
        _cashTendered.text = formattedTotal;
      }
      if (needsSplit && _splitCard.text.isEmpty && _splitCash.text.isEmpty) {
        _splitCard.text = formattedTotal;
      }
    });
  }

  bool _canCheckout(double total) {
    if (_checkingOut || _store.cart.isEmpty) return false;
    if (_paymentMode == _PaymentMode.split) {
      return (_paidAmount - total).abs() < 0.01;
    }
    return _paidAmount + 0.01 >= total;
  }

  double _changeDue(double total) => _paymentMode == _PaymentMode.cash
      ? (_paidAmount - total).clamp(0, double.infinity).toDouble()
      : 0;
  double _parse(String value) => double.tryParse(value.trim()) ?? 0;

  void _onPaymentChanged() {
    if (mounted) setState(() {});
  }

  /// The cart is emptied by the checkout, so the amounts tendered for the sale that just
  /// completed must not carry over into the next one.
  void _resetPaymentInputs() {
    _cashTendered.clear();
    _splitCash.clear();
    _splitCard.clear();
    _billDiscount.clear();
    _paymentReference.clear();
  }

  Future<void> _checkout(BuildContext context) async {
    final receiptLines = List<CartLine>.from(_store.cart);
    final customer = _selectedCustomer;
    final paid = _paidAmount;
    final change = _changeDue(_cartTotal);
    final paymentLabel = _paymentLabel;
    final paymentMethod = _paymentMethodValue;
    final cashAmount = _cashAmountForSale;
    final cardAmount = _cardAmountForSale;
    final upiAmount = _upiAmountForSale;
    setState(() => _checkingOut = true);
    try {
      final sale = await _posRepository.checkout(
        customer: customer,
        paid: paid,
        paymentMethod: paymentMethod,
        cashAmount: cashAmount,
        cardAmount: cardAmount,
        upiAmount: upiAmount,
        paymentReference: _paymentReference.text,
      );
      _resetPaymentInputs();
      if (!context.mounted) return;
      final invoice = InvoiceData(
        sale: sale,
        lines: invoiceLinesFor(
          cart: receiptLines,
          settings: _store.gstSettings,
          interState: sale.isInterState,
          hsnFor: (product) => product.hsnCode.trim().isNotEmpty
              ? product.hsnCode.trim()
              : _store.gstSettings.defaultHsnCode,
          rateFor: _store.gstRateFor,
        ),
        profile: _store.storeProfile,
        paid: paid,
        change: change,
        paymentLabel: paymentLabel,
        customerName: customer?.name,
        customerPhone: customer?.phone,
        customerAddress: customer?.address,
      );
      _lastInvoice = invoice;
      final note = await _deliverReceipt(invoice);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Completed ${sale.receipt}. $note')),
      );
    } finally {
      if (mounted) setState(() => _checkingOut = false);
    }
  }

  /// Gets the bill onto paper by whichever route the shop has configured, and
  /// returns the sentence to show the cashier.
  ///
  /// Direct thermal printing is attempted first when it is switched on, but a
  /// printer that is off, out of paper or renamed must not cost the shop the
  /// bill: the print dialog is the fallback, and the cashier is told that is
  /// what happened rather than being left wondering why nothing came out.
  Future<String> _deliverReceipt(InvoiceData invoice) async {
    final settings = _store.printerSettings;
    if (settings.isThermal && _printerService.supportsDirectPrinting) {
      try {
        final sent = await _printerService.send(
          buildThermalReceipt(data: invoice, settings: settings),
          printerName: settings.printerName,
          copies: settings.copies,
        );
        if (sent) return 'Bill printed.';
      } on Object {
        // Fall through to the dialog below.
      }
      await _printViaDialog(invoice);
      return 'The thermal printer did not answer, so the print dialog opened '
          'instead. Check it under Settings > Printing.';
    }
    await _printViaDialog(invoice);
    return 'Bill sent to the printer.';
  }

  Future<void> _printViaDialog(InvoiceData invoice) => Printing.layoutPdf(
    name: invoice.sale.receipt,
    format: _paper.format,
    onLayout: (_) => buildInvoicePdf(data: invoice, paper: _paper),
  );

  /// Reprints the bill that was just completed — the single most common request
  /// at a counter, and previously impossible without re-ringing the sale.
  Future<void> _reprintLast() async {
    final invoice = _lastInvoice;
    if (invoice == null) return;
    final note = await _deliverReceipt(invoice);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Reprinted ${invoice.sale.receipt}. $note')),
    );
  }

  /// The "no sale" button: opens the drawer to give change or take a float out,
  /// and records why so the till still reconciles at close.
  Future<void> _openDrawerWithoutSale() async {
    final settings = _store.printerSettings;
    if (!settings.isThermal || !_printerService.supportsDirectPrinting) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'The drawer opens through the thermal printer. Turn direct '
            'printing on under Settings > Printing first.',
          ),
        ),
      );
      return;
    }
    final opened = await _printerService.openDrawer(settings);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          opened
              ? 'Drawer opened.'
              : 'The printer did not answer, so the drawer stayed shut.',
        ),
      ),
    );
  }
}
