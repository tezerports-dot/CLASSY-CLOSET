import 'package:classy_closet/app/di/injection.dart';
import 'package:classy_closet/core/database/app_database.dart';
import 'package:classy_closet/core/services/retail_store.dart';
import 'package:classy_closet/features/pos/data/repositories/pos_repository.dart';
import 'package:classy_closet/features/pos/presentation/pos_page.dart';
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
    getIt.registerSingleton<PosRepository>(PosRepository(store));

    await store.initialize();
    await store.login('admin', 'admin123');
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
  });

  tearDown(() async {
    await getIt.reset();
    await db.close();
  });

  Future<void> pumpPos(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: PosPage())));
    await tester.pumpAndSettle();
  }

  testWidgets('defaults the customer to Walk-in Customer', (tester) async {
    await pumpPos(tester);

    expect(find.text('Walk-in Customer'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('adding to the cart auto-fills the cash tendered without a setState-during-build crash', (tester) async {
    await pumpPos(tester);

    await tester.tap(find.text('Cotton Shirt'));
    await tester.pumpAndSettle();

    // The auto-fill runs from build(), and the controller it writes to has a
    // listener that calls setState, so it has to be deferred past the frame.
    expect(tester.takeException(), isNull);

    final cashField = tester.widget<TextField>(
      find.byWidgetPredicate((w) => w is TextField && w.decoration?.labelText == 'Cash tendered'),
    );
    expect(cashField.controller?.text, '10.00');
    expect(store.cart.single.quantity, 1);
  });

  testWidgets('survives a store refresh that replaces the customer records', (tester) async {
    await pumpPos(tester);

    // refresh() rebuilds `customers` with new instances. If the page kept holding
    // the previous instance, the dropdown value would no longer match any of its
    // items and DropdownButtonFormField's assertion would fire.
    await store.refresh();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Walk-in Customer'), findsOneWidget);
  });
}
