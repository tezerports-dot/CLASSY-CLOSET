import 'package:classy_closet/core/database/app_database.dart';
import 'package:classy_closet/core/services/escpos.dart';
import 'package:classy_closet/core/services/printer_service.dart';
import 'package:classy_closet/core/services/retail_store.dart';
import 'package:classy_closet/core/utils/formatters.dart';
import 'package:classy_closet/features/pos/data/invoice_document.dart';
import 'package:classy_closet/features/pos/data/thermal_receipt.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/escpos_text.dart';

/// A thermal printer does not truncate a line that is too long — it wraps it.
///
/// So a bill laid out for 48 columns and sent to a 42-column head prints the
/// tail of every amount on the line underneath its own label, and the whole
/// bill reads as a ragged list instead of two columns. Nothing about that is
/// visible from the bytes alone; it only shows on paper, which is why it
/// survived every previous test. These assert the width the bill is laid out
/// to, at each column count the shop can select.
void main() {
  late AppDatabase db;
  late RetailStore store;

  setUp(() async {
    db = AppDatabase.withExecutor(NativeDatabase.memory());
    store = RetailStore(db);
    await store.initialize();
    await store.login('admin', 'admin123');
    await store.saveStoreProfile(
      const StoreProfile(
        storeName: 'CLASSY CLOSET',
        currencySymbol: '₹',
        gstin: '29ABCDE1234F1Z5',
        stateCode: '29',
        address: '12 Linking Road, Bandra West, Mumbai 400050',
        phone: '+91 98200 11223',
      ),
    );
    for (final (sku, name, price) in [
      ('KRT', 'Cotton Kurta', 1500.0),
      ('SHW', 'Sherwani Classic', 4200.0),
    ]) {
      await store.saveProduct(
        ProductRecord(
          id: 0,
          sku: sku,
          name: name,
          category: 'Apparel',
          brand: 'Classy',
          unit: 'pcs',
          stock: 20,
          minimumStock: 1,
          purchasePrice: price / 3,
          sellingPrice: price,
          barcode: 'BC-$sku',
          location: 'R1',
          size: 'M',
        ),
      );
    }
  });

  tearDown(() async => db.close());

  Future<InvoiceData> ringUp() async {
    for (final p in store.products) {
      store.addToCart(p);
    }
    store.applyBillDiscount(500);
    final totals = store.cartTotals();
    final lines = invoiceLinesFor(
      cart: store.cart,
      settings: store.gstSettings,
      interState: false,
      hsnFor: (_) => '6103',
      rateFor: store.gstRateFor,
      billDiscount: store.billDiscount,
    );
    final sale = await store.checkout(
      paid: totals.total,
      cashAmount: totals.total,
    );
    return InvoiceData(
      sale: sale,
      lines: lines,
      profile: store.storeProfile,
      paid: totals.total,
      change: 0,
      paymentLabel: 'Paid by cash',
      customerName: 'Aarav Sharma',
      customerPhone: '9812345678',
    );
  }

  List<String> paperLines(InvoiceData data, PrinterSettings settings) =>
      escPosPaperText(
        buildThermalReceipt(data: data, settings: settings),
      ).split('\n');

  group('nothing is laid out wider than the printer', () {
    for (final (label, settings) in [
      ('57 mm', const PrinterSettings(paper: ThermalPaper.mm57)),
      ('80 mm', const PrinterSettings(paper: ThermalPaper.mm80)),
      (
        '80 mm head that only fits 42',
        const PrinterSettings(paper: ThermalPaper.mm80, charactersPerLine: 42),
      ),
      (
        '57 mm head that only fits 30',
        const PrinterSettings(paper: ThermalPaper.mm57, charactersPerLine: 30),
      ),
    ]) {
      test(label, () async {
        final data = await ringUp();
        final width = settings.effectiveColumns;
        for (final line in paperLines(data, settings)) {
          expect(
            line.length,
            lessThanOrEqualTo(width),
            reason:
                'the printer wraps rather than truncates, so "$line" would '
                'drop its tail onto the next line',
          );
        }
      });
    }
  });

  test('the amount stays on the same line as its label', () async {
    final data = await ringUp();
    const settings = PrinterSettings(
      paper: ThermalPaper.mm80,
      charactersPerLine: 42,
    );

    final total = paperLines(
      data,
      settings,
    ).firstWhere((l) => l.trimLeft().startsWith('TOTAL'));
    expect(
      total,
      contains(AppFormatters.amount(data.sale.total)),
      reason: 'label and amount belong on one line — that is the whole point',
    );
  });

  test('the totals sit in from both edges on a wide roll', () async {
    final data = await ringUp();
    const settings = PrinterSettings(paper: ThermalPaper.mm80);

    final total = paperLines(
      data,
      settings,
    ).firstWhere((l) => l.trimLeft().startsWith('TOTAL'));
    expect(
      total.startsWith(' '),
      isTrue,
      reason: 'totals spread edge to edge read as two lists, not one bill',
    );
    expect(total.trimRight().length, lessThan(settings.effectiveColumns));
  });

  test(
    'the heading reads as centred phrases, not a two-column table',
    () async {
      final data = await ringUp();
      final lines = paperLines(
        data,
        const PrinterSettings(paper: ThermalPaper.mm80),
      );

      // "Invoice: INV/..." on one short line rather than the label and the
      // number pinned to opposite edges of the paper.
      final invoice = lines.firstWhere((l) => l.startsWith('Invoice'));
      expect(invoice, startsWith('Invoice: '));
      expect(invoice.length, lessThan(40));
    },
  );

  test('an unusable column count cannot be configured into the bill', () {
    // Clamped, so a stray value cannot produce a zero-width or absurd layout.
    expect(EscPosBuilder(columns: 2).columns, greaterThanOrEqualTo(20));
    expect(EscPosBuilder(columns: 500).columns, lessThanOrEqualTo(96));
  });
}
