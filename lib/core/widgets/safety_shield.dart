import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// The "All Safe" mark: a filled shield with a darker inner shield and a
/// white check.
///
/// Drawn rather than taken from Material Icons, which only offers a plain
/// silhouette — the two-tone inset is most of what gives this its depth.
/// Proportions are measured from the reference art: height is 1.194x width,
/// the top peaks at centre and falls to shoulders at 18% height, the body
/// runs full width to the halfway mark, then tapers to a point.
class SafetyShield extends StatelessWidget {
  const SafetyShield({
    super.key,
    this.size = 66,
    this.gradient,
    this.checkColor = Colors.white,
  });

  /// Width. Height follows the reference aspect ratio.
  final double size;

  final Gradient? gradient;
  final Color checkColor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size * _ShieldPainter.aspect,
      child: CustomPaint(
        painter: _ShieldPainter(
          gradient: gradient ?? AppColors.shieldGradient,
          checkColor: checkColor,
        ),
      ),
    );
  }
}

class _ShieldPainter extends CustomPainter {
  const _ShieldPainter({required this.gradient, required this.checkColor});

  final Gradient gradient;
  final Color checkColor;

  /// Height as a multiple of width, from the reference art.
  static const double aspect = 1.194;

  /// How far the inner shield is inset, as a fraction of the outer.
  static const double _innerInsetX = 0.127;
  static const double _innerInsetTop = 0.134;
  static const double _innerInsetBottom = 0.116;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final outer = _shieldPath(size);

    canvas.drawPath(
      outer,
      Paint()..shader = gradient.createShader(rect),
    );

    // Inner shield: the same silhouette, scaled down and re-centred, painted
    // as a translucent darkening rather than a second colour so it tracks
    // whatever gradient is passed in.
    final innerWidth = size.width * (1 - _innerInsetX * 2);
    final innerHeight =
        size.height * (1 - _innerInsetTop - _innerInsetBottom);

    final inner = _shieldPath(Size(innerWidth, innerHeight)).transform(
      Matrix4.translationValues(
        size.width * _innerInsetX,
        size.height * _innerInsetTop,
        0,
      ).storage,
    );

    canvas.drawPath(
      inner,
      Paint()..color = Colors.black.withValues(alpha: 0.13),
    );

    _drawCheck(canvas, size);
  }

  /// A heraldic shield: peak at top centre, shoulders, straight flanks to the
  /// waist, then a curve into the bottom point.
  Path _shieldPath(Size s) {
    final w = s.width;
    final h = s.height;

    return Path()
      ..moveTo(w * 0.5, 0)
      // Top edge falling to the right shoulder. Control points fitted to the
      // reference art's measured profile — the obvious guess opens the
      // shoulders about 12% too early.
      ..cubicTo(w * 0.64, h * 0.085, w * 0.77, h * 0.160, w, h * 0.181)
      // Straight flank down to the waist.
      ..lineTo(w, h * 0.50)
      // Taper into the point.
      ..cubicTo(w, h * 0.72, w * 0.82, h * 0.92, w * 0.5, h)
      // Mirror back up the left side.
      ..cubicTo(w * 0.18, h * 0.92, 0, h * 0.72, 0, h * 0.50)
      ..lineTo(0, h * 0.181)
      ..cubicTo(w * 0.23, h * 0.160, w * 0.36, h * 0.085, w * 0.5, 0)
      ..close();
  }

  void _drawCheck(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final path = Path()
      ..moveTo(w * 0.30, h * 0.52)
      ..lineTo(w * 0.44, h * 0.65)
      ..lineTo(w * 0.72, h * 0.37);

    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.115
        ..strokeCap = StrokeCap.square
        ..strokeJoin = StrokeJoin.miter
        ..color = checkColor,
    );
  }

  @override
  bool shouldRepaint(_ShieldPainter old) =>
      old.gradient != gradient || old.checkColor != checkColor;
}
