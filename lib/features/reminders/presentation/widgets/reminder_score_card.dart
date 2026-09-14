import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/glass_card.dart';
import '../../data/reminder_models.dart';

/// Today's reminders and how the month is going, on the home screen.
///
/// Two numbers and one line of faces' worth of information — deliberately not
/// a second reminders screen. The card answers "is there anything I still have
/// to do today", and if the answer is yes it gets out of the way and lets you
/// tap through.
///
/// Hidden entirely when there are no reminders at all. A card explaining a
/// feature somebody has not adopted is an advert, and the quick action above
/// it is already the way in.
class ReminderScoreCard extends StatelessWidget {
  const ReminderScoreCard({
    super.key,
    required this.today,
    required this.score,
    required this.onTap,
    this.pendingAssignments = 0,
  });

  final ReminderDay today;
  final ReminderScore score;
  final VoidCallback onTap;

  /// Reminders somebody set for me that I have not answered. Surfaced here
  /// because it is a request waiting on me, and the home screen is where
  /// requests waiting on me live.
  final int pendingAssignments;

  @override
  Widget build(BuildContext context) {
    final remaining = today.items
        .where((i) => !i.isSettled)
        .length;

    final accent = remaining == 0 ? AppColors.mint : AppColors.aqua;

    return GlassCard(
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 15),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accent.withValues(alpha: 0.14),
                  border: Border.all(color: accent.withValues(alpha: 0.35)),
                ),
                child: Icon(
                  remaining == 0
                      ? Icons.notifications_off_rounded
                      : Icons.notifications_active_rounded,
                  size: 20,
                  color: accent,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Reminders',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _subtitle(today, remaining),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              if (score.streak > 0) ...[
                const SizedBox(width: 8),
                _Streak(days: score.streak, accent: accent),
              ],
            ],
          ),

          // Somebody is waiting on an answer. Louder than the rest of the
          // card, because it is the only part with another person behind it.
          if (pendingAssignments > 0) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(11),
                color: AppColors.warmGold.withValues(alpha: 0.1),
                border: Border.all(
                  color: AppColors.warmGold.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.person_add_alt_1_rounded,
                      size: 16, color: AppColors.warmGold),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      pendingAssignments == 1
                          ? 'A family member set a reminder for you.'
                          : '$pendingAssignments reminders set for you by '
                              'family.',
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          if (today.due > 0) ...[
            const SizedBox(height: 13),
            _Progress(
              done: today.done,
              // Before anything has settled the denominator is what is due;
              // after, it is what actually counted. Otherwise a skipped item
              // makes the bar look permanently short of a full day.
              total: today.settled == 0 ? today.due : today.settled,
              accent: accent,
            ),
          ],

          if (score.total > 0) ...[
            const SizedBox(height: 11),
            Row(
              children: [
                Icon(Icons.insights_rounded,
                    size: 14, color: AppColors.textMuted),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    'Last 30 days · ${score.headline}'
                    '${score.rate == null ? '' : ' · ${score.rate}%'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.textMuted,
                    ),
                  ),
                ),
                Icon(Icons.chevron_right_rounded,
                    size: 17,
                    color: AppColors.textMuted.withValues(alpha: 0.7)),
              ],
            ),
          ],
        ],
      ),
    );
  }

  static String _subtitle(ReminderDay today, int remaining) {
    if (today.due == 0) return 'Nothing due today.';
    if (remaining == 0) return 'All done for today.';

    return remaining == 1
        ? '1 still to do today.'
        : '$remaining still to do today.';
  }
}

class _Progress extends StatelessWidget {
  const _Progress({
    required this.done,
    required this.total,
    required this.accent,
  });

  final int done;
  final int total;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final fraction = total == 0 ? 0.0 : (done / total).clamp(0.0, 1.0);

    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: fraction),
            duration: const Duration(milliseconds: 520),
            curve: Curves.easeOutCubic,
            builder: (context, value, _) => LinearProgressIndicator(
              value: value,
              minHeight: 7,
              backgroundColor: Colors.white.withValues(alpha: 0.08),
              valueColor: AlwaysStoppedAnimation(accent),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Text(
              '$done of $total done',
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: AppColors.textMuted,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Streak extends StatelessWidget {
  const _Streak({required this.days, required this.accent});

  final int days;
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
            '$days',
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
