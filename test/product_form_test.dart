import 'package:classy_closet/core/database/app_database.dart';
import 'package:classy_closet/core/services/retail_store.dart';
import 'package:classy_closet/features/products/presentation/widgets/product_form_dialog.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The add-product form, at the width it actually opens at.
///
/// Category, Brand and Unit each used to be a dropdown and a text box sharing
/// one controller inside a quarter of the dialog. The dropdowns had no
/// `isExpanded`, so a real category name overflowed by 150-odd pixels and
/// painted over the box beside it — taps meant for the text field, and for the
/// supplier dropdown next door, landed on the overflowing dropdown instead.
/// From the counter that reads as "the input does not accept anything".
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
        name: 'Surat Textiles Wholesale Pvt Ltd',
        phone: '9000000002',
        email: '',
        address: '',
        openingBalance: 0,
        balance: 0,
      ),
    );
    // Long names are the case that overflowed.
    await store.saveProduct(
      ProductRecord(
        id: 0,
        sku: 'X-1',
        name: 'Existing',
        category: 'Kurta & Pyjama Sets',
        brand: 'Manyavar Mohey',
        unit: 'pcs',
        stock: 1,
        minimumStock: 0,
        purchasePrice: 10,
        sellingPrice: 20,
        barcode: 'X-1',
        location: '',
        supplier: 'Surat Textiles Wholesale Pvt Ltd',
      ),
    );
    await store.refresh();
  });

  tearDown(() async => db.close());

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(child: ProductFormDialog(store: store)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder editableFor(String label) => find.descendant(
    of: find
        .ancestor(of: find.text(label), matching: find.byType(TextFormField))
        .first,
    matching: find.byType(EditableText),
  );

  testWidgets('lays out with no overflow at its real dialog width', (
    tester,
  ) async {
    await pump(tester);
    expect(
      tester.takeException(),
      isNull,
      reason:
          'an overflowing control paints over the one next to it, and '
          'swallows the taps meant for it',
    );
  });

  testWidgets('a new category can be typed and is kept', (tester) async {
    await pump(tester);
    await tester.enterText(editableFor('Category'), 'Sherwani');
    await tester.pumpAndSettle();

    expect(
      tester.widget<EditableText>(editableFor('Category')).controller.text,
      'Sherwani',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('an existing brand can be picked from the suggestions', (
    tester,
  ) async {
    await pump(tester);
    await tester.enterText(editableFor('Brand'), 'Many');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Manyavar Mohey').last);
    await tester.pumpAndSettle();

    expect(
      tester.widget<EditableText>(editableFor('Brand')).controller.text,
      'Manyavar Mohey',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('picking a supplier sticks', (tester) async {
    await pump(tester);

    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Surat Textiles Wholesale Pvt Ltd').last);
    await tester.pumpAndSettle();

    expect(find.text('Surat Textiles Wholesale Pvt Ltd'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
