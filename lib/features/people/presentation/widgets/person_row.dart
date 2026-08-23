import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../core/widgets/glass_card.dart';
import '../../data/people_api.dart';
import '../../data/people_models.dart';
import 'person_avatar.dart';

/// What the row's button does.
enum PersonRowAction {
  /// Follow, unfollow, or withdraw a request.
  follow,

  /// Remove this person from the family circle. Used in the Family tab, where
  /// the membership is the thing on screen — offering "Following" there would
  /// answer a question nobody asked.
  family,
}

/// One search result or list entry, with its follow button.
///
/// The button acts in place and reports the updated person back up, so a list
/// never has to be reloaded just because one row changed.
class PersonRow extends StatefulWidget {
  const PersonRow({
    super.key,
    required this.person,
    this.onTap,
    this.onChanged,
    this.onRemoved,
    this.action = PersonRowAction.follow,
  });

  final PersonSummary person;
  final VoidCallback? onTap;
  final ValueChanged<PersonSummary>? onChanged;

  /// Called after a family membership is removed, so the list can
  /// reload rather than guess at the new state.
  final VoidCallback? onRemoved;

  final PersonRowAction action;

  @override
  State<PersonRow> createState() => _PersonRowState();
}

class _PersonRowState extends State<PersonRow> {
  final _api = PeopleApi();
  bool _busy = false;

  @override
  void dispose() {
    _api.dispose();
    super.dispose();
  }

  Future<void> _toggleFollow() async {
    if (_busy) return;

    final person = widget.person;
    final rel = person.relationship;

    setState(() => _busy = true);

    try {
      // Following or already requested → this is a withdraw. Otherwise ask.
      final res = rel.isFollowing || rel.hasRequested
          ? await _api.unfollow(person.id)
          : await _api.follow(person.id);

      if (!mounted) return;

      if (res.success) {
        // The response is the full profile, so the row can be rebuilt from
        // the server's own view rather than a guess about what changed.
        widget.onChanged?.call(
          PersonSummary(
            id: person.id,
            name: person.name,
            username: person.username,
            avatarUrl: person.avatarUrl,
            userType: person.userType,
            relationship: Relationship.fromJson(
              res.dataMap['relationship'] as Map<String, dynamic>? ?? const {},
            ),
          ),
        );

        AppToast.success(context, res.message);
      } else {
        AppToast.error(context, res.message);
      }
    } catch (_) {
      if (mounted) AppToast.error(context, 'Could not reach the server.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _removeFromFamily() async {
    final familyId = widget.person.familyId;

    if (_busy || familyId == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => _ConfirmRemove(name: widget.person.name),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);

    try {
      final res = await _api.removeFamilyMember(familyId);

      if (!mounted) return;

      if (res.success) {
        AppToast.success(context, res.message);
        widget.onRemoved?.call();
      } else {
        AppToast.error(context, res.message);
      }
    } catch (_) {
      if (mounted) AppToast.error(context, 'Could not reach the server.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final person = widget.person;
    final rel = person.relationship;

    return GlassCard(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      radius: 16,
      onTap: widget.onTap,
      child: Row(
        children: [
          PersonAvatar(
            size: 46,
            imageUrl: person.avatarUrl,
            initials: person.initials,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  person.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        person.handle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ),
                    // Context that makes the follow decision easier, and the
                    // reason both directions are sent down.
                    if (rel.followsMe && !rel.isFollowing) ...[
                      const SizedBox(width: 6),
                      const _Tag(label: 'Follows you'),
                    ],
                    if (rel.isFamily) ...[
                      const SizedBox(width: 6),
                      _Tag(
                        label: person.relation == null
                            ? 'Family'
                            : person.relation![0].toUpperCase() +
                                person.relation!.substring(1),
                        accent: AppColors.mint,
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),

          // No button at all when the relationship is unknown —
          // a guessed "Follow" that silently does nothing is worse
          // than no button.
          if (!rel.isSelf && rel.isKnown)
            if (widget.action == PersonRowAction.family)
              _FollowButton(
                label: 'Remove',
                filled: false,
                busy: _busy,
                onTap: _removeFromFamily,
              )
            else
              _FollowButton(
                label: rel.followLabel,
                filled: !rel.isFollowing && !rel.hasRequested,
                busy: _busy,
                onTap: _toggleFollow,
              ),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label, this.accent = AppColors.textMuted});

  final String label;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        color: accent.withValues(alpha: 0.14),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
          color: accent,
        ),
      ),
    );
  }
}

class _FollowButton extends StatelessWidget {
  const _FollowButton({
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
    return GestureDetector(
      onTap: busy ? null : onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 34,
        constraints: const BoxConstraints(minWidth: 92),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
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
                  valueColor: AlwaysStoppedAnimation(
                    filled ? const Color(0xFF04121F) : AppColors.textPrimary,
                  ),
                ),
              )
            : Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: filled
                      ? const Color(0xFF04121F)
                      : AppColors.textPrimary,
                ),
              ),
      ),
    );
  }
}

/// Removing family is not something to do by accident — it is the link that
/// will carry location and SOS visibility.
class _ConfirmRemove extends StatelessWidget {
  const _ConfirmRemove({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.canvasRaised,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
      ),
      title: const Text(
        'Remove from family?',
        style: TextStyle(
          fontSize: 16.5,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
      ),
      content: Text(
        '$name will no longer be part of your family circle. You will still '
        'follow each other.',
        style: const TextStyle(
          fontSize: 13,
          height: 1.45,
          color: AppColors.textMuted,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text(
            'Cancel',
            style: TextStyle(color: AppColors.textMuted),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text(
            'Remove',
            style: TextStyle(
              color: AppColors.alertRed,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}
