import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// One person in the circle, as the home screen needs them.
class FamilyMember {
  const FamilyMember({
    required this.name,
    required this.status,
    this.id,
    this.avatarUrl,
    this.isSelf = false,
    this.online = true,
  });

  /// The other person's public id, so tapping can open their
  /// profile. Null for the placeholder self tile.
  final String? id;

  final String name;
  final String status;
  final String? avatarUrl;
  final bool isSelf;
  final bool online;

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }
}

/// Horizontal row of circle members, ending with "Add Family".
///
/// Scrolls horizontally rather than wrapping — a circle can grow past what
/// fits on one line, and a fixed grid would either clip or push the rest of
/// the page down.
class FamilyStrip extends StatelessWidget {
  const FamilyStrip({
    super.key,
    required this.members,
    this.onAdd,
    this.onTapMember,
  });

  final List<FamilyMember> members;
  final VoidCallback? onAdd;
  final void Function(FamilyMember member)? onTapMember;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 112,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        physics: const BouncingScrollPhysics(),
        itemCount: members.length + 1,
        separatorBuilder: (_, __) => const SizedBox(width: 11),
        itemBuilder: (context, i) {
          if (i == members.length) return _AddTile(onTap: onAdd);
          final m = members[i];
          return _MemberTile(
            member: m,
            onTap: () => onTapMember?.call(m),
          );
        },
      ),
    );
  }
}

class _MemberTile extends StatelessWidget {
  const _MemberTile({required this.member, required this.onTap});

  final FamilyMember member;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 76,
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: Colors.white.withValues(alpha: 0.055),
          border: Border.all(color: AppColors.glassBorder),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: AppColors.safeGradient,
                  ),
                  padding: const EdgeInsets.all(2),
                  child: Container(
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.canvasRaised,
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: member.avatarUrl != null
                        ? Image.network(
                            member.avatarUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                _Initials(member.initials),
                          )
                        : _Initials(member.initials),
                  ),
                ),
                if (member.online)
                  Positioned(
                    right: 1,
                    bottom: 1,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.mint,
                        border:
                            Border.all(color: AppColors.canvasRaised, width: 2),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              member.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              member.isSelf ? 'You' : member.status,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w600,
                color: member.isSelf ? AppColors.textMuted : AppColors.mint,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Initials extends StatelessWidget {
  const _Initials(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
      ),
    );
  }
}

class _AddTile extends StatelessWidget {
  const _AddTile({required this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 76,
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: AppColors.aqua.withValues(alpha: 0.06),
          border: Border.all(
            color: AppColors.aqua.withValues(alpha: 0.45),
            // A dashed border needs a custom painter; a lighter solid ring
            // reads as "empty slot" well enough without one.
            width: 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 6),
            const Icon(Icons.person_add_alt_1_rounded,
                size: 26, color: AppColors.aqua),
            const SizedBox(height: 13),
            const Text(
              'Add\nFamily',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 10.5,
                height: 1.2,
                fontWeight: FontWeight.w600,
                color: AppColors.aqua,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
