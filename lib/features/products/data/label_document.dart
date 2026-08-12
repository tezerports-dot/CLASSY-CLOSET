import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/services/retail_store.dart';
import '../../../core/utils/formatters.dart';

/// The label stock a sheet is laid out for.
///
/// A4 sheets of gummed labels are what a small shop actually buys; the roll
/// sizes are for a dedicated label printer. Columns and rows are what make the
/// grid line up with the die-cut, so they belong to the stock, not the caller.
enum LabelSheet {
  a4_65('A4 sheet — 65 labels (38 × 21 mm)', PdfPageFormat.a4, 5, 13, 38, 21),
  a4_24('A4 sheet — 24 labels (64 × 34 mm)', PdfPageFormat.a4, 3, 8, 64, 34),
  a4_12('A4 sheet — 12 labels (97 × 42 mm)', PdfPageFormat.a4, 2, 6, 97, 42),
  roll50(
    'Label roll — 50 × 25 mm',
    PdfPageFormat(50 * PdfPageFormat.mm, 25 * PdfPageFormat.mm),
    1,
    1,
    50,
    25,
  );

  const LabelSheet(
    this.label,
    this.pageFormat,
    this.columns,
    this.rows,
    this.widthMm,
    this.heightMm,
  );

  final String label;
  final PdfPageFormat pageFormat;
  final int columns;
  final int rows;
  final double widthMm;
  final double heightMm;

  int get perPage => columns * rows;
  bool get isRoll => this == LabelSheet.roll50;
}

/// One label to print, and how many copies of it.
class LabelRequest {
  const LabelRequest({required this.product, required this.copies});
  final ProductRecord product;
  final int copies;
}

/// What each label carries besides the barcode.
class LabelOptions {
  const LabelOptions({
    this.showStoreName = true,
    this.showProductName = true,
    this.showVariant = true,
    this.showPrice = true,
    this.showMrpPrefix = true,
  });

  final bool showStoreName;
  final bool showProductName;
  final bool showVariant;
  final bool showPrice;

  /// Indian price labels conventionally read "MRP ₹499".
  final bool showMrpPrefix;
}

/// Builds a printable sheet of barcode labels.
///
/// Code 128 is used because it encodes the full alphanumeric SKUs this app
/// generates; EAN-13 would only take 13 digits and could not represent a code
/// like `KRT-01-Blue-M`.
Future<Uint8List> buildLabelSheet({
  required List<LabelRequest> requests,
  required LabelSheet sheet,
  required StoreProfile? profile,
  LabelOptions options = const LabelOptions(),
}) async {
  // Flatten copies out, so a request for 12 of one design fills 12 cells.
  final cells = <ProductRecord>[
    for (final request in requests)
      for (var i = 0; i < request.copies; i++) request.product,
  ];

  final document = pw.Document();
  if (cells.isEmpty) return document.save();

  if (sheet.isRoll) {
    // One label per page: a roll printer advances and cuts between each.
    for (final product in cells) {
      document.addPage(
        pw.Page(
          pageFormat: sheet.pageFormat,
          margin: const pw.EdgeInsets.all(2),
          build: (context) => _label(product, profile, options, sheet),
        ),
      );
    }
    return document.save();
  }

  for (var start = 0; start < cells.length; start += sheet.perPage) {
    final page = cells.skip(start).take(sheet.perPage).toList();
    document.addPage(
      pw.Page(
        pageFormat: sheet.pageFormat,
        margin: const pw.EdgeInsets.all(6),
        build: (context) => pw.GridView(
          crossAxisCount: sheet.columns,
          childAspectRatio: sheet.widthMm / sheet.heightMm,
          children: [
            for (final product in page)
              _label(product, profile, options, sheet),
          ],
        ),
      ),
    );
  }
  return document.save();
}

pw.Widget _label(
  ProductRecord product,
  StoreProfile? profile,
  LabelOptions options,
  LabelSheet sheet,
) {
  // Small die-cuts cannot carry as much text as a large one, so the type scale
  // follows the label height rather than being fixed.
  final tiny = sheet.heightMm <= 25;
  final nameSize = tiny ? 5.0 : 7.0;
  final priceSize = tiny ? 7.0 : 10.0;
  final codeSize = tiny ? 4.5 : 6.0;
  final barcodeHeight = tiny ? 16.0 : 24.0;

  return pw.Container(
    padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 2),
    child: pw.Column(
      mainAxisAlignment: pw.MainAxisAlignment.center,
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        if (options.showStoreName && (profile?.storeName ?? '').isNotEmpty)
          pw.Text(
            profile!.storeName,
            style: pw.TextStyle(
              fontSize: codeSize,
              fontWeight: pw.FontWeight.bold,
            ),
            maxLines: 1,
            overflow: pw.TextOverflow.clip,
          ),
        if (options.showProductName)
          pw.Text(
            product.name,
            style: pw.TextStyle(fontSize: nameSize),
            maxLines: 1,
            overflow: pw.TextOverflow.clip,
            textAlign: pw.TextAlign.center,
          ),
        if (options.showVariant && product.variantLabel.isNotEmpty)
          pw.Text(
            product.variantLabel,
            style: pw.TextStyle(fontSize: nameSize),
            maxLines: 1,
          ),
        pw.SizedBox(height: 1),
        pw.BarcodeWidget(
          barcode: pw.Barcode.code128(),
          data: _codeFor(product),
          height: barcodeHeight,
          drawText: false,
        ),
        pw.Text(
          _codeFor(product),
          style: pw.TextStyle(fontSize: codeSize),
          maxLines: 1,
        ),
        if (options.showPrice)
          pw.Text(
            '${options.showMrpPrefix ? 'MRP ' : ''}'
            '${AppFormatters.currency(product.sellingPrice)}',
            style: pw.TextStyle(
              fontSize: priceSize,
              fontWeight: pw.FontWeight.bold,
            ),
            maxLines: 1,
          ),
      ],
    ),
  );
}

/// Prefers the printed barcode, falling back to the SKU so a product without
/// one still gets a scannable label.
String _codeFor(ProductRecord product) =>
    product.barcode.trim().isNotEmpty ? product.barcode.trim() : product.sku;
