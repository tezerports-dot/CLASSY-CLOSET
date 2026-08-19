import 'package:flutter/material.dart';

/// The Classy Closet palette.
///
/// Black and gold is the shop's own identity — it is on the sign, the bag and
/// the bill. It is not, however, a good ground to stare at for a nine-hour
/// shift, so the brand carries the rail, the headers and the primary buttons
/// while the working surface stays light and warm. Gold appears as a line, a
/// button and a mark; it is never flooded across an area.
///
/// Every value here is a token. Nothing outside `theme/` should name a hex.
class AppColors {
  const AppColors._();

  // ------------------------------------------------------------------ text
  /// Primary text.
  static const ink = Color(0xFF211D16);

  /// Secondary text and field labels.
  static const inkSoft = Color(0xFF6E6555);

  /// Placeholders, captions, disabled text.
  static const inkFaint = Color(0xFF938A78);

  // -------------------------------------------------------------- surfaces
  /// The working background the counter looks at all day.
  static const bg = Color(0xFFF6F4EF);

  /// Cards, tables, inputs.
  static const surface = Color(0xFFFFFFFF);

  /// Table headers, footers, hover fills.
  static const surfaceAlt = Color(0xFFFBFAF7);

  static const border = Color(0xFFE7E2D8);

  /// Row dividers — one step softer than [border].
  static const borderSoft = Color(0xFFF2EEE5);

  // ----------------------------------------------------------------- brand
  /// The rail, the top-bar text, dark buttons. A warm near-black rather than a
  /// true black, so it sits with the gold instead of fighting it.
  static const brand = Color(0xFF17140F);

  /// A raised brand surface — a selected rail item.
  static const brandRaised = Color(0xFF23201A);

  /// Hover on a brand surface.
  static const brandHover = Color(0xFF201C16);

  /// Gold text and icons on a brand surface.
  static const brandInk = Color(0xFFF0D67C);

  /// Idle rail text.
  static const brandInkSoft = Color(0xFFC9BFAC);

  /// Rail sub-labels.
  static const brandInkFaint = Color(0xFF8C8474);

  // ------------------------------------------------------------------ gold
  /// The single accent: the checkout button, the focus ring, small marks.
  static const gold = Color(0xFFC9962F);

  /// Gold that stays legible as text on a light ground.
  static const goldDeep = Color(0xFFB07A16);

  /// A gold tint for badges and the discount field.
  static const goldWash = Color(0xFFFBF3DE);
  static const goldWashBorder = Color(0xFFECDCB4);

  // ---------------------------------------------------------------- status
  static const success = Color(0xFF1F7A4D);
  static const successWash = Color(0xFFEAF3EC);

  /// Low stock, pending, partial. Shares its hex with [goldDeep] on purpose —
  /// a warning in this palette *is* the deep gold.
  static const warn = Color(0xFFB07A16);
  static const warnWash = Color(0xFFFBF3DE);

  static const danger = Color(0xFFC0392B);
  static const dangerWash = Color(0xFFF7E7E4);

  // ------------------------------------------------------------- elevation
  static const cardShadow = BoxShadow(
    color: Color(0x0A1A1712),
    blurRadius: 2,
    offset: Offset(0, 1),
  );

  static const panelShadow = BoxShadow(
    color: Color(0x0D1A1712),
    blurRadius: 3,
    offset: Offset(0, 1),
  );

  static const modalShadow = BoxShadow(
    color: Color(0x59000000),
    blurRadius: 60,
    offset: Offset(0, 24),
  );
}

/// Corner radii, one scale for the whole app.
class AppRadii {
  const AppRadii._();

  static const input = 8.0;
  static const button = 8.0;
  static const card = 12.0;
  static const pill = 6.0;
  static const tile = 11.0;

  static const inputBorder = BorderRadius.all(Radius.circular(input));
  static const cardBorder = BorderRadius.all(Radius.circular(card));
  static const pillBorder = BorderRadius.all(Radius.circular(pill));
  static const tileBorder = BorderRadius.all(Radius.circular(tile));
}

/// The spacing scale. Compact by choice — the shop asked to see more rows.
class AppSpacing {
  const AppSpacing._();

  static const xxs = 4.0;
  static const xs = 6.0;
  static const sm = 8.0;
  static const md = 10.0;
  static const base = 12.0;
  static const lg = 14.0;
  static const xl = 16.0;
  static const xxl = 20.0;
  static const xxxl = 24.0;

  /// Table cell padding.
  static const cell = EdgeInsets.symmetric(horizontal: lg, vertical: base);

  /// Page gutter, before the responsive step-down.
  static const page = EdgeInsets.all(xxl);
}

/// The width at which the layout changes shape.
///
/// The counter PC is the floor case, not the ideal one: 1366×768 is a typical
/// shop laptop, so the desktop layout has to survive it.
class AppBreakpoints {
  const AppBreakpoints._();

  /// Full rail and two-column screens.
  static const desktop = 1180.0;

  /// Columns stack, KPI grid halves.
  static const laptop = 900.0;

  /// Rail collapses to icons.
  static const tablet = 640.0;

  static bool isDesktop(double w) => w >= desktop;
  static bool isLaptop(double w) => w >= laptop && w < desktop;
  static bool isTablet(double w) => w >= tablet && w < laptop;
  static bool isPhone(double w) => w < tablet;

  /// How many columns a KPI grid gets at [width].
  static int kpiColumns(double width) {
    if (width >= desktop) return 4;
    if (width >= laptop) return 2;
    if (width >= tablet) return 2;
    return 1;
  }
}
