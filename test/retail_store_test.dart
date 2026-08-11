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

      // Gapless sequence within the Indian financial year, per Rule 46.
      expect(sale.receipt, matches(RegExp(r'^CC/\d{4}/0001$')));
      expect(sale.total, 20);
      // Shelf prices include GST, so profit is measured on the taxable value:
      // 20 gross at 5% is 19.05 taxable, less 12 cost.
      expect(sale.profit, closeTo(7.05, 0.01));
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

  test('invoice numbers run in an unbroken sequence', () async {
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

    final numbers = <String>[];
    for (var i = 0; i < 3; i++) {
      store.addToCart(store.products.single);
      numbers.add((await store.checkout(paid: 500, cashAmount: 500)).receipt);
    }

    expect(numbers[0], endsWith('/0001'));
    expect(numbers[1], endsWith('/0002'));
    expect(numbers[2], endsWith('/0003'));
    expect(numbers.toSet(), hasLength(3));
    // Rule 46 caps the invoice number at 16 characters.
    expect(numbers.every((n) => n.length <= 16), isTrue);
  });

  test(
    'a style saves its whole size and colour run as separate units',
    () async {
      await store.initialize();
      await store.login('admin', 'admin123');

      final styleId = await store.saveStyle(
        StyleRecord(
          id: 0,
          styleCode: 'CC-KURTA-01',
          name: 'Cotton Kurta',
          category: 'Kurta',
          brand: 'Classy',
          unit: 'pcs',
          hsnCode: '6206',
          sellingPrice: 899,
          purchasePrice: 450,
        ),
        variants: [
          for (final color in ['Blue', 'Red'])
            for (final size in ['S', 'M', 'L'])
              ProductRecord(
                id: 0,
                sku: 'CC-KURTA-01-$color-$size',
                name: 'Cotton Kurta',
                category: 'Kurta',
                brand: 'Classy',
                unit: 'pcs',
                stock: 4,
                minimumStock: 1,
                purchasePrice: 450,
                sellingPrice: 899,
                barcode: 'BC-$color-$size',
                location: 'R1',
                size: size,
                color: color,
              ),
        ],
      );

      expect(styleId, greaterThan(0));
      final style = store.styles.single;
      expect(style.styleCode, 'CC-KURTA-01');
      expect(style.variants, hasLength(6));
      expect(style.sizes, ['S', 'M', 'L']);
      expect(style.colors, ['Blue', 'Red']);
      expect(style.totalStock, 24);
      expect(style.variantAt('Blue', 'M')?.sku, 'CC-KURTA-01-Blue-M');
      expect(
        style.variantAt('Blue', 'M')?.displayName,
        'Cotton Kurta (Blue / M)',
      );
      // The HSN code set on the design flows down to every unit under it.
      expect(store.products.every((p) => p.hsnCode == '6206'), isTrue);
    },
  );

  test(
    'removing a cell from the matrix retires it instead of deleting it',
    () async {
      await store.initialize();
      await store.login('admin', 'admin123');

      ProductRecord cell(String size) => ProductRecord(
        id: 0,
        sku: 'ST-$size',
        name: 'Tee',
        category: 'Tops',
        brand: 'Classy',
        unit: 'pcs',
        stock: 2,
        minimumStock: 1,
        purchasePrice: 100,
        sellingPrice: 300,
        barcode: 'BC-$size',
        location: '',
        size: size,
        color: 'Black',
      );

      final style = StyleRecord(id: 0, styleCode: 'ST-1', name: 'Tee');
      final id = await store.saveStyle(
        style,
        variants: [cell('S'), cell('M'), cell('L')],
      );
      expect(store.styles.single.variants, hasLength(3));

      await store.saveStyle(
        StyleRecord(id: id, styleCode: 'ST-1', name: 'Tee'),
        variants: [cell('S'), cell('M')],
      );

      expect(store.styles.single.variants, hasLength(2));
      // The retired row is still on disk so old sale lines keep resolving.
      final allRows = await db.select(db.products).get();
      expect(allRows, hasLength(3));
      expect(allRows.where((r) => !r.isActive), hasLength(1));
    },
  );

  test(
    'a buyer in another state is charged IGST instead of CGST and SGST',
    () async {
      await store.initialize();
      await store.login('admin', 'admin123');
      await store.saveStoreProfile(
        const StoreProfile(
          storeName: 'Classy Closet',
          currencySymbol: '₹',
          gstin: '27AAPFU0939F1ZV', // Maharashtra
        ),
      );
      await store.saveProduct(_shirt());
      await store.saveCustomer(
        CustomerRecord(
          id: 0,
          name: 'Outstation Buyer',
          phone: '',
          email: '',
          address: '',
          creditLimit: 0,
          openingBalance: 0,
          balance: 0,
          gstin: '29AAPFU0939F1ZV', // Karnataka
        ),
      );
      final buyer = store.customers.firstWhere(
        (c) => c.name == 'Outstation Buyer',
      );

      store.addToCart(store.products.single);
      final sale = await store.checkout(
        customer: buyer,
        paid: 500,
        cashAmount: 500,
      );

      expect(sale.isInterState, isTrue);
      expect(sale.igst, greaterThan(0));
      expect(sale.cgst, 0);
      expect(sale.sgst, 0);
      expect(sale.customerGstin, '29AAPFU0939F1ZV');
      expect(sale.placeOfSupply, '29');
    },
  );

  test(
    'period summaries roll up sales, profit and the payment split',
    () async {
      await store.initialize();
      await store.login('admin', 'admin123');
      await store.saveProduct(_shirt());

      store.addToCart(store.products.single);
      await store.checkout(paid: 500, paymentMethod: 'cash', cashAmount: 500);
      store.addToCart(store.products.single);
      await store.checkout(paid: 500, paymentMethod: 'card', cardAmount: 500);

      final today = store.todaySummary;
      expect(today.count, 2);
      expect(today.total, closeTo(1000, 0.01));
      expect(today.cash, closeTo(500, 0.01));
      expect(today.card, closeTo(500, 0.01));
      // Two shirts at 500 inclusive of 5%: 952.38 taxable less 600 cost.
      expect(today.profit, closeTo(352.38, 0.05));
      expect(store.monthSummary.count, 2);
    },
  );
}

/// A single 500-rupee shirt, which sits in the 5% slab.
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
