import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/services/retail_store.dart';

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

/// What each label carries.
///
/// The tag is three things and nothing else: the garment's name with its size,
/// the barcode, and the barcode's number underneath. Everything the label used
/// to carry as well — the shop name, the MRP, the SKU repeated under the
/// number — competed with the two things somebody actually reaches for, which
/// are the bars for the scanner and the digits for when the scanner will not
/// read a creased tag.
///
/// The flags stay so a shop that wants a barcode-only tag, or one without the
/// size, can still have it; there is simply nothing else to switch off.
class LabelOptions {
  const LabelOptions({this.showProductName = true, this.showVariant = true});

  /// The garment's name, on the top line.
  final bool showProductName;

  /// The size (and colour when the design carries one), appended to the name.
  final bool showVariant;
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
  // The type scale follows the label's own height rather than a fixed pair of
  // sizes, so a 21 mm die-cut and a 42 mm one are both balanced instead of one
  // being cramped and the other half empty. Points, not millimetres, because
  // that is what the PDF layout works in.
  final heightPt = sheet.heightMm * PdfPageFormat.mm;
  final nameSize = (heightPt * 0.115).clamp(5.0, 11.0);
  final codeSize = (heightPt * 0.135).clamp(6.0, 13.0);

  // Bars take the room left once both text lines, the gaps around them, this
  // container's own padding and the page margin outside it are accounted for.
  //
  // The slack matters more than the bar height does. A column that overflows
  // its cell by even a point does not shrink — the PDF layout drops the last
  // child, and the last child here is the number. That is exactly how the
  // number went missing from the printed tag: the arithmetic looked right on
  // paper and the digits silently vanished off the bottom of every label.
  //
  // A line of text occupies roughly 1.2x its point size once ascender and
  // descender are counted, and 22pt covers the padding, the two gaps and
  // enough margin that rounding cannot tip it over.
  final textBlock = (nameSize + codeSize) * 1.2;
  final barcodeHeight = (heightPt - textBlock - 22).clamp(
    14.0,
    heightPt * 0.48,
  );

  // "Cotton Shirt · M" on one line: the name is what a person reads, the size
  // is the only part of it they need at the rail, and one line leaves the bars
  // the vertical room they need.
  final variant = product.variantLabel.trim();
  final caption = [
    if (options.showProductName) product.name.trim(),
    if (options.showVariant && variant.isNotEmpty) variant,
  ].where((part) => part.isNotEmpty).join('  ·  ');

  return pw.Container(
    padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
    child: pw.Column(
      mainAxisAlignment: pw.MainAxisAlignment.center,
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        if (caption.isNotEmpty) ...[
          pw.Text(
            caption,
            style: pw.TextStyle(
              fontSize: nameSize,
              fontWeight: pw.FontWeight.bold,
            ),
            maxLines: 1,
            overflow: pw.TextOverflow.clip,
            textAlign: pw.TextAlign.center,
          ),
          pw.SizedBox(height: 3),
        ],
        pw.BarcodeWidget(
          barcode: pw.Barcode.code128(),
          data: _codeFor(product),
          height: barcodeHeight,
          // The number is drawn separately below so it can be set at a size
          // somebody can read across a counter; the widget's own caption is
          // fixed small and cramped against the bars.
          drawText: false,
        ),
        pw.SizedBox(height: 2),
        pw.Text(
          _codeFor(product),
          style: pw.TextStyle(
            fontSize: codeSize,
            fontWeight: pw.FontWeight.bold,
            letterSpacing: 0.6,
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
