import 'dart:typed_data';

import '../../../core/services/escpos.dart';
import '../../../core/services/printer_service.dart';
import '../../../core/services/receipt_logo.dart';
import '../../../core/utils/formatters.dart';
import 'invoice_document.dart';

/// Lays a finished sale out as ESC/POS for a thermal roll.
///
/// This is the direct-print sibling of [buildInvoicePdf]. Both start from the
/// same [InvoiceData], so the bill a customer is handed carries the same
/// figures whichever route it took to paper.
///
/// The layout is column arithmetic rather than widgets — on a roll printer a
/// line is exactly [ThermalPaper.columns] characters and nothing reflows — so
/// every row is padded to width here rather than left to the device.
/// [logo] is the shop's mark already reduced to one bit per dot. It is passed
/// in rather than loaded here so this stays a pure function of the sale — the
/// caller does the file reading once and reuses the result across reprints.
Uint8List buildThermalReceipt({
  required InvoiceData data,
  required PrinterSettings settings,
  ReceiptLogo? logo,
}) {
  final paper = settings.paper;
  final builder = EscPosBuilder(
    paper: paper,
    columns: settings.charactersPerLine,
  );
  final profile = data.profile;
  final sale = data.sale;

  // ------------------------------------------------------------ shop header
  //
  // The logo replaces the name in large type rather than sitting above it —
  // the artwork already says what the shop is called, and roll paper is not
  // free.
  final printedLogo =
      settings.printLogoOnReceipt && logo != null && !logo.isEmpty;
  if (printedLogo) {
    builder
      ..rasterImage(logo.rows)
      ..feed();
  } else {
    builder.line(
      profile?.storeName ?? 'Classy Closet',
      bold: true,
      center: true,
      doubleHeight: true,
    );
  }
  final tagline = profile?.tagline.trim() ?? '';
  if (tagline.isNotEmpty) builder.line(tagline, center: true);
  final address = profile?.address?.trim() ?? '';
  if (address.isNotEmpty) builder.line(address, center: true);
  final phone = profile?.phone?.trim() ?? '';
  if (phone.isNotEmpty) builder.line('Ph: $phone', center: true);
  if (data.isTaxInvoice) {
    builder.line('GSTIN: ${profile!.gstin!}', center: true);
  }

  builder
    ..feed()
    ..line(
      data.isTaxInvoice ? 'TAX INVOICE' : 'RECEIPT',
      bold: true,
      center: true,
    )
    ..rule();

  // ------------------------------------------------------------ bill header
  // Centred, one phrase per line. Pushed to opposite edges these left a
  // corridor of white down the middle of the heading, which on an 80 mm roll
  // reads as a table with nothing in it.
  builder
    ..centeredPair('Invoice', sale.receipt)
    ..centeredPair('Date', AppFormatters.dateTime(sale.createdAt));
  final customer = data.customerName?.trim() ?? '';
  if (customer.isNotEmpty) builder.centeredPair('Customer', customer);
  final customerPhone = data.customerPhone?.trim() ?? '';
  if (customerPhone.isNotEmpty) builder.centeredPair('Phone', customerPhone);
  final buyerGstin = sale.customerGstin?.trim() ?? '';
  if (buyerGstin.isNotEmpty) builder.centeredPair('Buyer GSTIN', buyerGstin);
  if (data.isTaxInvoice && (sale.placeOfSupply ?? '').isNotEmpty) {
    builder.centeredPair('Place of supply', sale.placeOfSupply!);
  }
  builder.rule();

  // ------------------------------------------------------------------ lines
  //
  // The item name gets a line of its own so a full "Cotton Kurta (Blue / M)"
  // is never truncated, and the arithmetic sits underneath it right-aligned.
  // That shape fits 32 columns as readably as it fits 48.
  for (final line in data.lines) {
    builder.line(line.description);
    final tags = <String>[
      if (line.hsnCode.trim().isNotEmpty) 'HSN ${line.hsnCode.trim()}',
      if (data.isTaxInvoice && line.taxRate > 0)
        'GST ${AppFormatters.quantity(line.taxRate)}%',
    ];
    if (tags.isNotEmpty) builder.line('  ${tags.join('  ')}');
    final qtyAndRate =
        '  ${line.quantity} x ${AppFormatters.amount(line.unitPrice)}'
        '${line.discount > 0 ? '  less ${AppFormatters.amount(line.discount)}' : ''}';
    builder.columns2(qtyAndRate, AppFormatters.amount(line.lineTotal));
  }
  // Sum of the printed line totals — the gross subtotal before the discount.
  // Reading from the lines rather than sale.taxableValue+taxTotal is what
  // makes the "Subtotal / Discount / Total" block reconcile visibly: the
  // shopkeeper can add the item column up and get the Subtotal.
  final grossSubtotal = data.lines.fold<double>(
    0,
    (sum, line) => sum + line.lineTotal,
  );

  final inset = _totalsInset(builder.columns);
  builder
    ..rule()
    ..columns2(
      'Items ${AppFormatters.quantity(data.totalQuantity)}',
      AppFormatters.amount(grossSubtotal),
      inset: inset,
    );

  // ------------------------------------------------------------------ taxes
  if (sale.discountTotal > 0) {
    builder.columns2(
      'Discount',
      '-${AppFormatters.amount(sale.discountTotal)}',
      inset: inset,
    );
  }
  if (data.isTaxInvoice && sale.taxTotal > 0) {
    builder.columns2(
      'Taxable value',
      AppFormatters.amount(sale.taxableValue),
      inset: inset,
    );
    for (final entry in _taxByRate(data).entries) {
      final rate = AppFormatters.quantity(entry.key);
      if (sale.isInterState) {
        builder.columns2(
          'IGST $rate%',
          AppFormatters.amount(entry.value.igst),
          inset: inset,
        );
      } else {
        final half = AppFormatters.quantity(entry.key / 2);
        builder
          ..columns2(
            'CGST $half%',
            AppFormatters.amount(entry.value.cgst),
            inset: inset,
          )
          ..columns2(
            'SGST $half%',
            AppFormatters.amount(entry.value.sgst),
            inset: inset,
          );
      }
    }
  }

  builder
    ..rule()
    ..columns2(
      'TOTAL',
      AppFormatters.amount(sale.total),
      bold: true,
      inset: inset,
    )
    ..rule();

  // --------------------------------------------------------------- payment
  builder.columns2(
    data.paymentLabel,
    AppFormatters.amount(data.paid),
    inset: inset,
  );
  if (data.change > 0) {
    builder.columns2('Change', AppFormatters.amount(data.change), inset: inset);
  }
  if (sale.cashAmount > 0 && sale.cardAmount + sale.upiAmount > 0) {
    // Split tender: spell the parts out so the till reconciles at close.
    builder.columns2(
      '  Cash',
      AppFormatters.amount(sale.cashAmount),
      inset: inset,
    );
    if (sale.cardAmount > 0) {
      builder.columns2(
        '  Card',
        AppFormatters.amount(sale.cardAmount),
        inset: inset,
      );
    }
    if (sale.upiAmount > 0) {
      builder.columns2(
        '  UPI',
        AppFormatters.amount(sale.upiAmount),
        inset: inset,
      );
    }
  }
  builder
    ..feed()
    ..line('${amountInWords(sale.total)} only', center: true);

  // --------------------------------------------------------------- footer
  final footer = profile?.receiptFooterText?.trim() ?? '';
  if (footer.isNotEmpty) {
    builder
      ..feed()
      ..line(footer, center: true);
  }

  if (settings.canPrintUpiQr) {
    builder
      ..feed()
      ..line('Scan to pay by UPI', center: true)
      ..qr(
        upiPaymentUri(
          vpa: settings.upiVpa,
          payeeName: settings.upiPayeeName.trim().isEmpty
              ? (profile?.storeName ?? '')
              : settings.upiPayeeName,
          amount: sale.total,
          note: 'Bill ${sale.receipt}',
          reference: sale.receipt,
        ),
      );
  }

  if (settings.printBarcodeOnReceipt) {
    // Scanning this at the returns desk pulls the sale up without anyone
    // reading a sixteen-character invoice number off a creased receipt.
    builder
      ..feed()
      ..barcode128(sale.receipt);
  }

  // The exchange policy is the line a customer argues with a week later, so it
  // is the shop's own wording rather than something fixed in the code.
  final terms = profile?.termsText.trim() ?? '';
  if (terms.isNotEmpty) {
    builder
      ..feed()
      ..line(terms, center: true);
  }
  final jurisdiction = profile?.jurisdiction.trim() ?? '';
  if (jurisdiction.isNotEmpty) builder.line(jurisdiction, center: true);

  if (settings.openDrawerOnCashSale && sale.cashAmount > 0) {
    builder.openDrawer(pin: settings.drawerPin);
  }
  if (settings.cutAfterPrint) builder.cut();

  return builder.bytes();
}

/// How far to pull the totals block in from each edge.
///
/// A narrow roll has no room to spare, so it stays full width; a wide one gets
/// a margin, because totals stretched across 80 mm read as two separate lists
/// rather than one block. Proportional rather than fixed so an unusual column
/// count lands somewhere sensible.
int _totalsInset(int columns) => columns >= 40 ? (columns * 0.12).round() : 0;

/// Tax totalled by rate, so a bill mixing 5% and 18% apparel shows one line per
/// slab the way a GST invoice is expected to.
Map<double, _RateTotals> _taxByRate(InvoiceData data) {
  final byRate = <double, _RateTotals>{};
  for (final line in data.lines) {
    if (line.taxRate <= 0) continue;
    final totals = byRate.putIfAbsent(line.taxRate, _RateTotals.new);
    totals.cgst += line.cgst;
    totals.sgst += line.sgst;
    totals.igst += line.igst;
  }
  return Map.fromEntries(
    byRate.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
  );
}

class _RateTotals {
  double cgst = 0;
  double sgst = 0;
  double igst = 0;
}
