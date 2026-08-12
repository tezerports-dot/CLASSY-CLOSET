import 'package:classy_closet/core/database/app_database.dart';
import 'package:classy_closet/core/services/reports.dart';
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
        stock: 5,
        minimumStock: 1,
        purchasePrice: 400,
        sellingPrice: 899,
        barcode: 'BC-KRT-M',
        location: 'R1',
      ),
    );
  });

  tearDown(() async => db.close());

  int supplierId() => store.suppliers.single.id;
  ProductRecord kurta() => store.products.single;

  group('receiving stock', () {
    test('adds to stock and records the delivery', () async {
      await store.receiveStock(
        supplierId: supplierId(),
        invoiceNumber: 'MT-1001',
        lines: {kurta().id: const PurchaseLine(quantity: 20, unitCost: 420)},
        paidAmount: 8400,
      );

      expect(store.products.single.stock, 25);
      final purchase = store.purchases.single;
      expect(purchase.invoiceNumber, 'MT-1001');
      expect(purchase.supplierName, 'Mumbai Textiles');
      expect(purchase.total, 8400);
      expect(purchase.outstanding, 0);

      final movements = await db.select(db.inventoryMovements).get();
      expect(
        movements.where((m) => m.movementType == 'purchase').single.quantity,
        20,
      );
    });

    test('the cost price follows the latest delivery', () async {
      expect(kurta().purchasePrice, 400);

      await store.receiveStock(
        supplierId: supplierId(),
        invoiceNumber: 'MT-1002',
        lines: {kurta().id: const PurchaseLine(quantity: 10, unitCost: 455)},
      );

      expect(store.products.single.purchasePrice, 455);
    });

    test('anything unpaid is owed to the supplier', () async {
      await store.receiveStock(
        supplierId: supplierId(),
        invoiceNumber: 'MT-1003',
        lines: {kurta().id: const PurchaseLine(quantity: 10, unitCost: 400)},
        paidAmount: 1500,
      );

      expect(store.purchases.single.outstanding, 2500);
      expect(store.suppliers.single.balance, 2500);
    });

    test('paying in full leaves the supplier square', () async {
      await store.receiveStock(
        supplierId: supplierId(),
        invoiceNumber: 'MT-1004',
        lines: {kurta().id: const PurchaseLine(quantity: 5, unitCost: 400)},
        paidAmount: 2000,
      );

      expect(store.suppliers.single.balance, 0);
    });

    test('the same supplier invoice cannot be entered twice', () async {
      await store.receiveStock(
        supplierId: supplierId(),
        invoiceNumber: 'MT-2001',
        lines: {kurta().id: const PurchaseLine(quantity: 5, unitCost: 400)},
      );

      expect(
        () => store.receiveStock(
          supplierId: supplierId(),
          invoiceNumber: 'MT-2001',
          lines: {kurta().id: const PurchaseLine(quantity: 5, unitCost: 400)},
        ),
        throwsA(isA<StateError>()),
      );
      // Stock did not move on the refused attempt.
      expect(store.products.single.stock, 10);
    });

    test('an empty delivery is refused', () async {
      expect(
        () => store.receiveStock(
          supplierId: supplierId(),
          invoiceNumber: 'MT-3001',
          lines: {kurta().id: const PurchaseLine(quantity: 0, unitCost: 400)},
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('a delivery with no invoice number is refused', () async {
      expect(
        () => store.receiveStock(
          supplierId: supplierId(),
          invoiceNumber: '   ',
          lines: {kurta().id: const PurchaseLine(quantity: 5, unitCost: 400)},
        ),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('expenses', () {
    test('recording one shows up with its category', () async {
      await store.saveExpense(
        category: 'Rent',
        title: 'March shop rent',
        amount: 25000,
        notes: 'Paid by cheque',
      );

      final expense = store.expenses.single;
      expect(expense.title, 'March shop rent');
      expect(expense.category, 'Rent');
      expect(expense.amount, 25000);
      expect(expense.notes, 'Paid by cheque');
      expect(store.expenseCategoryNames, contains('Rent'));
    });

    test('a blank category falls back to General', () async {
      await store.saveExpense(category: '  ', title: 'Tea', amount: 60);

      expect(store.expenses.single.category, 'General');
    });

    test('the same category is reused rather than duplicated', () async {
      await store.saveExpense(category: 'Wages', title: 'Ravi', amount: 9000);
      await store.saveExpense(category: 'Wages', title: 'Sunita', amount: 9500);

      expect(
        store.expenseCategoryNames.where((n) => n == 'Wages'),
        hasLength(1),
      );
      expect(store.expenses, hasLength(2));
    });

    test('a zero or empty entry is refused', () async {
      expect(
        () => store.saveExpense(category: 'Rent', title: 'Nothing', amount: 0),
        throwsA(isA<StateError>()),
      );
      expect(
        () => store.saveExpense(category: 'Rent', title: '  ', amount: 100),
        throwsA(isA<StateError>()),
      );
    });

    test('totals for a period only count that period', () async {
      final month = DateRange.thisMonth();
      await store.saveExpense(
        category: 'Rent',
        title: 'This month',
        amount: 20000,
      );
      await store.saveExpense(
        category: 'Rent',
        title: 'Long ago',
        amount: 18000,
        spentAt: month.from.subtract(const Duration(days: 40)),
      );

      expect(store.expensesBetween(month.from, month.to), 20000);
    });

    test('one can be removed', () async {
      await store.saveExpense(
        category: 'Repairs',
        title: 'Shutter',
        amount: 800,
      );
      await store.deleteExpense(store.expenses.single.id);

      expect(store.expenses, isEmpty);
    });
  });
}
