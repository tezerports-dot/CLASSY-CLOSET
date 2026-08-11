import 'package:classy_closet/core/database/app_database.dart';
import 'package:classy_closet/core/services/retail_store.dart';
import 'package:classy_closet/features/products/presentation/widgets/style_matrix_dialog.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late RetailStore store;

  setUp(() async {
    db = AppDatabase.withExecutor(NativeDatabase.memory());
    store = RetailStore(db);
    await store.initialize();
    await store.login('admin', 'admin123');
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> pumpDialog(WidgetTester tester, {StyleRecord? style}) async {
    tester.view.physicalSize = const Size(1800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: StyleMatrixDialog(store: store, style: style),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> fill(WidgetTester tester, String label, String value) async {
    await tester.enterText(
      find.widgetWithText(TextFormField, label).first,
      value,
    );
  }

  testWidgets('opens with a default size run and one colour row', (
    tester,
  ) async {
    await pumpDialog(tester);

    for (final size in ['S', 'M', 'L', 'XL']) {
      expect(find.text(size), findsWidgets, reason: '$size should be a column');
    }
    expect(find.text('4 units'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('saves one design as a grid of individually stocked units', (
    tester,
  ) async {
    await pumpDialog(tester);

    await fill(tester, 'Design code', 'KRT-01');
    await fill(tester, 'Design name', 'Cotton Kurta');
    await fill(tester, 'Cost price', '450');
    await fill(tester, 'Selling price (MRP)', '899');
    await tester.pumpAndSettle();

    // Every cell of the default 4-size run gets three pieces. The finder is
    // re-evaluated each pass because filling a cell removes it from the match.
    for (var i = 0; i < 4; i++) {
      final remaining = find.byWidgetPredicate(
        (w) => w is TextFormField && w.controller?.text == '0',
      );
      if (remaining.evaluate().isEmpty) break;
      await tester.enterText(remaining.first, '3');
      await tester.pumpAndSettle();
    }

    await tester.tap(find.widgetWithText(FilledButton, 'Save design'));
    await tester.pumpAndSettle();

    final style = store.styles.single;
    expect(style.styleCode, 'KRT-01');
    expect(style.sizes, ['S', 'M', 'L', 'XL']);
    expect(style.variants, hasLength(4));
    expect(style.totalStock, 12);
    // Each unit carries its own barcode derived from the design code and size.
    expect(style.variants.map((v) => v.barcode).toSet(), {
      'KRT-01-S',
      'KRT-01-M',
      'KRT-01-L',
      'KRT-01-XL',
    });
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows the GST rate the entered price falls into', (
    tester,
  ) async {
    await pumpDialog(tester);

    // Below the 2,500 threshold, so the lower apparel band.
    await fill(tester, 'Selling price (MRP)', '899');
    await tester.pumpAndSettle();
    expect(find.textContaining('GST 5%'), findsOneWidget);

    // Above it, so the higher band.
    await fill(tester, 'Selling price (MRP)', '3200');
    await tester.pumpAndSettle();
    expect(find.textContaining('GST 18%'), findsOneWidget);
  });

  testWidgets('reopens an existing design with its grid populated', (
    tester,
  ) async {
    await store.saveStyle(
      StyleRecord(
        id: 0,
        styleCode: 'TEE-9',
        name: 'Basic Tee',
        sellingPrice: 499,
        purchasePrice: 200,
      ),
      variants: [
        for (final color in ['Black', 'Navy'])
          for (final size in ['M', 'L'])
            ProductRecord(
              id: 0,
              sku: 'TEE-9-$color-$size',
              name: 'Basic Tee',
              category: '',
              brand: '',
              unit: 'pcs',
              stock: 7,
              minimumStock: 1,
              purchasePrice: 200,
              sellingPrice: 499,
              barcode: 'TEE-9-$color-$size',
              location: '',
              size: size,
              color: color,
            ),
      ],
    );

    await pumpDialog(tester, style: store.styles.single);

    expect(find.text('Black'), findsWidgets);
    expect(find.text('Navy'), findsWidgets);
    expect(find.text('4 units'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
