import 'package:flutter/material.dart';

/// Type for a screen that is mostly numbers.
///
/// Three faces, each doing one job:
///
/// * **IBM Plex Sans** for everything a person reads — a clean grotesque with
///   real tabular figures, which is what a till needs.
/// * **IBM Plex Mono** for SKUs, invoice numbers and the receipt, where a
///   fixed advance makes a code scannable by eye.
/// * **Cormorant Garamond** for the wordmark alone. It carries the shop's
///   identity and would be unreadable at 13 px in a table, so it never
///   appears in UI text.
///
/// All three are bundled as assets. Nothing is fetched at runtime — the shop
/// has no internet, and a font that silently falls back would take the rupee
/// sign with it.
class AppTypography {
  const AppTypography._();

  static const sans = 'IBMPlexSans';
  static const mono = 'IBMPlexMono';
  static const display = 'CormorantGaramond';

  /// Lining, fixed-advance figures. Applied to every amount and quantity so
  /// columns of money line up rather than shimmering as digits change.
  static const tabular = <FontFeature>[FontFeature.tabularFigures()];

  static TextTheme textTheme() => const TextTheme(
    // Page titles.
    headlineLarge: TextStyle(
      fontSize: 22,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.22,
      height: 1.2,
    ),
    headlineMedium: TextStyle(
      fontSize: 20,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.2,
      height: 1.2,
    ),
    // Card and section titles.
    titleLarge: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
    titleMedium: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    // Body.
    bodyLarge: TextStyle(fontSize: 14, height: 1.5),
    bodyMedium: TextStyle(fontSize: 13, height: 1.5),
    // Captions.
    bodySmall: TextStyle(fontSize: 11.5, height: 1.4),
    // Field labels and buttons.
    labelLarge: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
    labelMedium: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
    labelSmall: TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.4,
    ),
  ).apply(fontFamily: sans);

  /// A KPI figure — the number a shopkeeper looks at first.
  static const kpi = TextStyle(
    fontFamily: sans,
    fontSize: 26,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.52,
    height: 1.1,
    fontFeatures: tabular,
  );

  /// The bill total.
  static const billTotal = TextStyle(
    fontFamily: sans,
    fontSize: 24,
    fontWeight: FontWeight.w700,
    height: 1.1,
    fontFeatures: tabular,
  );

  /// Any amount in a row or a total line.
  static const money = TextStyle(fontFamily: sans, fontFeatures: tabular);

  /// SKUs, invoice numbers, GSTINs.
  static const code = TextStyle(
    fontFamily: mono,
    fontSize: 12.5,
    fontWeight: FontWeight.w500,
  );

  /// The receipt body in the preview, which has to match the roll.
  static const receipt = TextStyle(
    fontFamily: mono,
    fontSize: 11.5,
    fontWeight: FontWeight.w500,
    height: 1.45,
  );

  /// The wordmark. Wide tracking is part of the mark, not a flourish.
  static const wordmark = TextStyle(
    fontFamily: display,
    fontWeight: FontWeight.w700,
    letterSpacing: 2.6,
    height: 1.05,
  );

  /// The line under the wordmark.
  static const wordmarkSub = TextStyle(
    fontFamily: sans,
    fontSize: 9.5,
    fontWeight: FontWeight.w600,
    letterSpacing: 2.5,
  );

  /// A small uppercase label — table headers, eyebrow text.
  static const microLabel = TextStyle(
    fontFamily: sans,
    fontSize: 11,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.6,
  );
}
