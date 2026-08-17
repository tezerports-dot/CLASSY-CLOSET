import 'package:classy_closet/core/database/app_database.dart';
import 'package:classy_closet/core/services/retail_store.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late RetailStore store;

  setUp(() async {
    db = AppDatabase.withExecutor(NativeDatabase.memory());
    store = RetailStore(db);
    await store.initialize();
    await store.login('admin', 'admin123');
    await store.saveStoreProfile(
      const StoreProfile(
        storeName: 'Classy Closet',
        currencySymbol: '₹',
        gstin: '29ABCDE1234F1Z5',
        stateCode: '29',
      ),
    );
    await store.saveProduct(
      ProductRecord(
        id: 0,
        sku: 'KRT',
        name: 'Kurta',
        category: 'Kurta',
        brand: 'Classy',
        unit: 'pcs',
        stock: 50,
        minimumStock: 1,
        purchasePrice: 600,
        sellingPrice: 1500,
        barcode: 'BC-KRT',
        location: 'R1',
      ),
    );
    await store.saveProduct(
      ProductRecord(
        id: 0,
        sku: 'DUP',
        name: 'Dupatta',
        category: 'Dupatta',
        brand: 'Classy',
        unit: 'pcs',
        stock: 50,
        minimumStock: 1,
        purchasePrice: 200,
        sellingPrice: 500,
        barcode: 'BC-DUP',
        location: 'R2',
      ),
    );
  });

  tearDown(() async => db.close());

  ProductRecord kurta() => store.products.firstWhere((p) => p.sku == 'KRT');
  ProductRecord dupatta() => store.products.firstWhere((p) => p.sku == 'DUP');

  group('a discount on the whole bill', () {
    test('the example from the counter: 2,000 less 200 is 1,800', () async {
      store.addToCart(kurta());
      store.addToCart(dupatta());
      expect(store.cartGrossTotal, 2000);

      store.applyBillDiscount(200);

      expect(store.cartDiscountTotal, 200);
      expect(store.cartGrandTotal(), 1800);
    });

    test('it is spread across the lines in proportion to their value', () {
      store.addToCart(kurta()); // 1500 — three quarters of the bill
      store.addToCart(dupatta()); // 500 — one quarter

      store.applyBillDiscount(200);

      final lines = {for (final l in store.cart) l.product.sku: l};
      expect(lines['KRT']!.discount, 150);
      expect(lines['DUP']!.discount, 50);
    });

    test('the pieces always add back up to the discount given', () {
      // 100 across a 1,500 / 500 split divides cleanly; 33.33 does not. The
      // remainder has to land somewhere or the printed bill will not foot.
      store.addToCart(kurta());
      store.addToCart(dupatta());

      for (final amount in [1.0, 33.33, 99.99, 777.77, 1234.56]) {
        store.applyBillDiscount(amount);
        expect(
          store.cartDiscountTotal,
          closeTo(amount, 0.005),
          reason: 'a $amount discount must be exactly $amount on the bill',
        );
      }
    });

    test('the GST on the bill is charged on the discounted value', () async {
      // This is the reason the discount is apportioned rather than subtracted
      // from the total: tax follows the money actually charged.
      store.addToCart(kurta());
      store.addToCart(dupatta());
      store.applyBillDiscount(200);

      final sale = await store.checkout(paid: 1800, cashAmount: 1800);

      expect(sale.total, 1800);
      expect(sale.discountTotal, 200);
      // Shelf prices include GST, and tax is worked out per line and summed —
      // which is what the invoice prints — so the kurta at 1,350 gives 64.29
      // and the dupatta at 450 gives 21.43.
      expect(sale.cgst + sale.sgst, 85.72);
      expect(sale.taxableValue, 1714.28);
      // The parts have to reconstruct the total a customer was charged, to the
      // paisa. Anything else is an invoice that does not foot.
      expect(sale.taxableValue + sale.taxTotal, 1800);
    });

    test('a discount bigger than the bill is capped, not negative', () {
      store.addToCart(dupatta());

      store.applyBillDiscount(9999);

      expect(store.cartDiscountTotal, 500);
      expect(store.cartGrandTotal(), 0);
    });

    test('a negative discount is treated as none', () {
      store.addToCart(kurta());

      store.applyBillDiscount(-50);

      expect(store.cartDiscountTotal, 0);
    });

    test('changing the amount replaces the old one rather than stacking', () {
      store.addToCart(kurta());
      store.addToCart(dupatta());

      store.applyBillDiscount(200);
      store.applyBillDiscount(50);

      expect(store.cartDiscountTotal, 50);
    });

    test('it can be taken back off', () {
      store.addToCart(kurta());
      store.applyBillDiscount(300);

      store.clearDiscounts();

      expect(store.cartDiscountTotal, 0);
      expect(store.cartGrandTotal(), 1500);
    });

    test('an empty cart is left alone', () {
      store.applyBillDiscount(100);

      expect(store.cart, isEmpty);
    });
  });

  group('a discount on one line', () {
    test('comes off that line only', () {
      store.addToCart(kurta());
      store.addToCart(dupatta());

      store.setLineDiscount(
        store.cart.firstWhere((l) => l.product.sku == 'KRT'),
        100,
      );

      expect(store.cartGrandTotal(), 1900);
      expect(store.cart.firstWhere((l) => l.product.sku == 'DUP').discount, 0);
    });

    test('cannot exceed what the line is worth', () {
      store.addToCart(dupatta());

      store.setLineDiscount(store.cart.single, 9999);

      expect(store.cart.single.discount, 500);
      expect(store.cart.single.total, 0);
    });
  });

  group('what the sale records', () {
    test('the discount is stored and survives a restart', () async {
      store.addToCart(kurta());
      store.addToCart(dupatta());
      store.applyBillDiscount(200);
      await store.checkout(paid: 1800, cashAmount: 1800);

      final reloaded = RetailStore(db);
      await reloaded.refresh();

      expect(reloaded.sales.single.discountTotal, 200);
      expect(reloaded.sales.single.total, 1800);
    });

    test('profit is measured after the discount, not before', () async {
      store.addToCart(kurta()); // costs 600, sells for 1500
      store.applyBillDiscount(300);

      final sale = await store.checkout(paid: 1200, cashAmount: 1200);

      // 1,200 gross at 5% is 1,142.86 taxable, less 600 of cost.
      expect(sale.profit, closeTo(542.86, 0.01));
    });

    test('the card reference is kept against the bill', () async {
      store.addToCart(dupatta());

      final sale = await store.checkout(
        paid: 500,
        paymentMethod: 'card',
        cardAmount: 500,
        paymentReference: 'PYTM-20260817-889134',
        paymentTerminal: 'EDC-01',
      );

      expect(sale.paymentReference, 'PYTM-20260817-889134');

      final reloaded = RetailStore(db);
      await reloaded.refresh();
      expect(reloaded.sales.single.paymentReference, 'PYTM-20260817-889134');
      expect(reloaded.sales.single.paymentTerminal, 'EDC-01');
    });

    test('a cash sale carries no reference', () async {
      store.addToCart(dupatta());

      final sale = await store.checkout(paid: 500, cashAmount: 500);

      expect(sale.paymentReference, isNull);
    });
  });
}
