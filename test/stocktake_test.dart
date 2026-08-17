import 'package:classy_closet/core/database/app_database.dart';
import 'package:classy_closet/core/services/retail_store.dart';
import 'package:classy_closet/core/services/stocktake.dart';
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
        sku: 'KRT-M',
        name: 'Cotton Kurta',
        category: 'Kurta',
        brand: 'Classy',
        unit: 'pcs',
        stock: 20,
        minimumStock: 1,
        purchasePrice: 400,
        sellingPrice: 899,
        barcode: 'BC-KRT-M',
        location: 'R1',
        size: 'M',
        color: 'Blue',
      ),
    );
    await store.saveProduct(
      ProductRecord(
        id: 0,
        sku: 'KRT-L',
        name: 'Cotton Kurta',
        category: 'Kurta',
        brand: 'Classy',
        unit: 'pcs',
        stock: 12,
        minimumStock: 1,
        purchasePrice: 400,
        sellingPrice: 899,
        barcode: 'BC-KRT-L',
        location: 'R1',
        size: 'L',
        color: 'Blue',
      ),
    );
  });

  tearDown(() async => db.close());

  ProductRecord medium() => store.products.firstWhere((p) => p.size == 'M');
  ProductRecord large() => store.products.firstWhere((p) => p.size == 'L');

  group('running a count', () {
    test('starting one opens a session with a reference', () async {
      final session = await store.startStocktake();

      expect(session.isOpen, isTrue);
      expect(session.reference, matches(RegExp(r'^STK/\d{6}/001$')));
      expect(store.openStocktake?.id, session.id);
      expect(session.lines, isEmpty);
    });

    test('two cannot be open at once', () async {
      await store.startStocktake();

      expect(() => store.startStocktake(), throwsA(isA<StateError>()));
    });

    test('a count records what the books said at that moment', () async {
      final session = await store.startStocktake();

      await store.recordCount(
        stocktakeId: session.id,
        productId: medium().id,
        counted: 18,
      );

      final line = store.openStocktake!.lines.single;
      expect(line.systemQuantity, 20);
      expect(line.countedQuantity, 18);
      expect(line.variance, -2);
      expect(line.varianceValue, -800);
      expect(line.matches, isFalse);
    });

    test('a sale after the count does not become fake shrinkage', () async {
      // The whole reason the system figure is captured per line rather than at
      // commit: the shop keeps trading while someone counts the back rail.
      final session = await store.startStocktake();
      await store.recordCount(
        stocktakeId: session.id,
        productId: medium().id,
        counted: 20,
      );

      store.addToCart(medium());
      await store.checkout(paid: 899, cashAmount: 899);

      expect(store.openStocktake!.lines.single.variance, 0);
    });

    test('counting the same item twice replaces the earlier line', () async {
      final session = await store.startStocktake();

      await store.recordCount(
        stocktakeId: session.id,
        productId: medium().id,
        counted: 15,
      );
      await store.recordCount(
        stocktakeId: session.id,
        productId: medium().id,
        counted: 19,
      );

      expect(store.openStocktake!.lines, hasLength(1));
      expect(store.openStocktake!.lines.single.countedQuantity, 19);
    });

    test('a line can be taken back off', () async {
      final session = await store.startStocktake();
      await store.recordCount(
        stocktakeId: session.id,
        productId: medium().id,
        counted: 15,
      );

      await store.removeCount(stocktakeId: session.id, productId: medium().id);

      expect(store.openStocktake!.lines, isEmpty);
    });

    test('a negative count is refused', () async {
      final session = await store.startStocktake();

      expect(
        () => store.recordCount(
          stocktakeId: session.id,
          productId: medium().id,
          counted: -1,
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('counting against a session that is not open is refused', () async {
      final session = await store.startStocktake();
      await store.abandonStocktake(session.id);

      expect(
        () => store.recordCount(
          stocktakeId: session.id,
          productId: medium().id,
          counted: 5,
        ),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('applying a count', () {
    test('stock becomes what was counted', () async {
      final session = await store.startStocktake();
      await store.recordCount(
        stocktakeId: session.id,
        productId: medium().id,
        counted: 18,
      );
      await store.recordCount(
        stocktakeId: session.id,
        productId: large().id,
        counted: 13,
      );

      await store.commitStocktake(session.id, notes: 'Monthly count');

      expect(medium().stock, 18);
      expect(large().stock, 13);
      expect(store.openStocktake, isNull);
    });

    test('an item nobody counted is left completely alone', () async {
      final session = await store.startStocktake();
      await store.recordCount(
        stocktakeId: session.id,
        productId: medium().id,
        counted: 18,
      );

      await store.commitStocktake(session.id);

      expect(large().stock, 12, reason: 'never counted, never touched');
    });

    test('only the lines that differ leave a movement behind', () async {
      final session = await store.startStocktake();
      await store.recordCount(
        stocktakeId: session.id,
        productId: medium().id,
        counted: 18,
      );
      await store.recordCount(
        stocktakeId: session.id,
        productId: large().id,
        counted: 12,
      );

      await store.commitStocktake(session.id);

      final movements = await (db.select(
        db.inventoryMovements,
      )..where((m) => m.movementType.equals('stocktake'))).get();
      expect(movements, hasLength(1));
      expect(movements.single.quantity, -2);
      expect(movements.single.productId, medium().id);
    });

    test('the shrinkage is valued at cost', () async {
      final session = await store.startStocktake();
      await store.recordCount(
        stocktakeId: session.id,
        productId: medium().id,
        counted: 17,
      );
      await store.recordCount(
        stocktakeId: session.id,
        productId: large().id,
        counted: 14,
      );

      final applied = await store.commitStocktake(session.id);

      expect(applied.shortValue, -1200, reason: '3 short at 400');
      expect(applied.overValue, 800, reason: '2 over at 400');
      expect(applied.netValue, -400);
      expect(applied.discrepancies, hasLength(2));
    });

    test('an empty count cannot be applied', () async {
      final session = await store.startStocktake();

      expect(
        () => store.commitStocktake(session.id),
        throwsA(isA<StateError>()),
      );
    });

    test('applying twice is refused', () async {
      final session = await store.startStocktake();
      await store.recordCount(
        stocktakeId: session.id,
        productId: medium().id,
        counted: 18,
      );
      await store.commitStocktake(session.id);

      expect(
        () => store.commitStocktake(session.id),
        throwsA(isA<StateError>()),
      );
    });

    test('abandoning changes nothing but keeps the record', () async {
      final session = await store.startStocktake();
      await store.recordCount(
        stocktakeId: session.id,
        productId: medium().id,
        counted: 5,
      );

      await store.abandonStocktake(session.id, reason: 'Miscounted the rail');

      expect(medium().stock, 20, reason: 'stock untouched');
      final record = store.stocktakes.single;
      expect(record.status, StocktakeStatus.abandoned);
      expect(record.notes, 'Miscounted the rail');
      expect(record.lines, hasLength(1));
    });

    test('the applied count survives a restart', () async {
      final session = await store.startStocktake();
      await store.recordCount(
        stocktakeId: session.id,
        productId: medium().id,
        counted: 18,
      );
      await store.commitStocktake(session.id, notes: 'End of March');

      final reloaded = RetailStore(db);
      await reloaded.refresh();

      final record = reloaded.stocktakes.single;
      expect(record.status, StocktakeStatus.committed);
      expect(record.notes, 'End of March');
      expect(record.committedAt, isNotNull);
      expect(record.lines.single.countedQuantity, 18);
    });
  });

  group('a one-off adjustment', () {
    test('takes stock off and records why', () async {
      await store.adjustStock(
        productId: medium().id,
        delta: -2,
        reason: 'Damaged in the fitting room',
      );

      expect(medium().stock, 18);
      final movement = await (db.select(
        db.inventoryMovements,
      )..where((m) => m.movementType.equals('adjustment'))).getSingle();
      expect(movement.quantity, -2);
      expect(
        store.auditLogs.any((l) => l.contains('Damaged in the fitting room')),
        isTrue,
      );
    });

    test('can add stock back on', () async {
      await store.adjustStock(
        productId: medium().id,
        delta: 3,
        reason: 'Found behind the counter',
      );

      expect(medium().stock, 23);
    });

    test('cannot push stock below zero', () async {
      expect(
        () => store.adjustStock(
          productId: medium().id,
          delta: -25,
          reason: 'Everything gone',
        ),
        throwsA(isA<StateError>()),
      );
      expect(medium().stock, 20);
    });

    test('needs a reason and a quantity', () async {
      expect(
        () =>
            store.adjustStock(productId: medium().id, delta: -1, reason: '   '),
        throwsA(isA<StateError>()),
      );
      expect(
        () => store.adjustStock(
          productId: medium().id,
          delta: 0,
          reason: 'Nothing',
        ),
        throwsA(isA<StateError>()),
      );
    });
  });
}
