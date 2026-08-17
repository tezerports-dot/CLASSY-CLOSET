import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:windows_printer/windows_printer.dart';

import 'escpos.dart';

/// How the till gets a bill onto paper.
enum ReceiptPrintMode {
  /// Render a PDF and hand it to the operating system's print dialog. Works
  /// with any printer, needs a click, and is what a shop without a dedicated
  /// till printer uses.
  dialog,

  /// Send ESC/POS straight to a named thermal printer. No dialog, no PDF
  /// rasterising, and the only route that can cut the paper or kick the drawer.
  thermal;

  String get label => this == ReceiptPrintMode.thermal
      ? 'Thermal printer (direct)'
      : 'Print dialog (any printer)';
}

/// Everything about the shop's printing hardware, kept in the settings table so
/// it survives a restart and can differ between the counter PC and the laptop.
@immutable
class PrinterSettings {
  const PrinterSettings({
    this.mode = ReceiptPrintMode.dialog,
    this.printerName,
    this.paper = ThermalPaper.mm80,
    this.copies = 1,
    this.cutAfterPrint = true,
    this.openDrawerOnCashSale = false,
    this.drawerPin = 0,
    this.printBarcodeOnReceipt = true,
    this.printUpiQr = false,
    this.upiVpa = '',
    this.upiPayeeName = '',
  });

  final ReceiptPrintMode mode;

  /// Windows printer name. Null means "whatever Windows calls the default".
  final String? printerName;
  final ThermalPaper paper;
  final int copies;
  final bool cutAfterPrint;

  /// Only cash and split-cash sales pop the drawer; a card-only sale has no
  /// reason to open it.
  final bool openDrawerOnCashSale;

  /// 0 kicks connector pin 2, 1 kicks pin 5. Which one a drawer answers to
  /// depends on its cable, so it is a setting rather than a constant.
  final int drawerPin;
  final bool printBarcodeOnReceipt;

  /// Print a UPI QR on the bill so the customer can scan and pay.
  final bool printUpiQr;
  final String upiVpa;
  final String upiPayeeName;

  bool get isThermal => mode == ReceiptPrintMode.thermal;

  /// A UPI QR is only worth printing once there is a VPA to put in it.
  bool get canPrintUpiQr => printUpiQr && upiVpa.trim().contains('@');

  PrinterSettings copyWith({
    ReceiptPrintMode? mode,
    String? printerName,
    bool clearPrinterName = false,
    ThermalPaper? paper,
    int? copies,
    bool? cutAfterPrint,
    bool? openDrawerOnCashSale,
    int? drawerPin,
    bool? printBarcodeOnReceipt,
    bool? printUpiQr,
    String? upiVpa,
    String? upiPayeeName,
  }) => PrinterSettings(
    mode: mode ?? this.mode,
    printerName: clearPrinterName ? null : (printerName ?? this.printerName),
    paper: paper ?? this.paper,
    copies: copies ?? this.copies,
    cutAfterPrint: cutAfterPrint ?? this.cutAfterPrint,
    openDrawerOnCashSale: openDrawerOnCashSale ?? this.openDrawerOnCashSale,
    drawerPin: drawerPin ?? this.drawerPin,
    printBarcodeOnReceipt: printBarcodeOnReceipt ?? this.printBarcodeOnReceipt,
    printUpiQr: printUpiQr ?? this.printUpiQr,
    upiVpa: upiVpa ?? this.upiVpa,
    upiPayeeName: upiPayeeName ?? this.upiPayeeName,
  );

  Map<String, dynamic> toJson() => {
    'mode': mode.name,
    'printerName': printerName,
    'paper': paper.name,
    'copies': copies,
    'cutAfterPrint': cutAfterPrint,
    'openDrawerOnCashSale': openDrawerOnCashSale,
    'drawerPin': drawerPin,
    'printBarcodeOnReceipt': printBarcodeOnReceipt,
    'printUpiQr': printUpiQr,
    'upiVpa': upiVpa,
    'upiPayeeName': upiPayeeName,
  };

  factory PrinterSettings.fromJson(Map<String, dynamic> json) =>
      PrinterSettings(
        mode: ReceiptPrintMode.values.firstWhere(
          (m) => m.name == json['mode'],
          orElse: () => ReceiptPrintMode.dialog,
        ),
        printerName: (json['printerName'] as String?)?.trim().isEmpty ?? true
            ? null
            : (json['printerName'] as String).trim(),
        paper: ThermalPaper.fromName(json['paper'] as String?),
        copies: (json['copies'] as num?)?.toInt().clamp(1, 5) ?? 1,
        cutAfterPrint: json['cutAfterPrint'] as bool? ?? true,
        openDrawerOnCashSale: json['openDrawerOnCashSale'] as bool? ?? false,
        drawerPin: (json['drawerPin'] as num?)?.toInt() == 1 ? 1 : 0,
        printBarcodeOnReceipt: json['printBarcodeOnReceipt'] as bool? ?? true,
        printUpiQr: json['printUpiQr'] as bool? ?? false,
        upiVpa: (json['upiVpa'] as String? ?? '').trim(),
        upiPayeeName: (json['upiPayeeName'] as String? ?? '').trim(),
      );

  String encode() => jsonEncode(toJson());

  factory PrinterSettings.decode(String json) =>
      PrinterSettings.fromJson(jsonDecode(json) as Map<String, dynamic>);
}

/// What actually pushes bytes at a printer.
///
/// Split out from [PrinterService] so the receipt-building path can be tested
/// on any machine: the tests swap in a transport that records what it was
/// handed instead of talking to a spooler that is not there.
abstract class RawPrinterTransport {
  /// False on macOS, Linux and anywhere else the raw path does not exist. The
  /// UI uses this to explain why direct printing is unavailable rather than
  /// offering a button that cannot work.
  bool get isSupported;

  Future<List<String>> listPrinters();

  Future<bool> sendRaw({String? printerName, required Uint8List data});
}

/// The Windows spooler, reached through the `windows_printer` plugin's
/// RAW datatype so ESC/POS reaches the printer uninterpreted.
class WindowsRawPrinterTransport implements RawPrinterTransport {
  const WindowsRawPrinterTransport();

  @override
  bool get isSupported => !kIsWeb && Platform.isWindows;

  @override
  Future<List<String>> listPrinters() async {
    if (!isSupported) return const [];
    try {
      return await WindowsPrinter.getAvailablePrinters();
    } on Object {
      // A missing plugin registration or a spooler that is not running must not
      // take the settings screen down with it.
      return const [];
    }
  }

  @override
  Future<bool> sendRaw({String? printerName, required Uint8List data}) async {
    if (!isSupported) return false;
    return WindowsPrinter.printRawData(
      printerName: printerName,
      data: data,
      useRawDatatype: true,
    );
  }
}

/// A transport for the platforms that have no raw path. Reports itself
/// unsupported and refuses politely rather than throwing.
class UnsupportedRawPrinterTransport implements RawPrinterTransport {
  const UnsupportedRawPrinterTransport();

  @override
  bool get isSupported => false;

  @override
  Future<List<String>> listPrinters() async => const [];

  @override
  Future<bool> sendRaw({String? printerName, required Uint8List data}) async =>
      false;
}

/// Sends prepared ESC/POS jobs, and answers what hardware is available.
class PrinterService {
  PrinterService({RawPrinterTransport? transport})
    : transport =
          transport ??
          (!kIsWeb && Platform.isWindows
              ? const WindowsRawPrinterTransport()
              : const UnsupportedRawPrinterTransport());

  final RawPrinterTransport transport;

  bool get supportsDirectPrinting => transport.isSupported;

  Future<List<String>> availablePrinters() => transport.listPrinters();

  /// Sends [job] as-is, [copies] times.
  Future<bool> send(
    Uint8List job, {
    String? printerName,
    int copies = 1,
  }) async {
    for (var i = 0; i < copies.clamp(1, 5); i++) {
      final ok = await transport.sendRaw(printerName: printerName, data: job);
      if (!ok) return false;
    }
    return true;
  }

  /// Kicks the drawer without printing anything — the "no sale" button behind
  /// the counter.
  Future<bool> openDrawer(PrinterSettings settings) {
    final builder = EscPosBuilder(paper: settings.paper)
      ..openDrawer(pin: settings.drawerPin);
    return send(builder.bytes(), printerName: settings.printerName);
  }

  /// A page that proves the printer, the cutter and the drawer are all wired
  /// up, so the shop can check the hardware before the first customer.
  Future<bool> printTestPage(PrinterSettings settings) {
    final builder = EscPosBuilder(paper: settings.paper)
      ..line('PRINTER TEST', bold: true, center: true, doubleHeight: true)
      ..feed()
      ..line('Paper width: ${settings.paper.label}')
      ..line('Characters per line: ${settings.paper.columns}')
      ..line('Printer: ${settings.printerName ?? 'Windows default'}')
      ..rule()
      ..line('The line below should reach both edges exactly:')
      ..line('1234567890' * 5)
      ..rule()
      ..columns2('Alignment check', 'RIGHT')
      ..line('Bold text', bold: true)
      ..line('Double height', doubleHeight: true)
      ..line('Rs. 1,234.50 renders as text, not squares')
      ..rule();
    if (settings.printBarcodeOnReceipt) {
      builder.barcode128('TEST123');
    }
    if (settings.canPrintUpiQr) {
      builder
        ..feed()
        ..line('Scan to pay ${settings.upiVpa}', center: true)
        ..qr(
          upiPaymentUri(
            vpa: settings.upiVpa,
            payeeName: settings.upiPayeeName,
            amount: 1,
            note: 'Printer test',
          ),
        );
    }
    builder
      ..feed()
      ..line('Hardware test complete', center: true, bold: true);
    if (settings.openDrawerOnCashSale) {
      builder.openDrawer(pin: settings.drawerPin);
    }
    if (settings.cutAfterPrint) builder.cut();
    return send(builder.bytes(), printerName: settings.printerName);
  }
}

/// Builds the `upi://pay` deep link that goes inside the bill's QR code.
///
/// Parameter names come from the NPCI UPI Linking Specification: `pa` is the
/// payee's VPA and the only mandatory field, `pn` the payee name, `am` the
/// amount, `cu` the currency (INR is the only accepted value) and `tn` a short
/// note. `tr` carries our invoice number so a payment can be matched back to
/// the bill.
///
/// See <https://www.labnol.org/files/linking.pdf> and
/// <https://docs.setu.co/payments/upi-deeplinks>.
String upiPaymentUri({
  required String vpa,
  String payeeName = '',
  double? amount,
  String? note,
  String? reference,
}) {
  final params = <String, String>{
    'pa': vpa.trim(),
    if (payeeName.trim().isNotEmpty) 'pn': payeeName.trim(),
    if (amount != null && amount > 0) 'am': amount.toStringAsFixed(2),
    'cu': 'INR',
    if (note != null && note.trim().isNotEmpty) 'tn': note.trim(),
    if (reference != null && reference.trim().isNotEmpty)
      'tr': reference.trim(),
  };
  final query = params.entries
      .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
      .join('&');
  return 'upi://pay?$query';
}
