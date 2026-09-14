import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// How a reminder category looks, and how it moves.
///
/// The colours come from the server so a category added by seed arrives fully
/// dressed. The *motion* cannot: an animation is code, and the best a server
/// can do is name one. So each category carries a `vibe` string and this file
/// is the lookup from that name to something that actually moves — with a
/// plain fallback, because a category invented after this build shipped must
/// render as calm rather than as a hole.
///
/// Everything here is drawn rather than loaded. No Lottie, no video, no image
/// pipeline: a gradient and two or three moving shapes in a CustomPainter cost
/// nothing to ship, scale to any screen, and recolour themselves from the
/// server's hex pair for free.
class CategoryTheme {
  const CategoryTheme({
    required this.from,
    required this.to,
    required this.vibe,
  });

  final Color from;
  final Color to;
  final String vibe;

  /// Parses "#RRGGBB" or "#AARRGGBB", falling back to the app's own blue.
  ///
  /// A bad colour from the server must never throw during a build — it would
  /// take the whole picker down over a typo in a seed file.
  static Color parse(String? hex, {Color fallback = AppColors.aqua}) {
    if (hex == null) return fallback;

    var value = hex.trim().replaceFirst('#', '');

    if (value.length == 6) value = 'FF$value';
    if (value.length != 8) return fallback;

    final parsed = int.tryParse(value, radix: 16);

    return parsed == null ? fallback : Color(parsed);
  }

  static CategoryTheme of(String? from, String? to, String? vibe) =>
      CategoryTheme(
        from: parse(from),
        to: parse(to, fallback: AppColors.mint),
        vibe: vibe ?? 'plain',
      );

  LinearGradient get gradient => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [from, to],
      );

  /// A tint for text and glyphs sitting on the app's dark canvas beside this
  /// category — not on the gradient itself.
  Color get accent => Color.lerp(from, to, 0.5) ?? from;

  /// Ink that stays legible on the gradient.
  ///
  /// Computed from luminance rather than fixed to white: the morning and
  /// fitness gradients are bright enough that white text on them is genuinely
  /// hard to read, and a category added later could be brighter still.
  Color get onGradient {
    final mid = accent;

    return mid.computeLuminance() > 0.55
        ? const Color(0xFF04121F)
        : Colors.white;
  }

  /// Material icon for a server-sent name.
  ///
  /// A lookup and not a codepoint, deliberately. Building an IconData from a
  /// number at runtime works perfectly in debug and draws empty boxes in
  /// release, because Flutter's icon tree-shaker strips any glyph it cannot
  /// see referenced in the source at compile time. Every icon this app can
  /// ever show has to appear literally, somewhere — so here they all are.
  static IconData icon(String? name) => switch (name) {
        'sunny' => Icons.wb_sunny_rounded,
        'alarm' => Icons.alarm_rounded,
        'water_drop' => Icons.water_drop_rounded,
        'shower' => Icons.shower_rounded,
        'breakfast' => Icons.free_breakfast_rounded,
        'self_improvement' => Icons.self_improvement_rounded,
        'school' => Icons.school_rounded,
        'account_balance' => Icons.account_balance_rounded,
        'edit_note' => Icons.edit_note_rounded,
        'menu_book' => Icons.menu_book_rounded,
        'assignment' => Icons.assignment_rounded,
        'work' => Icons.work_rounded,
        'business' => Icons.business_rounded,
        'groups' => Icons.groups_rounded,
        'coffee' => Icons.local_cafe_rounded,
        'record_voice_over' => Icons.record_voice_over_rounded,
        'logout' => Icons.logout_rounded,
        'fitness' => Icons.fitness_center_rounded,
        'run' => Icons.directions_run_rounded,
        'walk' => Icons.directions_walk_rounded,
        'spa' => Icons.spa_rounded,
        'family' => Icons.family_restroom_rounded,
        'call' => Icons.call_rounded,
        'child' => Icons.child_care_rounded,
        'directions_bus' => Icons.directions_bus_rounded,
        'cake' => Icons.cake_rounded,
        'person' => Icons.person_rounded,
        'shopping' => Icons.shopping_bag_rounded,
        'bank' => Icons.account_balance_wallet_rounded,
        'stethoscope' => Icons.medical_services_rounded,
        'content_cut' => Icons.content_cut_rounded,
        'receipt' => Icons.receipt_long_rounded,
        'home' => Icons.home_rounded,
        'travel' => Icons.luggage_rounded,
        'flag' => Icons.flag_rounded,
        'flight' => Icons.flight_takeoff_rounded,
        'luggage' => Icons.luggage_rounded,
        'night' => Icons.nightlight_round,
        'bed' => Icons.bed_rounded,
        'medicine' => Icons.medication_rounded,
        'restaurant' => Icons.restaurant_rounded,
        'celebration' => Icons.celebration_rounded,
        'movie' => Icons.movie_rounded,
        'music' => Icons.music_note_rounded,
        'palette' => Icons.palette_rounded,
        'game' => Icons.sports_esports_rounded,
        'sports_esports' => Icons.sports_esports_rounded,
        'timer_off' => Icons.timer_off_rounded,
        'add' => Icons.add_rounded,
        // Unknown name: a neutral bell rather than nothing. The server is
        // allowed to invent categories after this build has shipped, and a
        // missing glyph must not be a hole in the picker.
        _ => Icons.notifications_active_rounded,
      };
}

/// The moving backdrop behind a category tile or header.
///
/// One widget for every vibe, switching on the name. Motion is slow and
/// low-contrast on purpose: this sits *behind* a name and an icon that people
/// need to read, and an animation that competes with its own label is
/// decoration that costs comprehension.
class VibeBackdrop extends StatefulWidget {
  const VibeBackdrop({
    super.key,
    required this.theme,
    this.animate = true,
  });

  final CategoryTheme theme;

  /// Off for tiles in a long scrolling list.
  ///
  /// Twelve simultaneous animations is twelve tickers repainting every frame
  /// for decoration nobody is looking at — it shows up immediately as jank on
  /// the mid-range Android this app is mostly used on. The picker animates the
  /// selected tile only; the editor header, where there is one, animates
  /// freely.
  final bool animate;

  @override
  State<VibeBackdrop> createState() => _VibeBackdropState();
}

class _VibeBackdropState extends State<VibeBackdrop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      // Long and unhurried. A six-second loop reads as ambient; a two-second
      // one reads as a loading spinner.
      duration: const Duration(seconds: 6),
    );

    if (widget.animate) _controller.repeat();
  }

  @override
  void didUpdateWidget(covariant VibeBackdrop old) {
    super.didUpdateWidget(old);

    if (widget.animate && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.animate && _controller.isAnimating) {
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
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: DecoratedBox(
        decoration: BoxDecoration(gradient: widget.theme.gradient),
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => CustomPaint(
            painter: _VibePainter(
              vibe: widget.theme.vibe,
              t: _controller.value,
              ink: widget.theme.onGradient,
            ),
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
  }
}

/// Draws the motion for one vibe.
///
/// Every shape is translucent ink over the gradient rather than a new colour,
/// so a category recoloured by a seed edit keeps a coherent look without this
/// file knowing anything about it.
class _VibePainter extends CustomPainter {
  const _VibePainter({
    required this.vibe,
    required this.t,
    required this.ink,
  });

  final String vibe;

  /// 0 to 1, looping.
  final double t;

  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;

    switch (vibe) {
      case 'sunrise':
        // A sun climbing, and rays that breathe.
        final rise = size.height * (0.92 - 0.12 * _wave(t));

        paint.color = ink.withValues(alpha: 0.16);
        canvas.drawCircle(Offset(size.width * 0.78, rise), size.height * 0.34, paint);

        paint.color = ink.withValues(alpha: 0.08);
        canvas.drawCircle(Offset(size.width * 0.78, rise), size.height * 0.52, paint);
        break;

      case 'pulse':
        // A heartbeat: two rings expanding out of one point.
        for (var i = 0; i < 2; i++) {
          final phase = (t + i * 0.5) % 1.0;

          paint.color = ink.withValues(alpha: 0.22 * (1 - phase));
          canvas.drawCircle(
            Offset(size.width * 0.8, size.height * 0.5),
            size.height * (0.12 + 0.5 * phase),
            paint,
          );
        }
        break;

      case 'stars':
        // A fixed constellation that twinkles out of phase.
        const seeds = [
          [0.14, 0.28], [0.32, 0.62], [0.52, 0.22],
          [0.68, 0.72], [0.84, 0.38], [0.92, 0.74],
        ];

        for (var i = 0; i < seeds.length; i++) {
          final phase = (t + i / seeds.length) % 1.0;

          paint.color = ink.withValues(alpha: 0.18 + 0.34 * _wave(phase));
          canvas.drawCircle(
            Offset(size.width * seeds[i][0], size.height * seeds[i][1]),
            1.6 + 1.1 * _wave(phase),
            paint,
          );
        }
        break;

      case 'drift':
        // Clouds crossing, wrapping at the edge.
        for (var i = 0; i < 3; i++) {
          final x = ((t + i / 3) % 1.0) * (size.width + 90) - 45;

          paint.color = ink.withValues(alpha: 0.12);
          canvas.drawOval(
            Rect.fromCenter(
              center: Offset(x, size.height * (0.3 + 0.22 * i)),
              width: 74,
              height: 20,
            ),
            paint,
          );
        }
        break;

      case 'focus':
        // Concentric rings tightening — attention narrowing.
        for (var i = 0; i < 3; i++) {
          final phase = (t + i / 3) % 1.0;

          paint
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.4
            ..color = ink.withValues(alpha: 0.24 * (1 - phase));

          canvas.drawCircle(
            Offset(size.width * 0.82, size.height * 0.5),
            size.height * (0.62 - 0.42 * phase),
            paint,
          );
        }

        paint.style = PaintingStyle.fill;
        break;

      case 'care':
        // One slow, steady breath. Medicine should feel calm, not urgent —
        // this is the animation most likely to be seen three times a day
        // every day, by somebody who is unwell.
        paint.color = ink.withValues(alpha: 0.10 + 0.06 * _wave(t));
        canvas.drawCircle(
          Offset(size.width * 0.82, size.height * 0.5),
          size.height * (0.34 + 0.05 * _wave(t)),
          paint,
        );
        break;

      case 'confetti':
        for (var i = 0; i < 7; i++) {
          final phase = (t + i / 7) % 1.0;
          final x = size.width * (0.1 + 0.12 * i);

          paint.color = ink.withValues(alpha: 0.30 * (1 - phase));
          canvas.drawRect(
            Rect.fromCenter(
              center: Offset(x, size.height * phase),
              width: 4,
              height: 8,
            ),
            paint,
          );
        }
        break;

      case 'arcade':
        // A scanline sweeping down.
        paint.color = ink.withValues(alpha: 0.14);
        canvas.drawRect(
          Rect.fromLTWH(0, size.height * t, size.width, 3),
          paint,
        );

        for (var i = 0; i < 4; i++) {
          paint.color = ink.withValues(alpha: 0.10);
          canvas.drawRect(
            Rect.fromLTWH(size.width * (0.08 + 0.22 * i), size.height * 0.72, 6, 6),
            paint,
          );
        }
        break;

      case 'warmth':
        // Two soft overlapping glows, leaning together.
        paint.color = ink.withValues(alpha: 0.12);
        canvas.drawCircle(
          Offset(size.width * (0.72 + 0.03 * _wave(t)), size.height * 0.42),
          size.height * 0.3,
          paint,
        );
        canvas.drawCircle(
          Offset(size.width * (0.86 - 0.03 * _wave(t)), size.height * 0.58),
          size.height * 0.26,
          paint,
        );
        break;

      case 'steady':
        // A bar chart that barely moves. Work is not exciting.
        for (var i = 0; i < 4; i++) {
          final h = size.height * (0.22 + 0.1 * ((i + t) % 1.0));

          paint.color = ink.withValues(alpha: 0.13);
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(
                size.width * (0.66 + 0.07 * i),
                size.height - h - 6,
                8,
                h,
              ),
              const Radius.circular(3),
            ),
            paint,
          );
        }
        break;

      case 'calm':
        // A single slow wave.
        final path = Path()..moveTo(0, size.height * 0.72);

        for (var x = 0.0; x <= size.width; x += 6) {
          final y = size.height * 0.72 +
              8 * _sin((x / size.width + t) * 2);
          path.lineTo(x, y);
        }

        path
          ..lineTo(size.width, size.height)
          ..lineTo(0, size.height)
          ..close();

        paint.color = ink.withValues(alpha: 0.12);
        canvas.drawPath(path, paint);
        break;

      default:
        // 'plain', and anything the server invents later. Still gets the
        // gradient; simply does not move.
        break;
    }
  }

  /// A 0→1→0 ease, without importing dart:math for one curve.
  static double _wave(double t) => t < 0.5 ? t * 2 : (1 - t) * 2;

  /// A cheap sine over turns, accurate enough for a decorative wave.
  static double _sin(double turns) {
    final x = (turns % 1.0) * 4 - 1;
    final tri = x < 1 ? x : 3 - x - 2 * (x - 1);

    return tri.clamp(-1.0, 1.0);
  }

  @override
  bool shouldRepaint(_VibePainter old) => old.t != t || old.vibe != vibe;
}
