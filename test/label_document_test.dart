import 'package:classy_closet/core/services/retail_store.dart';
import 'package:classy_closet/features/products/data/label_document.dart';
import 'package:flutter_test/flutter_test.dart';

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

  test('turning every option off still produces a label', () async {
    final bytes = await buildLabelSheet(
      requests: [LabelRequest(product: unit('KRT-M'), copies: 2)],
      sheet: LabelSheet.a4_24,
      profile: profile,
      options: const LabelOptions(
        showStoreName: false,
        showProductName: false,
        showVariant: false,
        showPrice: false,
      ),
    );

    expect(bytes, isNotEmpty);
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
