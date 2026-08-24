import 'dart:convert';

import 'package:flutter/material.dart';

import 'app_colors.dart';

/// The palette a shop paints itself with.
///
/// A second shop drops onto this build without a rebuild: the owner picks a
/// preset or types two hex values under Settings, and the rail, the buttons
/// and the accents all move together. Everything painted from the theme reads
/// from the live [AppColors] instance the shell installs, so the change lands
/// on the next frame.
///
/// The scheme is intentionally two colours — brand and accent. Every other
/// swatch is derived: the raised brand surface, the hover, the gold wash. A
/// shop that hands over a swatch card can pick "the gold" and "the near-black"
/// without knowing what a "raised brand surface" is.
@immutable
class BrandTheme {
  const BrandTheme({
    required this.name,
    required this.brand,
    required this.accent,
  });

  /// A short label the owner sees in the settings dropdown. When the two
  /// colours match no preset, this reads "Custom".
  final String name;

  /// The rail, the top bar, the dark buttons. Kept warm rather than pure black
  /// so it does not fight the accent.
  final Color brand;

  /// The single accent — checkout button, focus ring, small marks. This is
  /// what a customer notices about the shop.
  final Color accent;

  /// Classy Closet's own: warm near-black and desert gold. Ships as the seed
  /// so a first install still opens in the shop's identity.
  static const classic = BrandTheme(
    name: 'Classic (black & gold)',
    brand: Color(0xFF17140F),
    accent: Color(0xFFC9962F),
  );

  /// The named combos shown as chips in the settings picker. A shop that does
  /// not want to pick a hex reaches for one of these and calls it done.
  static const presets = <BrandTheme>[
    classic,
    BrandTheme(
      name: 'Midnight blue & rose gold',
      brand: Color(0xFF14213D),
      accent: Color(0xFFC98A6B),
    ),
    BrandTheme(
      name: 'Forest & bone',
      brand: Color(0xFF264532),
      accent: Color(0xFFC7B49A),
    ),
    BrandTheme(
      name: 'Bordeaux & cream',
      brand: Color(0xFF5B1A1E),
      accent: Color(0xFFD8B679),
    ),
    BrandTheme(
      name: 'Charcoal & sky',
      brand: Color(0xFF1F252B),
      accent: Color(0xFF5BA3C6),
    ),
    BrandTheme(
      name: 'Espresso & terracotta',
      brand: Color(0xFF2E211A),
      accent: Color(0xFFC96F3F),
    ),
    BrandTheme(
      name: 'Slate & sage',
      brand: Color(0xFF2A2F3A),
      accent: Color(0xFF7FA491),
    ),
    BrandTheme(
      name: 'Plum & champagne',
      brand: Color(0xFF3A1B3A),
      accent: Color(0xFFDFC79C),
    ),
  ];

  /// True when [brand]+[accent] match one of [presets]. The picker uses this
  /// to decide whether a chip is selected or whether "Custom" is.
  bool get isPreset => presets.any(
    (p) =>
        p.brand.toARGB32() == brand.toARGB32() &&
        p.accent.toARGB32() == accent.toARGB32(),
  );

  /// The custom entry the settings picker offers when nothing matches, so the
  /// owner can type two hex values and have them named consistently.
  BrandTheme asCustom() =>
      BrandTheme(name: 'Custom', brand: brand, accent: accent);

  /// Painting derivatives — the shades the whole app needs given a brand and
  /// an accent, so `AppColors` can be recomputed without another decision.
  ///
  /// The derivation is small and deliberate:
  ///  - `brandRaised` and `brandHover` are the brand nudged toward the light,
  ///    which is what a "selected rail item" reads as on any near-black.
  ///  - `brandInk`, `brandInkSoft`, `brandInkFaint` are lightened tints of the
  ///    accent, so gold text on black stays gold when the palette changes.
  ///  - `goldDeep` is the accent darkened for readable text on the light card,
  ///    which is also the "warn" swatch — a warning in this palette *is* the
  ///    deep accent.
  ///  - `goldWash` and `goldWashBorder` are the accent lightened to a paper
  ///    tint — the badge fills and the discount field on white.
  BrandPalette resolve() {
    int chan(double a, double b, double t) =>
        ((a + (b - a) * t) * 255.0).round().clamp(0, 255);
    Color mix(Color a, Color b, double t) => Color.fromARGB(
      255,
      chan(a.r, b.r, t),
      chan(a.g, b.g, t),
      chan(a.b, b.b, t),
    );
    return BrandPalette(
      brand: brand,
      brandRaised: mix(brand, Colors.white, 0.05),
      brandHover: mix(brand, Colors.white, 0.03),
      brandInk: mix(accent, Colors.white, 0.15),
      brandInkSoft: mix(accent, Colors.white, 0.45),
      brandInkFaint: mix(accent, Colors.white, 0.65),
      gold: accent,
      goldDeep: mix(accent, Colors.black, 0.30),
      goldWash: mix(accent, Colors.white, 0.85),
      goldWashBorder: mix(accent, Colors.white, 0.70),
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'brand': brand.toARGB32(),
    'accent': accent.toARGB32(),
  };

  static BrandTheme fromJson(Object? raw) {
    if (raw is String && raw.isNotEmpty) {
      try {
        return fromJson(jsonDecode(raw));
      } catch (_) {
        return classic;
      }
    }
    if (raw is! Map) return classic;
    final map = raw.cast<String, dynamic>();
    final brand = map['brand'];
    final accent = map['accent'];
    if (brand is! int || accent is! int) return classic;
    final name = (map['name'] as String? ?? 'Custom').trim();
    return BrandTheme(name: name, brand: Color(brand), accent: Color(accent));
  }
}

/// The full palette derived from a [BrandTheme]. `AppColors` copies these into
/// its own fields when the shell installs a theme, so the rest of the app can
/// keep reading `AppColors.brand` without knowing the shop rebranded.
@immutable
class BrandPalette {
  const BrandPalette({
    required this.brand,
    required this.brandRaised,
    required this.brandHover,
    required this.brandInk,
    required this.brandInkSoft,
    required this.brandInkFaint,
    required this.gold,
    required this.goldDeep,
    required this.goldWash,
    required this.goldWashBorder,
  });

  final Color brand;
  final Color brandRaised;
  final Color brandHover;
  final Color brandInk;
  final Color brandInkSoft;
  final Color brandInkFaint;
  final Color gold;
  final Color goldDeep;
  final Color goldWash;
  final Color goldWashBorder;
}
