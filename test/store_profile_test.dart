import 'dart:convert';

import 'package:classy_closet/core/services/gst.dart';
import 'package:classy_closet/core/services/retail_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('StoreProfile serialization', () {
    test('round-trips every field through the settings JSON blob', () {
      const profile = StoreProfile(
        storeName: 'Classy Closet',
        currencySymbol: r'$',
        logoPath: '/var/lib/classy/store_logo.png',
        address: '12 High Street',
        phone: '555-0100',
        email: 'hello@classycloset.test',
        taxRegistrationNumber: 'VAT-9911',
        receiptFooterText: 'Thank you for shopping with us.',
        receiptNumberPrefix: 'CC',
      );

      final restored = StoreProfile.fromJson(
        jsonDecode(jsonEncode(profile.toJson())) as Map<String, dynamic>,
      );

      expect(restored.storeName, profile.storeName);
      expect(restored.currencySymbol, profile.currencySymbol);
      expect(restored.logoPath, profile.logoPath);
      expect(restored.address, profile.address);
      expect(restored.phone, profile.phone);
      expect(restored.email, profile.email);
      expect(restored.taxRegistrationNumber, profile.taxRegistrationNumber);
      expect(restored.receiptFooterText, profile.receiptFooterText);
      expect(restored.receiptNumberPrefix, profile.receiptNumberPrefix);
    });

    test(
      'defaults the receipt prefix and currency when the stored blob predates them',
      () {
        final restored = StoreProfile.fromJson(<String, dynamic>{
          'storeName': 'Legacy Store',
        });

        expect(restored.storeName, 'Legacy Store');
        expect(restored.currencySymbol, '₹');
        expect(restored.receiptNumberPrefix, isEmpty);
        expect(restored.logoPath, isNull);
      },
    );

    test(
      'trims the receipt prefix so it cannot inject padding into receipt numbers',
      () {
        final restored = StoreProfile.fromJson(<String, dynamic>{
          'storeName': ' Store ',
          'receiptNumberPrefix': '  INV  ',
        });

        expect(restored.storeName, 'Store');
        expect(restored.receiptNumberPrefix, 'INV');
      },
    );
  });

  group('the wording printed on the bill', () {
    test('every branding line survives a save and reload', () {
      const profile = StoreProfile(
        storeName: 'CLASSY CLOSET',
        currencySymbol: '₹',
        tagline: "Men's Fashion Store — Look Classy, Feel Content",
        termsText: 'Exchange within 7 days with the bill.',
        declarationText: 'We declare that this invoice shows the actual price.',
        bankDetails: 'HDFC Bank · A/c 50100123456789 · IFSC HDFC0000123',
        jurisdiction: 'Subject to Jaipur jurisdiction',
      );

      final restored = StoreProfile.fromJson(profile.toJson());

      expect(restored.tagline, profile.tagline);
      expect(restored.termsText, profile.termsText);
      expect(restored.declarationText, profile.declarationText);
      expect(restored.bankDetails, profile.bankDetails);
      expect(restored.jurisdiction, profile.jurisdiction);
    });

    test('a profile saved before these existed reads back empty, not null', () {
      // An installation upgraded from an earlier build has none of these keys
      // in its stored JSON, and an empty string is what the printing code
      // expects to mean "leave this line off".
      final restored = StoreProfile.fromJson(<String, dynamic>{
        'storeName': 'Old Shop',
      });

      expect(restored.tagline, isEmpty);
      expect(restored.termsText, isEmpty);
      expect(restored.declarationText, isEmpty);
      expect(restored.bankDetails, isEmpty);
      expect(restored.jurisdiction, isEmpty);
    });
  });

  group('what a fresh installation starts from', () {
    test('the packaged defaults are a complete, valid profile', () {
      const defaults = StoreProfile.firstRunDefaults;

      expect(defaults.storeName, 'CLASSY CLOSET');
      expect(defaults.currencySymbol, '₹');
      expect(defaults.address, contains('Jaipur'));
      expect(defaults.tagline, isNotEmpty);
      expect(defaults.termsText, isNotEmpty);
      expect(defaults.receiptNumberPrefix, 'CC');
    });

    test('the GSTIN is well formed and agrees with the state', () {
      const defaults = StoreProfile.firstRunDefaults;

      expect(defaults.hasGstin, isTrue, reason: 'must pass the format check');
      // 08 is Rajasthan, which is where Jaipur is. A GSTIN whose state
      // disagreed with the shop would tax every local sale as inter-state.
      expect(defaults.effectiveStateCode, '08');
      expect(indianStateCodes['08'], 'Rajasthan');
    });

    test('the defaults are only a starting point, not baked in', () {
      // A second shop types over them and nothing of the first shop remains.
      final second = StoreProfile.fromJson(
        StoreProfile.firstRunDefaults.toJson(),
      );
      const replaced = StoreProfile(
        storeName: 'Another Shop',
        currencySymbol: '₹',
        tagline: 'Something else entirely',
      );

      expect(second.storeName, 'CLASSY CLOSET');
      expect(replaced.storeName, 'Another Shop');
      expect(replaced.tagline, 'Something else entirely');
      expect(replaced.termsText, isEmpty);
    });
  });
}
