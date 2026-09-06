import 'package:flutter/material.dart';

/// Rings breathing outward from a point.
///
/// The app's one piece of ambient motion, and it earns its place in exactly
/// one situation: saying "this is live, look here" without making anybody
/// read a word. It sits behind the SOS button in the nav bar, behind the
/// hold-to-activate button, and behind every emergency service's glyph — one
/// implementation rather than three copies that would drift apart.
///
/// ---------------------------------------------------------------------------
/// How to place it
/// ---------------------------------------------------------------------------
///
/// **`Positioned.fill` inside a `Stack`.** It takes whatever size it is given
/// and never asks for one of its own — which is the whole trick, because a
/// wave usually needs to reach *past* the thing it surrounds:
///
/// ```dart
/// SizedBox(
///   width: d, height: d,
///   child: Stack(
///     clipBehavior: Clip.none,
///     children: [
///       Positioned.fill(
///         child: PulseRings(innerRadius: d / 2, outerRadius: d * 0.8, ...),
///       ),
///       theThing,
///     ],
///   ),
/// )
/// ```
///
/// [outerRadius] larger than half the box is not a mistake — a CustomPainter
/// may draw outside its bounds, and nothing clips it as long as the enclosing
/// Stack is `Clip.none`. So the layout stays exactly the size of the thing
/// being decorated while the wave travels beyond it.
///
/// An earlier version tried to do that with an `OverflowBox` and broke the
/// nav bar: OverflowBox sizes itself from its *parent's* constraints, not
/// from the max it is given, so under the loose constraints of a Stack it
/// collapsed and took the button's layout with it. Painting past the edge is
/// the correct tool; growing the box is not.
///
/// ---------------------------------------------------------------------------
/// Why it looks the way it does
/// ---------------------------------------------------------------------------
///
/// Two things keep it from being irritating, which matters when it is on
/// screen all day:
///
///  - **Slow.** Two and a half seconds a cycle. Fast animation on an
///    emergency control reads as panic and measurably makes people worse at
///    the task in front of them; a slow pulse reads as a heartbeat.
///  - **Quiet.** It fades as it grows and never reaches full opacity, so it
///    registers peripherally and does not compete with the thing it is
///    drawing attention to.
///
/// Painted in a single CustomPainter rather than built as N animated widgets.
/// This repaints sixty times a second for as long as it is on screen, and a
/// painter that only touches the canvas costs a fraction of a widget subtree
/// rebuilding each frame.
///
/// Purely decorative: it never takes a hit test, so it can be laid over a
/// button without swallowing the tap.
class PulseRings extends StatefulWidget {
  const PulseRings({
    super.key,
    required this.color,
    required this.innerRadius,
    required this.outerRadius,
    this.rings = 3,
    this.period = const Duration(milliseconds: 2500),
    this.strokeWidth = 1.4,
    this.peakOpacity = 0.45,
    this.running = true,
  });

  final Color color;

  /// Where a ring is born — usually the radius of whatever it surrounds, so
  /// rings appear to leave the object rather than pass through it.
  final double innerRadius;

  /// Where it dies. May exceed half the box; see the note above.
  final double outerRadius;

  final int rings;
  final Duration period;
  final double strokeWidth;
  final double peakOpacity;

  /// False stops the animation and paints nothing.
  ///
  /// Used where a second, louder animation takes over — the hold button's
  /// filling progress ring, for instance, which would otherwise compete with
  /// this for the same space.
  final bool running;

  @override
  State<PulseRings> createState() => _PulseRingsState();
}

class _PulseRingsState extends State<PulseRings>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.period,
  );

  @override
  void initState() {
    super.initState();

    if (widget.running) _controller.repeat();
  }

  @override
  void didUpdateWidget(covariant PulseRings old) {
    super.didUpdateWidget(old);

    if (widget.period != old.period) _controller.duration = widget.period;

    // Told rather than inferred: a widget that keeps spinning after it has
    // been switched off is a frame of work per frame, forever, for nothing.
    if (widget.running && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.running && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => CustomPaint(
          // No size and no child: it takes the constraints it is handed,
          // which under Positioned.fill are the parent's exact bounds.
          painter: widget.running
              ? _PulsePainter(
                  progress: _controller.value,
                  color: widget.color,
                  innerRadius: widget.innerRadius,
                  outerRadius: widget.outerRadius,
                  rings: widget.rings,
                  strokeWidth: widget.strokeWidth,
                  peakOpacity: widget.peakOpacity,
                )
              : null,
        ),
      ),
    );
  }
}

class _PulsePainter extends CustomPainter {
  const _PulsePainter({
    required this.progress,
    required this.color,
    required this.innerRadius,
    required this.outerRadius,
    required this.rings,
    required this.strokeWidth,
    required this.peakOpacity,
  });

  final double progress;
  final Color color;
  final double innerRadius;
  final double outerRadius;
  final int rings;
  final double strokeWidth;
  final double peakOpacity;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = Offset(size.width / 2, size.height / 2);

    for (var i = 0; i < rings; i++) {
      /*
       | Each ring runs a fraction of a cycle behind the one before it, so
       | one is always leaving as another arrives and the motion never has a
       | visible gap or a moment where they all line up.
       */
      final t = (progress + i / rings) % 1.0;

      final radius = innerRadius + (outerRadius - innerRadius) * t;

      /*
       | Fades as it grows, and fades *in* over the first tenth of its life
       | — without that, a ring pops into existence at full strength right on
       | the edge of whatever it surrounds, which reads as a flicker rather
       | than a pulse.
       */
      final fade = (1.0 - t) * (t < 0.1 ? t / 0.1 : 1.0);

      canvas.drawCircle(
        centre,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..color = color.withValues(alpha: peakOpacity * fade),
      );
    }
  }

  @override
  bool shouldRepaint(_PulsePainter old) =>
      old.progress != progress ||
      old.color != color ||
      old.outerRadius != outerRadius;
}
