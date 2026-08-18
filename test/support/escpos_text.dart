import 'package:flutter_test/flutter_test.dart';

/// How many bytes the ESC/POS command starting at [at] occupies.
///
/// Command parameters are ordinary bytes and many of them fall in the
/// printable range — `ESC E 1` ends in a byte that reads as a digit — so a
/// helper that only filters by byte value leaves debris all over the extracted
/// text. Knowing each command's length is the only way to separate what the
/// printer renders from what it obeys.
///
/// Only the commands `EscPosBuilder` emits need an entry. A command outside the
/// table fails the test loudly, which is the right outcome: the builder grew
/// something these helpers no longer understand.
int escPosCommandLength(List<int> bytes, int at) {
  const fixed = <int, int>{
    0x1B40: 2, // ESC @   initialise
    0x1B74: 3, // ESC t   code page
    0x1B61: 3, // ESC a   alignment
    0x1B45: 3, // ESC E   bold
    0x1B2D: 3, // ESC -   underline
    0x1B64: 3, // ESC d   feed n lines
    0x1B42: 4, // ESC B   buzzer
    0x1B70: 5, // ESC p   drawer pulse
    0x1D21: 3, // GS  !   character size
    0x1D56: 3, // GS  V   cut
    0x1D48: 3, // GS  H   barcode text position
    0x1D68: 3, // GS  h   barcode height
    0x1D77: 3, // GS  w   barcode width
  };
  final key = (bytes[at] << 8) | bytes[at + 1];
  final known = fixed[key];
  if (known != null) return known;
  if (key == 0x1D6B) return 4 + bytes[at + 3]; // GS k <m> <len> <data>
  if (key == 0x1D28 && bytes[at + 2] == 0x6B) {
    return 5 + (bytes[at + 3] | (bytes[at + 4] << 8)); // GS ( k pL pH ...
  }
  if (key == 0x1D76 && bytes[at + 2] == 0x30) {
    // GS v 0 m xL xH yL yH <xL|xH bytes per row × yL|yH rows>
    final bytesPerRow = bytes[at + 4] | (bytes[at + 5] << 8);
    final rows = bytes[at + 6] | (bytes[at + 7] << 8);
    return 8 + bytesPerRow * rows;
  }
  fail(
    'unrecognised ESC/POS command 0x${key.toRadixString(16)} at byte $at — '
    'add it to escPosCommandLength when the builder learns a new one',
  );
}

/// What the printer would actually put on the paper: text with every command
/// sequence removed and line feeds kept as newlines.
String escPosPaperText(List<int> bytes) {
  final out = StringBuffer();
  var i = 0;
  while (i < bytes.length) {
    final byte = bytes[i];
    if (byte == 0x1B || byte == 0x1D) {
      i += escPosCommandLength(bytes, i);
      continue;
    }
    out.writeCharCode(byte);
    i++;
  }
  return out.toString();
}

/// True when [needle] appears anywhere in [haystack].
bool containsBytes(List<int> haystack, List<int> needle) =>
    indexOfBytes(haystack, needle) >= 0;

/// The offset of [needle] in [haystack], or -1.
int indexOfBytes(List<int> haystack, List<int> needle) {
  for (var i = 0; i + needle.length <= haystack.length; i++) {
    var match = true;
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) {
        match = false;
        break;
      }
    }
    if (match) return i;
  }
  return -1;
}
