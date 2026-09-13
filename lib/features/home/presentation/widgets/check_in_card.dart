import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/glass_card.dart';
import '../../../people/presentation/widgets/person_avatar.dart';
// Dart imports are not transitive: safety_models.dart exposing NotifyList
// through its own import is not enough to name it here.
import '../../../safety/data/check_in_chain.dart';
import '../../../safety/data/safety_models.dart';
import '../../../safety/presentation/widgets/check_in_chain_view.dart';

/// Daily "tap to confirm you are safe" prompt.
///
/// The action sits full width along the bottom rather than squeezed beside the
/// text. A primary action competing with two lines of copy for the same row
/// ends up too small to be the obvious thing to press, which is the one job
/// this card has.
///
/// The card has two lives now, and the seam between them is the tap.
///
/// Before checking in it is a promise: the button, plus a small row of the
/// faces that are about to hear about it. After checking in it becomes a
/// report — the chain view, showing how far the news actually travelled. Same
/// card, because it is the same fact at two moments, and putting the second
/// half on another screen would mean nobody ever saw whether anyone answered.
class CheckInCard extends StatelessWidget {
  const CheckInCard({
    super.key,
    required this.onCheckIn,
    this.info,
    this.submitting = false,
    this.onEditContacts,
  });

  final Future<void> Function() onCheckIn;
  final CheckInInfo? info;
  final bool submitting;

  /// Open the picker. Offered before a chain has started and once it has
  /// settled, but not while one is running — a chain in flight holds its own
  /// copy of the order, and letting somebody rearrange it mid-run would show
  /// them an edit that changes nothing.
  final VoidCallback? onEditContacts;

  @override
  Widget build(BuildContext context) {
    final checkedIn = info?.doneToday ?? false;
    final overdue = info?.overdue ?? false;
    final chain = info?.chain;
    final notify = info?.notify;

    final accent = checkedIn
        ? AppColors.mint
        : overdue
            ? AppColors.warmGold
            : AppColors.aqua;

    return GlassCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accent.withValues(alpha: 0.14),
                  border: Border.all(color: accent.withValues(alpha: 0.35)),
                ),
                child: Icon(
                  checkedIn
                      ? Icons.verified_rounded
                      : Icons.touch_app_rounded,
                  size: 23,
                  color: accent,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Daily Safety Check-in',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _subtitle(checkedIn, overdue),
                      style: const TextStyle(
                        fontSize: 12,
                        height: 1.35,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              if ((info?.longestStreak ?? 0) > 0) ...[
                const SizedBox(width: 8),
                _StreakBadge(
                  current: info!.currentStreak,
                  accent: accent,
                ),
              ],
            ],
          ),

          if (info != null && info!.recent.isNotEmpty) ...[
            const SizedBox(height: 15),
            _WeekStrip(days: info!.recent, accent: accent),
          ],

          /*
           | The chain, once there is one.
           |
           | Separated from the rest by a rule rather than just a gap: above it
           | is the habit — the streak, the week, the button — and below it is
           | today's news. They are different kinds of information and a reader
           | should be able to stop at the line.
           */
          if (chain != null) ...[
            const SizedBox(height: 15),
            const Divider(height: 1, color: AppColors.glassBorder),
            const SizedBox(height: 15),
            CheckInChainView(
              chain: chain,
              // Editable only once the run has settled. See [onEditContacts].
              onEdit: chain.isPending ? null : onEditContacts,
            ),
          ] else if (!checkedIn && notify != null && notify.configured) ...[
            // Not yet checked in, but there is a list. Show who is about to
            // hear — the promise before the tap.
            const SizedBox(height: 14),
            _NotifyPreview(notify: notify, onEdit: onEditContacts),
          ],

          const SizedBox(height: 15),
          _SafeButton(
            checkedIn: checkedIn,
            submitting: submitting,
            label: checkedIn
                ? _checkedLabel(info)
                : (notify?.configured ?? false)
                    ? "I'm Safe"
                    // First time. The button says what the tap actually does,
                    // which is open a picker — a button labelled "I'm Safe"
                    // that shows a sheet instead of checking in is a button
                    // that lied.
                    : "I'm Safe — choose who to tell",
            onTap: onCheckIn,
          ),
        ],
      ),
    );
  }

  static String _subtitle(bool checkedIn, bool overdue) {
    if (checkedIn) return 'Your circle can see that you are safe today.';
    if (overdue) return 'This is past your usual time — a quick tap is enough.';
    return "Tap once a day to confirm you're safe.";
  }

  static String _checkedLabel(CheckInInfo? info) =>
      info?.checkedInLabel == null
          ? 'Checked in'
          : 'Checked in at ${info!.checkedInLabel}';
}

/// Who is about to hear, before anybody has tapped anything.
///
/// Overlapped rather than spaced, and small. This is a promise, not a report —
/// it should read as a footnote to the button underneath it, and the moment
/// the tap happens the full chain view takes over the same space. Giving it
/// the chain's own layout here would make the card look like it had already
/// done something.
class _NotifyPreview extends StatelessWidget {
  const _NotifyPreview({required this.notify, this.onEdit});

  final NotifyList notify;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    // Three faces at most. A fourth would push the sentence out of the row on
    // a narrow phone, and the sentence is the part that carries the order.
    final faces = notify.people.take(3).toList();

    return Row(
      children: [
        SizedBox(
          /*
           | 24 for the first — the 22dp avatar plus its 1dp ring on each
           | side — then 14 of exposed edge for every one behind it.
           |
           | Measured, not guessed: the ring is what makes overlapping circles
           | legible, and leaving it out of the arithmetic clips 2dp off the
           | last face. A Row would hide that by overflowing; a SizedBox over
           | a Stack just crops.
           */
          width: 24 + (faces.length - 1).clamp(0, 2) * 14,
          height: 24,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              for (var i = faces.length - 1; i >= 0; i--)
                Positioned(
                  left: i * 14,
                  child: Container(
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      // A ring in the card's tone, so overlapping circles read
                      // as a stack rather than as one smudged shape.
                      color: AppColors.canvasRaised,
                    ),
                    padding: const EdgeInsets.all(1),
                    child: PersonAvatar(
                      size: 22,
                      imageUrl: faces[i].avatarUrl,
                      initials: faces[i].initials,
                      fontSize: 9,
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Text(
            _sentence(notify),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11.5,
              height: 1.35,
              color: AppColors.textMuted,
            ),
          ),
        ),
        if (onEdit != null) ...[
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onEdit,
            behavior: HitTestBehavior.opaque,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 2, vertical: 6),
              child: Text(
                'Edit',
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

  /// Names the first person, because the order is the whole point and the
  /// first name in it is the only one that is certain to be used.
  static String _sentence(NotifyList notify) {
    final people = notify.people;

    if (people.isEmpty) return 'Nobody will be notified.';

    final first = people.first.shortName;

    if (people.length == 1) return '$first will be told.';

    final rest = people.length - 1;

    return '$first first, then $rest '
        '${rest == 1 ? 'other' : 'others'} if there is no answer.';
  }
}

/// Seven dots — the week at a glance, and the reason to keep the streak.
class _WeekStrip extends StatelessWidget {
  const _WeekStrip({required this.days, required this.accent});

  final List<CheckInDay> days;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (final day in days)
          Column(
            children: [
              Text(
                day.initial,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: day.isToday ? FontWeight.w700 : FontWeight.w500,
                  color: day.isToday
                      ? accent
                      : day.isFuture
                          ? AppColors.textMuted.withValues(alpha: 0.45)
                          : AppColors.textMuted,
                ),
              ),
              const SizedBox(height: 5),
              AnimatedContainer(
                duration: const Duration(milliseconds: 260),
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: day.done
                      ? accent.withValues(alpha: 0.9)
                      // Three states, not two: checked in, missed, and not
                      // yet. A day still to come is barely there; a missed
                      // one is a visible empty slot.
                      : Colors.white
                          .withValues(alpha: day.isFuture ? 0.025 : 0.07),
                  border: day.isToday && !day.done
                      ? Border.all(color: accent.withValues(alpha: 0.55))
                      : day.isFuture
                          ? Border.all(
                              color: Colors.white.withValues(alpha: 0.05))
                          : null,
                ),
                child: day.done
                    ? const Icon(Icons.check_rounded,
                        size: 13, color: Color(0xFF04121F))
                    : null,
              ),
            ],
          ),
      ],
    );
  }
}

class _StreakBadge extends StatelessWidget {
  const _StreakBadge({required this.current, required this.accent});

  final int current;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: accent.withValues(alpha: 0.12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.local_fire_department_rounded, size: 13, color: accent),
          const SizedBox(width: 3),
          Text(
            '$current',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: accent,
            ),
          ),
        ],
      ),
    );
  }
}

/// Full-width primary action.
class _SafeButton extends StatelessWidget {
  const _SafeButton({
    required this.checkedIn,
    required this.submitting,
    required this.label,
    required this.onTap,
  });

  final bool checkedIn;
  final bool submitting;
  final String label;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    final disabled = checkedIn || submitting;

    return GestureDetector(
      onTap: disabled ? null : () => onTap(),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 240),
        width: double.infinity,
        height: 50,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: checkedIn ? null : AppColors.safeGradient,
          color: checkedIn ? Colors.white.withValues(alpha: 0.06) : null,
          border: checkedIn
              ? Border.all(color: AppColors.mint.withValues(alpha: 0.45))
              : null,
          boxShadow: checkedIn
              ? const []
              : [
                  BoxShadow(
                    color: AppColors.mint.withValues(alpha: 0.28),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: submitting
              ? const SizedBox(
                  key: ValueKey('busy'),
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    valueColor:
                        AlwaysStoppedAnimation(Color(0xFF04121F)),
                  ),
                )
              : Row(
                  key: ValueKey(label),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      checkedIn
                          ? Icons.check_circle_rounded
                          : Icons.shield_rounded,
                      size: 18,
                      color: checkedIn
                          ? AppColors.mint
                          : const Color(0xFF04121F),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: checkedIn
                            ? AppColors.mint
                            : const Color(0xFF04121F),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
