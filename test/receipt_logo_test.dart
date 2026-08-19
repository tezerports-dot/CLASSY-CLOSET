import 'package:classy_closet/core/services/escpos.dart';
import 'package:classy_closet/core/services/receipt_logo.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'support/escpos_text.dart';

void main() {
  /// A [width] × [height] image, filled white, with [paint] applied.
  img.Image canvas(int width, int height, [void Function(img.Image)? paint]) {
    final image = img.Image(width: width, height: height, numChannels: 4);
    img.fill(image, color: img.ColorRgba8(255, 255, 255, 255));
    paint?.call(image);
    return image;
  }

  /// Whether the dot at [x] on [row] is set.
  bool dotAt(List<int> row, int x) => (row[x >> 3] & (0x80 >> (x & 7))) != 0;

  group('reducing a logo to dots', () {
    test('a black square becomes set bits and white paper becomes clear', () {
      final source = canvas(64, 64, (image) {
        img.fillRect(
          image,
          x1: 0,
          y1: 0,
          x2: 63,
          y2: 63,
          color: img.ColorRgba8(0, 0, 0, 255),
        );
      });

      final logo = prepareReceiptLogo(source, paper: ThermalPaper.mm58)!;

      // 58 mm is 384 dots. 60% of that would be 232 dots square, but a square
      // logo hits the 200-dot height cap first and the width follows it down —
      // a quarter of the roll's length is already a lot to give a logo.
      expect(logo.widthDots, 384, reason: 'rows are always the full roll');
      expect(logo.heightDots, 200);
      final middle = logo.rows[logo.heightDots ~/ 2];
      expect(middle.length, 48, reason: 'every row is the full roll width');
      // The artwork is centred, so the edges are paper and the middle is ink.
      expect(dotAt(middle, 192), isTrue, reason: 'centre of the roll is black');
      expect(dotAt(middle, 0), isFalse, reason: 'left margin is paper');
      expect(dotAt(middle, 383), isFalse, reason: 'right margin is paper');
    });

    test('the artwork is centred on the roll', () {
      final source = canvas(100, 20, (image) {
        img.fillRect(
          image,
          x1: 0,
          y1: 0,
          x2: 99,
          y2: 19,
          color: img.ColorRgba8(0, 0, 0, 255),
        );
      });

      final logo = prepareReceiptLogo(source, paper: ThermalPaper.mm80)!;
      final row = logo.rows.first;

      var first = -1, last = -1;
      for (var x = 0; x < logo.widthDots; x++) {
        if (!dotAt(row, x)) continue;
        if (first < 0) first = x;
        last = x;
      }
      final leftMargin = first;
      final rightMargin = logo.widthDots - 1 - last;
      expect(
        (leftMargin - rightMargin).abs(),
        lessThanOrEqualTo(8),
        reason: 'margins agree to within a byte',
      );
    });

    test('mid grey lands on the ink side, pale grey on the paper side', () {
      // A thermal head has no grey, so the threshold is what decides whether a
      // logo reads as artwork or as a smudge.
      final dark = canvas(16, 8, (image) {
        img.fillRect(
          image,
          x1: 0,
          y1: 0,
          x2: 15,
          y2: 7,
          color: img.ColorRgba8(90, 90, 90, 255),
        );
      });
      final pale = canvas(16, 8, (image) {
        img.fillRect(
          image,
          x1: 0,
          y1: 0,
          x2: 15,
          y2: 7,
          color: img.ColorRgba8(230, 230, 230, 255),
        );
      });

      final darkLogo = prepareReceiptLogo(dark, paper: ThermalPaper.mm58)!;
      final paleLogo = prepareReceiptLogo(pale, paper: ThermalPaper.mm58)!;

      expect(darkLogo.rows.first.any((b) => b != 0), isTrue);
      expect(paleLogo.rows.first.every((b) => b == 0), isTrue);
    });

    test('a transparent background is paper, not a black block', () {
      // A logo exported with transparency would otherwise burn as a solid
      // rectangle, which is the classic way a receipt logo goes wrong.
      final source = img.Image(width: 32, height: 16, numChannels: 4);
      img.fill(source, color: img.ColorRgba8(0, 0, 0, 0));

      final logo = prepareReceiptLogo(source, paper: ThermalPaper.mm58)!;

      expect(
        logo.rows.every((row) => row.every((b) => b == 0)),
        isTrue,
        reason: 'fully transparent artwork prints nothing at all',
      );
    });

    test('a tall logo is capped so it cannot push the bill down the roll', () {
      final source = canvas(50, 2000, (image) {
        img.fillRect(
          image,
          x1: 0,
          y1: 0,
          x2: 49,
          y2: 1999,
          color: img.ColorRgba8(0, 0, 0, 255),
        );
      });

      final logo = prepareReceiptLogo(
        source,
        paper: ThermalPaper.mm80,
        maxHeightDots: 200,
      )!;

      expect(logo.heightDots, lessThanOrEqualTo(200));
    });

    test('the aspect ratio is kept', () {
      // Twice as wide as it is tall must stay twice as wide as it is tall.
      final source = canvas(200, 100);

      final logo = prepareReceiptLogo(
        source,
        paper: ThermalPaper.mm80,
        widthFraction: 0.5,
      )!;

      // 576 dots × 0.5 = 288 dots wide, so a 2:1 source is 144 dots tall.
      expect(logo.heightDots, closeTo(144, 4));
    });

    test(
      'an empty image is refused rather than producing a broken command',
      () {
        expect(
          prepareReceiptLogo(
            img.Image(width: 0, height: 0),
            paper: ThermalPaper.mm58,
          ),
          isNull,
        );
      },
    );

    test('a missing file gives no logo instead of failing the sale', () async {
      expect(
        await loadReceiptLogo('/no/such/logo.png', paper: ThermalPaper.mm80),
        isNull,
      );
      expect(await loadReceiptLogo(null, paper: ThermalPaper.mm80), isNull);
      expect(await loadReceiptLogo('   ', paper: ThermalPaper.mm80), isNull);
    });
  });

  group('the raster command', () {
    test('carries the width in bytes and the height in dots', () {
      final builder = EscPosBuilder(paper: ThermalPaper.mm58)
        ..rasterImage([
          [0xFF, 0x00, 0xAA],
          [0x00, 0xFF, 0x55],
        ]);
      final bytes = builder.bytes();

      // GS v 0 m xL xH yL yH
      final at = indexOfBytes(bytes, [0x1D, 0x76, 0x30]);
      expect(at, greaterThanOrEqualTo(0));
      expect(bytes[at + 3], 0, reason: 'normal scale');
      expect(bytes[at + 4] | (bytes[at + 5] << 8), 3, reason: '3 bytes a row');
      expect(bytes[at + 6] | (bytes[at + 7] << 8), 2, reason: '2 rows tall');
      expect(bytes.sublist(at + 8, at + 14), [
        0xFF,
        0x00,
        0xAA,
        0x00,
        0xFF,
        0x55,
      ], reason: 'the rows follow the header in order');
    });

    test('a wide image sets the high length byte', () {
      final builder = EscPosBuilder()
        ..rasterImage([List<int>.filled(300, 0x00)]);
      final bytes = builder.bytes();
      final at = indexOfBytes(bytes, [0x1D, 0x76, 0x30]);

      expect(bytes[at + 4] | (bytes[at + 5] << 8), 300);
      expect(bytes[at + 5], 1, reason: '300 does not fit in one byte');
    });

    test('nothing is emitted for an empty or ragged image', () {
      expect(
        containsBytes((EscPosBuilder()..rasterImage(const [])).bytes(), [
          0x1D,
          0x76,
        ]),
        isFalse,
      );
      expect(
        containsBytes(
          (EscPosBuilder()..rasterImage([
                [0x01, 0x02],
                [0x03],
              ]))
              .bytes(),
          [0x1D, 0x76],
        ),
        isFalse,
        reason: 'ragged rows would desynchronise the printer',
      );
    });
  });
}
