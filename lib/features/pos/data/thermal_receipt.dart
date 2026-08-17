import 'dart:typed_data';

import '../../../core/services/escpos.dart';
import '../../../core/services/printer_service.dart';
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
Uint8List buildThermalReceipt({
  required InvoiceData data,
  required PrinterSettings settings,
}) {
  final paper = settings.paper;
  final builder = EscPosBuilder(paper: paper);
  final profile = data.profile;
  final sale = data.sale;

  // ------------------------------------------------------------ shop header
  builder.line(
    profile?.storeName ?? 'RetailPro',
    bold: true,
    center: true,
    doubleHeight: true,
  );
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
  builder
    ..columns2('Invoice', sale.receipt)
    ..columns2('Date', AppFormatters.dateTime(sale.createdAt));
  final customer = data.customerName?.trim() ?? '';
  if (customer.isNotEmpty) builder.columns2('Customer', customer);
  final customerPhone = data.customerPhone?.trim() ?? '';
  if (customerPhone.isNotEmpty) builder.columns2('Phone', customerPhone);
  final buyerGstin = sale.customerGstin?.trim() ?? '';
  if (buyerGstin.isNotEmpty) builder.columns2('Buyer GSTIN', buyerGstin);
  if (data.isTaxInvoice && (sale.placeOfSupply ?? '').isNotEmpty) {
    builder.columns2('Place of supply', sale.placeOfSupply!);
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
  builder
    ..rule()
    ..columns2(
      'Items ${AppFormatters.quantity(data.totalQuantity)}',
      AppFormatters.amount(sale.taxableValue + sale.taxTotal),
    );

  // ------------------------------------------------------------------ taxes
  if (sale.discountTotal > 0) {
    builder.columns2(
      'Discount',
      '-${AppFormatters.amount(sale.discountTotal)}',
    );
  }
  if (data.isTaxInvoice && sale.taxTotal > 0) {
    builder.columns2('Taxable value', AppFormatters.amount(sale.taxableValue));
    for (final entry in _taxByRate(data).entries) {
      final rate = AppFormatters.quantity(entry.key);
      if (sale.isInterState) {
        builder.columns2('IGST $rate%', AppFormatters.amount(entry.value.igst));
      } else {
        final half = AppFormatters.quantity(entry.key / 2);
        builder
          ..columns2('CGST $half%', AppFormatters.amount(entry.value.cgst))
          ..columns2('SGST $half%', AppFormatters.amount(entry.value.sgst));
      }
    }
  }

  builder
    ..rule()
    ..columns2('TOTAL', AppFormatters.amount(sale.total), bold: true)
    ..rule();

  // --------------------------------------------------------------- payment
  builder.columns2(data.paymentLabel, AppFormatters.amount(data.paid));
  if (data.change > 0) {
    builder.columns2('Change', AppFormatters.amount(data.change));
  }
  if (sale.cashAmount > 0 && sale.cardAmount + sale.upiAmount > 0) {
    // Split tender: spell the parts out so the till reconciles at close.
    builder.columns2('  Cash', AppFormatters.amount(sale.cashAmount));
    if (sale.cardAmount > 0) {
      builder.columns2('  Card', AppFormatters.amount(sale.cardAmount));
    }
    if (sale.upiAmount > 0) {
      builder.columns2('  UPI', AppFormatters.amount(sale.upiAmount));
    }
  }
  // The card machine's own reference, printed so a customer disputing a charge
  // weeks later can be matched to this bill without digging through statements.
  final reference = sale.paymentReference?.trim() ?? '';
  if (reference.isNotEmpty) {
    builder.columns2('Txn ref', reference);
  }
  final terminal = sale.paymentTerminal?.trim() ?? '';
  if (terminal.isNotEmpty) {
    builder.columns2('Terminal', terminal);
  }

  builder
    ..feed()
    ..line('${amountInWords(sale.total)} only');

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
