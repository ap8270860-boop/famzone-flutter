import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/gradient_border_card.dart';
import '../../../../core/widgets/safety_shield.dart';
import '../../../safety/data/safety_models.dart';

/// The hero card: whether everything is accounted for.
///
/// Every word on it comes from the server. The client picks colours and
/// animation, never wording — "All Safe" has to mean the same thing here as
/// it does on the web dashboard, and that only holds if one place decides it.
class SafetyStatusCard extends StatelessWidget {
  const SafetyStatusCard({super.key, this.status, this.loading = false});

  final SafetyStatus? status;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    if (status == null) {
      return _SafetyStatusSkeleton(shimmer: loading);
    }

    final s = status!;
    final accent = _accentFor(s.tone);

    return GradientBorderCard(
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 20),
      radius: 24,
      gradient: s.tone == SafetyTone.positive ? null : _strokeFor(accent),
      child: Row(
        children: [
          SafetyShield(size: 58, gradient: _shieldFor(s.tone)),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Animated so a state change reads as a change rather than a
                // repaint the eye misses.
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 260),
                  child: Text(
                    s.headline,
                    key: ValueKey(s.headline),
                    style: const TextStyle(
                      fontSize: 23,
                      fontWeight: FontWeight.w700,
                      height: 1.1,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(height: 7),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 260),
                  child: Text(
                    s.detail,
                    key: ValueKey(s.detail),
                    style: const TextStyle(
                      fontSize: 12.5,
                      height: 1.35,
                      color: AppColors.textMuted,
                    ),
                  ),
                ),
                if (s.checkIn.currentStreak > 1) ...[
                  const SizedBox(height: 9),
                  _StreakPill(days: s.checkIn.currentStreak, accent: accent),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          _PulseRing(accent: accent, tone: s.tone),
        ],
      ),
    );
  }

  static Color _accentFor(SafetyTone tone) => switch (tone) {
        SafetyTone.critical => AppColors.alertRed,
        SafetyTone.caution => AppColors.warmGold,
        SafetyTone.positive => AppColors.mint,
      };

  /// The shield keeps the brand gradient when all is well, and takes the
  /// state colour when it is not — a green shield above the words "Needs
  /// Attention" would undercut them.
  static Gradient _shieldFor(SafetyTone tone) => switch (tone) {
        SafetyTone.positive => AppColors.shieldGradient,
        SafetyTone.caution => const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFF2D26B), AppColors.warmGold, Color(0xFFC79A2A)],
          ),
        SafetyTone.critical => const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFF8199), AppColors.alertRed, Color(0xFFC9203F)],
          ),
      };

  static Gradient _strokeFor(Color accent) => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          accent.withValues(alpha: 0.65),
          accent.withValues(alpha: 0.18),
        ],
      );
}

/// "5 day streak" — small, and only once it means something.
class _StreakPill extends StatelessWidget {
  const _StreakPill({required this.days, required this.accent});

  final int days;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: accent.withValues(alpha: 0.12),
        border: Border.all(color: accent.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.local_fire_department_rounded, size: 13, color: accent),
          const SizedBox(width: 4),
          Text(
            '$days day streak',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: accent,
            ),
          ),
        ],
      ),
    );
  }
}

/// Placeholder while the first status is in flight.
///
/// Shaped like the real card so the layout does not jump when data arrives —
/// a spinner in the middle of the screen would shift everything below it.
class _SafetyStatusSkeleton extends StatelessWidget {
  const _SafetyStatusSkeleton({required this.shimmer});

  final bool shimmer;

  @override
  Widget build(BuildContext context) {
    Widget bar(double width, double height) => Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            color: Colors.white.withValues(alpha: shimmer ? 0.09 : 0.05),
          ),
        );

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
                bar(120, 20),
                const SizedBox(height: 11),
                bar(double.infinity, 11),
                const SizedBox(height: 6),
                bar(150, 11),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Breathing gradient ring — a quiet "this is live" signal.
class _PulseRing extends StatefulWidget {
  const _PulseRing({required this.accent, required this.tone});

  final Color accent;
  final SafetyTone tone;

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
  void didUpdateWidget(_PulseRing old) {
    super.didUpdateWidget(old);

    // An alert should feel urgent, not serene.
    final wanted = widget.tone == SafetyTone.critical
        ? const Duration(milliseconds: 900)
        : const Duration(milliseconds: 2600);

    if (_c.duration != wanted) {
      _c.duration = wanted;
      _c
        ..reset()
        ..repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final icon = switch (widget.tone) {
      SafetyTone.critical => Icons.priority_high_rounded,
      SafetyTone.caution => Icons.schedule_rounded,
      SafetyTone.positive => Icons.favorite_rounded,
    };

    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        final t = Curves.easeInOut.transform(_c.value);
        return SizedBox(
          width: 68,
          height: 68,
          child: CustomPaint(
            painter: _RingPainter(0.55 + 0.35 * t, widget.accent),
            child: Center(
              child: Icon(icon, size: 26, color: widget.accent),
            ),
          ),
        );
      },
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.opacity, this.accent);

  final double opacity;
  final Color accent;

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
            accent.withValues(alpha: opacity * 0.75),
            accent.withValues(alpha: opacity),
            accent.withValues(alpha: opacity * 0.75),
          ],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.opacity != opacity || old.accent != accent;
}
