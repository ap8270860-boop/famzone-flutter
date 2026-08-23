import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Slowly drifting colour fields behind the glass surfaces.
///
/// This is what makes the glass read as *liquid* rather than as a flat
/// translucent panel — the blur has something moving to refract.
class AuroraBackground extends StatefulWidget {
  const AuroraBackground({super.key, this.child});

  final Widget? child;

  @override
  State<AuroraBackground> createState() => _AuroraBackgroundState();
}

class _AuroraBackgroundState extends State<AuroraBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 18),
    )..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(color: AppColors.canvas),
      child: Stack(
        fit: StackFit.expand,
        children: [
          RepaintBoundary(
            child: AnimatedBuilder(
              animation: _c,
              builder: (_, __) => CustomPaint(
                painter: _AuroraPainter(_c.value),
                size: Size.infinite,
              ),
            ),
          ),
          if (widget.child != null) widget.child!,
        ],
      ),
    );
  }
}

class _AuroraPainter extends CustomPainter {
  _AuroraPainter(this.t);

  final double t;

  static const _blobs = <_Blob>[
    _Blob(AppColors.aqua, 0.18, 0.16, 0.72, 0.00),
    _Blob(AppColors.mint, 0.86, 0.30, 0.62, 0.35),
    _Blob(AppColors.electricBlue, 0.30, 0.78, 0.80, 0.65),
    _Blob(AppColors.neonPurple, 0.80, 0.88, 0.58, 0.85),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final shortest = size.shortestSide;

    for (final b in _blobs) {
      final angle = 2 * math.pi * (t + b.phase);
      final cx = size.width * b.x + math.cos(angle) * size.width * 0.10;
      final cy = size.height * b.y + math.sin(angle) * size.height * 0.06;
      final radius = shortest * b.scale;

      canvas.drawCircle(
        Offset(cx, cy),
        radius,
        Paint()
          ..shader = RadialGradient(
            colors: [
              b.color.withValues(alpha: 0.22),
              b.color.withValues(alpha: 0.0),
            ],
          ).createShader(
            Rect.fromCircle(center: Offset(cx, cy), radius: radius),
          ),
      );
    }
  }

  @override
  bool shouldRepaint(_AuroraPainter old) => old.t != t;
}

class _Blob {
  const _Blob(this.color, this.x, this.y, this.scale, this.phase);

  final Color color;
  final double x, y, scale, phase;
}
