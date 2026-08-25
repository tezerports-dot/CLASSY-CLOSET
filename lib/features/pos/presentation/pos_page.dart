import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../../app/di/injection.dart';
import '../../../core/services/escpos.dart';
import '../../../core/services/permissions.dart';
import '../../../core/services/printer_service.dart';
import '../../../core/services/receipt_logo.dart';
import '../../../core/services/retail_store.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/search.dart';
import '../../../core/widgets/ui_kit.dart';
import '../data/invoice_document.dart';
import '../data/repositories/pos_repository.dart';
import '../data/thermal_receipt.dart';
import 'widgets/bill_preview_dialog.dart';
import 'widgets/held_bills_sheet.dart';

/// Which rail the non-cash half of a split goes down.
///
/// The shop generates the QR or swipes the card on its own standalone machine
/// and types the split by hand — the app records which one it was so the
/// day's takings break down correctly, and nothing more.
enum _SplitTender {
  card('Card'),
  upi('UPI QR');

  const _SplitTender(this.label);
  final String label;
}

enum _PaymentMode {
  cash('Cash', Icons.payments_rounded),
  card('Card', Icons.credit_card_rounded),
  upi('UPI', Icons.qr_code_2_rounded),
  split('Split', Icons.call_split_rounded);

  const _PaymentMode(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// The counter.
///
/// Catalogue on the left, the running bill on the right. The bill panel is a
/// column whose line list scrolls and whose footer does not — that is
/// structural, not styling: on a 768px-high shop laptop the old single scroll
/// pushed the checkout button below the fold, and a checkout button you have
/// to hunt for is a checkout button that costs the shop time on every sale.
class PosPage extends StatefulWidget {
  const PosPage({super.key});

  @override
  State<PosPage> createState() => _PosPageState();
}

class _PosPageState extends State<PosPage> {
  late final RetailStore _store;
  late final PosRepository _posRepository;
  late final PrinterService _printerService;

  final _productSearch = TextEditingController();

  /// Held so focus can be pushed straight back after a scan.
  final _productSearchFocus = FocusNode();
  final _customerName = TextEditingController();
  final _customerPhone = TextEditingController();
  final _splitCash = TextEditingController();

  /// The non-cash half of a split, whichever rail it goes down.
  final _splitCard = TextEditingController();
  final _billDiscount = TextEditingController();

  CustomerRecord? _selectedCustomer;
  _PaymentMode _paymentMode = _PaymentMode.cash;

  /// Which rail the non-cash part of a split goes down. Only one can be used:
  /// the customer walks to the card machine once, and it either takes their
  /// card or shows them a QR — it cannot do both for one bill.
  _SplitTender _splitTender = _SplitTender.card;
  InvoicePaper _paper = InvoicePaper.roll80;
  bool _checkingOut = false;

  /// What the card machine is doing right now, shown under the payment
  /// buttons so the cashier is never left watching a spinner with no idea
  /// whether the customer has tapped yet.

  /// Set once the terminal has approved this bill, so a retry after a failed
  /// print does not charge the customer twice.

  /// Kept so the counter can reprint the bill it just handed over.
  InvoiceData? _lastInvoice;

  /// The number the next sale will carry, read from the counter without
  /// taking it. Refreshed after every sale rather than on every build, so the
  /// bill panel is not doing a database read per frame.
  String _nextBillNumber = '—';

  /// The logo reduced to printer dots. Converting is not free, so it is done
  /// once and reused across bills and reprints.
  ReceiptLogo? _thermalLogo;
  String? _thermalLogoSource;

  @override
  void initState() {
    super.initState();
    _store = getIt<RetailStore>();
    _posRepository = getIt<PosRepository>();
    _printerService = getIt<PrinterService>();
    _splitCash.addListener(_onPaymentChanged);
    _splitCard.addListener(_onPaymentChanged);
    _refreshNextBillNumber();
  }

  Future<void> _refreshNextBillNumber() async {
    final next = await _store.peekNextInvoiceNumber();
    if (mounted) setState(() => _nextBillNumber = next);
  }

  @override
  void dispose() {
    _productSearch.dispose();
    _productSearchFocus.dispose();
    _customerName.dispose();
    _customerPhone.dispose();
    _splitCash.dispose();
    _splitCard.dispose();
    _billDiscount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _store,
      builder: (context, _) {
        final total = _cartTotal;
        // No auto-fallback to any customer record. The bill is a walk-in until
        // the operator types a name or phone — the old code adopted the first
        // customer on the list, which attached every unnamed sale to whoever
        // happened to be sorted first and even used their state for GST.
        _selectedCustomer = _liveSelectedCustomer(_selectedCustomer);
        _syncPaymentDefaults(total);

        return LayoutBuilder(
          builder: (context, constraints) {
            final stacked = constraints.maxWidth < AppBreakpoints.desktop;
            final catalogue = _catalogue(context);
            final bill = _billPanel(context, total);

            if (stacked) {
              // Below the desktop breakpoint the bill goes underneath, but it
              // keeps its own pinned footer so checkout stays reachable.
              return Column(
                children: [
                  Expanded(child: catalogue),
                  SizedBox(
                    height: (constraints.maxHeight * 0.52).clamp(320.0, 520.0),
                    child: bill,
                  ),
                ],
              );
            }
            // Catalogue fills the middle, running bill down the right-hand
            // side. The assistant works left to right: find the garment, watch
            // it land on the bill.
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: catalogue),
                SizedBox(width: 400, child: bill),
              ],
            );
          },
        );
      },
    );
  }

  // --------------------------------------------------------------- catalogue

  Widget _catalogue(BuildContext context) {
    final theme = Theme.of(context);
    final products = _visibleProducts;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xxl,
            AppSpacing.xxl,
            AppSpacing.xxl,
            AppSpacing.xl,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Billing', style: theme.textTheme.headlineLarge),
                        const SizedBox(height: 3),
                        Text(
                          'Scan a garment, or tap a tile. The cursor stays in '
                          'the box, ready for the next scan.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: AppColors.inkSoft,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_store.heldBills.isNotEmpty)
                    SecondaryButton(
                      label: '${_store.heldBills.length} held',
                      icon: Icons.pause_circle_outline,
                      onPressed: _openHeldBills,
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.xl),
              _scanBox(context),
            ],
          ),
        ),
        Expanded(
          child: products.isEmpty
              ? _catalogueEmpty(context)
              : SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.xxl,
                    0,
                    AppSpacing.xxl,
                    AppSpacing.xxl,
                  ),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      const gap = AppSpacing.base;
                      final columns = (constraints.maxWidth / 190)
                          .floor()
                          .clamp(1, 8);
                      final width =
                          (constraints.maxWidth - gap * (columns - 1)) /
                          columns;
                      return Wrap(
                        spacing: gap,
                        runSpacing: gap,
                        children: [
                          for (final p in products)
                            SizedBox(
                              width: width,
                              child: _ProductTile(
                                product: p,
                                onTap: p.stock > 0 ? () => _addToBill(p) : null,
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  /// The scan box. Gold-ringed because it is the one control the assistant's
  /// hand returns to a hundred times a day.
  Widget _scanBox(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      borderRadius: AppRadii.inputBorder,
      boxShadow: [
        BoxShadow(
          color: AppColors.gold.withValues(alpha: 0.14),
          blurRadius: 0,
          spreadRadius: 3,
        ),
      ],
    ),
    child: TextField(
      controller: _productSearch,
      focusNode: _productSearchFocus,
      autofocus: true,
      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
      decoration: InputDecoration(
        hintText: 'Scan a barcode, or type a name, SKU or size…',
        prefixIcon: Icon(Icons.barcode_reader, color: AppColors.goldDeep),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadii.inputBorder,
          borderSide: BorderSide(color: AppColors.gold, width: 1.4),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.lg,
        ),
        suffixIcon: _productSearch.text.isEmpty
            ? Padding(
                padding: const EdgeInsets.only(right: AppSpacing.base),
                child: Center(
                  widthFactor: 1,
                  child: Text(
                    '↵',
                    style: AppTypography.code.copyWith(
                      color: AppColors.inkFaint,
                      fontSize: 15,
                    ),
                  ),
                ),
              )
            : IconButton(
                icon: const Icon(Icons.clear),
                onPressed: () {
                  _productSearch.clear();
                  setState(() {});
                  _productSearchFocus.requestFocus();
                },
              ),
      ),
      onChanged: (_) => setState(() {}),
      onSubmitted: _onSearchSubmitted,
    ),
  );

  Widget _catalogueEmpty(BuildContext context) => _store.products.isEmpty
      ? EmptyState(
          icon: Icons.checkroom_rounded,
          title: 'No garments yet',
          message:
              'Add your designs and their size run, then they will appear '
              'here ready to sell.',
          action: SecondaryButton(
            label: 'Go to Products',
            icon: Icons.arrow_forward,
            onPressed: () {},
          ),
        )
      : const EmptyState(
          icon: Icons.search_off_rounded,
          title: 'Nothing matches that',
          message: 'Try a shorter search, or scan the tag on the garment.',
        );

  // -------------------------------------------------------------- bill panel

  Widget _billPanel(BuildContext context, double total) {
    final theme = Theme.of(context);
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(left: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ---------------------------------------------------------- header
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              AppSpacing.xl,
              AppSpacing.xl,
              AppSpacing.base,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Current bill', style: theme.textTheme.titleLarge),
                      // Every bill carries a number, allocated in sequence
                      // within the financial year. Showing the next one before
                      // it is rung up means the counter can quote it to a
                      // customer, and it is what the card machine is told too.
                      Text(
                        _lastInvoice == null
                            ? 'Next bill: $_nextBillNumber'
                            : 'Last bill: ${_lastInvoice!.sale.receipt}',
                        style: AppTypography.code.copyWith(
                          fontSize: 10.5,
                          color: AppColors.inkFaint,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_store.cart.isNotEmpty)
                  TextButton.icon(
                    onPressed: _holdBill,
                    icon: const Icon(Icons.pause_circle_outline, size: 16),
                    label: const Text('Hold'),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
            child: _customerFields(),
          ),
          const SizedBox(height: AppSpacing.base),
          const Divider(height: 1),

          // ------------------------------------------------ the scrolling part
          Expanded(
            child: _store.cart.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.xxl),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.receipt_long_outlined,
                            size: 30,
                            color: AppColors.inkFaint,
                          ),
                          const SizedBox(height: AppSpacing.base),
                          Text(
                            'Scan the first garment to start a bill.',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: AppColors.inkFaint,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xl,
                      vertical: AppSpacing.base,
                    ),
                    itemCount: _store.cart.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) => _CartLineTile(
                      line: _store.cart[i],
                      onRemove: () =>
                          _posRepository.removeFromCart(_store.cart[i]),
                      onQuantity: (q) => _setQuantity(_store.cart[i], q),
                    ),
                  ),
          ),

          // ------------------------------- the part that never scrolls away
          _pinnedFooter(context, total),
        ],
      ),
    );
  }

  /// Discount, totals, payment and checkout, pinned to the bottom of the
  /// panel. Everything here has to stay on screen at 768px high.
  Widget _pinnedFooter(BuildContext context, double total) {
    final theme = Theme.of(context);
    // One pass over the cart — the totals object carries the subtotal, the
    // discount, and the tax already computed on the discounted net, so the
    // rows below only render numbers.
    final totals = _store.cartTotals(customer: _selectedCustomer);
    final discount = totals.discountTotal;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surfaceAlt,
        border: Border(top: BorderSide(color: AppColors.border)),
        boxShadow: [AppColors.panelShadow],
      ),
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_store.can(Permission.giveDiscount)) ...[
            _discountField(context, discount),
            const SizedBox(height: AppSpacing.base),
          ],
          // Subtotal → discount → taxable → GST → total. Same shape as the
          // printed bill so the customer at the counter can follow along.
          _amountRow('Subtotal', totals.gross),
          if (discount > 0) _amountRow('Discount', discount, signed: true),
          if (totals.cgst > 0 || totals.sgst > 0 || totals.igst > 0)
            _amountRow('Taxable value', totals.taxable),
          if (totals.cgst > 0) _amountRow('CGST', totals.cgst),
          if (totals.sgst > 0) _amountRow('SGST', totals.sgst),
          if (totals.igst > 0) _amountRow('IGST', totals.igst),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: _DashedRule(),
          ),
          Row(
            children: [
              Expanded(child: Text('Total', style: theme.textTheme.titleLarge)),
              MoneyText(total, style: AppTypography.billTotal),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          _paymentControls(context, total),
          const SizedBox(height: AppSpacing.lg),
          AccentButton(
            label: 'Checkout & print',
            icon: Icons.receipt_rounded,
            tall: true,
            expand: true,
            busy: _checkingOut,
            onPressed: _canCheckout(total) ? () => _checkout(context) : null,
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: SecondaryButton(
                  label: 'Preview',
                  icon: Icons.visibility_outlined,
                  onPressed: _store.cart.isEmpty ? null : _previewCurrentBill,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: SecondaryButton(
                  label: 'Reprint',
                  icon: Icons.print_outlined,
                  onPressed: _lastInvoice == null ? null : _reprintLast,
                ),
              ),
              // Only a shop that has a drawer wired to the printer gets this
              // button. Where cash is handled by hand it would do nothing, and
              // a button that does nothing is worse than no button.
              if (_store.printerSettings.openDrawerOnCashSale) ...[
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: SecondaryButton(
                    label: 'Drawer',
                    icon: Icons.point_of_sale_outlined,
                    onPressed: _openDrawerWithoutSale,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  /// A rupee amount off the whole bill, which is how a shopkeeper actually
  /// discounts — "call it 1,800" rather than "give them 10%".
  Widget _discountField(BuildContext context, double discount) => Container(
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.base,
      vertical: AppSpacing.sm,
    ),
    decoration: BoxDecoration(
      color: AppColors.goldWash,
      border: Border.all(color: AppColors.goldWashBorder),
      borderRadius: AppRadii.inputBorder,
    ),
    child: Row(
      children: [
        Icon(Icons.sell_outlined, size: 15, color: AppColors.goldDeep),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            'Discount on the bill',
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(color: AppColors.goldDeep),
          ),
        ),
        SizedBox(
          width: 108,
          height: 32,
          child: TextField(
            controller: _billDiscount,
            enabled: _store.cart.isNotEmpty,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textAlign: TextAlign.right,
            style: AppTypography.money.copyWith(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
            ),
            decoration: InputDecoration(
              isDense: true,
              hintText: '0',
              prefixText: '${AppFormatters.symbol} ',
              contentPadding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.sm,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: AppRadii.inputBorder,
                borderSide: BorderSide(color: AppColors.goldWashBorder),
              ),
            ),
            onChanged: (v) =>
                _store.applyBillDiscount(double.tryParse(v.trim()) ?? 0),
          ),
        ),
        if (discount > 0)
          IconButton(
            tooltip: 'Remove the discount',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.clear, size: 15),
            onPressed: () {
              _billDiscount.clear();
              _store.clearDiscounts();
            },
          ),
      ],
    ),
  );

  Widget _paymentControls(BuildContext context, double total) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 34,
          child: Row(
            children: [
              for (final mode in _PaymentMode.values) ...[
                Expanded(
                  child: _ModeButton(
                    mode: mode,
                    selected: _paymentMode == mode,
                    onTap: () => setState(() => _paymentMode = mode),
                  ),
                ),
                if (mode != _PaymentMode.values.last)
                  const SizedBox(width: AppSpacing.xxs),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.base),
        if (_paymentMode == _PaymentMode.cash)
          Text(
            'Cash. Checkout takes the bill total exactly — nothing to type, '
            'no reference needed.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.inkSoft,
            ),
          )
        else if (_paymentMode == _PaymentMode.split) ...[
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 38,
                  child: TextField(
                    controller: _splitCash,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    style: AppTypography.money.copyWith(fontSize: 13.5),
                    decoration: const InputDecoration(
                      labelText: 'Cash',
                      isDense: true,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: SizedBox(
                  height: 38,
                  child: TextField(
                    controller: _splitCard,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    style: AppTypography.money.copyWith(fontSize: 13.5),
                    decoration: InputDecoration(
                      labelText: 'On the machine',
                      isDense: true,
                      helperText: _splitTender.label,
                      helperStyle: const TextStyle(fontSize: 10),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          // Card or QR, never both: the customer goes to the machine once.
          _tenderChooser(context),
          if ((_paidAmount - total).abs() >= 0.01)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(
                'Cash plus the machine has to come to '
                '${AppFormatters.currency(total)}.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.danger,
                ),
              ),
            ),
        ],
      ],
    );
  }

  /// Card or UPI QR for the non-cash half of a split.
  Widget _tenderChooser(BuildContext context) => SizedBox(
    height: 30,
    child: Row(
      children: [
        for (final kind in _SplitTender.values) ...[
          Expanded(
            child: _TenderButton(
              label: kind.label,
              icon: kind == _SplitTender.card
                  ? Icons.credit_card_rounded
                  : Icons.qr_code_2_rounded,
              selected: _splitTender == kind,
              onTap: () => setState(() {
                _splitTender = kind;
              }),
            ),
          ),
          if (kind != _SplitTender.values.last)
            const SizedBox(width: AppSpacing.xxs),
        ],
      ],
    ),
  );

  Widget _amountRow(String label, double value, {bool signed = false}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 2.5),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: AppColors.inkSoft),
              ),
            ),
            MoneyText(value, signed: signed, size: 13),
          ],
        ),
      );

  Widget _customerFields() => Row(
    children: [
      Expanded(
        child: TextField(
          controller: _customerName,
          decoration: const InputDecoration(
            isDense: true,
            prefixIcon: Icon(Icons.person_outline, size: 17),
            labelText: 'Customer name (optional)',
          ),
        ),
      ),
      const SizedBox(width: AppSpacing.sm),
      Expanded(
        child: TextField(
          controller: _customerPhone,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            isDense: true,
            prefixIcon: Icon(Icons.phone_outlined, size: 17),
            labelText: 'Mobile number (optional)',
          ),
        ),
      ),
    ],
  );

  // ----------------------------------------------------------------- helpers

  List<ProductRecord> get _visibleProducts {
    final query = _productSearch.text.trim().toLowerCase();
    final active = _store.products.where((p) => p.active);
    if (query.isEmpty) return active.take(60).toList();
    return active
        .where(
          (p) => AppSearch.matches(
            '${p.name} ${p.sku} ${p.barcode} ${p.size} ${p.color}',
            query,
          ),
        )
        .toList();
  }

  /// A wedge scanner types the code and presses Enter, so an exact match goes
  /// straight onto the bill and focus comes back for the next garment.
  void _onSearchSubmitted(String value) {
    final code = value.trim().toLowerCase();
    if (code.isEmpty) return;

    final exact = _store.products
        .where(
          (p) =>
              p.active &&
              (p.barcode.toLowerCase() == code || p.sku.toLowerCase() == code),
        )
        .firstOrNull;

    final matches = _visibleProducts;
    final target = exact ?? (matches.length == 1 ? matches.single : null);

    if (target == null) {
      _toast('Nothing in the catalogue matches "$code".', ok: false);
      return;
    }
    _addToBill(target);
    _productSearch.clear();
    setState(() {});
    _productSearchFocus.requestFocus();
  }

  /// Puts one on the bill, or says why not.
  ///
  /// The store refuses once the bill already holds everything on the rail,
  /// which is what stops a sale driving stock negative. Saying so out loud
  /// matters: silently ignoring a scan reads as a broken scanner.
  void _addToBill(ProductRecord product) {
    if (_posRepository.addToCart(product)) return;
    _toast(
      product.stock <= 0
          ? '${product.displayName} is out of stock.'
          : 'Only ${AppFormatters.quantity(product.stock)} of '
                '${product.displayName} left on the rail.',
      ok: false,
    );
  }

  void _setQuantity(CartLine line, int quantity) {
    final wanted = quantity;
    _posRepository.setCartQuantity(line, wanted);
    if (wanted > line.quantity && wanted > 0) {
      _toast(
        'Only ${AppFormatters.quantity(line.product.stock)} of '
        '${line.product.displayName} left on the rail.',
        ok: false,
      );
    }
    setState(() {});
  }

  double get _cartTotal => _store.cartGrandTotal(customer: _selectedCustomer);

  double get _paidAmount => switch (_paymentMode) {
    _PaymentMode.cash || _PaymentMode.card || _PaymentMode.upi => _cartTotal,
    _PaymentMode.split => _parse(_splitCash.text) + _parse(_splitCard.text),
  };

  String get _paymentLabel => switch (_paymentMode) {
    _PaymentMode.cash => 'Paid by cash',
    _PaymentMode.card => 'Paid by card',
    _PaymentMode.upi => 'Paid by UPI',
    _PaymentMode.split =>
      'Split: cash ${AppFormatters.currency(_parse(_splitCash.text))}, '
          '${_splitTender == _SplitTender.card ? 'card' : 'UPI'} '
          '${AppFormatters.currency(_parse(_splitCard.text))}',
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
    _PaymentMode.split =>
      _splitTender == _SplitTender.card ? _parse(_splitCard.text) : 0,
  };

  double get _upiAmountForSale => switch (_paymentMode) {
    _PaymentMode.upi => _cartTotal,
    _PaymentMode.split =>
      _splitTender == _SplitTender.upi ? _parse(_splitCard.text) : 0,
    _PaymentMode.cash || _PaymentMode.card => 0,
  };

  /// Re-points a previously chosen customer at the reloaded record after a
  /// refresh; null stays null. A sale with no chosen customer is a walk-in
  /// on the printed bill, and no customer_id is written to the sale row.
  CustomerRecord? _liveSelectedCustomer(CustomerRecord? selected) {
    if (selected == null) return null;
    for (final customer in _store.customers) {
      if (customer.id == selected.id) return customer;
    }
    return null;
  }

  /// Called from [build], so the controller writes are deferred to the end of
  /// the frame: the controllers have listeners that call [setState], which
  /// cannot run while the tree is building.
  void _syncPaymentDefaults(double total) {
    if (total <= 0) return;
    final needsSplit =
        _paymentMode == _PaymentMode.split &&
        _splitCard.text.isEmpty &&
        _splitCash.text.isEmpty;
    if (!needsSplit) return;
    final formattedTotal = total.toStringAsFixed(2);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_paymentMode == _PaymentMode.split &&
          _splitCard.text.isEmpty &&
          _splitCash.text.isEmpty) {
        _splitCard.text = formattedTotal;
      }
    });
  }

  /// Whether Checkout is live.
  ///
  /// Cash needs nothing but a bill: there is no amount to reconcile, because
  /// what is tendered and what is owed are the same number. Requiring a cash
  /// figure to match the total is what used to leave the button dead with a
  /// full trolley on the counter, so it is not asked for at all.
  ///
  /// A split has to add up, since its two halves go to two different places.
  /// Card and UPI need a reference — which the machine supplies, or the
  /// cashier types when there is no machine.
  bool _canCheckout(double total) {
    if (_checkingOut || _store.cart.isEmpty) return false;
    if (_paymentMode == _PaymentMode.split &&
        (_paidAmount - total).abs() >= 0.01) {
      return false;
    }
    // Nothing else to satisfy. The shop takes the money on its own machine
    // and records which rail it came down; the app does not ask for a bank
    // reference, because it has no way to verify one and a box nobody fills
    // in is a box that stops a sale.
    return true;
  }

  double _parse(String value) => double.tryParse(value.trim()) ?? 0;

  void _onPaymentChanged() {
    if (mounted) setState(() {});
  }

  /// The cart is emptied by the checkout, so the amounts tendered for the sale
  /// that just completed must not carry over into the next one.
  void _resetPaymentInputs() {
    _customerName.clear();
    _customerPhone.clear();
    _splitCash.clear();
    _splitCard.clear();
    _billDiscount.clear();
  }

  Future<CustomerRecord?> _customerForManualEntry() async {
    final name = _customerName.text.trim();
    final phone = _customerPhone.text.trim();
    if (name.isEmpty && phone.isEmpty) return null;

    for (final customer in _store.customers) {
      if (phone.isNotEmpty && customer.phone.trim() == phone) return customer;
    }

    final customer = CustomerRecord(
      id: 0,
      name: name.isEmpty ? 'Customer $phone' : name,
      phone: phone,
      email: '',
      address: '',
      creditLimit: 0,
      openingBalance: 0,
      balance: 0,
    );
    final id = await _store.saveCustomer(customer);
    return CustomerRecord(
      id: id,
      name: customer.name,
      phone: customer.phone,
      email: '',
      address: '',
      creditLimit: 0,
      openingBalance: 0,
      balance: 0,
    );
  }

  // ----------------------------------------------------------------- actions

  /// Builds the printable invoice for whatever is on the counter now.
  InvoiceData _invoiceFor(SaleRecord sale, List<CartLine> lines, double paid) =>
      InvoiceData(
        sale: sale,
        lines: invoiceLinesFor(
          cart: lines,
          settings: _store.gstSettings,
          interState: sale.isInterState,
          hsnFor: (product) => product.hsnCode.trim().isNotEmpty
              ? product.hsnCode.trim()
              : _store.gstSettings.defaultHsnCode,
          rateFor: _store.gstRateFor,
          billDiscount: _store.billDiscount,
        ),
        profile: _store.storeProfile,
        paid: paid,
        change: (paid - sale.total).clamp(0, double.infinity).toDouble(),
        paymentLabel: _paymentLabel,
        customerName: _customerName.text.trim().isEmpty
            ? _selectedCustomer?.name
            : _customerName.text.trim(),
        customerPhone: _customerPhone.text.trim().isEmpty
            ? _selectedCustomer?.phone
            : _customerPhone.text.trim(),
        customerAddress: _selectedCustomer?.address,
      );

  /// Scan, checkout, charge, print — the whole counter transaction.
  ///
  /// The order matters and is not arbitrary. The money is taken *before* the
  /// sale is written, because a bill that exists for a payment that was
  /// declined is a bill the shop has to unpick by hand. Once the machine has
  /// approved, the sale is committed and the bill prints itself: nobody has to
  /// pick a printer, and nobody has to copy a transaction number off a slip.
  Future<void> _checkout(BuildContext context) async {
    if (_checkingOut) return;
    setState(() => _checkingOut = true);
    try {
      final receiptLines = List<CartLine>.from(_store.cart);
      final paymentMethod = _paymentMethodValue;

      // The shop takes the money on its own machine before pressing this —
      // there is nothing for the app to collect or verify.
      final customer = await _customerForManualEntry();
      final sale = await _posRepository.checkout(
        customer: customer,
        paid: _paidAmount,
        paymentMethod: paymentMethod,
        cashAmount: _cashAmountForSale,
        cardAmount: _cardAmountForSale,
        upiAmount: _upiAmountForSale,
      );
      final invoice = _invoiceFor(sale, receiptLines, sale.total);
      _resetPaymentInputs();
      if (!context.mounted) return;
      _lastInvoice = invoice;

      // ----------------------------------------------------- print the bill
      final note = await _deliverReceipt(invoice);
      unawaited(_refreshNextBillNumber());
      if (!context.mounted) return;
      _toast('Bill ${sale.receipt} done. $note');
      _productSearchFocus.requestFocus();
    } on StateError catch (e) {
      if (mounted) _toast(e.message, ok: false);
    } finally {
      if (mounted) setState(() => _checkingOut = false);
    }
  }

  /// Shows what the bill will look like before a sale is committed.
  ///
  /// The sale does not exist yet, so the preview is built against a stand-in
  /// receipt number — everything else is the real arithmetic.
  Future<void> _previewCurrentBill() async {
    final lines = List<CartLine>.from(_store.cart);
    if (lines.isEmpty) return;
    final total = _cartTotal;
    var taxable = 0.0, cgst = 0.0, sgst = 0.0, igst = 0.0;
    for (final line in lines) {
      final tax = _store.lineTaxFor(line, customer: _selectedCustomer);
      taxable += tax.taxableValue;
      cgst += tax.cgst;
      sgst += tax.sgst;
      igst += tax.igst;
    }

    final draft = SaleRecord(
      receipt: 'PREVIEW',
      customerName: _customerName.text.trim().isEmpty
          ? (_selectedCustomer?.name ?? 'Walk-in')
          : _customerName.text.trim(),
      total: total,
      profit: 0,
      createdAt: DateTime.now(),
      taxableValue: taxable,
      cgst: cgst,
      sgst: sgst,
      igst: igst,
      discountTotal: _store.cartDiscountTotal,
      paymentMethod: _paymentMethodValue,
      cashAmount: _cashAmountForSale,
      cardAmount: _cardAmountForSale,
      upiAmount: _upiAmountForSale,
      customerGstin: _selectedCustomer?.gstin,
      placeOfSupply:
          _selectedCustomer?.effectiveStateCode ??
          _store.storeProfile?.effectiveStateCode,
    );

    await _openPreview(_invoiceFor(draft, lines, _paidAmount), canPrint: false);
  }

  Future<void> _openPreview(InvoiceData invoice, {bool canPrint = true}) async {
    final settings = _store.printerSettings;
    final logo = await _logoFor(settings);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => BillPreviewDialog(
        invoice: invoice,
        settings: settings,
        logo: logo,
        onPrint: canPrint
            ? (paper) async {
                _paper = paper;
                await _deliverReceipt(invoice);
              }
            : null,
      ),
    );
  }

  /// Gets the bill onto paper by whichever route the shop has configured, and
  /// returns the sentence to show the cashier.
  ///
  /// Direct thermal printing is attempted first when it is switched on, but a
  /// printer that is off, out of paper or renamed must not cost the shop the
  /// bill: the print dialog is the fallback, and the cashier is told that is
  /// what happened rather than being left wondering why nothing came out.
  Future<String> _deliverReceipt(InvoiceData invoice) async {
    // The paper chosen on this bill wins over the stored default, so picking
    // A4 in the preview produces the full sheet rather than silently printing
    // the configured roll, and picking a roll width prints at that width.
    final settings = switch (_paper) {
      InvoicePaper.a4 => _store.printerSettings.copyWith(
        mode: ReceiptPrintMode.dialog,
      ),
      InvoicePaper.roll57 => _store.printerSettings.copyWith(
        paper: ThermalPaper.mm57,
      ),
      InvoicePaper.roll80 => _store.printerSettings.copyWith(
        paper: ThermalPaper.mm80,
      ),
    };
    if (settings.isThermal && _printerService.supportsDirectPrinting) {
      try {
        final sent = await _printerService.send(
          buildThermalReceipt(
            data: invoice,
            settings: settings,
            logo: await _logoFor(settings),
          ),
          printerName: settings.printerName,
          copies: settings.copies,
        );
        if (sent) return 'Bill printed.';
      } on Object {
        // Fall through to the dialog below.
      }
      await _printViaDialog(invoice);
      return 'The thermal printer did not answer, so the print dialog opened '
          'instead. Check it under Hardware.';
    }
    await _printViaDialog(invoice);
    return 'Bill sent to the printer.';
  }

  /// The logo prepared for the roll currently configured, converted on first
  /// use and again only if the file or the paper width changes.
  Future<ReceiptLogo?> _logoFor(PrinterSettings settings) async {
    if (!settings.printLogoOnReceipt) return null;
    final path = _store.storeProfile?.logoPath;
    final key = '$path@${settings.paper.name}';
    if (_thermalLogoSource == key) return _thermalLogo;
    _thermalLogo = await loadReceiptLogo(path, paper: settings.paper);
    _thermalLogoSource = key;
    return _thermalLogo;
  }

  Future<void> _printViaDialog(InvoiceData invoice) => Printing.layoutPdf(
    name: invoice.sale.receipt,
    format: _paper.format,
    onLayout: (_) => buildInvoicePdf(data: invoice, paper: _paper),
  );

  Future<void> _reprintLast() async {
    final invoice = _lastInvoice;
    if (invoice == null) return;
    final note = await _deliverReceipt(invoice);
    if (!mounted) return;
    _toast('Reprinted ${invoice.sale.receipt}. $note');
  }

  /// The "no sale" button: opens the drawer to give change or take a float
  /// out, without ringing anything up.
  Future<void> _openDrawerWithoutSale() async {
    final settings = _store.printerSettings;
    if (!settings.isThermal || !_printerService.supportsDirectPrinting) {
      _toast(
        'The drawer opens through the thermal printer. Turn direct printing '
        'on under Hardware first.',
        ok: false,
      );
      return;
    }
    final opened = await _printerService.openDrawer(settings);
    if (!mounted) return;
    _toast(
      opened
          ? 'Drawer opened.'
          : 'The printer did not answer, so the drawer stayed shut.',
      ok: opened,
    );
  }

  // -------------------------------------------------------------- held bills

  Future<void> _holdBill() async {
    final label = await showDialog<String>(
      context: context,
      builder: (_) => const _HoldBillDialog(),
    );
    if (label == null) return;
    try {
      await _store.holdCurrentBill(label: label, customer: _selectedCustomer);
      _resetPaymentInputs();
      if (!mounted) return;
      _toast('Bill held. Recall it from the "held" button.');
      _productSearchFocus.requestFocus();
    } on StateError catch (e) {
      if (mounted) _toast(e.message, ok: false);
    }
  }

  Future<void> _openHeldBills() async {
    final recalled = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => HeldBillsSheet(store: _store),
    );
    if (recalled == null || !mounted) return;
    _toast('Bill put back on the counter.');
    _productSearchFocus.requestFocus();
  }

  void _toast(String message, {bool ok = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: ok ? AppColors.brand : AppColors.danger,
      ),
    );
  }
}

// ---------------------------------------------------------------- fragments

class _ProductTile extends StatelessWidget {
  const _ProductTile({required this.product, this.onTap});

  final ProductRecord product;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final out = product.stock <= 0;

    return Opacity(
      opacity: out ? 0.55 : 1,
      child: Material(
        color: AppColors.surface,
        borderRadius: AppRadii.tileBorder,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadii.tileBorder,
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.border),
              borderRadius: AppRadii.tileBorder,
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  children: [
                    AspectRatio(aspectRatio: 1.35, child: _image(product)),
                    if (out)
                      Positioned(
                        left: 0,
                        right: 0,
                        top: 14,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          color: AppColors.danger,
                          child: const Text(
                            'OUT OF STOCK',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.base),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        product.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium,
                      ),
                      if (product.variantLabel.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.xxs),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.goldWash,
                            borderRadius: AppRadii.pillBorder,
                          ),
                          child: Text(
                            product.variantLabel,
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                              color: AppColors.goldDeep,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: AppSpacing.sm),
                      Row(
                        children: [
                          Expanded(
                            child: MoneyText(
                              product.sellingPrice,
                              size: 15,
                              weight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      StockPill(
                        stock: product.stock,
                        minimum: product.minimumStock,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _image(ProductRecord product) {
    final path = product.imagePath;
    if (path != null && path.isNotEmpty && File(path).existsSync()) {
      return Image.file(File(path), fit: BoxFit.cover);
    }
    return Container(
      color: AppColors.surfaceAlt,
      alignment: Alignment.center,
      child: const Icon(
        Icons.checkroom_rounded,
        size: 26,
        color: AppColors.inkFaint,
      ),
    );
  }
}

class _CartLineTile extends StatelessWidget {
  const _CartLineTile({
    required this.line,
    required this.onRemove,
    required this.onQuantity,
  });

  final CartLine line;
  final VoidCallback onRemove;
  final ValueChanged<int> onQuantity;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  line.product.displayName,
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    _StepButton(
                      icon: Icons.remove,
                      onTap: () => onQuantity(line.quantity - 1),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 9),
                      child: Text(
                        '${line.quantity}',
                        style: AppTypography.money.copyWith(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    _StepButton(
                      icon: Icons.add,
                      onTap: () => onQuantity(line.quantity + 1),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      '× ${AppFormatters.amount(line.product.sellingPrice)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.inkFaint,
                      ),
                    ),
                    if (line.discount > 0)
                      Padding(
                        padding: const EdgeInsets.only(left: AppSpacing.xs),
                        child: Text(
                          'less ${AppFormatters.amount(line.discount)}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppColors.danger,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              MoneyText(line.total, size: 13.5, weight: FontWeight.w600),
              const SizedBox(height: 2),
              InkWell(
                onTap: onRemove,
                borderRadius: BorderRadius.circular(4),
                child: const Padding(
                  padding: EdgeInsets.all(2),
                  child: Icon(Icons.close, size: 14, color: AppColors.inkFaint),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(4),
    child: Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Icon(icon, size: 13, color: AppColors.inkSoft),
    ),
  );
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({
    required this.mode,
    required this.selected,
    required this.onTap,
  });

  final _PaymentMode mode;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: selected ? AppColors.brand : AppColors.surface,
    borderRadius: AppRadii.inputBorder,
    child: InkWell(
      onTap: onTap,
      borderRadius: AppRadii.inputBorder,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: AppRadii.inputBorder,
          border: Border.all(
            color: selected ? AppColors.brand : AppColors.border,
          ),
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              mode.icon,
              size: 13,
              color: selected ? AppColors.brandInk : AppColors.inkSoft,
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                mode.label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: selected ? AppColors.brandInk : AppColors.inkSoft,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Card or UPI QR, for the machine half of a split bill.
class _TenderButton extends StatelessWidget {
  const _TenderButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: selected ? AppColors.goldWash : AppColors.surface,
    borderRadius: AppRadii.inputBorder,
    child: InkWell(
      onTap: onTap,
      borderRadius: AppRadii.inputBorder,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: AppRadii.inputBorder,
          border: Border.all(
            color: selected ? AppColors.goldWashBorder : AppColors.border,
          ),
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 12,
              color: selected ? AppColors.goldDeep : AppColors.inkSoft,
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: selected ? AppColors.goldDeep : AppColors.inkSoft,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// A dashed rule above the total, the way a printed bill separates it.
class _DashedRule extends StatelessWidget {
  const _DashedRule();

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      const dash = 4.0;
      final count = (constraints.maxWidth / (dash * 2)).floor();
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: List.generate(
          count,
          (_) => Container(width: dash, height: 1, color: AppColors.border),
        ),
      );
    },
  );
}

class _HoldBillDialog extends StatefulWidget {
  const _HoldBillDialog();

  @override
  State<_HoldBillDialog> createState() => _HoldBillDialogState();
}

class _HoldBillDialogState extends State<_HoldBillDialog> {
  final _label = TextEditingController();

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Hold this bill'),
    content: SizedBox(
      width: 380,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Give it a name you will recognise when the customer comes back.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.xl),
          TextField(
            controller: _label,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Name it',
              hintText: 'Ramesh, the blue shirt man, 98765…',
            ),
            onSubmitted: (v) => Navigator.of(context).pop(v),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.of(context).pop(_label.text),
        child: const Text('Hold it'),
      ),
    ],
  );
}
