import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/pulse_rings.dart';

/// Hold to raise the alarm.
///
/// A tap would be wrong here, and the reason is worth stating: this button
/// wakes up an entire family. A pocket press, a curious child, a mis-aimed
/// thumb reaching for the tab beside it — each of those becomes a phone
/// ringing at two in the morning. So it takes a deliberate, sustained gesture
/// that no accident produces.
///
/// But not *too* deliberate. Somebody being followed down a street has
/// seconds and shaking hands. Two seconds is the number: long enough that
/// nothing accidental survives it, short enough that it never feels like the
/// app is arguing with you.
///
/// Three channels say the same thing at once, because in an emergency any one
/// of them may be the only one getting through — a filling ring you can see,
/// haptic ticks you can feel, and a swelling glow at the edge of vision.
/// Letting go before the end cancels cleanly and says so.
class SosHoldButton extends StatefulWidget {
  const SosHoldButton({
    super.key,
    required this.onActivate,
    this.busy = false,
    this.size = 208,
  });

  final VoidCallback onActivate;
  final bool busy;
  final double size;

  @override
  State<SosHoldButton> createState() => _SosHoldButtonState();
}

class _SosHoldButtonState extends State<SosHoldButton>
    with TickerProviderStateMixin {
  static const Duration _hold = Duration(milliseconds: 2000);

  late final AnimationController _fill = AnimationController(
    vsync: this,
    duration: _hold,
  )..addStatusListener(_onFilled);

  /// The idle breathing, so the button looks alive before it is touched.
  late final AnimationController _breathe = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  )..repeat(reverse: true);

  bool _holding = false;

  /// Haptic ticks at each quarter, so the progress is felt as well as seen.
  int _lastTick = 0;

  @override
  void initState() {
    super.initState();

    _fill.addListener(_onProgress);
  }

  @override
  void dispose() {
    _fill.removeListener(_onProgress);
    _fill.dispose();
    _breathe.dispose();

    super.dispose();
  }

  void _onProgress() {
    final tick = (_fill.value * 4).floor();

    if (tick != _lastTick && tick > 0 && tick < 4) {
      _lastTick = tick;

      // Light, and getting no heavier. An escalating buzz reads as the phone
      // panicking, which is the opposite of what somebody needs from it.
      HapticFeedback.selectionClick();
    }
  }

  void _onFilled(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;

    HapticFeedback.heavyImpact();

    setState(() => _holding = false);

    _fill.reset();
    _lastTick = 0;

    widget.onActivate();
  }

  void _start() {
    if (widget.busy) return;

    setState(() => _holding = true);

    _lastTick = 0;

    HapticFeedback.mediumImpact();

    _fill.forward(from: 0);
  }

  void _cancel() {
    if (!_holding) return;

    setState(() => _holding = false);

    // Runs back rather than snapping to zero, so a slip reads as "not yet"
    // rather than as the app having rejected you.
    _fill.reverse();
    _lastTick = 0;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _start(),
      onTapUp: (_) => _cancel(),
      onTapCancel: _cancel,
      behavior: HitTestBehavior.opaque,
      child: AnimatedBuilder(
        animation: Listenable.merge([_fill, _breathe]),
        builder: (context, _) {
          final progress = _fill.value;
          final breath = _holding ? 0.0 : _breathe.value;

          return SizedBox(
            width: widget.size,
            height: widget.size,
            child: Stack(
              alignment: Alignment.center,
              children: [
                /*
                 | The wave, while idle only.
                 |
                 | Switched off the moment a hold starts. The filling
                 | progress ring takes over as the thing that is moving, and
                 | two animations in the same space would make it harder to
                 | read how far through the hold you are — which is the one
                 | piece of information that matters here.
                 */
                Positioned.fill(
                  child: PulseRings(
                    color: AppColors.alertRed,
                    innerRadius: widget.size * 0.31,
                    outerRadius: widget.size / 2,
                    period: const Duration(milliseconds: 2800),
                    peakOpacity: 0.40,
                    strokeWidth: 1.6,
                    running: !_holding && !widget.busy,
                  ),
                ),

                // The halo. Grows with the hold, breathes when idle.
                Container(
                  width: widget.size * (0.86 + 0.06 * breath + 0.14 * progress),
                  height: widget.size * (0.86 + 0.06 * breath + 0.14 * progress),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.alertRed
                        .withValues(alpha: 0.10 + 0.18 * progress),
                  ),
                ),

                CustomPaint(
                  size: Size.square(widget.size),
                  painter: _HoldRingPainter(progress: progress),
                ),

                // The button itself.
                AnimatedScale(
                  scale: _holding ? 0.94 : 1.0,
                  duration: const Duration(milliseconds: 140),
                  child: Container(
                    width: widget.size * 0.62,
                    height: widget.size * 0.62,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: AppColors.sosGradient,
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.alertRed
                              .withValues(alpha: 0.30 + 0.35 * progress),
                          blurRadius: 26 + 22 * progress,
                          spreadRadius: 1 + 3 * progress,
                        ),
                      ],
                    ),
                    child: Center(
                      child: widget.busy
                          ? const SizedBox(
                              width: 30,
                              height: 30,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.6,
                                color: Colors.white,
                              ),
                            )
                          : Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.sos_rounded,
                                  size: 40,
                                  color: Colors.white,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _holding ? 'KEEP HOLDING' : 'HOLD',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1.6,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// The ring that fills while you hold.
class _HoldRingPainter extends CustomPainter {
  const _HoldRingPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 6;

    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..color = Colors.white.withValues(alpha: 0.10);

    canvas.drawCircle(centre, radius, track);

    if (progress <= 0) return;

    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..shader = const SweepGradient(
        colors: [AppColors.alertRed, AppColors.neonPink, AppColors.alertRed],
      ).createShader(Rect.fromCircle(center: centre, radius: radius));

    canvas.drawArc(
      Rect.fromCircle(center: centre, radius: radius),
      // From the top, clockwise — the direction every progress ring people
      // have ever seen goes.
      -math.pi / 2,
      2 * math.pi * progress,
      false,
      arc,
    );
  }

  @override
  bool shouldRepaint(_HoldRingPainter old) => old.progress != progress;
}
