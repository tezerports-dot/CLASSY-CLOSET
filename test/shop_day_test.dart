import 'package:classy_closet/core/database/app_database.dart';
import 'package:classy_closet/core/services/reports.dart';
import 'package:classy_closet/core/services/retail_store.dart';
import 'package:classy_closet/core/services/returns_and_shifts.dart';
import 'package:classy_closet/core/services/statements.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// One trading day, played out end to end.
///
/// The other test files each prove one feature in isolation. This one proves
/// the features are *joined up*: that receiving a delivery moves the same stock
/// figure the till later sells from, that the sale moves the same drawer the
/// shift reconciles, that a return puts the stock back where the count then
/// finds it, and that the day's reports agree with everything that happened.
///
/// A shop does not experience features one at a time, and this is where a
/// break between two of them shows up.
void main() {
  late AppDatabase db;
  late RetailStore store;

  setUp(() async {
    db = AppDatabase.withExecutor(NativeDatabase.memory());
    store = RetailStore(db);
    await store.initialize();
    await store.login('admin', 'admin123');
    await store.saveStoreProfile(StoreProfile.firstRunDefaults);
  });

  tearDown(() async => db.close());

  // ------------------------------------------------------------- fixtures

  Future<ProductRecord> stockShirt({
    double stock = 0,
    double cost = 300,
    double price = 500,
  }) async {
    await store.saveProduct(
      ProductRecord(
        id: 0,
        sku: 'SH-M-BLUE',
        name: 'Cotton Shirt',
        category: 'Apparel',
        brand: 'Classy',
        unit: 'pcs',
        stock: stock,
        minimumStock: 2,
        purchasePrice: cost,
        sellingPrice: price,
        barcode: '8901234567890',
        location: 'A1',
        size: 'M',
        color: 'Blue',
      ),
    );
    return store.products.single;
  }

  Future<SupplierRecord> supplier() async {
    await store.saveSupplier(
      SupplierRecord(
        id: 0,
        name: 'Surat Textiles',
        phone: '9876500000',
        email: '',
        address: '',
        openingBalance: 0,
        balance: 0,
      ),
    );
    return store.suppliers.first;
  }

  Future<CustomerRecord> regular() async {
    await store.saveCustomer(
      CustomerRecord(
        id: 0,
        name: 'Ramesh Gupta',
        phone: '9811100000',
        email: '',
        address: '',
        creditLimit: 10000,
        openingBalance: 0,
        balance: 0,
      ),
    );
    return store.customers.firstWhere((c) => c.name == 'Ramesh Gupta');
  }

  /// Rings up [quantity] of [product] and takes the money.
  Future<SaleRecord> sell(
    ProductRecord product, {
    int quantity = 1,
    CustomerRecord? customer,
    double? paid,
    String method = 'cash',
  }) async {
    for (var i = 0; i < quantity; i++) {
      store.addToCart(store.products.firstWhere((p) => p.id == product.id));
    }
    final total = store.cartGrandTotal(customer: customer);
    final tendered = paid ?? total;
    return store.checkout(
      customer: customer,
      paid: tendered,
      paymentMethod: method,
      cashAmount: method == 'cash' ? tendered : 0,
      cardAmount: method == 'card' ? tendered : 0,
      upiAmount: method == 'upi' ? tendered : 0,
    );
  }

  // ------------------------------------------------------------ the day

  test(
    'a delivery, a day of selling and a count all agree at the end',
    () async {
      final shirt = await stockShirt(stock: 0);
      final wholesaler = await supplier();

      // --- morning: the delivery arrives -----------------------------------
      await store.receiveStock(
        supplierId: wholesaler.id,
        invoiceNumber: 'ST/4471',
        lines: {shirt.id: const PurchaseLine(quantity: 20, unitCost: 320)},
        paidAmount: 2000,
      );

      var onHand = store.products.single;
      expect(onHand.stock, 20, reason: 'the delivery is on the rail');
      expect(
        onHand.purchasePrice,
        320,
        reason: 'the cost price follows the latest invoice',
      );
      expect(
        store.suppliers.firstWhere((s) => s.id == wholesaler.id).balance,
        closeTo(20 * 320 - 2000, 0.01),
        reason: 'what is still owed for the delivery',
      );

      // --- the till opens ---------------------------------------------------
      await store.startShift(openingFloat: 2000);
      expect(store.openShift, isNotNull);

      // --- selling ----------------------------------------------------------
      final cashSale = await sell(onHand, quantity: 3);
      expect(store.products.single.stock, 17, reason: 'three shirts left');
      expect(
        cashSale.receipt,
        startsWith('CC'),
        reason: "the shop's own prefix",
      );

      await sell(onHand, quantity: 2, method: 'card');
      expect(store.products.single.stock, 15);

      // A regular takes two on account rather than paying now.
      final ramesh = await regular();
      final creditSale = await sell(
        onHand,
        quantity: 2,
        customer: ramesh,
        paid: 0,
      );
      expect(store.products.single.stock, 13);
      expect(
        store.customers.firstWhere((c) => c.id == ramesh.id).balance,
        closeTo(creditSale.total, 0.01),
        reason: 'the unpaid bill lands on their account',
      );

      // --- the regular settles up ------------------------------------------
      await store.recordPartyPayment(
        kind: PartyKind.customer,
        partyId: ramesh.id,
        amount: creditSale.total,
      );
      expect(
        store.customers.firstWhere((c) => c.id == ramesh.id).balance,
        closeTo(0, 0.01),
        reason: 'paying the bill clears the account',
      );

      // --- one comes back ---------------------------------------------------
      final found = (await store.findSaleByReceipt(cashSale.receipt))!;
      await store.processReturn(
        sale: found,
        selections: [ReturnSelection(line: found.lines.single, quantity: 1)],
        refundMethod: RefundMethod.cash,
        reason: 'Wrong size',
      );
      expect(
        store.products.single.stock,
        14,
        reason: 'the returned shirt goes back on the rail',
      );
      expect(store.returns, hasLength(1));
      expect(store.returns.single.saleReceipt, cashSale.receipt);

      // --- an expense -------------------------------------------------------
      await store.saveExpense(
        category: 'Transport',
        title: 'Tempo from the market',
        amount: 450,
      );

      // --- evening: count the rail -----------------------------------------
      // One shirt has gone missing during the day. The count finds it.
      final session = await store.startStocktake();
      await store.recordCount(
        stocktakeId: session.id,
        productId: shirt.id,
        counted: 13,
      );
      final committed = await store.commitStocktake(session.id);

      expect(
        store.products.single.stock,
        13,
        reason: 'the books now match what is actually on the rail',
      );
      expect(
        committed.netValue,
        closeTo(-320, 0.01),
        reason: 'one shirt short, valued at what it cost',
      );

      // --- close the till ---------------------------------------------------
      final live = await store.currentShiftWithTotals();
      final expected = live!.computedExpectedCash;
      final closed = await store.endShift(countedCash: expected);

      expect(
        closed!.variance,
        closeTo(0, 0.01),
        reason: 'counting exactly what the day says should be there balances',
      );
      expect(
        expected,
        greaterThan(2000),
        reason: 'the float plus the cash taken, less the cash refunded',
      );

      // --- the day's report -------------------------------------------------
      final report = await store.buildReports(DateRange.today());
      expect(report.billCount, 3);
      expect(report.returnCount, 1);
      expect(
        report.netSales,
        closeTo(report.grossSales - report.returnsTotal, 0.01),
        reason: 'net sales is what was sold less what came back',
      );
      expect(
        store.expensesBetween(DateRange.today().from, DateRange.today().to),
        450,
      );
    },
  );

  // --------------------------------------------------- individual journeys

  test(
    'a bill held while a customer changes their mind comes back whole',
    () async {
      final shirt = await stockShirt(stock: 10);

      store.addToCart(shirt);
      store.addToCart(shirt);
      store.applyBillDiscount(100);
      final held = await store.holdCurrentBill(label: 'Blue shirt, trial room');

      expect(
        store.cart,
        isEmpty,
        reason: 'the counter is free for the next one',
      );
      expect(store.heldBills, hasLength(1));
      expect(held.itemCount, 2);
      expect(
        store.products.single.stock,
        10,
        reason: 'holding a bill must not move stock — nothing has been sold',
      );

      // Someone else is served in the meantime.
      await sell(shirt, quantity: 1);
      expect(store.products.single.stock, 9);

      await store.recallHeldBill(held.id);
      expect(store.heldBills, isEmpty);
      expect(store.cart, hasLength(1));
      expect(store.cart.single.quantity, 2, reason: 'both shirts came back');
      expect(
        store.cart.single.discount,
        closeTo(100, 0.01),
        reason: 'the discount that was agreed comes back with the bill',
      );
    },
  );

  test(
    'a rupee discount survives to the printed bill and the GST on it',
    () async {
      final shirt = await stockShirt(stock: 10, price: 1000);

      store.addToCart(shirt);
      store.addToCart(shirt);
      expect(store.cartGrossTotal, 2000);

      // "It came to 2,000 — call it 1,800."
      store.applyBillDiscount(200);
      expect(store.cartDiscountTotal, closeTo(200, 0.01));

      final sale = await sell(shirt, quantity: 0, paid: 1800);

      expect(sale.total, closeTo(1800, 0.01), reason: 'what the customer paid');
      expect(sale.discountTotal, closeTo(200, 0.01));
      expect(
        sale.taxableValue + sale.cgst + sale.sgst + sale.igst,
        closeTo(sale.total, 0.01),
        reason:
            'the figures printed on the bill must reconstruct the amount '
            'charged, to the paisa',
      );
    },
  );

  test(
    'money paid out of the drawer shows up when the till is counted',
    () async {
      final shirt = await stockShirt(stock: 5);
      await store.startShift(openingFloat: 1000);

      await sell(shirt, quantity: 1); // + 500 cash
      await store.recordCashMovement(
        isIn: false,
        amount: 300,
        reason: 'Paid the tea stall',
      );

      final live = await store.currentShiftWithTotals();
      expect(
        live!.computedExpectedCash,
        closeTo(1000 + 500 - 300, 0.01),
        reason: 'float plus what was sold for cash, less what was paid out',
      );

      // The shopkeeper counts 50 short.
      final closed = await store.endShift(countedCash: 1150);
      expect(closed!.variance, closeTo(-50, 0.01));
    },
  );

  test(
    'a shop that has not been set up is sent to setup, not to the till',
    () async {
      final fresh = AppDatabase.withExecutor(NativeDatabase.memory());
      final blank = RetailStore(fresh);
      await blank.initialize();

      expect(
        blank.storeProfile,
        isNull,
        reason: 'the router uses this to decide the first screen',
      );
      expect(
        blank.displayStoreName,
        isNotEmpty,
        reason: 'the window title must never be blank, even before setup',
      );

      await fresh.close();
    },
  );
}
