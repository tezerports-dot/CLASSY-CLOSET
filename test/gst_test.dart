import 'package:classy_closet/core/services/gst.dart';
import 'package:classy_closet/features/pos/data/invoice_document.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('apparel rate slabs', () {
    const settings = GstSettings();

    test('a garment at or below the threshold takes the lower rate', () {
      expect(settings.rateFor(unitPrice: 499), 5);
      expect(settings.rateFor(unitPrice: 2500), 5);
    });

    test('a garment above the threshold takes the higher rate', () {
      expect(settings.rateFor(unitPrice: 2500.01), 18);
      expect(settings.rateFor(unitPrice: 9999), 18);
    });

    test('a rate set on the product overrides the slab', () {
      expect(settings.rateFor(unitPrice: 200, productRate: 12), 12);
    });

    test('a zero product rate falls through to the slab', () {
      expect(settings.rateFor(unitPrice: 200, productRate: 0), 5);
    });

    test('disabling GST zeroes the rate', () {
      const off = GstSettings(enabled: false);
      expect(off.rateFor(unitPrice: 5000, productRate: 18), 0);
    });

    test('custom slabs survive a settings round trip', () {
      const custom = GstSettings(
        slabs: [
          GstSlab(upToPrice: 1000, ratePercent: 5),
          GstSlab(upToPrice: null, ratePercent: 12),
        ],
        pricesIncludeTax: false,
        defaultHsnCode: '6203',
      );
      final restored = GstSettings.decode(custom.encode());

      expect(restored.rateFor(unitPrice: 900), 5);
      expect(restored.rateFor(unitPrice: 1500), 12);
      expect(restored.pricesIncludeTax, isFalse);
      expect(restored.defaultHsnCode, '6203');
    });
  });

  group('line tax', () {
    test('extracts GST from a tax-inclusive shelf price', () {
      final tax = computeLineTax(
        lineTotal: 1050,
        ratePercent: 5,
        priceIncludesTax: true,
        interState: false,
      );

      expect(tax.taxableValue, closeTo(1000, 0.01));
      expect(tax.taxAmount, closeTo(50, 0.01));
      expect(tax.grossValue, closeTo(1050, 0.01));
    });

    test('adds GST on top of a tax-exclusive price', () {
      final tax = computeLineTax(
        lineTotal: 1000,
        ratePercent: 5,
        priceIncludesTax: false,
        interState: false,
      );

      expect(tax.taxableValue, closeTo(1000, 0.01));
      expect(tax.taxAmount, closeTo(50, 0.01));
      expect(tax.grossValue, closeTo(1050, 0.01));
    });

    test('splits a local sale into equal CGST and SGST halves', () {
      final tax = computeLineTax(
        lineTotal: 1180,
        ratePercent: 18,
        priceIncludesTax: true,
        interState: false,
      );

      expect(tax.cgst, closeTo(90, 0.01));
      expect(tax.sgst, closeTo(90, 0.01));
      expect(tax.igst, 0);
      expect(tax.cgst + tax.sgst, closeTo(tax.taxAmount, 0.01));
    });

    test('charges a single IGST amount across state lines', () {
      final tax = computeLineTax(
        lineTotal: 1180,
        ratePercent: 18,
        priceIncludesTax: true,
        interState: true,
      );

      expect(tax.igst, closeTo(180, 0.01));
      expect(tax.cgst, 0);
      expect(tax.sgst, 0);
    });

    test('a zero rate leaves the whole line taxable and untaxed', () {
      final tax = computeLineTax(
        lineTotal: 500,
        ratePercent: 0,
        priceIncludesTax: true,
        interState: false,
      );

      expect(tax.taxableValue, 500);
      expect(tax.taxAmount, 0);
    });
  });

  group('GSTIN', () {
    test('accepts a well-formed number and reads its state', () {
      expect(isValidGstinFormat('27AAPFU0939F1ZV'), isTrue);
      expect(stateCodeFromGstin('27AAPFU0939F1ZV'), '27');
      expect(indianStateCodes['27'], 'Maharashtra');
    });

    test('rejects wrong length, wrong shape and unknown state codes', () {
      expect(isValidGstinFormat('27AAPFU0939F1Z'), isFalse);
      expect(isValidGstinFormat('AAPFU270939F1ZV'), isFalse);
      expect(isValidGstinFormat('99AAPFU0939F1ZV'), isFalse);
      expect(isValidGstinFormat(null), isFalse);
      expect(stateCodeFromGstin('99AAPFU0939F1ZV'), isNull);
    });
  });

  group('amount in words', () {
    test('writes rupees using the Indian numbering system', () {
      expect(amountInWords(0), 'Rupees Zero');
      expect(amountInWords(45), 'Rupees Forty Five');
      expect(amountInWords(100), 'Rupees One Hundred');
      expect(amountInWords(1250), 'Rupees One Thousand Two Hundred and Fifty');
      expect(amountInWords(125000), 'Rupees One Lakh Twenty Five Thousand');
      expect(amountInWords(10000000), 'Rupees One Crore');
    });

    test('includes paise when the amount is not whole', () {
      expect(amountInWords(99.50), 'Rupees Ninety Nine and Fifty paise');
    });
  });
}
