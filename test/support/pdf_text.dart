import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// Pulls the words back out of a generated PDF.
///
/// Asserting that a document "is not empty and starts with %PDF" says nothing
/// about what is printed on it — which is how a label went to press for three
/// releases with its number missing and every test still green. Reading the
/// text back is the only assertion that can tell the difference between a
/// label that carries the barcode number and one that quietly dropped it.
///
/// The pdf package writes each run of text as `[(word)]TJ` inside a
/// Flate-compressed content stream, so this inflates every stream and collects
/// the string literals.
String pdfText(Uint8List document) {
  final latin = latin1.decode(document, allowInvalid: true);
  final words = <String>[];
  final streamStart = RegExp(r'stream\r?\n');

  var cursor = 0;
  while (cursor < latin.length) {
    final match = streamStart.firstMatch(latin.substring(cursor));
    if (match == null) break;
    final start = cursor + match.end;
    final end = latin.indexOf('endstream', start);
    if (end < 0) break;

    // Streams that are not Flate — images, fonts — simply fail to inflate and
    // are skipped; they carry no page text.
    try {
      final inflated = const ZLibDecoder().decodeBytes(
        document.sublist(start, end),
      );
      final content = latin1.decode(inflated, allowInvalid: true);
      for (final show in RegExp(r'\[\((.*?)\)\]TJ').allMatches(content)) {
        words.add(show.group(1)!);
      }
    } catch (_) {
      // Not a text stream.
    }
    cursor = end + 'endstream'.length;
  }
  return words.join(' ');
}
