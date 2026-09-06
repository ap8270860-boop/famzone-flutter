import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/session/session.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../location/data/location_models.dart';
import '../../../location/presentation/live_map_screen.dart';
import '../../data/chat_models.dart';

/// A location, in a thread.
///
/// Two things wear the same shape here and they are not the same thing:
///
///  - A **pin** is a statement about a moment. It is as true tomorrow as it
///    is now, it never changes, and tapping it opens the phone's own maps app
///    — which is what you actually want when the question is "how do I get
///    there".
///  - A **live share** is a claim about the present, and claims expire. It
///    counts down, it goes quiet when it ends, and tapping it opens our map
///    rather than a static point, because the whole value is the movement.
///
/// Deliberately no map thumbnail. A static map image is a separate billed
/// Google SKU charged per bubble rendered — a busy thread would quietly cost
/// real money to scroll — and a pulsing dot says "this is live" far better
/// than a postage stamp of a street.
class LocationBubble extends StatefulWidget {
  const LocationBubble({
    super.key,
    required this.message,
    required this.radius,
    required this.mine,
  });

  final ChatMessage message;
  final BorderRadius radius;
  final bool mine;

  @override
  State<LocationBubble> createState() => _LocationBubbleState();
}

class _LocationBubbleState extends State<LocationBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  MessageLocation? get _location => widget.message.location;

  bool get _isLive => _location?.live == true && _location?.active == true;

  @override
  void initState() {
    super.initState();

    if (_isLive) _pulse.repeat();
  }

  @override
  void didUpdateWidget(covariant LocationBubble old) {
    super.didUpdateWidget(old);

    // A share ending is a rebuild, not a new widget, so the animation has to
    // be told — otherwise an ended share keeps pulsing forever and the bubble
    // goes on insisting it is live.
    if (_isLive && !_pulse.isAnimating) {
      _pulse.repeat();
    } else if (!_isLive && _pulse.isAnimating) {
      _pulse.stop();
    }
  }

  @override
  void dispose() {
    _pulse.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final location = _location;
    final mine = widget.mine;

    final live = location?.live == true;
    final active = _isLive;

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width * 0.72,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: location == null ? null : _open,
          borderRadius: widget.radius,
          child: Container(
            padding: const EdgeInsets.fromLTRB(13, 12, 15, 12),
            decoration: BoxDecoration(
              borderRadius: widget.radius,
              gradient: mine ? AppColors.safeGradient : null,
              color: mine ? null : Colors.white.withValues(alpha: 0.07),
              border: Border.all(
                color: active
                    ? AppColors.mint.withValues(alpha: 0.55)
                    : Colors.white.withValues(alpha: mine ? 0.0 : 0.09),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _Glyph(pulse: _pulse, live: live, active: active),
                const SizedBox(width: 12),
                Flexible(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        live ? 'Live location' : 'Location',
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _subtitle(location),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: active
                              ? AppColors.mint
                              : AppColors.textPrimary
                                  .withValues(alpha: 0.62),
                          fontSize: 12.5,
                          fontWeight:
                              active ? FontWeight.w600 : FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Icon(
                  live ? Icons.chevron_right_rounded : Icons.open_in_new_rounded,
                  size: live ? 20 : 16,
                  color: AppColors.textPrimary.withValues(alpha: 0.55),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _subtitle(MessageLocation? location) {
    if (location == null) return 'Unavailable';

    if (!location.live) return 'Tap to open in Maps';

    if (!location.active) {
      // Named rather than timed. "Sharing ended" is the fact; when it ended is
      // already written under the bubble as the message's own timestamp.
      return 'Live sharing ended';
    }

    final until = location.expiresAt;

    if (until == null) return 'Sharing now';

    final left = until.difference(DateTime.now());

    if (left.isNegative) return 'Live sharing ended';

    final hours = left.inHours;

    if (hours > 0) return 'Sharing · $hours hr ${left.inMinutes % 60} min left';

    return 'Sharing · ${left.inMinutes + 1} min left';
  }

  /*
  |----------------------------------------------------------------------------
  | Tapping
  |----------------------------------------------------------------------------
  */

  Future<void> _open() async {
    final location = _location;

    if (location == null || !location.hasPoint) return;

    if (location.live) {
      /*
       | Our map, centred on whoever sent it.
       |
       | senderId is null only on a bubble this device made itself, which by
       | definition is mine — so falling back to my own id is correct rather
       | than defensive.
       */
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => LiveMapScreen(
            focusUserId:
                widget.message.senderId ?? Session.instance.user?.id,
          ),
        ),
      );

      return;
    }

    /*
     | A static pin opens the phone's own maps app.
     |
     | This is both what people expect and the cheap answer: it costs no
     | Google Maps quota at all, and it hands the person directions, transit
     | times and everything else a real maps app does that ours never will.
     */
    final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1'
      '&query=${location.latitude},${location.longitude}',
    );

    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

/// The disc on the left: a pin, or a pulsing dot while a share is running.
class _Glyph extends StatelessWidget {
  const _Glyph({
    required this.pulse,
    required this.live,
    required this.active,
  });

  final AnimationController pulse;
  final bool live;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final tint = active ? AppColors.mint : AppColors.aqua;

    return SizedBox(
      width: 42,
      height: 42,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (active)
            // The ring expanding out of the dot. The one piece of motion in
            // the thread, and it earns its place: "is this still running" is
            // the only question anybody asks of a live share.
            AnimatedBuilder(
              animation: pulse,
              builder: (context, _) => Container(
                width: 22 + 20 * pulse.value,
                height: 22 + 20 * pulse.value,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: tint.withValues(alpha: 0.5 * (1 - pulse.value)),
                    width: 1.5,
                  ),
                ),
              ),
            ),
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: tint.withValues(alpha: 0.18),
              border: Border.all(color: tint.withValues(alpha: 0.5)),
            ),
            child: Icon(
              live
                  ? (active ? Icons.near_me_rounded : Icons.near_me_outlined)
                  : Icons.place_rounded,
              size: 17,
              color: tint,
            ),
          ),
        ],
      ),
    );
  }
}
