import 'package:classy_closet/app/di/injection.dart';
import 'package:classy_closet/core/database/app_database.dart';
import 'package:classy_closet/core/services/retail_store.dart';
import 'package:classy_closet/features/products/presentation/products_page.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late RetailStore store;

  setUp(() async {
    await getIt.reset();
    db = AppDatabase.withExecutor(NativeDatabase.memory());
    store = RetailStore(db);
    getIt.registerSingleton<AppDatabase>(db);
    getIt.registerSingleton<RetailStore>(store);
    await store.initialize();
    await store.login('admin', 'admin123');
    for (final (sku, name, barcode) in [
      ('KRT-01-M', 'Cotton Kurta', '890123456789'),
      ('SHRT-01-M', 'Linen Shirt', '890999999999'),
    ]) {
      await store.saveProduct(
        ProductRecord(
          id: 0,
          sku: sku,
          name: name,
          category: 'Apparel',
          brand: 'Classy',
          unit: 'pcs',
          stock: 4,
          minimumStock: 1,
          purchasePrice: 400,
          sellingPrice: 899,
          barcode: barcode,
          location: 'R1',
          size: 'M',
        ),
      );
    }
  });

  tearDown(() async {
    await getIt.reset();
    await db.close();
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: ProductsPage())),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a page opened by a search arrives with the box filled', (
    tester,
  ) async {
    store.requestSearch('890123456789', '/products');
    await pump(tester);

    expect(find.text('890123456789'), findsWidgets);
  });

  testWidgets('a page already open picks up the next search', (tester) async {
    await pump(tester);

    // This is the case that used to do nothing at all: the query was only ever
    // read in initState, so searching again from the top bar while standing on
    // the destination page left the old text sitting in the box.
    store.requestSearch('890999999999', '/products');
    await tester.pumpAndSettle();

    expect(find.text('890999999999'), findsWidgets);
  });

  testWidgets('a search addressed elsewhere is left alone', (tester) async {
    await pump(tester);

    store.requestSearch('INV/2026/0001', '/sales');
    await tester.pumpAndSettle();

    expect(find.text('INV/2026/0001'), findsNothing);
    expect(
      store.takeSearchFor('/sales'),
      'INV/2026/0001',
      reason: 'still waiting for the page it was meant for',
    );
  });
}
