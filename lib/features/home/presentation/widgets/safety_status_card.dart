import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/gradient_border_card.dart';
import '../../../../core/widgets/safety_shield.dart';

/// The hero card: whether everyone is accounted for.
class SafetyStatusCard extends StatelessWidget {
  const SafetyStatusCard({
    super.key,
    this.status = 'All Safe',
    this.lastCheckIn = 'Just now',
    this.detail = 'Your status has been confirmed.',
  });

  final String status;
  final String lastCheckIn;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return GradientBorderCard(
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 20),
      radius: 24,
      child: Row(
        children: [
          const SafetyShield(size: 58),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  status,
                  style: const TextStyle(
                    fontSize: 23,
                    fontWeight: FontWeight.w700,
                    height: 1.1,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text.rich(
                  TextSpan(
                    style: const TextStyle(
                      fontSize: 12.5,
                      height: 1.35,
                      color: AppColors.textMuted,
                    ),
                    children: [
                      const TextSpan(text: 'Last check-in: '),
                      TextSpan(
                        text: lastCheckIn,
                        style: const TextStyle(
                          color: AppColors.mint,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  style: const TextStyle(
                    fontSize: 12.5,
                    height: 1.35,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          const _PulseRing(),
        ],
      ),
    );
  }
}

/// Breathing gradient ring — a quiet "this is live" signal.
class _PulseRing extends StatefulWidget {
  const _PulseRing();

  @override
  State<_PulseRing> createState() => _PulseRingState();
}

class _PulseRingState extends State<_PulseRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        final t = Curves.easeInOut.transform(_c.value);
        return SizedBox(
          width: 68,
          height: 68,
          child: CustomPaint(
            painter: _RingPainter(0.55 + 0.35 * t),
            child: const Center(
              child: Icon(Icons.favorite_rounded,
                  size: 26, color: AppColors.mint),
            ),
          ),
        );
      },
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.opacity);

  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final centre = rect.center;
    final radius = size.width / 2 - 3;

    // Track.
    canvas.drawCircle(
      centre,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..color = Colors.white.withValues(alpha: 0.07),
    );

    // Gradient arc, leaving a gap so it reads as progress rather than a ring.
    canvas.drawArc(
      Rect.fromCircle(center: centre, radius: radius),
      -math.pi / 2,
      math.pi * 1.75,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(
          startAngle: -math.pi / 2,
          endAngle: 3 * math.pi / 2,
          colors: [
            AppColors.aqua.withValues(alpha: opacity),
            AppColors.mint.withValues(alpha: opacity),
            AppColors.aqua.withValues(alpha: opacity),
          ],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.opacity != opacity;
}
