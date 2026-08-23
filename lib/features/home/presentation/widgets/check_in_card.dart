import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/glass_card.dart';
import '../../../safety/data/safety_models.dart';

/// Daily "tap to confirm you are safe" prompt.
///
/// The action sits full width along the bottom rather than squeezed beside the
/// text. A primary action competing with two lines of copy for the same row
/// ends up too small to be the obvious thing to press, which is the one job
/// this card has.
class CheckInCard extends StatelessWidget {
  const CheckInCard({
    super.key,
    required this.onCheckIn,
    this.info,
    this.submitting = false,
  });

  final Future<void> Function() onCheckIn;
  final CheckInInfo? info;
  final bool submitting;

  @override
  Widget build(BuildContext context) {
    final checkedIn = info?.doneToday ?? false;
    final overdue = info?.overdue ?? false;

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

          const SizedBox(height: 15),
          _SafeButton(
            checkedIn: checkedIn,
            submitting: submitting,
            label: checkedIn ? _checkedLabel(info) : "I'm Safe",
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
                  color: day.isToday ? accent : AppColors.textMuted,
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
                      : Colors.white.withValues(alpha: 0.06),
                  border: day.isToday && !day.done
                      ? Border.all(color: accent.withValues(alpha: 0.55))
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
