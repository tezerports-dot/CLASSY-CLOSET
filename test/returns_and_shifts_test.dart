import 'package:classy_closet/core/database/app_database.dart';
import 'package:classy_closet/core/services/retail_store.dart';
import 'package:classy_closet/core/services/returns_and_shifts.dart';
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
        receiptNumberPrefix: 'CC',
      ),
    );
    await store.saveProduct(_shirt());
  });

  tearDown(() async => db.close());

  /// Sells [quantity] shirts and returns the bill.
  Future<SaleRecord> sell({int quantity = 1, CustomerRecord? customer}) async {
    for (var i = 0; i < quantity; i++) {
      store.addToCart(store.products.single);
    }
    final total = store.cartGrandTotal(customer: customer);
    return store.checkout(
      customer: customer,
      paid: total,
      paymentMethod: 'cash',
      cashAmount: total,
    );
  }

  group('finding a bill', () {
    test('an unknown bill number finds nothing', () async {
      expect(await store.findSaleByReceipt('NOPE'), isNull);
      expect(await store.findSaleByReceipt('   '), isNull);
    });

    test(
      'a bill comes back with its lines and what is still returnable',
      () async {
        final sale = await sell(quantity: 3);

        final found = await store.findSaleByReceipt(sale.receipt);

        expect(found, isNotNull);
        expect(found!.receiptNumber, sale.receipt);
        expect(found.lines, hasLength(1));
        expect(found.lines.single.soldQuantity, 3);
        expect(found.lines.single.alreadyReturned, 0);
        expect(found.lines.single.returnableQuantity, 3);
        expect(found.hasAnythingLeft, isTrue);
      },
    );
  });

  group('taking goods back', () {
    test('a partial return restocks and refunds proportionally', () async {
      final sale = await sell(quantity: 3);
      final found = (await store.findSaleByReceipt(sale.receipt))!;
      final stockBefore = store.products.single.stock;

      final credit = await store.processReturn(
        sale: found,
        selections: [ReturnSelection(line: found.lines.single, quantity: 1)],
        refundMethod: RefundMethod.cash,
        reason: 'Wrong size',
      );

      // One of three shirts, so a third of the bill.
      expect(credit.totalAmount, closeTo(sale.total / 3, 0.01));
      expect(credit.returnNumber, matches(RegExp(r'^CN/\d{4}/0001$')));
      expect(credit.reason, 'Wrong size');
      expect(store.products.single.stock, stockBefore + 1);

      final movements = await db.select(db.inventoryMovements).get();
      expect(
        movements.where((m) => m.movementType == 'return').single.quantity,
        1,
      );
    });

    test('tax is reversed in the same proportion as the goods', () async {
      final sale = await sell(quantity: 2);
      final found = (await store.findSaleByReceipt(sale.receipt))!;

      final credit = await store.processReturn(
        sale: found,
        selections: [ReturnSelection(line: found.lines.single, quantity: 1)],
        refundMethod: RefundMethod.cash,
      );

      expect(credit.taxTotal, closeTo(sale.taxTotal / 2, 0.02));
      expect(credit.taxableTotal, closeTo(sale.taxableValue / 2, 0.02));
      // A local sale, so the tax comes back as CGST and SGST, not IGST.
      expect(credit.cgst, closeTo(credit.sgst, 0.01));
      expect(credit.igst, 0);
    });

    test('the same garment cannot be refunded twice', () async {
      final sale = await sell(quantity: 2);
      var found = (await store.findSaleByReceipt(sale.receipt))!;

      await store.processReturn(
        sale: found,
        selections: [ReturnSelection(line: found.lines.single, quantity: 2)],
        refundMethod: RefundMethod.cash,
      );

      found = (await store.findSaleByReceipt(sale.receipt))!;
      expect(found.lines.single.alreadyReturned, 2);
      expect(found.lines.single.returnableQuantity, 0);
      expect(found.hasAnythingLeft, isFalse);

      expect(
        () => store.processReturn(
          sale: found,
          selections: [ReturnSelection(line: found.lines.single, quantity: 1)],
          refundMethod: RefundMethod.cash,
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('returning more than was sold is refused', () async {
      final sale = await sell(quantity: 1);
      final found = (await store.findSaleByReceipt(sale.receipt))!;

      expect(
        () => store.processReturn(
          sale: found,
          selections: [ReturnSelection(line: found.lines.single, quantity: 5)],
          refundMethod: RefundMethod.cash,
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('returning nothing is refused', () async {
      final sale = await sell();
      final found = (await store.findSaleByReceipt(sale.receipt))!;

      expect(
        () => store.processReturn(
          sale: found,
          selections: const [],
          refundMethod: RefundMethod.cash,
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('a credit refund reduces what the customer owes', () async {
      final walkIn = store.customers.firstWhere(
        (c) => c.name == 'Walk-in Customer',
      );
      // Sell on account so there is a balance to credit against.
      store.addToCart(store.products.single);
      await store.checkout(customer: walkIn, paid: 0, paymentMethod: 'cash');
      final owedBefore = store.customers
          .firstWhere((c) => c.id == walkIn.id)
          .balance;
      expect(owedBefore, greaterThan(0));

      final sale = store.sales.first;
      final found = (await store.findSaleByReceipt(sale.receipt))!;
      final credit = await store.processReturn(
        sale: found,
        selections: [ReturnSelection(line: found.lines.single, quantity: 1)],
        refundMethod: RefundMethod.credit,
      );

      expect(
        store.customers.firstWhere((c) => c.id == walkIn.id).balance,
        closeTo(owedBefore - credit.totalAmount, 0.01),
      );
    });

    test('credit notes run in their own gapless sequence', () async {
      for (var i = 0; i < 3; i++) {
        final sale = await sell();
        final found = (await store.findSaleByReceipt(sale.receipt))!;
        await store.processReturn(
          sale: found,
          selections: [ReturnSelection(line: found.lines.single, quantity: 1)],
          refundMethod: RefundMethod.cash,
        );
      }

      final numbers = store.returns.map((r) => r.returnNumber).toList()..sort();
      expect(numbers[0], endsWith('/0001'));
      expect(numbers[1], endsWith('/0002'));
      expect(numbers[2], endsWith('/0003'));
    });
  });

  group('till sessions', () {
    test('a session records what was sold through it', () async {
      await store.startShift(openingFloat: 1000);
      expect(store.openShift, isNotNull);
      expect(store.openShift!.openingFloat, 1000);

      await sell(quantity: 2);

      final live = await store.currentShiftWithTotals();
      expect(live!.saleCount, 1);
      expect(live.cashSales, closeTo(1000, 0.01));
      // Float plus cash taken.
      expect(live.computedExpectedCash, closeTo(2000, 0.01));
    });

    test('paying in and out moves the expected cash', () async {
      await store.startShift(openingFloat: 500);
      await store.recordCashMovement(
        isIn: false,
        amount: 200,
        reason: 'Paid the delivery boy',
      );
      await store.recordCashMovement(
        isIn: true,
        amount: 50,
        reason: 'Change from the bank',
      );

      final live = await store.currentShiftWithTotals();
      expect(live!.paidOut, 200);
      expect(live.paidIn, 50);
      expect(live.computedExpectedCash, closeTo(350, 0.01));
    });

    test('a cash refund comes out of the drawer', () async {
      await store.startShift(openingFloat: 0);
      final sale = await sell();
      final found = (await store.findSaleByReceipt(sale.receipt))!;
      await store.processReturn(
        sale: found,
        selections: [ReturnSelection(line: found.lines.single, quantity: 1)],
        refundMethod: RefundMethod.cash,
      );

      final live = await store.currentShiftWithTotals();
      expect(live!.cashRefunds, closeTo(sale.total, 0.01));
      // Took 500 in and gave 500 back, so the drawer is level again.
      expect(live.computedExpectedCash, closeTo(0, 0.01));
    });

    test('closing records the count and the shortfall', () async {
      await store.startShift(openingFloat: 1000);
      await sell();

      // 100 short of the 1,500 that should be there.
      final closed = await store.endShift(
        countedCash: 1400,
        notes: 'Drawer short',
      );

      expect(closed, isNotNull);
      expect(closed!.isOpen, isFalse);
      expect(closed.expectedCash, closeTo(1500, 0.01));
      expect(closed.closingCount, 1400);
      expect(closed.variance, closeTo(-100, 0.01));
      expect(closed.notes, 'Drawer short');
      expect(store.openShift, isNull);
    });

    test('a balanced drawer shows no difference', () async {
      await store.startShift(openingFloat: 200);
      await sell();
      final closed = await store.endShift(countedCash: 700);

      expect(closed!.variance, closeTo(0, 0.01));
    });

    test('closing with no session open does nothing', () async {
      expect(await store.endShift(countedCash: 100), isNull);
    });

    test('opening twice keeps the first session', () async {
      final first = await store.startShift(openingFloat: 100);
      final second = await store.startShift(openingFloat: 999);

      expect(second!.id, first!.id);
      expect(store.shifts.where((s) => s.isOpen), hasLength(1));
    });
  });
}

ProductRecord _shirt() => ProductRecord(
  id: 0,
  sku: 'SKU-SHIRT',
  name: 'Cotton Shirt',
  category: 'Apparel',
  brand: 'Classy',
  unit: 'pcs',
  stock: 50,
  minimumStock: 2,
  purchasePrice: 300,
  sellingPrice: 500,
  barcode: '111222333',
  location: 'A1',
);
