import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_typography.dart';

/// The shop's identity, drawn rather than photographed.
///
/// The supplied artwork is a JPEG on a solid black disc. Pasting it onto a
/// dark rail leaves a visible square edge, and onto a light card a heavy black
/// coin — so the mark is redrawn here as a gold ring with the hanger and the
/// initials. It scales cleanly, tints to whatever ground it sits on, and adds
/// nothing to the install size.
///
/// [ClassyCloasetPhotoMark] shows the real artwork where a photograph belongs:
/// the login panel and the setup screen.
class BrandMark extends StatelessWidget {
  const BrandMark({
    super.key,
    this.size = 34,
    this.color = AppColors.gold,
    this.ringed = true,
  });

  final double size;
  final Color color;

  /// The circle around the mark. Dropped at small sizes where it closes up.
  final bool ringed;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _HangerPainter(color: color, ringed: ringed),
      ),
    );
  }
}

class _HangerPainter extends CustomPainter {
  const _HangerPainter({required this.color, required this.ringed});

  final Color color;
  final bool ringed;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final stroke = (s * 0.055).clamp(1.0, 3.0);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    if (ringed) {
      canvas.drawCircle(
        Offset(s / 2, s / 2),
        s / 2 - stroke,
        paint..strokeWidth = stroke,
      );
    }

    // The hanger: a hook, then the shoulders sloping down to the bar.
    final inset = ringed ? s * 0.22 : s * 0.06;
    final top = ringed ? s * 0.30 : s * 0.16;
    final apex = Offset(s / 2, top);
    final barY = ringed ? s * 0.56 : s * 0.62;

    final hook = Path()
      ..moveTo(s / 2, top)
      ..cubicTo(
        s / 2,
        top - s * 0.10,
        s / 2 + s * 0.075,
        top - s * 0.13,
        s / 2 + s * 0.05,
        top - s * 0.055,
      );
    canvas.drawPath(hook, paint);

    final shoulders = Path()
      ..moveTo(inset, barY)
      ..lineTo(apex.dx, apex.dy + s * 0.045)
      ..lineTo(s - inset, barY);
    canvas.drawPath(shoulders, paint);

    canvas.drawLine(
      Offset(inset + s * 0.015, barY),
      Offset(s - inset - s * 0.015, barY),
      paint..strokeWidth = stroke * 0.9,
    );
  }

  @override
  bool shouldRepaint(_HangerPainter old) =>
      old.color != color || old.ringed != ringed;
}

/// The supplied artwork, for the two places a real photograph belongs.
class ClassyClosetPhotoMark extends StatelessWidget {
  const ClassyClosetPhotoMark({super.key, this.size = 120});

  final double size;

  @override
  Widget build(BuildContext context) => ClipOval(
    child: Image.asset(
      'assets/brand/classy-closet-mark.jpg',
      width: size,
      height: size,
      fit: BoxFit.cover,
      // A missing asset must never take a screen down with it.
      errorBuilder: (_, __, ___) => BrandMark(size: size),
    ),
  );
}

/// The wordmark: name, then the two lines of the shop's own strapline.
///
/// The tagline is deliberately two lines. The artwork already says "Men's
/// Fashion Store"; squeezing "Look Classy, Feel Content" onto the same line
/// would set it at a size nobody reads.
class BrandWordmark extends StatelessWidget {
  const BrandWordmark({
    super.key,
    this.size = 15,
    this.color = AppColors.brandInk,
    this.subColor = AppColors.brandInkFaint,
    this.subtitle = "MEN'S FASHION STORE",
    this.tagline,
    this.align = CrossAxisAlignment.start,
  });

  final double size;
  final Color color;
  final Color subColor;
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
          'CLASSY CLOSET',
          style: AppTypography.wordmark.copyWith(fontSize: size, color: color),
        ),
        if (subtitle != null) ...[
          SizedBox(height: size * 0.22),
          Text(
            subtitle!,
            style: AppTypography.wordmarkSub.copyWith(
              color: subColor,
              fontSize: size * 0.62,
            ),
          ),
        ],
        if (tagline != null) ...[
          SizedBox(height: size * 0.16),
          Text(
            tagline!,
            style: AppTypography.wordmarkSub.copyWith(
              color: subColor,
              fontSize: size * 0.6,
              letterSpacing: 1.4,
            ),
          ),
        ],
      ],
    );
  }
}
