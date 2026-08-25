import 'package:classy_closet/core/database/app_database.dart';
import 'package:classy_closet/core/services/global_search.dart';
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
    await store.saveProduct(
      ProductRecord(
        id: 0,
        sku: 'KRT-01-M',
        name: 'Cotton Kurta',
        category: 'Kurta',
        brand: 'Classy',
        unit: 'pcs',
        stock: 6,
        minimumStock: 1,
        purchasePrice: 450,
        sellingPrice: 899,
        barcode: '890123456789',
        location: 'R1',
        size: 'M',
      ),
    );
  });

  tearDown(() async => db.close());

  test('a garment name finds the garment, not the customer list', () {
    // The whole reason this exists. The old top bar guessed a destination:
    // "Customers if the shop has any, Products otherwise" — and first run
    // seeds a walk-in customer, so the guess was *always* Customers. Typing a
    // garment name landed on an empty customer list, which is what "the
    // search bar stopped working" meant.
    expect(store.customers, isNotEmpty, reason: 'walk-in is seeded on setup');

    final hits = searchEverything(store, 'kurta');

    expect(hits.first.kind, GlobalHitKind.product);
    expect(hits.first.route, '/products');
    expect(hits.first.title, contains('Cotton Kurta'));
  });

  test('the page it sends you to is told what to search for', () {
    // Sending somebody to Products with an empty box is barely better than
    // not moving them at all: the hit carries the unique code, so the
    // destination lands on this one unit rather than everything sharing a word.
    final hit = searchEverything(store, 'kurta').first;
    expect(hit.query, '890123456789');
  });

  test('an exact barcode outranks a partial name match', () async {
    await store.saveProduct(
      ProductRecord(
        id: 0,
        sku: 'SHRT-01-M',
        name: 'Barcode Sample Shirt',
        category: 'Shirt',
        brand: 'Classy',
        unit: 'pcs',
        stock: 2,
        minimumStock: 1,
        purchasePrice: 300,
        sellingPrice: 699,
        barcode: '111111111111',
        location: 'R2',
        size: 'M',
      ),
    );

    final hits = searchEverything(store, '890123456789');
    expect(hits.first.title, contains('Cotton Kurta'));
  });

  test('a bill number finds the bill', () async {
    store.addToCart(store.products.first);
    await store.checkout(paid: 899, cashAmount: 899);
    final receipt = store.sales.first.receipt;

    final hits = searchEverything(store, receipt);
    expect(hits.first.kind, GlobalHitKind.bill);
    expect(hits.first.route, '/sales');
    expect(hits.first.query, receipt);
  });

  test('a phone number finds the customer', () async {
    await store.saveCustomer(
      CustomerRecord(
        id: 0,
        name: 'Aarav Sharma',
        phone: '9812345678',
        email: '',
        address: '',
        creditLimit: 0,
        openingBalance: 0,
        balance: 0,
      ),
    );

    final hits = searchEverything(store, '9812345678');
    expect(hits.first.kind, GlobalHitKind.customer);
    expect(hits.first.route, '/customers');
  });

  test('a typo says so rather than going quiet', () {
    final hits = searchEverything(store, 'zzzznothing');
    expect(hits, hasLength(1));
    expect(hits.single.isActionable, isFalse);
    expect(hits.single.title, contains('Nothing matches'));
  });

  test('an empty box offers nothing', () {
    expect(searchEverything(store, '   '), isEmpty);
  });

  group('the handoff to the destination page', () {
    test('only the addressed page may claim a search', () {
      store.requestSearch('890123456789', '/products');

      // The page that happens to be on screen used to swallow this a moment
      // before the navigation, so the real destination arrived empty.
      expect(store.takeSearchFor('/customers'), isEmpty);
      expect(store.takeSearchFor('/products'), '890123456789');
    });

    test('a claimed search is not handed out twice', () {
      store.requestSearch('kurta', '/products');
      expect(store.takeSearchFor('/products'), 'kurta');
      expect(store.takeSearchFor('/products'), isEmpty);
    });

    test('a page already open is notified', () {
      var notified = 0;
      store.addListener(() => notified++);
      store.requestSearch('kurta', '/products');

      // Without the notification a page only ever read the query once, in
      // initState — so every search after the first did nothing at all when
      // you were already on the destination.
      expect(notified, greaterThan(0));
    });
  });
}
