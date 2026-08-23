import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// Who the account is for. Mirrors `users.user_type` on the API.
enum AccountType { adult, kid, senior }

/// Only asked when [AccountType.kid] is chosen. Mirrors
/// `users.education_stage`.
enum EducationStage { school, college }

/// Three mutually exclusive cards, plus a school/college follow-up for kids.
///
/// Deliberately not checkboxes — an account cannot be both a child and a
/// senior, and checkboxes invite exactly that.
class AccountTypePicker extends StatelessWidget {
  const AccountTypePicker({
    super.key,
    required this.type,
    required this.stage,
    required this.onTypeChanged,
    required this.onStageChanged,
  });

  final AccountType type;
  final EducationStage stage;
  final ValueChanged<AccountType> onTypeChanged;
  final ValueChanged<EducationStage> onStageChanged;

  static const _options = <AccountType, (IconData, String, String, Color)>{
    AccountType.adult: (
      Icons.person_rounded,
      'Adult',
      'Full access',
      AppColors.aqua,
    ),
    AccountType.kid: (
      Icons.child_care_rounded,
      'Child',
      'Guarded',
      AppColors.mint,
    ),
    AccountType.senior: (
      Icons.elderly_rounded,
      'Senior',
      'Simplified',
      AppColors.warmGold,
    ),
  };

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 10),
          child: Text(
            'Who is this account for?',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
              color: AppColors.textMuted,
            ),
          ),
        ),
        Row(
          children: [
            for (final entry in _options.entries) ...[
              Expanded(
                child: _TypeCard(
                  icon: entry.value.$1,
                  label: entry.value.$2,
                  caption: entry.value.$3,
                  tint: entry.value.$4,
                  selected: type == entry.key,
                  onTap: () => onTypeChanged(entry.key),
                ),
              ),
              if (entry.key != AccountType.senior) const SizedBox(width: 10),
            ],
          ],
        ),
        // Follow-up, only for a child account.
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: type == AccountType.kid
              ? Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(left: 4, bottom: 8),
                        child: Text(
                          'Still studying at',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: _StagePill(
                              icon: Icons.backpack_rounded,
                              label: 'School',
                              selected: stage == EducationStage.school,
                              onTap: () =>
                                  onStageChanged(EducationStage.school),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _StagePill(
                              icon: Icons.school_rounded,
                              label: 'College',
                              selected: stage == EducationStage.college,
                              onTap: () =>
                                  onStageChanged(EducationStage.college),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

class _TypeCard extends StatelessWidget {
  const _TypeCard({
    required this.icon,
    required this.label,
    required this.caption,
    required this.tint,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String caption;
  final Color tint;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: selected
              ? tint.withValues(alpha: 0.16)
              : Colors.white.withValues(alpha: 0.05),
          border: Border.all(
            color: selected
                ? tint.withValues(alpha: 0.85)
                : AppColors.glassBorder,
            width: selected ? 1.4 : 1,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: tint.withValues(alpha: 0.22),
                    blurRadius: 16,
                  ),
                ]
              : const [],
        ),
        child: Column(
          children: [
            Icon(
              icon,
              size: 22,
              color: selected ? tint : AppColors.textMuted,
            ),
            const SizedBox(height: 7),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: selected ? AppColors.textPrimary : AppColors.textMuted,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              caption,
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w500,
                color: selected
                    ? tint.withValues(alpha: 0.9)
                    : AppColors.textMuted.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StagePill extends StatelessWidget {
  const _StagePill({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: selected ? AppColors.safeGradient : null,
          color: selected ? null : Colors.white.withValues(alpha: 0.05),
          border: Border.all(
            color: selected ? Colors.transparent : AppColors.glassBorder,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 17,
              color: selected ? const Color(0xFF04121F) : AppColors.textMuted,
            ),
            const SizedBox(width: 7),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color:
                    selected ? const Color(0xFF04121F) : AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
