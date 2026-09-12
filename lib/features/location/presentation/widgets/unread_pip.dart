import 'package:flutter/material.dart';

/// An unread-message count, arriving with a bit of life in it.
///
/// This sits on somebody's face on the family map, and the whole reason it
/// animates is that the map is a screen people *stare* at. A number that
/// silently changes from 2 to 3 while you are watching a marker crawl down a
/// street is a number nobody notices. Motion is what makes the difference
/// between a badge and a notification.
///
/// ## The rules the animation follows
///
/// **In, then settle.** It scales up past its resting size and comes back —
/// an overshoot, not a pulse. A badge that pulses forever is an anxiety
/// generator on a safety app, and after ten seconds it is also invisible,
/// because the eye tunes out anything perfectly periodic.
///
/// **A new message re-announces.** The count changing is its own event and
/// gets its own overshoot, which is the behaviour people expect from every
/// chat app they have ever used.
///
/// **Zero leaves.** It shrinks away rather than vanishing, so the card
/// underneath does not appear to twitch.
class UnreadPip extends StatefulWidget {
  const UnreadPip({
    super.key,
    required this.count,
    this.onTap,
    this.size = 18,
  });

  final int count;
  final VoidCallback? onTap;

  /// Diameter at rest. The badge grows wider than this for counts above 9.
  final double size;

  @override
  State<UnreadPip> createState() => _UnreadPipState();
}

class _UnreadPipState extends State<UnreadPip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  );

  /// Out past one and back. `elasticOut` is tempting here and wrong — it
  /// wobbles three times, which on a badge reads as a rendering fault rather
  /// than as emphasis.
  late final Animation<double> _scale = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(begin: 0.0, end: 1.22)
          .chain(CurveTween(curve: Curves.easeOutBack)),
      weight: 55,
    ),
    TweenSequenceItem(
      tween: Tween(begin: 1.22, end: 1.0)
          .chain(CurveTween(curve: Curves.easeOutCubic)),
      weight: 45,
    ),
  ]).animate(_c);

  @override
  void initState() {
    super.initState();

    if (widget.count > 0) _c.value = 1;
  }

  @override
  void didUpdateWidget(UnreadPip old) {
    super.didUpdateWidget(old);

    if (widget.count == old.count) return;

    if (widget.count == 0) {
      _c.reverse();

      return;
    }

    // Any increase is news, whether from nothing or from three to four.
    _c
      ..reset()
      ..forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Held in the tree at zero rather than removed, so the row it sits in
    // does not re-lay-out every time somebody reads their messages.
    return ScaleTransition(
      scale: _scale,
      child: _Badge(
        count: widget.count,
        size: widget.size,
        onTap: widget.onTap,
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({
    required this.count,
    required this.size,
    this.onTap,
  });

  final int count;
  final double size;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    // "9+" rather than a three-digit number that would double the badge's
    // width. Past nine the exact figure stops changing what anybody does.
    final label = count > 9 ? '9+' : '$count';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(size),
        child: Container(
          constraints: BoxConstraints(minWidth: size, minHeight: size),
          padding: EdgeInsets.symmetric(horizontal: count > 9 ? 5 : 0),
          decoration: BoxDecoration(
            color: const Color(0xFFE5484D),
            borderRadius: BorderRadius.circular(size),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFE5484D).withValues(alpha: 0.35),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: Colors.white,
                fontSize: size * 0.58,
                fontWeight: FontWeight.w800,
                height: 1,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The same count, as a chip with an envelope on it.
///
/// Used where there is room for more than a dot — the profile sheet, and the
/// member card when a message is genuinely waiting. The icon is what makes it
/// unambiguous: a red circle with a number in it could be anything, and on a
/// safety app "anything" is a word that makes people worry.
class UnreadChip extends StatelessWidget {
  const UnreadChip({
    super.key,
    required this.count,
    this.onTap,
  });

  final int count;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();

    return Material(
      color: const Color(0xFFE5484D).withValues(alpha: 0.13),
      borderRadius: BorderRadius.circular(9),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.mark_chat_unread_rounded,
                size: 13,
                color: Color(0xFFE5484D),
              ),
              const SizedBox(width: 5),
              Text(
                count > 99 ? '99+' : '$count',
                style: const TextStyle(
                  color: Color(0xFFE5484D),
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
