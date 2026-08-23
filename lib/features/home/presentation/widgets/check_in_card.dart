import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/glass_card.dart';

/// Daily "tap to confirm you are safe" prompt.
class CheckInCard extends StatelessWidget {
  const CheckInCard({
    super.key,
    required this.onCheckIn,
    this.reminderTime = '09:00 PM',
    this.checkedIn = false,
  });

  final VoidCallback onCheckIn;
  final String reminderTime;
  final bool checkedIn;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.aqua.withValues(alpha: 0.14),
              border: Border.all(color: AppColors.aqua.withValues(alpha: 0.35)),
            ),
            child: const Icon(Icons.touch_app_rounded,
                size: 25, color: AppColors.aqua),
          ),
          const SizedBox(width: 14),
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
                const Text(
                  "Tap the button daily to confirm you're safe.",
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    color: AppColors.textMuted,
                  ),
                ),
                const SizedBox(height: 7),
                Row(
                  children: [
                    const Icon(Icons.schedule_rounded,
                        size: 13, color: AppColors.mint),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        'Reminds you at $reminderTime',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.mint,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          _SafeButton(checkedIn: checkedIn, onTap: onCheckIn),
        ],
      ),
    );
  }
}

class _SafeButton extends StatelessWidget {
  const _SafeButton({required this.checkedIn, required this.onTap});

  final bool checkedIn;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: checkedIn ? null : onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: checkedIn ? null : AppColors.safeGradient,
          color: checkedIn ? Colors.white.withValues(alpha: 0.07) : null,
          border: checkedIn
              ? Border.all(color: AppColors.mint.withValues(alpha: 0.5))
              : null,
          boxShadow: checkedIn
              ? const []
              : [
                  BoxShadow(
                    color: AppColors.mint.withValues(alpha: 0.32),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (checkedIn) ...[
              const Icon(Icons.check_rounded, size: 15, color: AppColors.mint),
              const SizedBox(width: 5),
            ],
            Text(
              checkedIn ? 'Checked in' : "I'm Safe",
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: checkedIn ? AppColors.mint : const Color(0xFF04121F),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
