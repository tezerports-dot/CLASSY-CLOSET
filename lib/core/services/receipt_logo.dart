import 'dart:io';

import 'package:image/image.dart' as img;

import 'escpos.dart';

/// A logo reduced to what a thermal head can actually print.
///
/// A print head has one decision per dot — burn or don't. There is no grey, so
/// the conversion has to happen here rather than being left to the printer,
/// which would otherwise render a photo as a solid black rectangle.
class ReceiptLogo {
  const ReceiptLogo({
    required this.rows,
    required this.widthDots,
    required this.heightDots,
  });

  /// One entry per scan line, each packed 8 dots to a byte, most significant
  /// bit leftmost, a set bit meaning a black dot.
  final List<List<int>> rows;
  final int widthDots;
  final int heightDots;

  bool get isEmpty => rows.isEmpty;

  /// Roughly how much of the roll this will use, for a sanity check before
  /// putting a very tall logo on every bill.
  double get millimetresTall => heightDots / 8;
}

/// Reads the shop's logo file and prepares it for [paper].
///
/// Returns null when there is no logo, the file has gone, or the image cannot
/// be decoded — in every one of those cases the bill simply prints the shop
/// name instead, which is a better outcome than failing the sale.
Future<ReceiptLogo?> loadReceiptLogo(
  String? path, {
  required ThermalPaper paper,
  double widthFraction = 0.6,
  int maxHeightDots = 200,
}) async {
  if (path == null || path.trim().isEmpty) return null;
  final file = File(path);
  if (!await file.exists()) return null;
  try {
    final decoded = img.decodeImage(await file.readAsBytes());
    if (decoded == null) return null;
    return prepareReceiptLogo(
      decoded,
      paper: paper,
      widthFraction: widthFraction,
      maxHeightDots: maxHeightDots,
    );
  } on Object {
    return null;
  }
}

/// Scales [source] to the roll, reduces it to black and white, and centres it.
///
/// Kept apart from the file reading so the arithmetic — the part worth being
/// sure about — can be exercised without a file on disk.
ReceiptLogo? prepareReceiptLogo(
  img.Image source, {
  required ThermalPaper paper,
  double widthFraction = 0.6,
  int maxHeightDots = 200,
  double threshold = 0.62,
}) {
  if (source.width <= 0 || source.height <= 0) return null;

  // A row is always a whole number of bytes, so the target width is rounded
  // down to a multiple of 8 rather than left to overflow into the margin.
  final fullBytes = paper.dots ~/ 8;
  var targetBytes = (fullBytes * widthFraction).round().clamp(1, fullBytes);
  var targetWidth = targetBytes * 8;

  var scaled = img.copyResize(
    source,
    width: targetWidth,
    maintainAspect: true,
    interpolation: img.Interpolation.average,
  );

  // A tall logo would push the whole bill down the roll, so height is capped
  // and the width follows it down.
  if (scaled.height > maxHeightDots) {
    scaled = img.copyResize(
      source,
      height: maxHeightDots,
      maintainAspect: true,
      interpolation: img.Interpolation.average,
    );
    targetBytes = (scaled.width / 8).ceil().clamp(1, fullBytes);
    targetWidth = targetBytes * 8;
  }

  // Centring by padding the bitmap rather than by sending an alignment command:
  // not every printer honours alignment for a raster image, but every printer
  // honours white dots.
  final leftPadBytes = ((fullBytes - targetBytes) / 2).floor().clamp(
    0,
    fullBytes,
  );
  final rowBytes = fullBytes;

  final rows = <List<int>>[];
  for (var y = 0; y < scaled.height; y++) {
    final row = List<int>.filled(rowBytes, 0);
    for (var x = 0; x < targetWidth; x++) {
      final dark = x < scaled.width && _isDark(scaled, x, y, threshold);
      if (!dark) continue;
      final dot = leftPadBytes * 8 + x;
      final byte = dot >> 3;
      if (byte >= rowBytes) continue;
      row[byte] |= 0x80 >> (dot & 7);
    }
    rows.add(row);
  }

  if (rows.isEmpty) return null;
  return ReceiptLogo(
    rows: rows,
    widthDots: rowBytes * 8,
    heightDots: rows.length,
  );
}

/// Whether a pixel should burn.
///
/// Transparency counts as paper, not as black — a logo exported with a
/// transparent background would otherwise come out as a solid block.
bool _isDark(img.Image image, int x, int y, double threshold) {
  final pixel = image.getPixel(x, y);
  if (image.numChannels > 3 && pixel.a < pixel.maxChannelValue / 2) {
    return false;
  }
  return pixel.luminanceNormalized < threshold;
}
