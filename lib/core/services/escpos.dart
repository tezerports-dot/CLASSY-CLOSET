/// Builds ESC/POS command streams for thermal receipt printers.
///
/// This is deliberately plain Dart with no plugin dependency: the bytes it
/// produces are the whole contract with the printer, so they can be asserted on
/// in a normal test run without a printer, a Windows box or a spooler.
///
/// Commands follow the Epson ESC/POS command set, which the generic Chinese
/// 58 mm and 80 mm printers sold in India implement:
///
///   ESC @        (1B 40)          initialise
///   ESC t n      (1B 74 n)        select character code table, 0 = PC437
///   ESC a n      (1B 61 n)        justification, 0 left / 1 centre / 2 right
///   ESC E n      (1B 45 n)        emphasis (bold)
///   ESC - n      (1B 2D n)        underline
///   GS  ! n      (1D 21 n)        character size, ((w-1) << 4) | (h-1)
///   ESC d n      (1B 64 n)        print and feed n lines
///   GS  V m      (1D 56 m)        cut, m = 0 full / 1 partial
///   ESC p m t1 t2(1B 70 ..)       drawer kick pulse, t in units of 2 ms
///   GS  h n      (1D 68 n)        barcode height
///   GS  w n      (1D 77 n)        barcode module width
///   GS  H n      (1D 48 n)        where to print the human readable digits
///   GS  k m n d  (1D 6B ..)       print barcode
///   GS  ( k ...  (1D 28 6B ..)    QR code, functions 165/167/169/180/181
///
/// See the command reference at
/// <https://download4.epson.biz/sec_pubs/pos/reference_en/escpos/index.html>,
/// the quick reference at
/// <http://www.novopos.ch/client/EPSON/TM-T20/TM-T20_eng_qr.pdf> and the
/// summary at <https://github.com/portixhq/escpos-cheatsheet>.
library;

import 'dart:typed_data';

/// Roll width, expressed as the number of characters that fit on one line in
/// the printer's default font. Those two counts are what the layout code needs;
/// millimetres never enter into it.
enum ThermalPaper {
  mm58(32, 384, '57 mm roll'),
  mm80(48, 576, '80 mm roll');

  const ThermalPaper(this.columns, this.dots, this.label);

  /// Characters per line at normal width.
  final int columns;

  /// Printable width in dots, which is what an image has to be sized to.
  /// 384 and 576 are the two standard head widths.
  final int dots;
  final String label;

  static ThermalPaper fromName(String? name) => ThermalPaper.values.firstWhere(
    (p) => p.name == name,
    orElse: () => ThermalPaper.mm80,
  );
}

/// Horizontal placement of a cell inside [EscPosBuilder.row].
enum CellAlign { left, right }

/// Error correction level for [EscPosBuilder.qr]. Higher survives more damage
/// at the cost of a denser symbol.
enum QrErrorCorrection {
  low(48),
  medium(49),
  quartile(50),
  high(51);

  const QrErrorCorrection(this.value);
  final int value;
}

class EscPosBuilder {
  EscPosBuilder({this.paper = ThermalPaper.mm80}) {
    _initialise();
  }

  final ThermalPaper paper;
  final _bytes = <int>[];

  static const _esc = 0x1B;
  static const _gs = 0x1D;
  static const _lf = 0x0A;

  /// Page 0 is PC437, the table every ESC/POS printer implements and the one
  /// its factory default already selects. Everything this builder emits is
  /// transliterated into the 0x20..0x7E range, which PC437 shares with ASCII,
  /// so the selection is belt and braces against a printer left on another page
  /// by earlier software.
  static const codePagePc437 = 0;

  void _initialise() {
    _bytes
      ..addAll([_esc, 0x40])
      ..addAll([_esc, 0x74, codePagePc437]);
  }

  /// The finished command stream.
  Uint8List bytes() => Uint8List.fromList(_bytes);

  /// Number of bytes queued so far. Handy in tests and for a size sanity check
  /// before handing the job to the spooler.
  int get length => _bytes.length;

  // ------------------------------------------------------------------- text

  /// Prints [text] as one line, wrapping at the roll width rather than letting
  /// the printer chop the tail off.
  ///
  /// Double width halves how much fits, which is why wrapping consults the
  /// style instead of always using [ThermalPaper.columns].
  void line(
    String text, {
    bool bold = false,
    bool underline = false,
    bool center = false,
    bool right = false,
    bool doubleHeight = false,
    bool doubleWidth = false,
  }) {
    final width = doubleWidth ? paper.columns ~/ 2 : paper.columns;
    _align(center ? 1 : (right ? 2 : 0));
    _emphasis(bold);
    _underline(underline);
    _size(doubleWidth: doubleWidth, doubleHeight: doubleHeight);
    for (final part in wrap(text, width)) {
      _bytes
        ..addAll(encodeText(part))
        ..add(_lf);
    }
    _resetStyle();
  }

  /// A blank line, or [lines] of them.
  void feed([int lines = 1]) {
    if (lines <= 0) return;
    _bytes.addAll([_esc, 0x64, lines.clamp(1, 255)]);
  }

  /// A full-width horizontal rule.
  void rule([String char = '-']) {
    _align(0);
    _bytes
      ..addAll(encodeText(char * paper.columns))
      ..add(_lf);
  }

  /// A label on the left and a value pushed hard against the right margin.
  ///
  /// When the two cannot both fit, the label is what gives way: the amount is
  /// the part a customer checks.
  void columns2(String left, String right, {bool bold = false}) {
    row(
      [left, right],
      [paper.columns - right.length, right.length],
      aligns: const [CellAlign.left, CellAlign.right],
      bold: bold,
    );
  }

  /// A row of fixed-width cells. Widths must sum to at most the roll width;
  /// anything left over pads the last cell.
  void row(
    List<String> cells,
    List<int> widths, {
    List<CellAlign>? aligns,
    bool bold = false,
  }) {
    assert(cells.length == widths.length, 'one width per cell');
    final buffer = StringBuffer();
    for (var i = 0; i < cells.length; i++) {
      final width = widths[i].clamp(0, paper.columns);
      if (width == 0) continue;
      final align = aligns == null || i >= aligns.length
          ? CellAlign.left
          : aligns[i];
      buffer.write(_fit(cells[i], width, align));
    }
    _align(0);
    _emphasis(bold);
    _bytes
      ..addAll(encodeText(_clip(buffer.toString(), paper.columns)))
      ..add(_lf);
    _resetStyle();
  }

  // --------------------------------------------------------------- graphics

  /// A Code 128 barcode, used on the receipt so a return can be scanned back in
  /// rather than typed.
  ///
  /// `GS k 73` takes an explicit length rather than a null terminator, which is
  /// what lets the data contain any printable byte.
  void barcode128(
    String data, {
    int height = 60,
    int moduleWidth = 2,
    bool showText = true,
  }) {
    final payload = encodeText(data);
    if (payload.isEmpty || payload.length > 255) return;
    _align(1);
    _bytes
      ..addAll([_gs, 0x48, showText ? 2 : 0]) // digits below the bars
      ..addAll([_gs, 0x68, height.clamp(1, 255)])
      ..addAll([_gs, 0x77, moduleWidth.clamp(2, 6)])
      ..addAll([_gs, 0x6B, 73, payload.length])
      ..addAll(payload)
      ..add(_lf);
    _align(0);
  }

  /// Prints a 1-bit raster image — the shop's logo at the head of the bill.
  ///
  /// [rows] holds one entry per scan line, each already packed 8 dots to a
  /// byte, most significant bit leftmost, a set bit meaning a black dot. All
  /// rows must be the same length.
  ///
  /// `GS v 0` is what the generic 58 mm and 80 mm printers sold in India
  /// implement. Epson's own reference marks it obsolete in favour of
  /// `GS ( L`, but the newer command is not present on the cheap hardware this
  /// runs against, and there is no printer here to verify a fallback against —
  /// so the widely-implemented command is the one emitted.
  void rasterImage(List<List<int>> rows) {
    if (rows.isEmpty) return;
    final bytesPerRow = rows.first.length;
    if (bytesPerRow == 0) return;
    if (rows.any((r) => r.length != bytesPerRow)) return;
    final height = rows.length;

    _align(1);
    _bytes.addAll([
      _gs,
      0x76,
      0x30,
      0x00, // normal scale
      bytesPerRow & 0xFF,
      (bytesPerRow >> 8) & 0xFF,
      height & 0xFF,
      (height >> 8) & 0xFF,
    ]);
    for (final row in rows) {
      _bytes.addAll(row);
    }
    _align(0);
  }

  /// A QR code — used for the UPI payment link, so the customer can scan the
  /// bill and pay rather than being read a VPA out loud.
  ///
  /// The five sub-commands have to arrive in this order: select the model,
  /// set the module size, set the error correction, store the data, print it.
  void qr(
    String data, {
    int moduleSize = 6,
    QrErrorCorrection errorCorrection = QrErrorCorrection.medium,
  }) {
    final payload = encodeText(data, allowExtended: true);
    if (payload.isEmpty) return;
    _align(1);

    // Function 165: model 2 (the ubiquitous one).
    _bytes.addAll([_gs, 0x28, 0x6B, 0x04, 0x00, 0x31, 0x41, 50, 0x00]);
    // Function 167: module size in dots.
    _bytes.addAll([
      _gs,
      0x28,
      0x6B,
      0x03,
      0x00,
      0x31,
      0x43,
      moduleSize.clamp(1, 16),
    ]);
    // Function 169: error correction level.
    _bytes.addAll([
      _gs,
      0x28,
      0x6B,
      0x03,
      0x00,
      0x31,
      0x45,
      errorCorrection.value,
    ]);
    // Function 180: store the payload. pL/pH count the data plus the three
    // bytes of cn/fn/m that follow the length.
    final storeLength = payload.length + 3;
    _bytes.addAll([
      _gs,
      0x28,
      0x6B,
      storeLength & 0xFF,
      (storeLength >> 8) & 0xFF,
      0x31,
      0x50,
      0x30,
    ]);
    _bytes.addAll(payload);
    // Function 181: print what was stored.
    _bytes.addAll([_gs, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x51, 0x30]);
    _bytes.add(_lf);
    _align(0);
  }

  // --------------------------------------------------------------- hardware

  /// Feeds clear of the cutter and then cuts.
  ///
  /// The feed matters: the blade sits above the print head, so cutting without
  /// it slices through the last few lines.
  void cut({bool partial = true}) {
    feed(4);
    _bytes.addAll([_gs, 0x56, partial ? 1 : 0]);
  }

  /// Kicks the cash drawer wired to the printer's RJ11 port.
  ///
  /// [pin] 0 is connector pin 2 and 1 is pin 5; drawers are wired to one or the
  /// other, and which one is not something software can detect, so it is a
  /// setting the shop picks once. Times are in milliseconds and are sent in the
  /// 2 ms units the command expects.
  void openDrawer({int pin = 0, int onMs = 120, int offMs = 240}) {
    _bytes.addAll([
      _esc,
      0x70,
      pin == 1 ? 1 : 0,
      (onMs ~/ 2).clamp(1, 255),
      (offMs ~/ 2).clamp(1, 255),
    ]);
  }

  /// Sounds the printer's buzzer, if it has one. Harmless when it does not.
  void beep({int count = 1, int duration = 3}) {
    for (var i = 0; i < count.clamp(1, 9); i++) {
      _bytes.addAll([_esc, 0x42, duration.clamp(1, 9), 1]);
    }
  }

  /// Escape hatch for a printer that needs a command this class does not model.
  void raw(List<int> command) => _bytes.addAll(command);

  // -------------------------------------------------------------- internals

  void _align(int mode) => _bytes.addAll([_esc, 0x61, mode]);
  void _emphasis(bool on) => _bytes.addAll([_esc, 0x45, on ? 1 : 0]);
  void _underline(bool on) => _bytes.addAll([_esc, 0x2D, on ? 1 : 0]);

  void _size({bool doubleWidth = false, bool doubleHeight = false}) {
    final value = (doubleWidth ? 0x10 : 0x00) | (doubleHeight ? 0x01 : 0x00);
    _bytes.addAll([_gs, 0x21, value]);
  }

  void _resetStyle() {
    _emphasis(false);
    _underline(false);
    _size();
    _align(0);
  }

  static String _fit(String value, int width, CellAlign align) {
    final text = _clip(value, width);
    return align == CellAlign.right
        ? text.padLeft(width)
        : text.padRight(width);
  }

  static String _clip(String value, int width) =>
      value.length <= width ? value : value.substring(0, width);
}

/// Reads a finished job back as the text the printer will put on the paper.
///
/// This is what the on-screen bill preview renders, so the preview shows the
/// actual byte stream rather than a second layout that could drift from it.
/// Command sequences are stepped over by length — parameters are ordinary
/// bytes and many are printable, so filtering by value alone would leave
/// debris like the `1` from `ESC E 1` scattered through the text.
///
/// Anything drawn rather than typed — a logo raster, a barcode, a QR — is
/// reported through [onGraphic] instead of being turned into gibberish.
String renderEscPosAsText(
  List<int> job, {
  void Function(EscPosGraphic graphic)? onGraphic,
}) {
  final out = StringBuffer();
  var i = 0;
  while (i < job.length) {
    final byte = job[i];
    if (byte != 0x1B && byte != 0x1D) {
      if (byte == 0x0A) {
        out.write('\n');
      } else if (byte >= 0x20 && byte <= 0x7E) {
        out.writeCharCode(byte);
      }
      i++;
      continue;
    }

    final length = _commandLength(job, i);
    if (length <= 0) break;

    // Feeds are the one command that puts something on the paper.
    if (byte == 0x1B && i + 1 < job.length && job[i + 1] == 0x64) {
      out.write('\n' * job[i + 2]);
    } else if (byte == 0x1D && i + 2 < job.length) {
      final second = job[i + 1];
      if (second == 0x6B) {
        onGraphic?.call(EscPosGraphic.barcode);
      } else if (second == 0x76) {
        onGraphic?.call(EscPosGraphic.image);
      } else if (second == 0x28 && job[i + 2] == 0x6B) {
        // Only the print sub-command marks a finished QR.
        if (i + 7 < job.length && job[i + 6] == 0x51) {
          onGraphic?.call(EscPosGraphic.qr);
        }
      }
    }
    i += length;
  }
  return out.toString();
}

/// Something drawn on the receipt rather than typed.
enum EscPosGraphic { image, barcode, qr }

/// How many bytes the command starting at [at] occupies.
int _commandLength(List<int> job, int at) {
  if (at + 1 >= job.length) return job.length - at;
  final key = (job[at] << 8) | job[at + 1];
  const fixed = <int, int>{
    0x1B40: 2, // ESC @
    0x1B74: 3, 0x1B61: 3, 0x1B45: 3, 0x1B2D: 3, 0x1B64: 3,
    0x1B42: 4, // ESC B
    0x1B70: 5, // ESC p
    0x1D21: 3, 0x1D56: 3, 0x1D48: 3, 0x1D68: 3, 0x1D77: 3,
  };
  final known = fixed[key];
  if (known != null) return known;
  if (key == 0x1D6B && at + 3 < job.length) return 4 + job[at + 3];
  if (key == 0x1D28 && at + 4 < job.length && job[at + 2] == 0x6B) {
    return 5 + (job[at + 3] | (job[at + 4] << 8));
  }
  if (key == 0x1D76 && at + 7 < job.length && job[at + 2] == 0x30) {
    final bytesPerRow = job[at + 4] | (job[at + 5] << 8);
    final rows = job[at + 6] | (job[at + 7] << 8);
    return 8 + bytesPerRow * rows;
  }
  // An unrecognised escape: step over the two bytes rather than stalling.
  return 2;
}

/// Splits [text] into lines of at most [width] characters, breaking between
/// words where it can and mid-word only when a single word is too long.
List<String> wrap(String text, int width) {
  if (width <= 0) return [text];
  final out = <String>[];
  for (final paragraph in text.split('\n')) {
    if (paragraph.trim().isEmpty) {
      out.add('');
      continue;
    }
    var current = '';
    for (final word in paragraph.split(RegExp(r'\s+'))) {
      if (word.isEmpty) continue;
      if (current.isEmpty) {
        current = word;
      } else if (current.length + 1 + word.length <= width) {
        current = '$current $word';
      } else {
        out.add(current);
        current = word;
      }
      while (current.length > width) {
        out.add(current.substring(0, width));
        current = current.substring(width);
      }
    }
    if (current.isNotEmpty) out.add(current);
  }
  return out.isEmpty ? [''] : out;
}

/// Turns Dart text into bytes a thermal printer will actually render.
///
/// Receipt printers are single-byte devices. Handing them UTF-8 puts the
/// multi-byte sequences straight through as garbage — the ₹ sign alone would
/// print as three random glyphs on every total. So anything outside plain ASCII
/// is transliterated first, and whatever has no sensible stand-in becomes '?'
/// rather than corrupting the line.
///
/// Set [allowExtended] for payloads the printer never renders as text — a QR
/// code's contents, for instance, which are encoded as data.
List<int> encodeText(String text, {bool allowExtended = false}) {
  if (allowExtended) {
    return [for (final unit in text.codeUnits) unit & 0xFF];
  }
  final out = <int>[];
  for (final rune in text.runes) {
    final replacement = _transliterations[rune];
    if (replacement != null) {
      out.addAll(replacement.codeUnits);
      continue;
    }
    if (rune >= 0x20 && rune <= 0x7E) {
      out.add(rune);
    } else if (rune == 0x0A) {
      out.add(0x0A);
    } else {
      out.add(0x3F); // '?'
    }
  }
  return out;
}

/// Characters that turn up in Indian retail text and have a printable stand-in.
///
/// The rupee sign is the important one: it is not in PC437 at all, and it
/// appears on every single line of every total.
const _transliterations = <int, String>{
  0x20B9: 'Rs.', // ₹ INDIAN RUPEE SIGN
  0x20A8: 'Rs.', // ₨ RUPEE SIGN
  0x00A0: ' ', // non-breaking space
  0x2009: ' ', // thin space
  0x202F: ' ', // narrow no-break space
  0x2013: '-', // – en dash
  0x2014: '-', // — em dash
  0x2018: "'",
  0x2019: "'",
  0x201C: '"',
  0x201D: '"',
  0x2026: '...',
  0x2022: '*',
  0x00D7: 'x', // × multiplication sign
  0x00B0: 'deg',
  0x00E9: 'e', 0x00E8: 'e', 0x00EA: 'e', 0x00EB: 'e',
  0x00E0: 'a', 0x00E1: 'a', 0x00E2: 'a', 0x00E4: 'a', 0x00E3: 'a',
  0x00EC: 'i', 0x00ED: 'i', 0x00EE: 'i', 0x00EF: 'i',
  0x00F2: 'o', 0x00F3: 'o', 0x00F4: 'o', 0x00F6: 'o', 0x00F5: 'o',
  0x00F9: 'u', 0x00FA: 'u', 0x00FB: 'u', 0x00FC: 'u',
  0x00E7: 'c', 0x00F1: 'n',
  0x00C9: 'E', 0x00C8: 'E', 0x00C0: 'A', 0x00C1: 'A', 0x00C7: 'C',
};
