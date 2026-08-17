import 'package:classy_closet/core/services/escpos.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/escpos_text.dart';

/// The bytes are the whole contract with the printer, so they are what these
/// tests assert on. A wrong byte here is a receipt that comes out as noise, and
/// nothing short of the byte sequence would catch it.
void main() {
  bool contains(List<int> haystack, List<int> needle) =>
      containsBytes(haystack, needle);
  String printableText(List<int> bytes) => escPosPaperText(bytes);

  group('initialisation', () {
    test('every job starts by resetting the printer and picking PC437', () {
      final bytes = EscPosBuilder().bytes();

      expect(bytes.take(2), [0x1B, 0x40], reason: 'ESC @ initialise');
      expect(bytes.skip(2).take(3), [0x1B, 0x74, 0x00], reason: 'ESC t 0');
    });
  });

  group('text encoding', () {
    test('the rupee sign becomes Rs. instead of three junk glyphs', () {
      // The whole point: ₹ is not in any single-byte printer code page, and it
      // appears on every total line in the shop.
      expect(String.fromCharCodes(encodeText('₹1,299.00')), 'Rs.1,299.00');
    });

    test('plain ASCII passes through untouched', () {
      expect(
        String.fromCharCodes(encodeText('INV/25-26/00042')),
        'INV/25-26/00042',
      );
    });

    test('typographic punctuation is flattened, not dropped', () {
      expect(
        String.fromCharCodes(encodeText('“Kids’ wear” — 2 x 3')),
        '"Kids\' wear" - 2 x 3',
      );
    });

    test('accented letters lose the accent rather than becoming noise', () {
      expect(String.fromCharCodes(encodeText('Café Coton')), 'Cafe Coton');
    });

    test('anything unprintable becomes a question mark', () {
      // Devanagari cannot render on a generic thermal printer at all. A visible
      // '?' is honest; a multi-byte sequence would desynchronise the line.
      expect(String.fromCharCodes(encodeText('कुर्ता')), '??????');
    });

    test('QR payloads keep their bytes, since they are data not glyphs', () {
      final bytes = encodeText('upi://pay?pa=a@b', allowExtended: true);
      expect(String.fromCharCodes(bytes), 'upi://pay?pa=a@b');
    });
  });

  group('wrapping', () {
    test('breaks between words at the roll width', () {
      expect(wrap('Cotton Kurta Blue Medium Size', 12), [
        'Cotton Kurta',
        'Blue Medium',
        'Size',
      ]);
    });

    test('splits a word that cannot fit rather than overflowing', () {
      expect(wrap('ABCDEFGHIJKLM', 5), ['ABCDE', 'FGHIJ', 'KLM']);
    });

    test('a line that already fits is left alone', () {
      expect(wrap('Cotton Kurta', 32), ['Cotton Kurta']);
    });
  });

  group('layout', () {
    test('a label and an amount are padded to exactly the roll width', () {
      final bytes = EscPosBuilder(paper: ThermalPaper.mm58)
        ..columns2('TOTAL', '1,798.00');
      final text = printableText(bytes.bytes()).trim();

      expect(text.length, 32, reason: '58 mm rolls hold 32 characters');
      expect(text.startsWith('TOTAL'), isTrue);
      expect(text.endsWith('1,798.00'), isTrue);
    });

    test('80 mm gets the wider line', () {
      final builder = EscPosBuilder(paper: ThermalPaper.mm80)
        ..columns2('TOTAL', '1,798.00');

      expect(printableText(builder.bytes()).trim().length, 48);
    });

    test('a long label gives way to the amount, never the other way round', () {
      final builder = EscPosBuilder(
        paper: ThermalPaper.mm58,
      )..columns2('An extremely long description of the item sold', '1,798.00');
      final text = printableText(builder.bytes()).trim();

      expect(text.length, 32);
      expect(text.endsWith('1,798.00'), isTrue);
    });

    test('a rule spans the paper', () {
      final builder = EscPosBuilder(paper: ThermalPaper.mm80)..rule();

      expect(printableText(builder.bytes()).trim(), '-' * 48);
    });

    test('double width halves how much text fits before wrapping', () {
      final builder = EscPosBuilder(paper: ThermalPaper.mm80)
        ..line('A' * 30, doubleWidth: true);
      final lines = printableText(builder.bytes()).trim().split('\n');

      expect(lines.first.length, 24, reason: '48 columns halve to 24');
      expect(lines.length, 2);
    });
  });

  group('hardware commands', () {
    test('the drawer kick is ESC p with the times in 2 ms units', () {
      final builder = EscPosBuilder()..openDrawer(onMs: 120, offMs: 240);

      // ESC p 0 60 120 — pin 2, 120 ms on, 240 ms off.
      expect(contains(builder.bytes(), [0x1B, 0x70, 0x00, 60, 120]), isTrue);
    });

    test('pin 5 is selectable for drawers wired the other way', () {
      final builder = EscPosBuilder()..openDrawer(pin: 1);

      expect(contains(builder.bytes(), [0x1B, 0x70, 0x01]), isTrue);
    });

    test('the pulse is clamped into the single byte the command allows', () {
      final builder = EscPosBuilder()..openDrawer(onMs: 100000, offMs: 0);
      final at = indexOfBytes(builder.bytes(), [0x1B, 0x70, 0x00]);

      expect(builder.bytes()[at + 3], 255);
      expect(builder.bytes()[at + 4], 1, reason: 'zero would be no pulse');
    });

    test('the cut feeds clear of the blade first', () {
      final builder = EscPosBuilder()..cut();
      final bytes = builder.bytes();

      final feed = indexOfBytes(bytes, [0x1B, 0x64]);
      final cut = indexOfBytes(bytes, [0x1D, 0x56]);
      expect(feed, greaterThanOrEqualTo(0));
      expect(cut, greaterThan(feed), reason: 'cutting first slices the total');
    });

    test('a full cut is available for printers without a partial blade', () {
      final builder = EscPosBuilder()..cut(partial: false);

      expect(contains(builder.bytes(), [0x1D, 0x56, 0x00]), isTrue);
    });
  });

  group('barcodes and QR', () {
    test('code 128 is length-prefixed rather than null-terminated', () {
      final builder = EscPosBuilder()..barcode128('ABC123');
      final bytes = builder.bytes();

      // GS k 73 <len> A B C 1 2 3
      final at = indexOfBytes(bytes, [0x1D, 0x6B, 73]);
      expect(at, greaterThanOrEqualTo(0));
      expect(bytes[at + 3], 6, reason: 'the length byte');
      expect(String.fromCharCodes(bytes.sublist(at + 4, at + 10)), 'ABC123');
    });

    test(
      'an empty barcode is skipped instead of emitting a broken command',
      () {
        final builder = EscPosBuilder()..barcode128('');

        expect(contains(builder.bytes(), [0x1D, 0x6B]), isFalse);
      },
    );

    test('the QR sub-commands are emitted in the order the spec requires', () {
      final builder = EscPosBuilder()..qr('upi://pay?pa=shop@bank');
      final bytes = builder.bytes();

      final model = indexOfBytes(bytes, [0x31, 0x41]); // fn 165
      final size = indexOfBytes(bytes, [0x31, 0x43]); // fn 167
      final ecc = indexOfBytes(bytes, [0x31, 0x45]); // fn 169
      final store = indexOfBytes(bytes, [0x31, 0x50, 0x30]); // fn 180
      final print = indexOfBytes(bytes, [0x31, 0x51, 0x30]); // fn 181

      expect(model, greaterThanOrEqualTo(0));
      expect(size, greaterThan(model));
      expect(ecc, greaterThan(size));
      expect(store, greaterThan(ecc), reason: 'data is stored after settings');
      expect(print, greaterThan(store));
    });

    test(
      'the QR length bytes count the payload plus the three header bytes',
      () {
        const payload = 'upi://pay?pa=shop@bank';
        final builder = EscPosBuilder()..qr(payload);
        final bytes = builder.bytes();

        final store = indexOfBytes(bytes, [0x31, 0x50, 0x30]);
        // pL and pH sit two bytes before cn.
        final pL = bytes[store - 2];
        final pH = bytes[store - 1];
        expect(pL | (pH << 8), payload.length + 3);
      },
    );
  });
}
