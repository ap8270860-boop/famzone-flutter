import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import 'person_avatar.dart';

/// Confirms a block, and says plainly what it will do.
///
/// Blocking is destructive and quiet: it tears down follows in both
/// directions, ends any family link, and the other person is never told. All
/// three of those deserve saying out loud before somebody taps it, because
/// none of them are guessable from the word "block".
class BlockSheet extends StatelessWidget {
  const BlockSheet({
    super.key,
    required this.name,
    this.username,
    this.avatarUrl,
    this.initials = '?',
    this.isFamily = false,
  });

  final String name;
  final String? username;
  final String? avatarUrl;
  final String initials;

  /// Adds the line about the family link, which is the consequence people are
  /// least likely to expect.
  final bool isFamily;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        22, 14, 22, 18 + MediaQuery.viewPaddingOf(context).bottom,
      ),
      decoration: const BoxDecoration(
        color: AppColors.canvasRaised,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(2),
                color: Colors.white.withValues(alpha: 0.18),
              ),
            ),
          ),
          const SizedBox(height: 20),

          Row(
            children: [
              PersonAvatar(
                size: 52,
                imageUrl: avatarUrl,
                initials: initials,
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Block $name?',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    if (username != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        '@$username',
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          const _Point(
            icon: Icons.person_off_outlined,
            text: 'You will both stop following each other, and neither of '
                'you can follow again until you unblock them.',
          ),
          if (isFamily)
            const _Point(
              icon: Icons.heart_broken_outlined,
              text: 'They will be removed from your family, so they lose '
                  'access to your location and SOS alerts.',
            ),
          const _Point(
            icon: Icons.search_off_rounded,
            text: 'You will not find each other in search, and your profiles '
                'become invisible to one another.',
          ),
          const _Point(
            icon: Icons.chat_bubble_outline_rounded,
            text: 'They will not be able to message you once chat arrives.',
          ),
          const _Point(
            icon: Icons.visibility_off_outlined,
            text: 'They are not told that you blocked them.',
          ),

          const SizedBox(height: 8),
          Text(
            'You can unblock from Settings › Blocked accounts. Following and '
            'family are not restored automatically.',
            style: TextStyle(
              fontSize: 11.5,
              height: 1.45,
              color: AppColors.textMuted.withValues(alpha: 0.8),
            ),
          ),

          const SizedBox(height: 20),

          _Button(
            label: 'Block',
            danger: true,
            onTap: () => Navigator.of(context).pop(true),
          ),
          const SizedBox(height: 9),
          _Button(
            label: 'Cancel',
            danger: false,
            onTap: () => Navigator.of(context).pop(false),
          ),
        ],
      ),
    );
  }
}

class _Point extends StatelessWidget {
  const _Point({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 13),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: AppColors.textMuted),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 12.5,
                height: 1.45,
                color: AppColors.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Button extends StatelessWidget {
  const _Button({
    required this.label,
    required this.danger,
    required this.onTap,
  });

  final String label;
  final bool danger;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: danger
              ? AppColors.alertRed.withValues(alpha: 0.14)
              : Colors.white.withValues(alpha: 0.06),
          border: Border.all(
            color: danger
                ? AppColors.alertRed.withValues(alpha: 0.45)
                : Colors.white.withValues(alpha: 0.14),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: danger ? AppColors.alertRed : AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
}

/// The three-dot menu itself.
class ProfileActionsSheet extends StatelessWidget {
  const ProfileActionsSheet({super.key, required this.isBlocked});

  final bool isBlocked;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        14, 12, 14, 14 + MediaQuery.viewPaddingOf(context).bottom,
      ),
      decoration: const BoxDecoration(
        color: AppColors.canvasRaised,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(2),
                color: Colors.white.withValues(alpha: 0.18),
              ),
            ),
          ),
          const SizedBox(height: 14),
          _Row(
            icon: isBlocked
                ? Icons.lock_open_rounded
                : Icons.block_flipped,
            label: isBlocked ? 'Unblock' : 'Block',
            danger: !isBlocked,
            onTap: () => Navigator.of(context).pop('block'),
          ),
          _Row(
            icon: Icons.flag_outlined,
            label: 'Report',
            danger: false,
            onTap: () => Navigator.of(context).pop('report'),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.label,
    required this.danger,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool danger;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tint = danger ? AppColors.alertRed : AppColors.textPrimary;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 15),
        child: Row(
          children: [
            Icon(icon, size: 20, color: tint),
            const SizedBox(width: 15),
            Text(
              label,
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
                color: tint,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
