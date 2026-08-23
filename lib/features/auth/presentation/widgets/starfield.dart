import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// Drifting dots and soft arcs behind the welcome content.
///
/// Positions come from a fixed seed, so the layout is identical on every
/// launch and across hot reloads.
class Starfield extends StatelessWidget {
  const Starfield({super.key, required this.t});

  /// 0..1, looping.
  final double t;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(painter: _StarfieldPainter(t), size: Size.infinite),
    );
  }
}

class _StarfieldPainter extends CustomPainter {
  _StarfieldPainter(this.t);

  final double t;

  static final List<_Star> _stars = _generate();

  static List<_Star> _generate() {
    final rng = math.Random(20260822);
    return List.generate(46, (i) {
      return _Star(
        x: rng.nextDouble(),
        y: rng.nextDouble(),
        r: 0.7 + rng.nextDouble() * 1.7,
        phase: rng.nextDouble(),
        color: [
          AppColors.neonCyan,
          AppColors.softWhite,
          AppColors.neonPurple,
          AppColors.neonPink,
        ][rng.nextInt(4)],
      );
    });
  }

  @override
  void paint(Canvas canvas, Size size) {
    // Sweeping arcs, echoing the orbit lines in the brand art.
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..shader = const LinearGradient(
        colors: [Colors.transparent, AppColors.neonPurple, Colors.transparent],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    for (var i = 0; i < 3; i++) {
      final rect = Rect.fromCenter(
        center: Offset(size.width * 0.5, size.height * (0.30 + i * 0.10)),
        width: size.width * (1.15 + i * 0.22),
        height: size.height * (0.52 + i * 0.14),
      );
      canvas.drawArc(rect, math.pi * 0.15, math.pi * 0.70, false, arc);
    }

    for (final s in _stars) {
      final twinkle = 0.35 + 0.65 * (0.5 + 0.5 * math.sin(2 * math.pi * (t + s.phase)));
      final drift = math.sin(2 * math.pi * (t + s.phase)) * 3;

      canvas.drawCircle(
        Offset(s.x * size.width, s.y * size.height + drift),
        s.r,
        Paint()
          ..color = s.color.withValues(alpha: 0.55 * twinkle)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.4),
      );
    }
  }

  @override
  bool shouldRepaint(_StarfieldPainter old) => old.t != t;
}

class _Star {
  const _Star({
    required this.x,
    required this.y,
    required this.r,
    required this.phase,
    required this.color,
  });

  final double x, y, r, phase;
  final Color color;
}
