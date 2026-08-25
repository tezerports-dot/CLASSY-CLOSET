import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// A standing guard against the defect that made the add-product form unusable.
///
/// A `DropdownButtonFormField` in a constrained box sizes itself to its longest
/// item unless told otherwise. With a real supplier name or printer name in it
/// that overflows the box by a hundred pixels or more — and an overflowing
/// widget still paints and still takes taps, straight over whatever sits beside
/// it. The visible symptom is not a layout warning anybody sees on a shop
/// counter; it is "this input does not accept anything", because the taps are
/// landing on the neighbour that overflowed onto it.
///
/// Every dropdown this app puts in a row, a dialog or a form therefore needs
/// `isExpanded: true`. Checking the source is what makes this cheap enough to
/// cover all of them at once, rather than pumping thirty screens.
void main() {
  test('every DropdownButtonFormField sets isExpanded', () {
    final offenders = <String>[];
    final pattern = RegExp(r'DropdownButtonFormField<[^>]*>\(');

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();
      for (final match in pattern.allMatches(source)) {
        // The argument list up to `items:` is where the flags live.
        final head = source.substring(
          match.start,
          (match.start + 700).clamp(0, source.length),
        );
        final flags = head.split('items:').first;
        if (flags.contains('isExpanded')) continue;
        final line =
            '\n'.allMatches(source.substring(0, match.start)).length + 1;
        offenders.add('${entity.path}:$line');
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'these dropdowns will overflow onto the control beside them and '
          'swallow its taps:\n  ${offenders.join('\n  ')}',
    );
  });
}
