import 'package:classy_closet/app/di/injection.dart';
import 'package:classy_closet/core/database/app_database.dart';
import 'package:classy_closet/core/services/pos_terminal.dart';
import 'package:classy_closet/core/services/printer_service.dart';
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
    // The till reads the printer service on build; a transport that reports
    // itself unsupported keeps the widget test off the Windows plugin channel.
    getIt.registerSingleton<PrinterService>(
      PrinterService(transport: const UnsupportedRawPrinterTransport()),
    );
    getIt.registerSingleton<PosTerminalService>(
      PosTerminalService(transport: const UnsupportedPosTerminalTransport()),
    );

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
        stock: 3,
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

  /// Finds a control by the label it is wearing, which is how a cashier finds
  /// it too.
  Finder fieldLabelled(String label) => find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.labelText == label,
  );

  /// The catalogue tile for a product, as distinct from the same name on the
  /// bill. The bill fills the counter and the catalogue is the sidebar, so a
  /// bare `find.text` matches the bill line once anything is rung up — the
  /// tile is the one inside an InkWell.
  Finder tileFor(String name) =>
      find.ancestor(of: find.text(name), matching: find.byType(InkWell)).first;

  testWidgets('takes a name and a number rather than picking a customer', (
    tester,
  ) async {
    await pumpPos(tester);

    // A customer buys once, at the counter, and is usually a stranger. The old
    // dropdown made every bill pick from a list of everyone who had ever
    // shopped here, which is the wrong shape for the job.
    expect(fieldLabelled('Customer name (optional)'), findsOneWidget);
    expect(fieldLabelled('Mobile number (optional)'), findsOneWidget);
    expect(find.byType(DropdownButtonFormField<CustomerRecord>), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a cash bill asks for nothing but the garments', (tester) async {
    await pumpPos(tester);

    await tester.tap(tileFor('Cotton Shirt'));
    await tester.pumpAndSettle();

    // Cash tendered and change due are gone: what is tendered and what is owed
    // are the same number, and requiring them to be typed and matched is what
    // used to leave the checkout button dead.
    expect(fieldLabelled('Cash tendered'), findsNothing);
    expect(find.text('Change due'), findsNothing);

    // The checkout button is a FilledButton — active when its onPressed is
    // non-null. This is what the old test used to check with a "cash tendered"
    // field: with the field gone, checking the button directly is the point.
    final checkout = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('Checkout & print'),
        matching: find.byType(FilledButton),
      ),
    );
    expect(
      checkout.onPressed,
      isNotNull,
      reason: 'one garment on the bill is enough to take cash',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('cash needs no transaction reference, card does', (tester) async {
    await pumpPos(tester);
    await tester.tap(tileFor('Cotton Shirt'));
    await tester.pumpAndSettle();

    expect(fieldLabelled('Transaction reference (optional)'), findsNothing);

    await tester.tap(find.text('Card'));
    await tester.pumpAndSettle();

    // With no machine set up the cashier copies the reference off the slip.
    // With one, this box is replaced by the machine's own status.
    expect(fieldLabelled('Transaction reference (optional)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a split bill offers card or UPI, never both', (tester) async {
    await pumpPos(tester);
    await tester.tap(tileFor('Cotton Shirt'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Split'));
    await tester.pumpAndSettle();

    // One cash box and one machine box — the customer walks to the terminal
    // once, and it either takes their card or shows them a QR.
    expect(fieldLabelled('Cash'), findsOneWidget);
    expect(fieldLabelled('On the machine'), findsOneWidget);
    expect(fieldLabelled('UPI'), findsNothing);

    expect(find.text('Card'), findsWidgets);
    expect(find.text('UPI QR'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the bill carries a number before it is rung up', (tester) async {
    await pumpPos(tester);

    // Without a number there is nothing to tie a bill to the database, to the
    // card machine's slip, or to a return three weeks later.
    expect(find.textContaining('Next bill: INV/'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the bill cannot hold more than the rail does', (tester) async {
    await pumpPos(tester);

    // Only the first tap is unambiguous — after that the cart also shows the
    // name. Tap the catalogue tile each time.
    for (var i = 0; i < 5; i++) {
      await tester.tap(tileFor('Cotton Shirt'));
      await tester.pump();
    }
    await tester.pumpAndSettle();

    expect(
      store.cart.single.quantity,
      3,
      reason:
          'three in stock is three on the bill, however many times it is '
          'tapped — this is what stopped stock going to minus seven',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('an unnamed bill is not attached to some other customer', (
    tester,
  ) async {
    // A shop with customers on the books used to have the till silently adopt
    // whichever one sorted first for any bill where nobody typed a name —
    // so a walk-in's purchase landed on a stranger's lifetime spend, and the
    // stranger's state code decided the GST split.
    await store.saveCustomer(
      CustomerRecord(
        id: 0,
        name: 'Aarav Regular',
        phone: '9000000001',
        email: '',
        address: '',
        creditLimit: 0,
        openingBalance: 0,
        balance: 0,
      ),
    );
    await pumpPos(tester);
    await tester.tap(tileFor('Cotton Shirt'));
    await tester.pumpAndSettle();

    await store.checkout(paid: 10, cashAmount: 10);
    await tester.pumpAndSettle();

    // The shop seeds a walk-in record on first run, so assert across every
    // customer rather than a single one: none of them may own this bill.
    for (final c in store.customers) {
      expect(
        c.lifetimeBills,
        0,
        reason: 'nobody typed a name, so ${c.name} must not own this bill',
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('survives a store refresh that replaces the product records', (
    tester,
  ) async {
    await pumpPos(tester);
    await tester.tap(tileFor('Cotton Shirt'));
    await tester.pumpAndSettle();

    // refresh() rebuilds every ProductRecord. A cart line still pointing at
    // the old instance would quote a stale price and a stale stock level.
    await store.refresh();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(store.cart.single.product, same(store.products.single));
  });
}
