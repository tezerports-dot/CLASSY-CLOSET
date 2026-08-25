import 'package:classy_closet/core/services/retail_store.dart';
import 'package:classy_closet/features/products/data/label_document.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/pdf_text.dart';

void main() {
  const profile = StoreProfile(storeName: 'Classy Closet', currencySymbol: '₹');

  ProductRecord unit(String sku, {String barcode = '', String size = 'M'}) =>
      ProductRecord(
        id: sku.hashCode,
        sku: sku,
        name: 'Cotton Kurta',
        category: 'Kurta',
        brand: 'Classy',
        unit: 'pcs',
        stock: 4,
        minimumStock: 1,
        purchasePrice: 450,
        sellingPrice: 899,
        barcode: barcode,
        location: 'R1',
        size: size,
        color: 'Blue',
      );

  test('label stock knows how many fit on a page', () {
    expect(LabelSheet.a4_65.perPage, 65);
    expect(LabelSheet.a4_24.perPage, 24);
    expect(LabelSheet.a4_12.perPage, 12);
    expect(LabelSheet.roll50.isRoll, isTrue);
    expect(LabelSheet.a4_65.isRoll, isFalse);
  });

  test('a sheet of labels produces a real PDF', () async {
    final bytes = await buildLabelSheet(
      requests: [LabelRequest(product: unit('KRT-M'), copies: 10)],
      sheet: LabelSheet.a4_65,
      profile: profile,
    );

    expect(bytes, isNotEmpty);
    // Every PDF starts with this signature.
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
  });

  test(
    'printing nothing produces an empty document rather than failing',
    () async {
      final bytes = await buildLabelSheet(
        requests: const [],
        sheet: LabelSheet.a4_65,
        profile: profile,
      );

      expect(bytes, isNotEmpty);
      expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    },
  );

  test('more labels than fit on one sheet spill onto another', () async {
    // 70 labels on 65-up stock has to be two pages.
    final twoPages = await buildLabelSheet(
      requests: [LabelRequest(product: unit('KRT-M'), copies: 70)],
      sheet: LabelSheet.a4_65,
      profile: profile,
    );
    final onePage = await buildLabelSheet(
      requests: [LabelRequest(product: unit('KRT-M'), copies: 10)],
      sheet: LabelSheet.a4_65,
      profile: profile,
    );

    expect(twoPages.length, greaterThan(onePage.length));
  });

  test('a whole size run can be printed in one go', () async {
    final bytes = await buildLabelSheet(
      requests: [
        for (final size in ['S', 'M', 'L', 'XL'])
          LabelRequest(product: unit('KRT-$size', size: size), copies: 3),
      ],
      sheet: LabelSheet.a4_24,
      profile: profile,
    );

    expect(bytes, isNotEmpty);
  });

  test('roll stock puts one label on each page', () async {
    final bytes = await buildLabelSheet(
      requests: [LabelRequest(product: unit('KRT-M'), copies: 3)],
      sheet: LabelSheet.roll50,
      profile: profile,
    );

    expect(bytes, isNotEmpty);
  });

  test('a product with no barcode still gets a scannable label', () async {
    // Falls back to the SKU rather than printing an empty barcode.
    final bytes = await buildLabelSheet(
      requests: [
        LabelRequest(product: unit('SKU-ONLY', barcode: ''), copies: 1),
      ],
      sheet: LabelSheet.a4_24,
      profile: profile,
    );

    expect(bytes, isNotEmpty);
  });

  test('turning every option off still prints the barcode', () async {
    // The name and the size can be switched off; the barcode and its number
    // cannot, because a tag without them is not a tag.
    final bytes = await buildLabelSheet(
      requests: [LabelRequest(product: unit('KRT-M'), copies: 2)],
      sheet: LabelSheet.a4_24,
      profile: profile,
      options: const LabelOptions(showProductName: false, showVariant: false),
    );

    expect(bytes, isNotEmpty);
  });

  group('what is actually printed on the tag', () {
    // These read the words back out of the PDF. The tests above only ever
    // asserted that bytes came out, which is why "the label never changed"
    // could be true three releases running with every test passing.

    test(
      'carries the name, the size and the number — and nothing else',
      () async {
        final bytes = await buildLabelSheet(
          requests: [
            LabelRequest(
              product: unit('KRT-M', barcode: '890123456789'),
              copies: 1,
            ),
          ],
          sheet: LabelSheet.a4_65,
          profile: profile,
        );
        final text = pdfText(bytes);

        expect(
          text,
          contains('890123456789'),
          reason: 'the number under the bars',
        );
        expect(text, contains('Cotton'), reason: 'the garment name');
        expect(text, contains('Kurta'));
        expect(text, contains('M'), reason: 'the size');

        // The three things and no fourth. The shop name and the MRP used to
        // crowd the tag and were what pushed the number off the bottom of it.
        expect(text, isNot(contains('Classy Closet')));
        expect(text, isNot(contains('899')));
        expect(text.toUpperCase(), isNot(contains('MRP')));
      },
    );

    test('the number survives every stock size', () async {
      for (final sheet in LabelSheet.values) {
        final bytes = await buildLabelSheet(
          requests: [
            LabelRequest(
              product: unit('KRT-M', barcode: '890123456789'),
              copies: 1,
            ),
          ],
          sheet: sheet,
          profile: profile,
        );
        expect(
          pdfText(bytes),
          contains('890123456789'),
          reason:
              '${sheet.label}: an overflowing column drops its last child, and '
              'the last child is the number',
        );
      }
    });

    test('a unit with no barcode prints its SKU as the number', () async {
      final bytes = await buildLabelSheet(
        requests: [LabelRequest(product: unit('SKU-ONLY'), copies: 1)],
        sheet: LabelSheet.a4_24,
        profile: profile,
      );
      expect(pdfText(bytes), contains('SKU-ONLY'));
    });

    test('switching the name off leaves the number', () async {
      final bytes = await buildLabelSheet(
        requests: [
          LabelRequest(
            product: unit('KRT-M', barcode: '890123456789'),
            copies: 1,
          ),
        ],
        sheet: LabelSheet.a4_24,
        profile: profile,
        options: const LabelOptions(showProductName: false, showVariant: false),
      );
      final text = pdfText(bytes);

      expect(text, contains('890123456789'));
      expect(text, isNot(contains('Cotton')));
    });

    test('the dialog preview is the same label as the print', () async {
      // The panel in the print dialog renders this. If it could drift from
      // the printed sheet it would be worse than no preview at all.
      final preview = await buildLabelPreview(
        product: unit('KRT-M', barcode: '890123456789'),
        sheet: LabelSheet.a4_65,
        profile: profile,
      );
      final text = pdfText(preview);

      expect(text, contains('890123456789'));
      expect(text, contains('Kurta'));
      expect(text, isNot(contains('Classy Closet')));
    });
  });

  test('no store profile is handled', () async {
    final bytes = await buildLabelSheet(
      requests: [LabelRequest(product: unit('KRT-M'), copies: 1)],
      sheet: LabelSheet.a4_65,
      profile: null,
    );

    expect(bytes, isNotEmpty);
  });
}
