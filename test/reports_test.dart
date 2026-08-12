import 'package:classy_closet/core/database/app_database.dart';
import 'package:classy_closet/core/services/reports.dart';
import 'package:classy_closet/core/services/retail_store.dart';
import 'package:classy_closet/core/services/returns_and_shifts.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CSV', () {
    test('quotes every field so a comma cannot shift the columns', () {
      final csv = toCsv(
        ['Item', 'Price'],
        [
          ['Kurta, cotton', 899],
        ],
      );

      expect(csv, contains('"Kurta, cotton"'));
      expect(csv.trim().split('\n'), hasLength(2));
    });

    test('doubles an embedded quote rather than breaking the row', () {
      final csv = toCsv(
        ['Item'],
        [
          ['The 32" shirt'],
        ],
      );

      expect(csv, contains('"The 32"" shirt"'));
    });

    test('a null cell becomes an empty field', () {
      expect(
        toCsv(
          ['A', 'B'],
          [
            [null, 1],
          ],
        ),
        contains('"",'),
      );
    });
  });

  group('date ranges', () {
    test('today covers midnight to midnight', () {
      final range = DateRange.today();
      final now = DateTime.now();

      expect(range.contains(now), isTrue);
      expect(range.contains(range.from), isTrue);
      // The end is exclusive, so tomorrow's first moment is out.
      expect(range.contains(range.to), isFalse);
      expect(range.to.difference(range.from).inHours, 24);
    });

    test('the financial year runs April to April', () {
      final range = DateRange.thisFinancialYear();

      expect(range.from.month, 4);
      expect(range.to.month, 4);
      expect(range.to.year, range.from.year + 1);
    });

    test('a custom range includes the whole of the last day', () {
      final range = DateRange.custom(
        DateTime(2026, 3, 1),
        DateTime(2026, 3, 31),
      );

      expect(range.contains(DateTime(2026, 3, 31, 23, 59)), isTrue);
      expect(range.contains(DateTime(2026, 4, 1)), isFalse);
    });
  });

  group('against real sales', () {
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
          receiptNumberPrefix: 'CC',
          gstin: '27AAPFU0939F1ZV',
        ),
      );
      // Two price points so they land in different GST bands.
      await store.saveProduct(_item('CHEAP', 'Cotton Shirt', 500, 300, '6205'));
      await store.saveProduct(_item('RICH', 'Silk Saree', 4000, 2500, '6211'));
    });

    tearDown(() async => db.close());

    ProductRecord bySku(String sku) =>
        store.products.firstWhere((p) => p.sku == sku);

    Future<SaleRecord> sell(String sku, {int quantity = 1}) async {
      for (var i = 0; i < quantity; i++) {
        store.addToCart(bySku(sku));
      }
      final total = store.cartGrandTotal();
      return store.checkout(
        paid: total,
        paymentMethod: 'cash',
        cashAmount: total,
      );
    }

    test('an empty period reports zeroes rather than failing', () async {
      final report = await store.buildReports(DateRange.lastMonth());

      expect(report.billCount, 0);
      expect(report.grossSales, 0);
      expect(report.register, isEmpty);
      expect(report.gstByRate, isEmpty);
      expect(report.marginPercent, 0);
      expect(report.averageBill, 0);
    });

    test('the register lists every bill with its tax split', () async {
      await sell('CHEAP');
      await sell('RICH');

      final report = await store.buildReports(DateRange.today());

      expect(report.billCount, 2);
      expect(report.grossSales, closeTo(4500, 0.01));
      // Local sale, so CGST and SGST rather than IGST.
      expect(report.register.every((r) => r.igst == 0), isTrue);
      expect(report.register.every((r) => r.cgst > 0), isTrue);
      expect(report.taxTotal, greaterThan(0));
    });

    test('GST is grouped by rate, which is what the return needs', () async {
      await sell('CHEAP', quantity: 2);
      await sell('RICH');

      final report = await store.buildReports(DateRange.today());
      final rates = report.gstByRate.map((g) => g.ratePercent).toList();

      // 500 falls in the lower band, 4,000 in the higher one.
      expect(rates, containsAll(<double>[5, 18]));
      final low = report.gstByRate.firstWhere((g) => g.ratePercent == 5);
      final high = report.gstByRate.firstWhere((g) => g.ratePercent == 18);
      expect(low.cgst, closeTo(low.sgst, 0.01));
      expect(low.igst, 0);
      expect(high.taxableValue, greaterThan(low.taxableValue));
      // The parts add back up to the whole.
      expect(
        report.gstByRate.fold(0.0, (s, g) => s + g.taxTotal),
        closeTo(report.taxTotal, 0.05),
      );
    });

    test('HSN summary groups by code and carries quantity', () async {
      await sell('CHEAP', quantity: 3);
      await sell('RICH');

      final report = await store.buildReports(DateRange.today());
      final codes = report.hsn.map((h) => h.hsnCode).toList();

      expect(codes, containsAll(<String>['6205', '6211']));
      final shirts = report.hsn.firstWhere((h) => h.hsnCode == '6205');
      expect(shirts.quantity, 3);
      expect(shirts.total, closeTo(1500, 0.05));
    });

    test('best sellers rank by quantity and carry margin', () async {
      await sell('CHEAP', quantity: 5);
      await sell('RICH');

      final report = await store.buildReports(DateRange.today());

      expect(report.topSellers.first.description, contains('Cotton Shirt'));
      expect(report.topSellers.first.quantitySold, 5);
      expect(report.topSellers.first.profit, greaterThan(0));
      expect(report.topSellers.first.marginPercent, greaterThan(0));
    });

    test('dead stock lists what is on the rail but never sold', () async {
      await sell('CHEAP');

      final report = await store.buildReports(DateRange.today());

      expect(report.deadStock.map((p) => p.description), [
        contains('Silk Saree'),
      ]);
      expect(report.deadStock.every((p) => p.quantitySold == 0), isTrue);
    });

    test('returns are netted off sales and tax', () async {
      final sale = await sell('CHEAP', quantity: 2);
      final found = (await store.findSaleByReceipt(sale.receipt))!;
      await store.processReturn(
        sale: found,
        selections: [ReturnSelection(line: found.lines.single, quantity: 1)],
        refundMethod: RefundMethod.cash,
      );

      final report = await store.buildReports(DateRange.today());

      expect(report.grossSales, closeTo(1000, 0.01));
      expect(report.returnCount, 1);
      expect(report.returnsTotal, closeTo(500, 0.01));
      expect(report.netSales, closeTo(500, 0.01));
      expect(report.netTax, lessThan(report.taxTotal));
    });

    test('profit uses the cost captured at the time of sale', () async {
      await sell('CHEAP', quantity: 2);

      // Raise the cost after the fact; the report must not follow it.
      final existing = bySku('CHEAP');
      await store.saveProduct(
        ProductRecord(
          id: existing.id,
          sku: existing.sku,
          name: existing.name,
          category: existing.category,
          brand: existing.brand,
          unit: existing.unit,
          stock: existing.stock,
          minimumStock: existing.minimumStock,
          purchasePrice: 480,
          sellingPrice: existing.sellingPrice,
          barcode: existing.barcode,
          location: existing.location,
          hsnCode: existing.hsnCode,
        ),
      );

      final report = await store.buildReports(DateRange.today());

      // 1,000 gross at 5% is 952.38 taxable, less the 600 it actually cost.
      expect(report.grossProfit, closeTo(352.38, 0.05));
    });

    test('payment split adds up to the takings', () async {
      await sell('CHEAP');
      store.addToCart(bySku('RICH'));
      final total = store.cartGrandTotal();
      await store.checkout(
        paid: total,
        paymentMethod: 'card',
        cardAmount: total,
      );

      final report = await store.buildReports(DateRange.today());

      expect(report.cashTotal, closeTo(500, 0.01));
      expect(report.cardTotal, closeTo(4000, 0.01));
      expect(report.upiTotal, 0);
      expect(
        report.cashTotal + report.cardTotal + report.upiTotal,
        closeTo(report.grossSales, 0.01),
      );
    });
  });
}

ProductRecord _item(
  String sku,
  String name,
  double price,
  double cost,
  String hsn,
) => ProductRecord(
  id: 0,
  sku: sku,
  name: name,
  category: 'Apparel',
  brand: 'Classy',
  unit: 'pcs',
  stock: 20,
  minimumStock: 1,
  purchasePrice: cost,
  sellingPrice: price,
  barcode: 'BC-$sku',
  location: 'A1',
  hsnCode: hsn,
);
