import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/place_models.dart';
import 'map_style.dart';

/// "Aarav arrived at School", for a few seconds.
///
/// Deliberately not the SOS banner. That one is red, persistent, and cannot
/// be dismissed with a back gesture, because an alarm you can sweep away is
/// not an alarm. This is the opposite kind of news: a child reaching school
/// is the thing you *hoped* would happen, and it should say so and then get
/// out of the way.
///
/// Auto-dismissing matters more than it looks. A family of four generates a
/// dozen crossings on a weekday — school, office, home, home again — and a
/// banner that waits to be tapped would mean a map permanently wearing a hat.
///
/// The sentence is the server's, verbatim. It is also what a push
/// notification will carry once push exists, and two places writing the same
/// sentence differently is how a product starts contradicting itself.
class CrossingBanner extends StatefulWidget {
  const CrossingBanner({
    super.key,
    required this.crossing,
    required this.palette,
    required this.onDismiss,
  });

  final PlaceCrossing? crossing;
  final MapPalette palette;
  final VoidCallback onDismiss;

  @override
  State<CrossingBanner> createState() => _CrossingBannerState();
}

class _CrossingBannerState extends State<CrossingBanner> {
  Timer? _timer;

  static const Duration _linger = Duration(seconds: 6);

  @override
  void initState() {
    super.initState();

    if (widget.crossing != null) _restart();
  }

  @override
  void didUpdateWidget(CrossingBanner old) {
    super.didUpdateWidget(old);

    // A new crossing resets the clock rather than inheriting the old one's
    // remaining time — otherwise the second arrival in quick succession
    // flashes past in whatever was left of the first one's six seconds.
    if (widget.crossing != null && widget.crossing != old.crossing) {
      _restart();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _restart() {
    _timer?.cancel();
    _timer = Timer(_linger, () {
      if (mounted) widget.onDismiss();
    });
  }

  @override
  Widget build(BuildContext context) {
    final crossing = widget.crossing;
    final palette = widget.palette;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) => SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, -0.4),
          end: Offset.zero,
        ).animate(animation),
        child: FadeTransition(opacity: animation, child: child),
      ),
      child: crossing == null
          ? const SizedBox.shrink(key: ValueKey('none'))
          : Padding(
              key: ValueKey(
                '${crossing.personId}|${crossing.placeName}|${crossing.direction}',
              ),
              padding: const EdgeInsets.only(top: 10),
              child: Material(
                color: palette.surface,
                borderRadius: BorderRadius.circular(16),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: widget.onDismiss,
                  child: Container(
                    padding:
                        const EdgeInsets.fromLTRB(12, 11, 10, 11),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: crossing.tint.withValues(alpha: 0.45),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: palette.shadow,
                          blurRadius: 16,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: crossing.tint.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(11),
                          ),
                          child: Icon(
                            crossing.isArrival
                                ? Icons.login_rounded
                                : Icons.logout_rounded,
                            size: 17,
                            color: crossing.tint,
                          ),
                        ),
                        const SizedBox(width: 11),
                        Expanded(
                          child: Text(
                            crossing.message,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: palette.textPrimary,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              height: 1.3,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.close_rounded,
                          size: 17,
                          color: palette.textMuted,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}
