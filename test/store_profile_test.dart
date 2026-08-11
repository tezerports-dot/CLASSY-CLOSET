import 'dart:convert';

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
        expect(restored.currencySymbol, r'$');
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
}
