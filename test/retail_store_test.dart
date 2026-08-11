import 'package:classy_closet/core/database/app_database.dart';
import 'package:classy_closet/core/services/retail_store.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Exercises the startup path and a full POS checkout against a real (in-memory)
/// SQLite database, so the Drift schema, the first-run seed and the sale/payment
/// columns are verified without needing the desktop runner.
void main() {
  late AppDatabase db;
  late RetailStore store;

  setUp(() async {
    db = AppDatabase.withExecutor(NativeDatabase.memory());
    store = RetailStore(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('initialize creates the schema and seeds first-run data', () async {
    await store.initialize();

    expect(store.customers.map((c) => c.name), contains('Walk-in Customer'));
    expect(store.unitNames, contains('pcs'));
    expect(
      store.storeProfile,
      isNull,
      reason: 'a fresh install has no store profile yet',
    );
  });

  test(
    'the seeded admin can sign in and a wrong password is rejected',
    () async {
      await store.initialize();

      expect(await store.login('admin', 'wrong'), isFalse);
      expect(store.isAuthenticated, isFalse);

      expect(await store.login('admin', 'admin123'), isTrue);
      expect(store.currentUser?.username, 'admin');
      expect(store.currentUser?.role, UserRole.admin);
    },
  );

  test(
    'saving a store profile persists the receipt prefix across a reload',
    () async {
      await store.initialize();
      await store.saveStoreProfile(
        const StoreProfile(
          storeName: 'Classy Closet',
          currencySymbol: r'$',
          receiptNumberPrefix: 'CC',
        ),
      );

      final reloaded = RetailStore(db);
      await reloaded.refresh();

      expect(reloaded.storeProfile?.storeName, 'Classy Closet');
      expect(reloaded.storeProfile?.receiptNumberPrefix, 'CC');
      expect(reloaded.hasStoreProfile, isTrue);
    },
  );

  test(
    'a split-payment checkout records the sale, splits cash/card and draws down stock',
    () async {
      await store.initialize();
      await store.login('admin', 'admin123');
      await store.saveStoreProfile(
        const StoreProfile(
          storeName: 'Classy Closet',
          currencySymbol: r'$',
          receiptNumberPrefix: 'CC',
        ),
      );
      await store.saveProduct(
        ProductRecord(
          id: 0,
          sku: 'SKU-1',
          name: 'Cotton Shirt',
          category: 'Apparel',
          brand: 'Generic',
          unit: 'pcs',
          stock: 10,
          minimumStock: 2,
          purchasePrice: 6,
          sellingPrice: 10,
          barcode: '111222333',
          location: 'A1',
        ),
      );

      final product = store.products.single;
      store.addToCart(product);
      store.addToCart(product);
      expect(store.cart.single.quantity, 2);

      final sale = await store.checkout(
        paid: 20,
        paymentMethod: 'split',
        cashAmount: 12,
        cardAmount: 8,
      );

      expect(sale.receipt, startsWith('CC-'));
      expect(sale.total, 20);
      expect(sale.profit, 8);
      expect(store.cart, isEmpty);

      final row = await db.select(db.sales).getSingle();
      expect(row.paymentMethod, 'split');
      expect(row.cashAmount, 12);
      expect(row.cardAmount, 8);
      expect(row.grandTotal, 20);
      expect(row.receiptNumber, sale.receipt);

      expect(
        store.products.single.stock,
        8,
        reason: 'two units were sold from a stock of ten',
      );
      final movements = await db.select(db.inventoryMovements).get();
      expect(
        movements.where((m) => m.movementType == 'sale').single.quantity,
        -2,
      );
    },
  );

  test('an unpaid balance is carried onto the customer ledger', () async {
    await store.initialize();
    await store.login('admin', 'admin123');
    await store.saveProduct(
      ProductRecord(
        id: 0,
        sku: 'SKU-2',
        name: 'Wool Scarf',
        category: 'Apparel',
        brand: 'Generic',
        unit: 'pcs',
        stock: 5,
        minimumStock: 1,
        purchasePrice: 10,
        sellingPrice: 25,
        barcode: '444555666',
        location: 'B2',
      ),
    );
    final customer = store.customers.firstWhere(
      (c) => c.name == 'Walk-in Customer',
    );

    store.addToCart(store.products.single);
    await store.checkout(
      customer: customer,
      paid: 10,
      paymentMethod: 'cash',
      cashAmount: 10,
    );

    expect(store.customers.firstWhere((c) => c.id == customer.id).balance, 15);
  });
}
