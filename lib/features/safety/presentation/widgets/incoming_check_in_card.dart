import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../people/presentation/widgets/person_avatar.dart';
import '../../data/check_in_chain.dart';

/// "Kulsoom, your father checked in — do you know?"
///
/// Sits at the very top of the home screen, above everything including the
/// safety status, for as long as somebody is waiting on an answer. That
/// placement is the point: this is the only card in the app that represents
/// another person's clock running down, and burying it under the user's own
/// status would mean the chain moves on because the notification was three
/// scrolls away.
///
/// The same request is also in the notification feed, with the same two
/// buttons, and both are drawn from the step's live status — so answering here
/// removes it there, and a request that timed out while the phone was in a
/// pocket has no buttons in either place.
class IncomingCheckInCard extends StatelessWidget {
  const IncomingCheckInCard({
    super.key,
    required this.request,
    required this.busy,
    required this.onAccept,
    required this.onDecline,
  });

  final CheckInRequestInfo request;
  final bool busy;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    final person = request.person;
    final left = request.minutesLeft;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: AppColors.warmGold.withValues(alpha: 0.08),
        border: Border.all(color: AppColors.warmGold.withValues(alpha: 0.32)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PersonAvatar(
                size: 42,
                imageUrl: person?.avatarUrl,
                initials: person?.initials ?? '?',
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      request.message,
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.35,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _timing(request, left),
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppColors.warmGold,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: _Action(
                  label: 'I know they are safe',
                  filled: true,
                  busy: busy,
                  onTap: onAccept,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: _Action(
                  // Not "Decline". Passing it on is a helpful act — the next
                  // person gets it immediately instead of waiting out the
                  // timer — and a word that reads as a refusal would stop
                  // people doing the useful thing.
                  label: 'Pass on',
                  filled: false,
                  busy: busy,
                  onTap: onDecline,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Where this sits in the order, and how long is left.
  ///
  /// Both matter and neither alone is enough: "you are the second of three"
  /// explains why it arrived now, and "moves on in 22 minutes" explains why it
  /// is worth answering rather than closing.
  static String _timing(CheckInRequestInfo request, int? minutesLeft) {
    final place = request.total > 1
        ? 'You are ${request.position} of ${request.total}'
        : 'You are the only person asked';

    if (minutesLeft == null) return place;

    if (minutesLeft <= 0) return '$place · moving on now';

    return '$place · moves on in $minutesLeft '
        '${minutesLeft == 1 ? 'minute' : 'minutes'}';
  }
}

class _Action extends StatelessWidget {
  const _Action({
    required this.label,
    required this.filled,
    required this.busy,
    required this.onTap,
  });

  final String label;
  final bool filled;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = filled ? const Color(0xFF04121F) : AppColors.textPrimary;

    return GestureDetector(
      onTap: busy ? null : onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 40,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: filled ? AppColors.safeGradient : null,
          color: filled ? null : Colors.white.withValues(alpha: 0.07),
          border: filled
              ? null
              : Border.all(color: Colors.white.withValues(alpha: 0.16)),
        ),
        child: busy
            ? SizedBox(
                width: 15,
                height: 15,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(fg),
                ),
              )
            : FittedBox(
                // The accepting label is long by design — "I know they are
                // safe" says what the tap means, where "Accept" says nothing
                // — so it is allowed to shrink rather than wrap or ellipsise.
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: fg,
                  ),
                ),
              ),
      ),
    );
  }
}
