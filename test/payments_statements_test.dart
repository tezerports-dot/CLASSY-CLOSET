import 'package:classy_closet/core/database/app_database.dart';
import 'package:classy_closet/core/services/reports.dart';
import 'package:classy_closet/core/services/retail_store.dart';
import 'package:classy_closet/core/services/statements.dart';
import 'package:drift/drift.dart' show Value;
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
    await store.saveCustomer(
      CustomerRecord(
        id: 0,
        name: 'Ramesh Patel',
        phone: '9876500001',
        email: '',
        address: '4 Church Street',
        creditLimit: 20000,
        openingBalance: 0,
        balance: 0,
      ),
    );
    await store.saveSupplier(
      SupplierRecord(
        id: 0,
        name: 'Mumbai Textiles',
        phone: '',
        email: '',
        address: '',
        openingBalance: 0,
        balance: 0,
      ),
    );
    await store.saveProduct(
      ProductRecord(
        id: 0,
        sku: 'KRT-M',
        name: 'Cotton Kurta',
        category: 'Kurta',
        brand: 'Classy',
        unit: 'pcs',
        stock: 20,
        minimumStock: 1,
        purchasePrice: 400,
        sellingPrice: 1000,
        barcode: 'BC-KRT-M',
        location: 'R1',
      ),
    );
  });

  tearDown(() async => db.close());

  CustomerRecord customer() =>
      store.customers.firstWhere((c) => c.name == 'Ramesh Patel');
  SupplierRecord supplier() => store.suppliers.single;

  /// Sells one kurta to Ramesh on credit, leaving [unpaid] outstanding.
  Future<void> sellOnCredit({double paid = 0}) async {
    store.addToCart(store.products.single);
    await store.checkout(
      customer: customer(),
      paid: paid,
      paymentMethod: 'cash',
      cashAmount: paid,
    );
  }

  group('settling a customer balance', () {
    test('a credit sale leaves the customer owing', () async {
      await sellOnCredit();

      expect(customer().balance, 1000);
    });

    test('a payment brings the balance down', () async {
      await sellOnCredit();

      await store.recordPartyPayment(
        kind: PartyKind.customer,
        partyId: customer().id,
        amount: 400,
      );

      expect(customer().balance, 600);
      expect(store.partyPayments.single.amount, 400);
      expect(store.partyPayments.single.partyName, 'Ramesh Patel');
    });

    test('paying the lot clears it', () async {
      await sellOnCredit();

      await store.recordPartyPayment(
        kind: PartyKind.customer,
        partyId: customer().id,
        amount: 1000,
      );

      expect(customer().balance, 0);
    });

    test(
      'vouchers are numbered in sequence within the financial year',
      () async {
        await sellOnCredit();

        final first = await store.recordPartyPayment(
          kind: PartyKind.customer,
          partyId: customer().id,
          amount: 100,
        );
        final second = await store.recordPartyPayment(
          kind: PartyKind.customer,
          partyId: customer().id,
          amount: 100,
        );

        expect(first.reference, matches(RegExp(r'^RCP/\d{4}/0001$')));
        expect(second.reference, matches(RegExp(r'^RCP/\d{4}/0002$')));
      },
    );

    test('money paid out to a supplier gets its own series', () async {
      final payment = await store.recordPartyPayment(
        kind: PartyKind.supplier,
        partyId: supplier().id,
        amount: 500,
      );

      expect(payment.reference, matches(RegExp(r'^PMT/\d{4}/0001$')));
    });

    test('a zero or negative amount is refused', () async {
      expect(
        () => store.recordPartyPayment(
          kind: PartyKind.customer,
          partyId: customer().id,
          amount: 0,
        ),
        throwsA(isA<StateError>()),
      );
      expect(
        () => store.recordPartyPayment(
          kind: PartyKind.customer,
          partyId: customer().id,
          amount: -50,
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('a party that does not exist is refused', () async {
      expect(
        () => store.recordPartyPayment(
          kind: PartyKind.customer,
          partyId: 9999,
          amount: 100,
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('payments survive a restart', () async {
      await store.recordPartyPayment(
        kind: PartyKind.supplier,
        partyId: supplier().id,
        amount: 750,
        method: PaymentMethod.bank,
        notes: 'NEFT ref 8891',
      );

      final reloaded = RetailStore(db);
      await reloaded.refresh();

      final payment = reloaded.partyPayments.single;
      expect(payment.amount, 750);
      expect(payment.method, PaymentMethod.bank);
      expect(payment.notes, 'NEFT ref 8891');
      expect(payment.kind, PartyKind.supplier);
    });
  });

  group('settling a supplier balance', () {
    test('an unpaid delivery leaves the shop owing', () async {
      await store.receiveStock(
        supplierId: supplier().id,
        invoiceNumber: 'MT-9001',
        lines: {
          store.products.single.id: const PurchaseLine(
            quantity: 10,
            unitCost: 400,
          ),
        },
      );

      expect(supplier().balance, 4000);
    });

    test('paying the supplier brings it down', () async {
      await store.receiveStock(
        supplierId: supplier().id,
        invoiceNumber: 'MT-9002',
        lines: {
          store.products.single.id: const PurchaseLine(
            quantity: 10,
            unitCost: 400,
          ),
        },
      );

      await store.recordPartyPayment(
        kind: PartyKind.supplier,
        partyId: supplier().id,
        amount: 2500,
        method: PaymentMethod.cheque,
      );

      expect(supplier().balance, 1500);
    });
  });

  group('the till', () {
    test('cash taken from a customer lands in the open drawer', () async {
      await store.startShift(openingFloat: 1000);
      await sellOnCredit();

      await store.recordPartyPayment(
        kind: PartyKind.customer,
        partyId: customer().id,
        amount: 600,
      );

      final shift = await store.currentShiftWithTotals();
      expect(shift!.paidIn, 600);
      expect(shift.paidOut, 0);
    });

    test('cash handed to a supplier comes out of the drawer', () async {
      await store.startShift(openingFloat: 5000);

      await store.recordPartyPayment(
        kind: PartyKind.supplier,
        partyId: supplier().id,
        amount: 1200,
      );

      final shift = await store.currentShiftWithTotals();
      expect(shift!.paidOut, 1200);
      expect(shift.paidIn, 0);
    });

    test('a bank transfer never touches the drawer', () async {
      await store.startShift(openingFloat: 1000);
      await sellOnCredit();

      await store.recordPartyPayment(
        kind: PartyKind.customer,
        partyId: customer().id,
        amount: 600,
        method: PaymentMethod.bank,
      );

      final shift = await store.currentShiftWithTotals();
      expect(shift!.paidIn, 0);
    });
  });

  group('the running balance', () {
    test('debits add and credits subtract, in date order', () {
      final lines = runningBalance(100, [
        StatementMovement(
          date: DateTime(2026, 3, 5),
          reference: 'B',
          description: 'Payment',
          credit: 200,
        ),
        StatementMovement(
          date: DateTime(2026, 3, 1),
          reference: 'A',
          description: 'Sale',
          debit: 500,
        ),
      ]);

      expect(lines.map((l) => l.reference), ['A', 'B']);
      expect(lines[0].balance, 600);
      expect(lines[1].balance, 400);
    });

    test('an empty account keeps its opening balance', () {
      expect(runningBalance(250, const []), isEmpty);
    });
  });

  group('the statement', () {
    test('closes on the balance the customers screen shows', () async {
      await sellOnCredit();
      await store.recordPartyPayment(
        kind: PartyKind.customer,
        partyId: customer().id,
        amount: 300,
      );

      final statement = await store.buildStatement(
        kind: PartyKind.customer,
        partyId: customer().id,
        range: DateRange.thisFinancialYear(),
      );

      expect(statement.closingBalance, customer().balance);
      expect(statement.closingBalance, 700);
    });

    test('shows the sale as a debit and the payment as a credit', () async {
      await sellOnCredit();
      await store.recordPartyPayment(
        kind: PartyKind.customer,
        partyId: customer().id,
        amount: 300,
      );

      final statement = await store.buildStatement(
        kind: PartyKind.customer,
        partyId: customer().id,
        range: DateRange.thisFinancialYear(),
      );

      expect(statement.totalDebit, 1000);
      expect(statement.totalCredit, 300);
      expect(statement.lines.first.description, 'Sale on credit');
      expect(statement.lines.last.description, contains('Payment received'));
    });

    test('a cash sale never appears — nothing was owed', () async {
      store.addToCart(store.products.single);
      await store.checkout(
        customer: customer(),
        paid: 1000,
        paymentMethod: 'cash',
        cashAmount: 1000,
      );

      final statement = await store.buildStatement(
        kind: PartyKind.customer,
        partyId: customer().id,
        range: DateRange.thisFinancialYear(),
      );

      expect(statement.isEmpty, isTrue);
      expect(statement.closingBalance, 0);
    });

    test(
      'movements outside the window are carried in as the opening',
      () async {
        // A sale two months ago, then a payment today. Asking for this month
        // should open at the old debt rather than starting from zero.
        store.addToCart(store.products.single);
        await store.checkout(customer: customer(), paid: 0);
        await db
            .update(db.sales)
            .write(
              SalesCompanion(
                soldAt: Value(
                  DateTime.now().subtract(const Duration(days: 60)),
                ),
              ),
            );
        await store.refresh();

        await store.recordPartyPayment(
          kind: PartyKind.customer,
          partyId: customer().id,
          amount: 400,
        );

        final statement = await store.buildStatement(
          kind: PartyKind.customer,
          partyId: customer().id,
          range: DateRange.thisMonth(),
        );

        expect(statement.openingBalance, 1000);
        expect(statement.lines, hasLength(1));
        expect(statement.closingBalance, 600);
      },
    );

    test('a supplier statement shows the delivery and the payment', () async {
      await store.receiveStock(
        supplierId: supplier().id,
        invoiceNumber: 'MT-7001',
        lines: {
          store.products.single.id: const PurchaseLine(
            quantity: 5,
            unitCost: 400,
          ),
        },
        paidAmount: 500,
      );
      await store.recordPartyPayment(
        kind: PartyKind.supplier,
        partyId: supplier().id,
        amount: 1000,
      );

      final statement = await store.buildStatement(
        kind: PartyKind.supplier,
        partyId: supplier().id,
        range: DateRange.thisFinancialYear(),
      );

      expect(
        statement.totalDebit,
        1500,
        reason: '2000 delivered less 500 paid',
      );
      expect(statement.totalCredit, 1000);
      expect(statement.closingBalance, supplier().balance);
    });

    test('exports as CSV with an opening and a closing line', () async {
      await sellOnCredit();

      final statement = await store.buildStatement(
        kind: PartyKind.customer,
        partyId: customer().id,
        range: DateRange.thisFinancialYear(),
      );
      final csv = statement.csv();
      final rows = csv.trim().split('\n');

      expect(rows.first, contains('Balance'));
      expect(csv, contains('Opening balance'));
      expect(csv, contains('Closing balance'));
      // Header, opening, one movement, closing.
      expect(rows, hasLength(4));
    });
  });
}
