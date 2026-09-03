import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../people/presentation/widgets/person_avatar.dart';
import '../../data/chat_models.dart';

/// What tapping somebody in a group's member list offers.
enum MemberAction { message, profile, remove }

/// One member, and what you can do about them.
///
/// A sheet rather than a jump straight to their profile: from a member list
/// the likely intention is to say something to them, and burying that behind
/// a profile screen makes the common act the slow one.
Future<MemberAction?> showGroupMemberSheet(
  BuildContext context, {
  required ChatPerson member,
  required bool canRemove,
}) {
  return showModalBottomSheet<MemberAction>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (_) => _MemberSheet(member: member, canRemove: canRemove),
  );
}

class _MemberSheet extends StatelessWidget {
  const _MemberSheet({required this.member, required this.canRemove});

  final ChatPerson member;

  /// True only for an admin looking at somebody who is not themselves.
  final bool canRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        color: AppColors.canvasRaised,
        border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                margin: const EdgeInsets.only(top: 10, bottom: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  color: Colors.white.withValues(alpha: 0.16),
                ),
              ),
            ),

            // Named and pictured, because the sheet covers the row you
            // tapped and one of these actions is destructive.
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 2, 20, 14),
              child: Row(
                children: [
                  PersonAvatar(
                    size: 44,
                    imageUrl: member.avatarUrl,
                    initials: member.initials,
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          member.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        if (member.username != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            '@${member.username}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),

            Divider(height: 1, color: Colors.white.withValues(alpha: 0.07)),
            const SizedBox(height: 4),

            _Row(
              icon: Icons.chat_bubble_outline_rounded,
              label: 'Message ${member.name.split(' ').first}',
              action: MemberAction.message,
            ),
            _Row(
              icon: Icons.person_outline_rounded,
              label: 'View profile',
              action: MemberAction.profile,
            ),

            if (canRemove) ...[
              Divider(
                height: 9,
                indent: 18,
                endIndent: 18,
                color: Colors.white.withValues(alpha: 0.07),
              ),
              _Row(
                icon: Icons.person_remove_outlined,
                label: 'Remove from group',
                action: MemberAction.remove,
                danger: true,
              ),
            ],

            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.label,
    required this.action,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final MemberAction action;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final tint = danger ? AppColors.alertRed : AppColors.textPrimary;

    return InkWell(
      onTap: () => Navigator.of(context).pop(action),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 13, 20, 13),
        child: Row(
          children: [
            Icon(icon, size: 19, color: danger ? tint : AppColors.aqua),
            const SizedBox(width: 15),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                  color: tint,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
