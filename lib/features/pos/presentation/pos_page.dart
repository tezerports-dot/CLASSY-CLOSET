import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../app/di/injection.dart';
import '../../../core/services/retail_store.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/section_card.dart';
import '../data/repositories/pos_repository.dart';

enum _PaymentMode { cash, card, split }

class PosPage extends StatefulWidget {
  const PosPage({super.key});

  @override
  State<PosPage> createState() => _PosPageState();
}

class _PosPageState extends State<PosPage> {
  late final RetailStore _store;
  late final PosRepository _posRepository;
  final _customerSearch = TextEditingController();
  final _cashTendered = TextEditingController();
  final _splitCash = TextEditingController();
  final _splitCard = TextEditingController();
  CustomerRecord? _selectedCustomer;
  _PaymentMode _paymentMode = _PaymentMode.cash;
  bool _checkingOut = false;

  @override
  void initState() {
    super.initState();
    _store = getIt<RetailStore>();
    _posRepository = getIt<PosRepository>();
    _cashTendered.addListener(_onPaymentChanged);
    _splitCash.addListener(_onPaymentChanged);
    _splitCard.addListener(_onPaymentChanged);
  }

  @override
  void dispose() {
    _customerSearch.dispose();
    _cashTendered.dispose();
    _splitCash.dispose();
    _splitCard.dispose();
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
                  child: SingleChildScrollView(
                    child: Wrap(spacing: 12, runSpacing: 12, children: [
                      for (final p in _store.products.where((p) => p.active))
                        SizedBox(
                          width: 210,
                          child: Card(
                            color: Colors.grey.shade50,
                            child: InkWell(
                              onTap: p.stock > 0 ? () => _posRepository.addToCart(p) : null,
                              child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(p.name, style: Theme.of(context).textTheme.titleMedium),
                                  const SizedBox(height: 8),
                                  Text(p.sku),
                                  Text('Stock: ${p.stock.toStringAsFixed(0)}'),
                                  Text(AppFormatters.currency(p.sellingPrice), style: Theme.of(context).textTheme.titleLarge),
                                ]),
                              ),
                            ),
                          ),
                        ),
                    ]),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 2,
                child: SectionCard(
                  title: 'Cart',
                  actions: [Text(AppFormatters.currency(total), style: Theme.of(context).textTheme.titleLarge)],
                  child: SingleChildScrollView(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      _customerPicker(),
                      const SizedBox(height: 16),
                      for (final line in _store.cart)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(line.product.name),
                          subtitle: Text('${line.quantity} × ${AppFormatters.currency(line.product.sellingPrice)}'),
                          trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => _posRepository.removeFromCart(line)),
                        ),
                      if (_store.cart.isEmpty) const Text('Add products to start a sale.'),
                      const Divider(height: 28),
                      _totalsPanel(total),
                      const SizedBox(height: 16),
                      _paymentPanel(total),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _canCheckout(total) ? () => _checkout(context) : null,
                          icon: _checkingOut ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.receipt),
                          label: const Text('Checkout and print receipt'),
                        ),
                      ),
                    ]),
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
    final filtered = _store.customers.where((customer) => customer.name.toLowerCase().contains(_customerSearch.text.trim().toLowerCase())).toList();
    if (_selectedCustomer != null && !filtered.any((customer) => customer.id == _selectedCustomer!.id)) {
      filtered.insert(0, _selectedCustomer!);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      TextField(controller: _customerSearch, decoration: const InputDecoration(labelText: 'Search customer', prefixIcon: Icon(Icons.search)), onChanged: (_) => setState(() {})),
      const SizedBox(height: 8),
      DropdownButtonFormField<CustomerRecord>(
        value: _selectedCustomer,
        decoration: const InputDecoration(labelText: 'Customer'),
        items: filtered.map((customer) => DropdownMenuItem(value: customer, child: Text(customer.name))).toList(),
        onChanged: (customer) => setState(() => _selectedCustomer = customer),
      ),
    ]);
  }

  Widget _totalsPanel(double total) {
    final subtotal = _store.cart.fold(0.0, (sum, line) => sum + line.quantity * line.product.sellingPrice);
    final tax = _store.cart.fold(0.0, (sum, line) => sum + line.quantity * line.product.sellingPrice * line.product.taxRate / 100);
    return Column(children: [
      _amountRow('Subtotal', subtotal),
      _amountRow('Tax', tax),
      const Divider(),
      _amountRow('Total', total, prominent: true),
    ]);
  }

  Widget _paymentPanel(double total) {
    final paid = _paidAmount;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SegmentedButton<_PaymentMode>(
        segments: const [
          ButtonSegment(value: _PaymentMode.cash, label: Text('Cash'), icon: Icon(Icons.payments)),
          ButtonSegment(value: _PaymentMode.card, label: Text('Card'), icon: Icon(Icons.credit_card)),
          ButtonSegment(value: _PaymentMode.split, label: Text('Split'), icon: Icon(Icons.call_split)),
        ],
        selected: {_paymentMode},
        onSelectionChanged: (selection) => setState(() => _paymentMode = selection.single),
      ),
      const SizedBox(height: 12),
      if (_paymentMode == _PaymentMode.cash) TextField(controller: _cashTendered, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Cash tendered')),
      if (_paymentMode == _PaymentMode.card) const Text('Card payment will charge the full grand total.'),
      if (_paymentMode == _PaymentMode.split) ...[
        TextField(controller: _splitCash, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Cash amount')),
        const SizedBox(height: 8),
        TextField(controller: _splitCard, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Card amount')),
      ],
      const SizedBox(height: 10),
      _amountRow('Paid', paid),
      _amountRow('Change due', _changeDue(total)),
    ]);
  }

  Widget _amountRow(String label, double amount, {bool prominent = false}) => Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(label, style: prominent ? const TextStyle(fontWeight: FontWeight.bold) : null), Text(AppFormatters.currency(amount), style: prominent ? const TextStyle(fontWeight: FontWeight.bold) : null)]);

  double get _cartTotal => _store.cart.fold(0.0, (sum, line) => sum + line.total);
  double get _paidAmount => switch (_paymentMode) { _PaymentMode.cash => _parse(_cashTendered.text), _PaymentMode.card => _cartTotal, _PaymentMode.split => _parse(_splitCash.text) + _parse(_splitCard.text) };
  String get _paymentLabel => switch (_paymentMode) { _PaymentMode.cash => 'Cash', _PaymentMode.card => 'Card', _PaymentMode.split => 'Split: cash ${AppFormatters.currency(_parse(_splitCash.text))}, card ${AppFormatters.currency(_parse(_splitCard.text))}' };
  String get _paymentMethodValue => switch (_paymentMode) { _PaymentMode.cash => 'cash', _PaymentMode.card => 'card', _PaymentMode.split => 'split' };
  double get _cashAmountForSale => switch (_paymentMode) { _PaymentMode.cash => _cartTotal, _PaymentMode.card => 0, _PaymentMode.split => _parse(_splitCash.text) };
  double get _cardAmountForSale => switch (_paymentMode) { _PaymentMode.cash => 0, _PaymentMode.card => _cartTotal, _PaymentMode.split => _parse(_splitCard.text) };

  CustomerRecord? get _walkInCustomer {
    for (final customer in _store.customers) {
      if (customer.name.toLowerCase().contains('walk-in')) return customer;
    }
    return _store.customers.isEmpty ? null : _store.customers.first;
  }

  CustomerRecord? _resolveSelectedCustomer(CustomerRecord? selected, CustomerRecord? walkIn) {
    if (selected != null && _store.customers.any((customer) => customer.id == selected.id)) return selected;
    return walkIn;
  }

  void _syncPaymentDefaults(double total) {
    final formattedTotal = total == 0 ? '' : total.toStringAsFixed(2);
    if (_paymentMode == _PaymentMode.cash && _cashTendered.text.isEmpty && total > 0) _cashTendered.text = formattedTotal;
    if (_paymentMode == _PaymentMode.split && _splitCard.text.isEmpty && _splitCash.text.isEmpty && total > 0) _splitCard.text = formattedTotal;
  }

  bool _canCheckout(double total) {
    if (_checkingOut || _store.cart.isEmpty) return false;
    if (_paymentMode == _PaymentMode.split) return (_paidAmount - total).abs() < 0.01;
    return _paidAmount + 0.01 >= total;
  }

  double _changeDue(double total) => _paymentMode == _PaymentMode.cash ? (_paidAmount - total).clamp(0, double.infinity).toDouble() : 0;
  double _parse(String value) => double.tryParse(value.trim()) ?? 0;

  void _onPaymentChanged() {
    if (mounted) setState(() {});
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
    setState(() => _checkingOut = true);
    try {
      final sale = await _posRepository.checkout(customer: customer, paid: paid, paymentMethod: paymentMethod, cashAmount: cashAmount, cardAmount: cardAmount);
      if (!context.mounted) return;
      await Printing.layoutPdf(name: sale.receipt, onLayout: (_) => _buildReceiptPdf(sale: sale, lines: receiptLines, paid: paid, change: change, paymentLabel: paymentLabel));
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Completed ${sale.receipt}')));
    } finally {
      if (mounted) setState(() => _checkingOut = false);
    }
  }

  Future<Uint8List> _buildReceiptPdf({required SaleRecord sale, required List<CartLine> lines, required double paid, required double change, required String paymentLabel}) async {
    final profile = _store.storeProfile;
    final document = pw.Document();
    pw.MemoryImage? logo;
    final logoPath = profile?.logoPath;
    if (logoPath != null && logoPath.trim().isNotEmpty) {
      final file = File(logoPath);
      if (await file.exists()) logo = pw.MemoryImage(await file.readAsBytes());
    }
    final subtotal = lines.fold(0.0, (sum, line) => sum + line.quantity * line.product.sellingPrice);
    final tax = lines.fold(0.0, (sum, line) => sum + line.quantity * line.product.sellingPrice * line.product.taxRate / 100);
    document.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.letter,
      build: (context) => [
        pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          if (logo != null) pw.Container(width: 72, height: 72, margin: const pw.EdgeInsets.only(right: 16), child: pw.Image(logo, fit: pw.BoxFit.contain)),
          pw.Expanded(child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text(profile?.storeName ?? 'RetailPro', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
            if ((profile?.address ?? '').isNotEmpty) pw.Text(profile!.address!),
            if ((profile?.phone ?? '').isNotEmpty) pw.Text('Phone: ${profile!.phone!}'),
          ])),
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [pw.Text('Receipt ${sale.receipt}'), pw.Text(AppFormatters.dateTime(sale.createdAt)), pw.Text('Customer: ${sale.customerName}')]),
        ]),
        pw.SizedBox(height: 24),
        pw.TableHelper.fromTextArray(headers: ['Item', 'Qty', 'Unit', 'Line total'], data: lines.map((line) => [line.product.name, line.quantity.toString(), AppFormatters.currency(line.product.sellingPrice), AppFormatters.currency(line.total)]).toList()),
        pw.SizedBox(height: 16),
        pw.Align(alignment: pw.Alignment.centerRight, child: pw.SizedBox(width: 220, child: pw.Column(children: [
          _pdfAmountRow('Subtotal', subtotal),
          _pdfAmountRow('Tax', tax),
          _pdfAmountRow('Total', sale.total),
          _pdfAmountRow('Paid', paid),
          _pdfAmountRow('Change due', change),
          pw.SizedBox(height: 6),
          pw.Text(paymentLabel),
        ]))),
        pw.SizedBox(height: 32),
        if ((profile?.receiptFooterText ?? '').isNotEmpty) pw.Center(child: pw.Text(profile!.receiptFooterText!)),
      ],
    ));
    return document.save();
  }

  pw.Widget _pdfAmountRow(String label, double amount) => pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [pw.Text(label), pw.Text(AppFormatters.currency(amount))]);
}
