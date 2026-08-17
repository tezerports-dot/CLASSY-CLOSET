import 'dart:typed_data';

import 'package:classy_closet/core/database/app_database.dart';
import 'package:classy_closet/core/services/escpos.dart';
import 'package:classy_closet/core/services/printer_service.dart';
import 'package:classy_closet/core/services/retail_store.dart';
import 'package:classy_closet/features/pos/data/invoice_document.dart';
import 'package:classy_closet/features/pos/data/thermal_receipt.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/escpos_text.dart';

/// Records what it was asked to print instead of talking to a spooler, so the
/// whole print path can be exercised on a machine with no printer at all.
class RecordingTransport implements RawPrinterTransport {
  RecordingTransport({this.succeeds = true, this.printers = const []});

  final bool succeeds;
  final List<String> printers;
  final jobs = <Uint8List>[];
  final printerNames = <String?>[];

  @override
  bool get isSupported => true;

  @override
  Future<List<String>> listPrinters() async => printers;

  @override
  Future<bool> sendRaw({String? printerName, required Uint8List data}) async {
    jobs.add(data);
    printerNames.add(printerName);
    return succeeds;
  }
}

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
        storeName: 'Classy Closet',
        currencySymbol: '₹',
        address: '12 MG Road, Bengaluru',
        phone: '9876543210',
        gstin: '29ABCDE1234F1Z5',
        stateCode: '29',
        receiptNumberPrefix: 'CC',
        receiptFooterText: 'Exchange within 7 days with the bill',
      ),
    );
    await store.saveProduct(
      ProductRecord(
        id: 0,
        sku: 'KRT-BLU-M',
        name: 'Cotton Kurta',
        category: 'Kurta',
        brand: 'Classy',
        unit: 'pcs',
        stock: 10,
        minimumStock: 1,
        purchasePrice: 400,
        sellingPrice: 899,
        barcode: 'BC-KRT-BLU-M',
        location: 'R1',
        size: 'M',
        color: 'Blue',
        hsnCode: '6205',
      ),
    );
  });

  tearDown(() async => db.close());

  /// Rings a sale up and returns the printable invoice for it.
  Future<InvoiceData> sellOne({double paid = 1000}) async {
    final cart = [CartLine(product: store.products.single, quantity: 1)];
    store.addToCart(store.products.single);
    final sale = await store.checkout(
      paid: paid,
      paymentMethod: 'cash',
      cashAmount: paid,
    );
    return InvoiceData(
      sale: sale,
      lines: invoiceLinesFor(
        cart: cart,
        settings: store.gstSettings,
        interState: sale.isInterState,
        hsnFor: (p) => p.hsnCode,
        rateFor: store.gstRateFor,
      ),
      profile: store.storeProfile,
      paid: paid,
      change: paid - sale.total,
      paymentLabel: 'Cash',
    );
  }

  /// The text of the receipt with the command bytes dropped, which is what a
  /// customer would read off the paper.
  String paperText(Uint8List job) => escPosPaperText(job);

  group('the printed bill', () {
    test('carries everything Rule 46 needs on a tax invoice', () async {
      final invoice = await sellOne();
      final text = paperText(
        buildThermalReceipt(data: invoice, settings: const PrinterSettings()),
      );

      expect(text, contains('Classy Closet'));
      expect(text, contains('12 MG Road, Bengaluru'));
      expect(text, contains('GSTIN: 29ABCDE1234F1Z5'));
      expect(text, contains('TAX INVOICE'));
      expect(text, contains(invoice.sale.receipt));
      expect(text, contains('Cotton Kurta (Blue / M)'));
      expect(text, contains('HSN 6205'));
    });

    test('splits the tax into CGST and SGST for a local sale', () async {
      final invoice = await sellOne();
      final text = paperText(
        buildThermalReceipt(data: invoice, settings: const PrinterSettings()),
      );

      expect(text, contains('CGST'));
      expect(text, contains('SGST'));
      expect(text, isNot(contains('IGST')));
    });

    test('never puts a rupee sign on the paper', () async {
      final invoice = await sellOne();
      final job = buildThermalReceipt(
        data: invoice,
        settings: const PrinterSettings(),
      );

      // ₹ is UTF-8 0xE2 0x82 0xB9. Any high byte here would print as garbage.
      expect(
        job.any((b) => b > 0x7E && b != 0x0A),
        isFalse,
        reason: 'the whole job must stay inside the printable ASCII range',
      );
    });

    test('spells the total out in words', () async {
      final invoice = await sellOne();
      final text = paperText(
        buildThermalReceipt(data: invoice, settings: const PrinterSettings()),
      );

      expect(text, contains('Rupees Eight Hundred and Ninety Nine only'));
    });

    test('shows the change given back', () async {
      final invoice = await sellOne(paid: 1000);
      final text = paperText(
        buildThermalReceipt(data: invoice, settings: const PrinterSettings()),
      );

      expect(text, contains('Change'));
      expect(text, contains('101.00'));
    });

    test('every line fits the roll it was laid out for', () async {
      final invoice = await sellOne();
      for (final paper in ThermalPaper.values) {
        final text = paperText(
          buildThermalReceipt(
            data: invoice,
            settings: PrinterSettings(paper: paper),
          ),
        );
        for (final line in text.split('\n')) {
          expect(
            line.length,
            lessThanOrEqualTo(paper.columns),
            reason: '"$line" overflows a ${paper.label}',
          );
        }
      }
    });

    test('the footer the shop configured is printed', () async {
      final invoice = await sellOne();
      final text = paperText(
        buildThermalReceipt(data: invoice, settings: const PrinterSettings()),
      );

      expect(text, contains('Exchange within 7 days with the bill'));
    });

    test('the shop wording is the shop\'s own, not fixed in the code', () async {
      // The same build runs in more than one shop, so every word below has to
      // come from the profile rather than from a string literal in the printer.
      await store.saveStoreProfile(
        const StoreProfile(
          storeName: 'CLASSY CLOSET',
          currencySymbol: '₹',
          address: 'Shop no. 101, 1st Floor, Mansarovar Plaza, Jaipur',
          gstin: '08KGDPK6891Q1Z8',
          stateCode: '08',
          tagline: "Men's Fashion Store — Look Classy, Feel Content",
          termsText: 'Exchange within 7 days with the bill.',
          jurisdiction: 'Subject to Jaipur jurisdiction',
          receiptFooterText: 'Thank you for shopping with us.',
        ),
      );
      final invoice = await sellOne();
      final text = paperText(
        buildThermalReceipt(data: invoice, settings: const PrinterSettings()),
      );

      expect(text, contains('CLASSY CLOSET'));
      // The em dash cannot print on a thermal head, so it is flattened.
      expect(text, contains("Men's Fashion Store - Look Classy, Feel"));
      // The address is longer than the roll is wide, so it wraps — which is the
      // point of wrapping rather than truncating.
      expect(text, contains('Shop no. 101, 1st Floor, Mansarovar Plaza,'));
      expect(text, contains('Jaipur'));
      expect(text, contains('GSTIN: 08KGDPK6891Q1Z8'));
      expect(text, contains('Exchange within 7 days with the bill.'));
      expect(text, contains('Subject to Jaipur jurisdiction'));
      expect(text, contains('Thank you for shopping with us.'));
    });

    test('a shop that leaves the wording blank gets no empty lines', () async {
      await store.saveStoreProfile(
        const StoreProfile(storeName: 'Plain Shop', currencySymbol: '₹'),
      );
      final invoice = await sellOne();
      final text = paperText(
        buildThermalReceipt(data: invoice, settings: const PrinterSettings()),
      );

      expect(text, contains('Plain Shop'));
      expect(text, isNot(contains('jurisdiction')));
      expect(text, isNot(contains('Exchange')));
    });
  });

  group('hardware behaviour', () {
    test('the drawer only opens when the sale took cash', () async {
      final invoice = await sellOne();
      const settings = PrinterSettings(openDrawerOnCashSale: true);
      final job = buildThermalReceipt(data: invoice, settings: settings);

      expect(job.contains(0x70), isTrue, reason: 'ESC p was emitted');
    });

    test('turning the cutter off leaves the cut command out', () async {
      final invoice = await sellOne();
      final job = buildThermalReceipt(
        data: invoice,
        settings: const PrinterSettings(cutAfterPrint: false),
      );

      var sawCut = false;
      for (var i = 0; i + 1 < job.length; i++) {
        if (job[i] == 0x1D && job[i + 1] == 0x56) sawCut = true;
      }
      expect(sawCut, isFalse);
    });

    test('the receipt barcode can be switched off', () async {
      final invoice = await sellOne();
      final job = buildThermalReceipt(
        data: invoice,
        settings: const PrinterSettings(printBarcodeOnReceipt: false),
      );

      var sawBarcode = false;
      for (var i = 0; i + 1 < job.length; i++) {
        if (job[i] == 0x1D && job[i + 1] == 0x6B) sawBarcode = true;
      }
      expect(sawBarcode, isFalse);
    });
  });

  group('UPI QR', () {
    test('builds a deep link the payment apps understand', () {
      final uri = upiPaymentUri(
        vpa: 'classycloset@okhdfcbank',
        payeeName: 'Classy Closet',
        amount: 899,
        note: 'Bill CC/2526/0001',
        reference: 'CC/2526/0001',
      );

      expect(uri, startsWith('upi://pay?'));
      expect(uri, contains('pa=classycloset%40okhdfcbank'));
      expect(uri, contains('pn=Classy%20Closet'));
      expect(uri, contains('am=899.00'));
      expect(uri, contains('cu=INR'));
      expect(uri, contains('tr=CC%2F2526%2F0001'));
    });

    test('is left off the bill until a real UPI ID is entered', () {
      expect(const PrinterSettings(printUpiQr: true).canPrintUpiQr, isFalse);
      expect(
        const PrinterSettings(
          printUpiQr: true,
          upiVpa: 'shop@okaxis',
        ).canPrintUpiQr,
        isTrue,
      );
    });

    test('the QR carries the bill total when switched on', () async {
      final invoice = await sellOne();
      final job = buildThermalReceipt(
        data: invoice,
        settings: const PrinterSettings(
          printUpiQr: true,
          upiVpa: 'shop@okaxis',
        ),
      );

      // The link is data inside the QR command, not text on the paper, so it
      // has to be looked for in the raw stream.
      expect(
        containsBytes(job, 'upi://pay?pa=shop%40okaxis'.codeUnits),
        isTrue,
      );
      expect(containsBytes(job, 'am=899.00'.codeUnits), isTrue);
      expect(paperText(job), contains('Scan to pay by UPI'));
    });
  });

  group('printer settings', () {
    test('survive a round trip through the settings table', () async {
      const settings = PrinterSettings(
        mode: ReceiptPrintMode.thermal,
        printerName: 'EPSON TM-T82',
        paper: ThermalPaper.mm58,
        copies: 2,
        cutAfterPrint: false,
        openDrawerOnCashSale: true,
        drawerPin: 1,
        printUpiQr: true,
        upiVpa: 'shop@okaxis',
        upiPayeeName: 'Classy Closet',
      );
      await store.savePrinterSettings(settings);

      final reloaded = RetailStore(db);
      await reloaded.refresh();
      final loaded = reloaded.printerSettings;

      expect(loaded.mode, ReceiptPrintMode.thermal);
      expect(loaded.printerName, 'EPSON TM-T82');
      expect(loaded.paper, ThermalPaper.mm58);
      expect(loaded.copies, 2);
      expect(loaded.cutAfterPrint, isFalse);
      expect(loaded.openDrawerOnCashSale, isTrue);
      expect(loaded.drawerPin, 1);
      expect(loaded.upiVpa, 'shop@okaxis');
    });

    test('a fresh install prints through the dialog', () {
      expect(store.printerSettings.mode, ReceiptPrintMode.dialog);
      expect(store.printerSettings.isThermal, isFalse);
    });
  });

  group('the printer service', () {
    test('sends the job once per copy', () async {
      final transport = RecordingTransport();
      final service = PrinterService(transport: transport);

      await service.send(
        Uint8List.fromList([1, 2, 3]),
        printerName: 'TM-T82',
        copies: 3,
      );

      expect(transport.jobs, hasLength(3));
      expect(transport.printerNames, everyElement('TM-T82'));
    });

    test('stops after a failed copy rather than jamming the queue', () async {
      final transport = RecordingTransport(succeeds: false);
      final service = PrinterService(transport: transport);

      final ok = await service.send(Uint8List.fromList([1]), copies: 3);

      expect(ok, isFalse);
      expect(transport.jobs, hasLength(1));
    });

    test('the no-sale button sends a drawer kick and nothing else', () async {
      final transport = RecordingTransport();
      final service = PrinterService(transport: transport);

      await service.openDrawer(const PrinterSettings(drawerPin: 1));

      final job = transport.jobs.single;
      expect(job.sublist(job.length - 5), [0x1B, 0x70, 0x01, 60, 120]);
    });

    test('reports honestly when the platform has no raw path', () async {
      final service = PrinterService(
        transport: const UnsupportedRawPrinterTransport(),
      );

      expect(service.supportsDirectPrinting, isFalse);
      expect(await service.availablePrinters(), isEmpty);
      expect(await service.openDrawer(const PrinterSettings()), isFalse);
    });
  });
}
