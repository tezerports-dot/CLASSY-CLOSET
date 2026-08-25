import 'package:classy_closet/core/database/app_database.dart';
import 'package:classy_closet/core/services/gst.dart';
import 'package:classy_closet/core/services/retail_store.dart';
import 'package:classy_closet/features/pos/data/invoice_document.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// The bill has to add up, and the tax on it has to be the tax on the money
/// that actually crossed the counter.
///
/// A bill discount used to be deducted only in the footer: every line, and
/// every stored sale_item row behind it, was taxed on the full shelf price.
/// The printed GST was therefore higher than the GST collected — and the rows
/// are what the reports total, so the shop would have remitted tax on money it
/// never took.
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
    for (final (sku, name, price) in [
      ('KRT', 'Kurta', 1500.0),
      ('DUP', 'Dupatta', 500.0),
    ]) {
      await store.saveProduct(
        ProductRecord(
          id: 0,
          sku: sku,
          name: name,
          category: 'Apparel',
          brand: 'Classy',
          unit: 'pcs',
          stock: 50,
          minimumStock: 1,
          purchasePrice: price / 3,
          sellingPrice: price,
          barcode: 'BC-$sku',
          location: 'R1',
        ),
      );
    }
  });

  tearDown(() async => db.close());

  void ringUp({double discount = 0}) {
    for (final p in store.products) {
      store.addToCart(p);
    }
    if (discount > 0) store.applyBillDiscount(discount);
  }

  double round(double v) => (v * 100).round() / 100;

  group('the discount reaches the tax', () {
    test('GST falls when a discount is given', () {
      ringUp();
      final full = store.cartTotals();

      store.applyBillDiscount(200);
      final discounted = store.cartTotals();

      expect(
        discounted.cgst + discounted.sgst,
        lessThan(full.cgst + full.sgst),
        reason: 'tax is owed on what the customer pays, not the shelf price',
      );
      expect(discounted.total, round(full.total - 200));
    });

    test('the printed lines are taxed after the discount, not before', () {
      ringUp(discount: 200);
      final totals = store.cartTotals();

      final lines = invoiceLinesFor(
        cart: store.cart,
        settings: store.gstSettings,
        interState: false,
        hsnFor: (_) => '6103',
        rateFor: store.gstRateFor,
        billDiscount: store.billDiscount,
      );

      // Every column on the bill has to reconcile with the bill's own totals.
      expect(
        round(lines.fold<double>(0, (s, l) => s + l.cgst)),
        closeTo(totals.cgst, 0.02),
        reason: 'line CGST must sum to the bill CGST',
      );
      expect(
        round(lines.fold<double>(0, (s, l) => s + l.sgst)),
        closeTo(totals.sgst, 0.02),
      );
      expect(
        round(lines.fold<double>(0, (s, l) => s + l.taxableValue)),
        closeTo(totals.taxable, 0.02),
        reason: 'line taxable values must sum to the bill taxable value',
      );
      expect(
        round(lines.fold<double>(0, (s, l) => s + l.lineTotal)),
        closeTo(totals.total, 0.02),
        reason: 'the item column must add up to what the customer pays',
      );
    });

    test('what is stored is what was collected', () async {
      ringUp(discount: 200);
      final totals = store.cartTotals();
      final sale = await store.checkout(
        paid: totals.total,
        cashAmount: totals.total,
      );

      final items = await db.select(db.saleItems).get();
      expect(
        round(items.fold<double>(0, (s, i) => s + i.taxableValue)),
        closeTo(sale.taxableValue, 0.02),
        reason:
            'the sale_item rows are what the GST report adds up — if they '
            'carry pre-discount tax the shop over-remits',
      );
      expect(
        round(items.fold<double>(0, (s, i) => s + i.lineTotal)),
        closeTo(sale.total, 0.02),
      );
      expect(round(sale.cgst + sale.sgst + sale.taxableValue), sale.total);
    });

    test('a reprinted bill shows the same figures as the original', () async {
      ringUp(discount: 200);
      final totals = store.cartTotals();
      final sale = await store.checkout(
        paid: totals.total,
        cashAmount: totals.total,
      );

      final reprint = await store.loadInvoiceForReceipt(sale.receipt);
      expect(reprint, isNotNull);
      expect(
        round(reprint!.lines.fold<double>(0, (s, l) => s + l.lineTotal)),
        closeTo(sale.total, 0.02),
        reason: 'a bill pulled up weeks later must match the one printed',
      );
      expect(
        round(reprint.lines.fold<double>(0, (s, l) => s + l.taxableValue)),
        closeTo(sale.taxableValue, 0.02),
      );
    });
  });

  group('the allocator', () {
    test('shares always sum to the discount exactly', () {
      // Thirds of a rupee are where a pro-rata split usually loses a paisa.
      final shares = allocateDiscount([100, 100, 100], 10);
      expect(round(shares.fold<double>(0, (s, v) => s + v)), 10.0);
    });

    test('a discount larger than the bill cannot go negative', () {
      final shares = allocateDiscount([50, 50], 500);
      expect(round(shares.fold<double>(0, (s, v) => s + v)), 100.0);
    });

    test('no discount means no shares', () {
      expect(allocateDiscount([10, 20], 0), [0, 0]);
      expect(allocateDiscount([], 50), isEmpty);
    });
  });
}
