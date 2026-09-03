import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// What the three dots at the top of the inbox offer.
enum InboxMenuChoice { newGroup, familyGroup, starred }

/// The inbox overflow menu.
///
/// Anchored under the button rather than presented as a bottom sheet: these
/// act on the whole screen rather than on one row, and a menu that drops from
/// the control you pressed says so without needing a header to explain it.
Future<InboxMenuChoice?> showInboxMenu(BuildContext context) {
  return showGeneralDialog<InboxMenuChoice>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Inbox menu',
    barrierColor: Colors.black.withValues(alpha: 0.35),
    transitionDuration: const Duration(milliseconds: 140),
    pageBuilder: (context, animation, _) => _InboxMenu(animation: animation),
  );
}

class _InboxMenu extends StatelessWidget {
  const _InboxMenu({required this.animation});

  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.viewPaddingOf(context);

    return Stack(
      children: [
        Positioned(
          top: insets.top + 44,
          right: 12,
          width: 232,
          child: FadeTransition(
            opacity: animation,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.93, end: 1).animate(
                CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
              ),
              // Grows out of the button it belongs to.
              alignment: Alignment.topRight,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    color: AppColors.canvasRaised,
                    border:
                        Border.all(color: Colors.white.withValues(alpha: 0.1)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.5),
                        blurRadius: 26,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const _Row(
                        icon: Icons.group_add_outlined,
                        label: 'New group',
                        choice: InboxMenuChoice.newGroup,
                      ),
                      const _Row(
                        icon: Icons.diversity_1_outlined,
                        label: 'Family group',
                        choice: InboxMenuChoice.familyGroup,
                      ),
                      Divider(
                        height: 9,
                        indent: 14,
                        endIndent: 14,
                        color: Colors.white.withValues(alpha: 0.07),
                      ),
                      const _Row(
                        icon: Icons.star_outline_rounded,
                        label: 'Starred messages',
                        choice: InboxMenuChoice.starred,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.label,
    required this.choice,
    this.soon = false,
  });

  final IconData icon;
  final String label;
  final InboxMenuChoice choice;

  /// Present but not built yet. Shown rather than hidden so the menu's shape
  /// is settled now and does not move under people when groups land.
  final bool soon;

  @override
  Widget build(BuildContext context) {
    final tint = soon
        ? AppColors.textPrimary.withValues(alpha: 0.45)
        : AppColors.textPrimary;

    return InkWell(
      onTap: () => Navigator.of(context).pop(choice),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 14, 12),
        child: Row(
          children: [
            Icon(
              icon,
              size: 19,
              color: soon ? AppColors.textMuted.withValues(alpha: 0.55) : AppColors.aqua,
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                  color: tint,
                ),
              ),
            ),
            if (soon)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: AppColors.warmGold.withValues(alpha: 0.16),
                ),
                child: const Text(
                  'Soon',
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                    color: AppColors.warmGold,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
