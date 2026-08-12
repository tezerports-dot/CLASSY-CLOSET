import 'dart:io';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/services/gst.dart';
import '../../../core/services/retail_store.dart';
import '../../../core/utils/formatters.dart';

/// Paper the invoice can be laid out for.
///
/// The two roll widths are the standard thermal receipt sizes; A4 is for a
/// desk printer. Picking one changes the layout, not just the page size — a
/// 58 mm roll cannot carry the same columns as an A4 sheet.
enum InvoicePaper {
  roll58(PdfPageFormat.roll57, 'Thermal 58 mm'),
  roll80(PdfPageFormat.roll80, 'Thermal 80 mm'),
  a4(PdfPageFormat.a4, 'A4 sheet');

  const InvoicePaper(this.format, this.label);
  final PdfPageFormat format;
  final String label;

  bool get isRoll => this != InvoicePaper.a4;
}

/// One printable line of the invoice.
class InvoiceLine {
  const InvoiceLine({
    required this.description,
    required this.hsnCode,
    required this.quantity,
    required this.unitPrice,
    required this.discount,
    required this.taxableValue,
    required this.taxRate,
    required this.cgst,
    required this.sgst,
    required this.igst,
    required this.lineTotal,
  });

  final String description;
  final String hsnCode;
  final int quantity;
  final double unitPrice;
  final double discount;
  final double taxableValue;
  final double taxRate;
  final double cgst;
  final double sgst;
  final double igst;
  final double lineTotal;
}

/// Everything the printed invoice needs, already computed.
///
/// The document is built from this rather than from the live cart so a reprint
/// months later reproduces exactly what was charged.
class InvoiceData {
  const InvoiceData({
    required this.sale,
    required this.lines,
    required this.profile,
    required this.paid,
    required this.change,
    required this.paymentLabel,
    this.customerName,
    this.customerPhone,
    this.customerAddress,
  });

  final SaleRecord sale;
  final List<InvoiceLine> lines;
  final StoreProfile? profile;
  final double paid;
  final double change;
  final String paymentLabel;
  final String? customerName;
  final String? customerPhone;
  final String? customerAddress;

  bool get isTaxInvoice => profile?.hasGstin ?? false;
  double get totalQuantity =>
      lines.fold(0.0, (sum, line) => sum + line.quantity);
}

/// Builds the invoice PDF for the chosen paper size.
Future<Uint8List> buildInvoicePdf({
  required InvoiceData data,
  required InvoicePaper paper,
}) async {
  final document = pw.Document();
  final logo = await _loadLogo(data.profile?.logoPath);

  document.addPage(
    pw.MultiPage(
      pageFormat: paper.format,
      margin: paper.isRoll
          ? const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 8)
          : const pw.EdgeInsets.all(28),
      build: (context) =>
          paper.isRoll ? _rollBody(data, logo, paper) : _sheetBody(data, logo),
    ),
  );
  return document.save();
}

Future<pw.MemoryImage?> _loadLogo(String? path) async {
  if (path == null || path.trim().isEmpty) return null;
  final file = File(path);
  if (!await file.exists()) return null;
  return pw.MemoryImage(await file.readAsBytes());
}

// ---------------------------------------------------------------- roll layout

/// Thermal rolls are narrow and monospaced, so the layout is a single column of
/// stacked rows rather than a table with columns that would not fit.
List<pw.Widget> _rollBody(
  InvoiceData data,
  pw.MemoryImage? logo,
  InvoicePaper paper,
) {
  final profile = data.profile;
  final sale = data.sale;
  final narrow = paper == InvoicePaper.roll58;
  final base = narrow ? 7.0 : 8.0;

  return [
    if (logo != null)
      pw.Center(
        child: pw.Container(
          height: 34,
          margin: const pw.EdgeInsets.only(bottom: 4),
          child: pw.Image(logo, fit: pw.BoxFit.contain),
        ),
      ),
    pw.Center(
      child: pw.Text(
        profile?.storeName ?? 'RetailPro',
        style: pw.TextStyle(fontSize: base + 3, fontWeight: pw.FontWeight.bold),
        textAlign: pw.TextAlign.center,
      ),
    ),
    if ((profile?.address ?? '').isNotEmpty)
      pw.Center(
        child: pw.Text(
          profile!.address!,
          style: pw.TextStyle(fontSize: base - 1),
          textAlign: pw.TextAlign.center,
        ),
      ),
    if ((profile?.phone ?? '').isNotEmpty)
      pw.Center(
        child: pw.Text(
          'Ph: ${profile!.phone!}',
          style: pw.TextStyle(fontSize: base - 1),
        ),
      ),
    if (data.isTaxInvoice)
      pw.Center(
        child: pw.Text(
          'GSTIN: ${profile!.gstin!}',
          style: pw.TextStyle(fontSize: base - 1),
        ),
      ),
    pw.SizedBox(height: 4),
    pw.Center(
      child: pw.Text(
        data.isTaxInvoice ? 'TAX INVOICE' : 'RECEIPT',
        style: pw.TextStyle(fontSize: base + 1, fontWeight: pw.FontWeight.bold),
      ),
    ),
    _rollDivider(),
    _rollKeyValue('Invoice', sale.receipt, base),
    _rollKeyValue('Date', AppFormatters.dateTime(sale.createdAt), base),
    if ((data.customerName ?? '').isNotEmpty)
      _rollKeyValue('Customer', data.customerName!, base),
    if ((data.customerPhone ?? '').isNotEmpty)
      _rollKeyValue('Phone', data.customerPhone!, base),
    if ((sale.customerGstin ?? '').isNotEmpty)
      _rollKeyValue('Buyer GSTIN', sale.customerGstin!, base),
    _rollDivider(),

    // Each item takes two rows: the name on its own line so long descriptions
    // are not truncated, then the arithmetic underneath.
    for (final line in data.lines) ...[
      pw.Text(line.description, style: pw.TextStyle(fontSize: base)),
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            '${line.quantity} x ${AppFormatters.amount(line.unitPrice)}'
            '${line.discount > 0 ? '  -${AppFormatters.amount(line.discount)}' : ''}',
            style: pw.TextStyle(fontSize: base - 1),
          ),
          pw.Text(
            AppFormatters.amount(line.lineTotal),
            style: pw.TextStyle(fontSize: base),
          ),
        ],
      ),
      pw.SizedBox(height: 2),
    ],

    _rollDivider(),
    _rollTotal('Taxable', sale.taxableValue, base),
    if (sale.cgst > 0) _rollTotal('CGST', sale.cgst, base),
    if (sale.sgst > 0) _rollTotal('SGST', sale.sgst, base),
    if (sale.igst > 0) _rollTotal('IGST', sale.igst, base),
    if (sale.discountTotal > 0)
      _rollTotal('Discount', sale.discountTotal, base),
    _rollDivider(),
    _rollTotal('TOTAL', sale.total, base + 2, bold: true),
    _rollTotal('Paid', data.paid, base),
    if (data.change > 0) _rollTotal('Change', data.change, base),
    pw.SizedBox(height: 2),
    pw.Text(data.paymentLabel, style: pw.TextStyle(fontSize: base - 1)),
    _rollDivider(),

    // A scannable invoice number turns returns into a scan instead of typing.
    pw.Center(
      child: pw.BarcodeWidget(
        barcode: pw.Barcode.code128(),
        data: sale.receipt,
        width: narrow ? 120 : 160,
        height: 28,
        drawText: false,
      ),
    ),
    pw.SizedBox(height: 3),
    pw.Center(
      child: pw.Text(sale.receipt, style: pw.TextStyle(fontSize: base - 1)),
    ),
    if ((profile?.receiptFooterText ?? '').isNotEmpty) ...[
      pw.SizedBox(height: 5),
      pw.Center(
        child: pw.Text(
          profile!.receiptFooterText!,
          style: pw.TextStyle(fontSize: base - 1),
          textAlign: pw.TextAlign.center,
        ),
      ),
    ],
    pw.SizedBox(height: 10),
  ];
}

pw.Widget _rollDivider() => pw.Padding(
  padding: const pw.EdgeInsets.symmetric(vertical: 3),
  child: pw.Divider(height: 0.5, thickness: 0.5),
);

pw.Widget _rollKeyValue(String label, String value, double size) => pw.Row(
  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
  children: [
    pw.Text('$label:', style: pw.TextStyle(fontSize: size - 1)),
    pw.Flexible(
      child: pw.Text(
        value,
        style: pw.TextStyle(fontSize: size - 1),
        textAlign: pw.TextAlign.right,
      ),
    ),
  ],
);

pw.Widget _rollTotal(
  String label,
  double amount,
  double size, {
  bool bold = false,
}) {
  final style = pw.TextStyle(
    fontSize: size,
    fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
  );
  return pw.Row(
    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
    children: [
      pw.Text(label, style: style),
      pw.Text(AppFormatters.amount(amount), style: style),
    ],
  );
}

// --------------------------------------------------------------- sheet layout

/// A4 carries the full Rule 46 table: HSN, taxable value, and each tax head in
/// its own column.
List<pw.Widget> _sheetBody(InvoiceData data, pw.MemoryImage? logo) {
  final profile = data.profile;
  final sale = data.sale;
  final interState = sale.isInterState;

  final headers = <String>[
    '#',
    'Description',
    'HSN',
    'Qty',
    'Rate',
    'Taxable',
    if (interState) 'IGST' else 'CGST',
    if (!interState) 'SGST',
    'Amount',
  ];

  final rows = <List<String>>[
    for (var i = 0; i < data.lines.length; i++)
      [
        '${i + 1}',
        data.lines[i].description,
        data.lines[i].hsnCode,
        '${data.lines[i].quantity}',
        AppFormatters.amount(data.lines[i].unitPrice),
        AppFormatters.amount(data.lines[i].taxableValue),
        if (interState)
          '${AppFormatters.amount(data.lines[i].igst)} (${data.lines[i].taxRate.toStringAsFixed(0)}%)'
        else
          '${AppFormatters.amount(data.lines[i].cgst)} (${(data.lines[i].taxRate / 2).toStringAsFixed(1)}%)',
        if (!interState)
          '${AppFormatters.amount(data.lines[i].sgst)} (${(data.lines[i].taxRate / 2).toStringAsFixed(1)}%)',
        AppFormatters.amount(data.lines[i].lineTotal),
      ],
  ];

  return [
    pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        if (logo != null)
          pw.Container(
            width: 64,
            height: 64,
            margin: const pw.EdgeInsets.only(right: 14),
            child: pw.Image(logo, fit: pw.BoxFit.contain),
          ),
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                profile?.storeName ?? 'RetailPro',
                style: pw.TextStyle(
                  fontSize: 17,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              if ((profile?.address ?? '').isNotEmpty)
                pw.Text(
                  profile!.address!,
                  style: const pw.TextStyle(fontSize: 9),
                ),
              if ((profile?.phone ?? '').isNotEmpty)
                pw.Text(
                  'Phone: ${profile!.phone!}',
                  style: const pw.TextStyle(fontSize: 9),
                ),
              if (data.isTaxInvoice)
                pw.Text(
                  'GSTIN: ${profile!.gstin!}',
                  style: pw.TextStyle(
                    fontSize: 9,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              if ((profile?.effectiveStateCode ?? '').isNotEmpty)
                pw.Text(
                  'State code: ${profile!.effectiveStateCode!}',
                  style: const pw.TextStyle(fontSize: 9),
                ),
            ],
          ),
        ),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text(
              data.isTaxInvoice ? 'TAX INVOICE' : 'RECEIPT',
              style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              'No: ${sale.receipt}',
              style: const pw.TextStyle(fontSize: 9),
            ),
            pw.Text(
              'Date: ${AppFormatters.dateTime(sale.createdAt)}',
              style: const pw.TextStyle(fontSize: 9),
            ),
            if ((sale.placeOfSupply ?? '').isNotEmpty)
              pw.Text(
                'Place of supply: ${sale.placeOfSupply}',
                style: const pw.TextStyle(fontSize: 9),
              ),
          ],
        ),
      ],
    ),
    pw.SizedBox(height: 14),
    pw.Container(
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.5)),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'Bill to',
            style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
          ),
          pw.Text(
            data.customerName ?? 'Walk-in Customer',
            style: const pw.TextStyle(fontSize: 10),
          ),
          if ((data.customerAddress ?? '').isNotEmpty)
            pw.Text(
              data.customerAddress!,
              style: const pw.TextStyle(fontSize: 9),
            ),
          if ((data.customerPhone ?? '').isNotEmpty)
            pw.Text(
              'Phone: ${data.customerPhone!}',
              style: const pw.TextStyle(fontSize: 9),
            ),
          if ((sale.customerGstin ?? '').isNotEmpty)
            pw.Text(
              'GSTIN: ${sale.customerGstin!}',
              style: const pw.TextStyle(fontSize: 9),
            ),
        ],
      ),
    ),
    pw.SizedBox(height: 12),
    pw.TableHelper.fromTextArray(
      headers: headers,
      data: rows,
      headerStyle: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold),
      cellStyle: const pw.TextStyle(fontSize: 8.5),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
      cellAlignment: pw.Alignment.centerRight,
      cellAlignments: {0: pw.Alignment.centerLeft, 1: pw.Alignment.centerLeft},
    ),
    pw.SizedBox(height: 12),
    pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'Amount in words',
                style: pw.TextStyle(
                  fontSize: 8.5,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Text(
                '${amountInWords(sale.total)} only',
                style: const pw.TextStyle(fontSize: 9),
              ),
              pw.SizedBox(height: 10),
              pw.Text(
                data.paymentLabel,
                style: const pw.TextStyle(fontSize: 9),
              ),
              pw.SizedBox(height: 14),
              pw.BarcodeWidget(
                barcode: pw.Barcode.code128(),
                data: sale.receipt,
                width: 150,
                height: 34,
                drawText: false,
              ),
            ],
          ),
        ),
        pw.SizedBox(width: 16),
        pw.SizedBox(
          width: 210,
          child: pw.Column(
            children: [
              _sheetTotal('Taxable value', sale.taxableValue),
              if (sale.discountTotal > 0)
                _sheetTotal('Discount', sale.discountTotal),
              if (sale.cgst > 0) _sheetTotal('CGST', sale.cgst),
              if (sale.sgst > 0) _sheetTotal('SGST', sale.sgst),
              if (sale.igst > 0) _sheetTotal('IGST', sale.igst),
              pw.Divider(height: 8),
              _sheetTotal('Grand total', sale.total, bold: true),
              _sheetTotal('Paid', data.paid),
              if (data.change > 0) _sheetTotal('Change due', data.change),
            ],
          ),
        ),
      ],
    ),
    pw.SizedBox(height: 26),
    pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      crossAxisAlignment: pw.CrossAxisAlignment.end,
      children: [
        pw.Expanded(
          child: pw.Text(
            (profile?.receiptFooterText ?? ''),
            style: const pw.TextStyle(fontSize: 8.5),
          ),
        ),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.SizedBox(height: 26),
            pw.Container(width: 150, height: 0.5, color: PdfColors.black),
            pw.SizedBox(height: 3),
            pw.Text(
              'For ${profile?.storeName ?? 'the seller'}',
              style: const pw.TextStyle(fontSize: 8.5),
            ),
            pw.Text(
              'Authorised signatory',
              style: const pw.TextStyle(fontSize: 8),
            ),
          ],
        ),
      ],
    ),
  ];
}

pw.Widget _sheetTotal(String label, double amount, {bool bold = false}) {
  final style = pw.TextStyle(
    fontSize: bold ? 11 : 9.5,
    fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
  );
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(label, style: style),
        pw.Text(AppFormatters.currency(amount), style: style),
      ],
    ),
  );
}

/// Rupees in words, in the Indian system, as invoices conventionally carry.
String amountInWords(double amount) {
  final rupees = amount.floor();
  final paise = ((amount - rupees) * 100).round();
  final buffer = StringBuffer('Rupees ${_wordsForIndianNumber(rupees)}');
  if (paise > 0) {
    buffer.write(' and ${_wordsForIndianNumber(paise)} paise');
  }
  return buffer.toString();
}

const _ones = [
  '',
  'One',
  'Two',
  'Three',
  'Four',
  'Five',
  'Six',
  'Seven',
  'Eight',
  'Nine',
  'Ten',
  'Eleven',
  'Twelve',
  'Thirteen',
  'Fourteen',
  'Fifteen',
  'Sixteen',
  'Seventeen',
  'Eighteen',
  'Nineteen',
];
const _tens = [
  '',
  '',
  'Twenty',
  'Thirty',
  'Forty',
  'Fifty',
  'Sixty',
  'Seventy',
  'Eighty',
  'Ninety',
];

String _wordsForIndianNumber(int value) {
  if (value == 0) return 'Zero';
  if (value < 0) return 'Minus ${_wordsForIndianNumber(-value)}';

  final parts = <String>[];
  // Indian grouping: crore, lakh, thousand, then the last three digits.
  for (final group in const [
    [10000000, 'Crore'],
    [100000, 'Lakh'],
    [1000, 'Thousand'],
    [100, 'Hundred'],
  ]) {
    final divisor = group[0] as int;
    final name = group[1] as String;
    final count = value ~/ divisor;
    if (count > 0) {
      parts.add('${_wordsUnderHundred(count)} $name');
      value %= divisor;
    }
  }
  if (value > 0) {
    if (parts.isNotEmpty) parts.add('and');
    parts.add(_wordsUnderHundred(value));
  }
  return parts.join(' ').replaceAll(RegExp(r'\s+'), ' ').trim();
}

String _wordsUnderHundred(int value) {
  if (value < 20) return _ones[value];
  final tens = _tens[value ~/ 10];
  final ones = _ones[value % 10];
  return ones.isEmpty ? tens : '$tens $ones';
}

/// Turns the persisted sale plus its cart snapshot into printable lines.
List<InvoiceLine> invoiceLinesFor({
  required List<CartLine> cart,
  required GstSettings settings,
  required bool interState,
  required String Function(ProductRecord) hsnFor,
  required double Function(ProductRecord) rateFor,
}) {
  return [
    for (final line in cart)
      () {
        final tax = computeLineTax(
          lineTotal: line.total,
          ratePercent: rateFor(line.product),
          priceIncludesTax: settings.pricesIncludeTax,
          interState: interState,
        );
        return InvoiceLine(
          description: line.product.displayName,
          hsnCode: hsnFor(line.product),
          quantity: line.quantity,
          unitPrice: line.product.sellingPrice,
          discount: line.discount,
          taxableValue: tax.taxableValue,
          taxRate: tax.ratePercent,
          cgst: tax.cgst,
          sgst: tax.sgst,
          igst: tax.igst,
          lineTotal: settings.pricesIncludeTax ? line.total : tax.grossValue,
        );
      }(),
  ];
}
