import 'dart:io';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_typography.dart';

/// The shop's identity, on any surface.
///
/// The old build carried a hand-drawn hanger. It scaled cleanly, but it was
/// not the shop's mark — the mark is the round black-and-gold artwork on the
/// sign and the bag. This widget shows that artwork instead, taken from the
/// path the shop set under Settings when there is one, and from the bundled
/// asset otherwise.
///
/// The bundled asset is used as a proper fallback for two reasons: a first
/// install with no path set, and a saved path pointing at a file that has
/// gone. A missing image must never take a screen down with it.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 34, this.path, this.ringed = true});

  final double size;

  /// The shop's uploaded brand image. Null falls back to the bundled artwork.
  final String? path;

  /// Kept for callers that previously had a ring around the painted mark;
  /// the image is already a round disc so it clips to a circle either way,
  /// and the flag now has no visual effect. Left as a named parameter so no
  /// caller had to change on the rebrand.
  final bool ringed;

  @override
  Widget build(BuildContext context) {
    final chosen = path;
    final file = (chosen != null && chosen.trim().isNotEmpty)
        ? File(chosen)
        : null;
    final useFile = file != null && file.existsSync();
    return ClipOval(
      child: useFile
          ? Image.file(
              file,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => _bundled(size),
            )
          : _bundled(size),
    );
  }

  static Image _bundled(double size) => Image.asset(
    'assets/brand/classy-closet-mark.jpg',
    width: size,
    height: size,
    fit: BoxFit.cover,
    // A missing asset would leave a broken frame on the login card, so we
    // draw a plain warm-black square with the accent as a fallback ring.
    errorBuilder: (_, _, _) => Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.brand,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.gold, width: 2),
      ),
    ),
  );
}

/// The larger photograph-scale version of the mark used on the login and the
/// first-run setup screens.
///
/// Kept as a thin alias over [BrandMark] so the two never drift out of step
/// when the shop rebrands — they are the same image at different sizes.
class ClassyClosetPhotoMark extends StatelessWidget {
  const ClassyClosetPhotoMark({super.key, this.size = 120, this.path});

  final double size;
  final String? path;

  @override
  Widget build(BuildContext context) => BrandMark(size: size, path: path);
}

/// The wordmark: name, then the subtitle line from the store profile.
///
/// The subtitle is a field on the profile so a second shop reads its own line
/// here — "MEN'S FASHION STORE" is the seed, not a fixed piece of text.
class BrandWordmark extends StatelessWidget {
  const BrandWordmark({
    super.key,
    this.name = 'CLASSY CLOSET',
    this.size = 15,
    this.color = AppColors.ink,
    this.subColor = AppColors.inkFaint,
    this.subtitle,
    this.tagline,
    this.align = CrossAxisAlignment.start,
  });

  /// The shop's own name. Comes from the store profile wherever the profile
  /// has been loaded.
  final String name;

  final double size;
  final Color color;
  final Color subColor;

  /// The small line under the shop name. Null omits it — used in tight places
  /// like the rail where the name alone is enough.
  final String? subtitle;

  /// The second strapline line. Left off in tight places like the rail.
  final String? tagline;
  final CrossAxisAlignment align;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: align,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          name,
          textAlign: align == CrossAxisAlignment.center
              ? TextAlign.center
              : TextAlign.start,
          style: TextStyle(
            fontFamily: AppTypography.display,
            fontSize: size,
            fontWeight: FontWeight.w700,
            color: color,
            letterSpacing: 2.0,
          ),
        ),
        if (subtitle != null && subtitle!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              subtitle!,
              textAlign: align == CrossAxisAlignment.center
                  ? TextAlign.center
                  : TextAlign.start,
              style: TextStyle(
                fontFamily: AppTypography.sans,
                fontSize: size * 0.52,
                fontWeight: FontWeight.w600,
                color: subColor,
                letterSpacing: 1.6,
              ),
            ),
          ),
        if (tagline != null && tagline!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Text(
              tagline!,
              textAlign: align == CrossAxisAlignment.center
                  ? TextAlign.center
                  : TextAlign.start,
              style: TextStyle(
                fontFamily: AppTypography.sans,
                fontSize: size * 0.5,
                fontStyle: FontStyle.italic,
                color: subColor,
              ),
            ),
          ),
      ],
    );
  }
}
