import 'dart:math' as math;
// Prefixed, and only for PathFillType.
//
// material.dart re-exports a fixed list of dart:ui names — Path, Paint, Rect,
// Offset and so on are all there, which is why CustomPainter code usually
// needs no extra import. PathFillType is not on that list, so naming it bare
// is a compile error rather than a lint. The prefix also guarantees it can
// never collide with anything material brings in.
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../people/presentation/widgets/person_avatar.dart';
import '../../data/check_in_chain.dart';

/// Today's check-in, as a row of faces with a bar running through them.
///
/// The question this answers is "who knows". A list of names with statuses
/// beside them would answer it too, and would be worse: the thing people
/// actually want to see is *how far it got*, which is a distance, and a
/// distance wants to be drawn rather than written.
///
/// So the bar is the primary object and the faces sit on it. It fills from the
/// first person to whoever holds the request now, which means the bar reaching
/// somebody and that person having it are the same picture. When Kulsoom
/// confirms, the bar stops at Kulsoom and Vinod and Devrat stay faint — that
/// is the whole feature, visible without reading a word.
///
/// Every colour and glyph here is keyed on the step's own status rather than
/// on its position, so a chain that ends at the second person looks exactly
/// like one that ends at the fourth.
class CheckInChainView extends StatefulWidget {
  const CheckInChainView({
    super.key,
    required this.chain,
    this.onEdit,
  });

  final CheckInChain chain;

  /// Change the order. Absent once the chain has started — rearranging a queue
  /// that is already being worked through would be a lie, since the run holds
  /// its own copy.
  final VoidCallback? onEdit;

  @override
  State<CheckInChainView> createState() => _CheckInChainViewState();
}

class _CheckInChainViewState extends State<CheckInChainView>
    with SingleTickerProviderStateMixin {
  /// One controller for the whole row.
  ///
  /// Only ever one person is being waited on, so a controller per avatar would
  /// be N animations to drive one blinking ring.
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();

    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );

    _syncPulse();
  }

  @override
  void didUpdateWidget(covariant CheckInChainView old) {
    super.didUpdateWidget(old);

    _syncPulse();
  }

  /// Run the pulse only while somebody actually holds the request.
  ///
  /// A settled chain is a still picture. Leaving a repeating animation running
  /// on a card that will sit on the home screen all day is a wakeup every
  /// frame for something nobody is waiting on.
  void _syncPulse() {
    final waiting = widget.chain.isPending && widget.chain.holder != null;

    if (waiting && !_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    } else if (!waiting && _pulse.isAnimating) {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chain = widget.chain;

    if (chain.visibleSteps.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header(chain),
        const SizedBox(height: 16),
        LayoutBuilder(builder: (context, box) => _row(chain, box.maxWidth)),
        const SizedBox(height: 13),
        _caption(chain),
      ],
    );
  }

  Widget _header(CheckInChain chain) {
    final tint = _toneColour(chain.tone);

    return Row(
      children: [
        Icon(_toneIcon(chain.tone), size: 16, color: tint),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            chain.headline,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: tint,
            ),
          ),
        ),
        if (widget.onEdit != null) ...[
          const SizedBox(width: 8),
          GestureDetector(
            onTap: widget.onEdit,
            behavior: HitTestBehavior.opaque,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 2, vertical: 4),
              child: Text(
                'Edit order',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.aqua,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _caption(CheckInChain chain) {
    return Text(
      chain.detail,
      style: const TextStyle(
        fontSize: 11.5,
        height: 1.4,
        color: AppColors.textMuted,
      ),
    );
  }

  /// The bar and the faces on it.
  ///
  /// Slot arithmetic, at a 360dp phone with 296dp of card to work with:
  ///
  ///   3 people → 98.7dp each, no scroll
  ///   5 people → 59.2dp each, no scroll — the last size that fits
  ///   6 people → held at the 58dp floor, 348dp total, scrolls
  ///
  /// The floor exists because a 44dp avatar in a 42dp slot overlaps its
  /// neighbour. Clamping only upward — never squeezing below the floor — is
  /// what makes the common case of three or four people fill the card instead
  /// of huddling in the middle of it.
  Widget _row(CheckInChain chain, double width) {
    final steps = chain.visibleSteps;
    final count = steps.length;
    final available = width.isFinite && width > 0 ? width : 296.0;

    const slotFloor = 58.0;
    final slot = math.max(available / count, slotFloor);
    final total = slot * count;

    final content = SizedBox(
      width: total,
      height: 68,
      child: Stack(
        // Badges hang off the corner of their avatar. Without this they are
        // silently clipped away at the edge of the stack.
        clipBehavior: Clip.none,
        children: [
          if (count > 1) ..._track(chain, slot, count),
          Positioned.fill(
            child: Row(
              children: [
                for (final step in steps)
                  SizedBox(
                    width: slot,
                    child: _Face(
                      step: step,
                      pulse: _pulse,
                      settled: !chain.isPending,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );

    // A hair of tolerance: total and available are the same number by
    // construction in the non-scrolling case, and floating point should not be
    // allowed to turn that into a scrollable with one pixel of travel.
    if (total <= available + 0.5) return content;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: content,
    );
  }

  /// The track, and the part of it that has been covered.
  ///
  /// Both run between the *centres* of the first and last avatars rather than
  /// edge to edge, so "the bar has reached Vinod" is literally true on screen.
  ///
  /// The track is painted first and so sits behind the faces — but "behind"
  /// was not enough. A face whose turn has not come is drawn at partial
  /// opacity, and a translucent avatar lets whatever is behind it show
  /// through, so the line appeared to run *across* people's photographs while
  /// passing invisibly behind the one person who happened to be fully opaque.
  ///
  /// The fix is to remove the track from under the avatars entirely rather
  /// than to try to hide it there: [_AvatarHoles] punches a circle out of the
  /// line at every face. No colour has to be matched against the card's glass
  /// background, and it stays correct at any opacity a face is ever given.
  List<Widget> _track(CheckInChain chain, double slot, int count) {
    final left = slot / 2;
    final span = slot * (count - 1);
    final tint = _toneColour(chain.tone);

    /*
     | 24, not 25 or 28.
     |
     | The avatar's ring ends at 22, so 24 leaves the line stopping two points
     | clear of it — enough to read as a gap, not so much that the connector
     | disappears. At the tightest layout the slots are 58 apart, which leaves
     | 58 - 48 = 10dp of visible line between neighbours; every point added to
     | this radius takes two off that.
     */
    Widget hollowed(Widget bar) => ClipPath(
          clipper: _AvatarHoles(slot: slot, count: count, radius: 24),
          child: bar,
        );

    return [
      Positioned.fill(
        child: hollowed(
          Stack(
            children: [
              Positioned(
                left: left,
                top: 20,
                child: Container(
                  width: span,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.09),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Positioned(
                left: left,
                top: 20,
                child: TweenAnimationBuilder<double>(
                  // Animated rather than jumped, because this bar moves while
                  // somebody is looking at it — a websocket frame arrives and
                  // the fill slides to the next face. That slide is the
                  // notification.
                  tween: Tween(begin: 0, end: chain.progress),
                  duration: const Duration(milliseconds: 620),
                  curve: Curves.easeOutCubic,
                  builder: (context, value, _) => Container(
                    width: span * value,
                    height: 4,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [tint.withValues(alpha: 0.55), tint],
                      ),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ];
  }

  static Color _toneColour(String tone) => switch (tone) {
        'positive' => AppColors.mint,
        'caution' => AppColors.warmGold,
        'muted' => AppColors.textMuted,
        _ => AppColors.aqua,
      };

  static IconData _toneIcon(String tone) => switch (tone) {
        'positive' => Icons.verified_rounded,
        'caution' => Icons.report_problem_rounded,
        'muted' => Icons.remove_circle_outline_rounded,
        _ => Icons.podcasts_rounded,
      };
}

/// Everything except the circles the faces sit in.
///
/// Used to cut the connecting line so it stops at each avatar's edge and picks
/// up again on the far side, instead of passing underneath. Painting order
/// alone cannot do this: a partly transparent avatar shows whatever is behind
/// it, and the faces in this row are deliberately dimmed by status.
///
/// The radius is a little wider than the 22dp avatar so the line ends just
/// clear of the ring rather than appearing to touch it.
class _AvatarHoles extends CustomClipper<Path> {
  const _AvatarHoles({
    required this.slot,
    required this.count,
    required this.radius,
  });

  final double slot;
  final int count;
  final double radius;

  @override
  Path getClip(Size size) {
    final path = Path()
      // evenOdd is what turns the circles into holes rather than into the
      // only thing kept. With the default nonZero winding they would union
      // with the rectangle and clip nothing at all.
      ..fillType = ui.PathFillType.evenOdd
      ..addRect(Offset.zero & size);

    for (var i = 0; i < count; i++) {
      path.addOval(
        Rect.fromCircle(
          // The avatar sits at the top of its slot, 44dp tall, so its centre
          // is 22dp down — the same line the 4dp track is centred on.
          center: Offset(slot * (i + 0.5), 22),
          radius: radius,
        ),
      );
    }

    return path;
  }

  @override
  bool shouldReclip(_AvatarHoles old) =>
      old.slot != slot || old.count != count || old.radius != radius;
}

/// One person on the bar.
class _Face extends StatelessWidget {
  const _Face({
    required this.step,
    required this.pulse,
    required this.settled,
  });

  final ChainStep step;
  final Animation<double> pulse;

  /// Whether the chain has stopped. A waiting face on a finished chain is
  /// somebody who was never asked, and should read as spared rather than as
  /// still pending.
  final bool settled;

  @override
  Widget build(BuildContext context) {
    final person = step.person;
    final tint = _tint(step.status);
    final dim = _dim(step.status, settled);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 44,
          height: 44,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              if (step.status == StepStatus.notified)
                // The halo, sized by the shared controller. Behind the avatar
                // and outside it, so it never eats into the face.
                Positioned(
                  left: -6,
                  top: -6,
                  child: AnimatedBuilder(
                    animation: pulse,
                    builder: (context, _) => Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: tint.withValues(
                          alpha: 0.05 + 0.16 * pulse.value,
                        ),
                      ),
                    ),
                  ),
                ),
              Opacity(
                opacity: dim,
                child: Container(
                  width: 44,
                  height: 44,
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: tint, width: 2),
                  ),
                  child: person == null
                      ? const Icon(Icons.person_rounded,
                          size: 20, color: AppColors.textMuted)
                      : PersonAvatar(
                          size: 36,
                          imageUrl: person.avatarUrl,
                          initials: person.initials,
                        ),
                ),
              ),
              if (_badge(step.status) != null)
                Positioned(
                  right: -3,
                  bottom: -3,
                  child: Container(
                    width: 17,
                    height: 17,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: tint,
                      // A ring in the card's own colour, so the badge reads as
                      // sitting on top of the avatar rather than merging into
                      // its edge.
                      border: Border.all(color: AppColors.canvasRaised, width: 2),
                    ),
                    child: Icon(
                      _badge(step.status),
                      size: 9,
                      color: const Color(0xFF04121F),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 7),
        Opacity(
          opacity: dim,
          child: Text(
            person?.shortName ?? '—',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 10.5,
              // The person holding it is the one to read first.
              fontWeight: step.status == StepStatus.notified
                  ? FontWeight.w800
                  : FontWeight.w600,
              color: step.status == StepStatus.notified
                  ? AppColors.textPrimary
                  : AppColors.textMuted,
            ),
          ),
        ),
      ],
    );
  }

  static Color _tint(StepStatus status) => switch (status) {
        StepStatus.accepted => AppColors.mint,
        StepStatus.notified => AppColors.warmGold,
        StepStatus.rejected => AppColors.aqua,
        StepStatus.expired => AppColors.textMuted,
        _ => const Color(0x26FFFFFF),
      };

  /// Four levels, not two.
  ///
  /// Somebody who answered is fully present; somebody still to come is faint;
  /// and somebody who was never asked because the chain stopped earlier is
  /// fainter still — that last group is the point of the feature and should
  /// look untouched, not pending.
  static double _dim(StepStatus status, bool settled) => switch (status) {
        StepStatus.accepted || StepStatus.notified => 1,
        StepStatus.rejected || StepStatus.expired => 0.78,
        StepStatus.skipped => 0.38,
        StepStatus.waiting => settled ? 0.38 : 0.55,
      };

  static IconData? _badge(StepStatus status) => switch (status) {
        StepStatus.accepted => Icons.check_rounded,
        StepStatus.notified => Icons.more_horiz_rounded,
        // Passed it on, deliberately — an arrow, not a cross. Declining is
        // "ask the next person", and drawing it as a refusal would make a
        // helpful act look like a rebuff.
        StepStatus.rejected => Icons.arrow_forward_rounded,
        StepStatus.expired => Icons.schedule_rounded,
        _ => null,
      };
}
