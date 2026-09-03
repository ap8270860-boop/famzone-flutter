import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../core/widgets/aurora_background.dart';
import '../../people/presentation/user_profile_screen.dart';
import '../../people/presentation/widgets/person_avatar.dart';
import '../data/chat_api.dart';
import '../data/chat_models.dart';
import '../state/conversation_store.dart';
import 'chat_screen.dart';
import 'widgets/group_member_sheet.dart';

/// Who is in the group, and the way out of it.
///
/// Reads the conversation already loaded by the chat screen rather than
/// fetching its own: the member list arrives with the single-thread payload,
/// and a second request would only be a slower way to draw the same names.
class GroupInfoScreen extends StatefulWidget {
  const GroupInfoScreen({
    super.key,
    required this.store,
    required this.meId,
  });

  final ConversationStore store;
  final String meId;

  @override
  State<GroupInfoScreen> createState() => _GroupInfoScreenState();
}

class _GroupInfoScreenState extends State<GroupInfoScreen> {
  final ChatApi _api = ChatApi();
  final ImagePicker _picker = ImagePicker();

  bool _busy = false;

  ConversationStore get store => widget.store;
  String get meId => widget.meId;

  @override
  void dispose() {
    _api.dispose();
    super.dispose();
  }

  String? get _conversationId => store.conversation?.id;

  /// Rename it, or give it a different picture.
  ///
  /// Open to every member, not only an admin: a group's name and face are how
  /// the room describes itself, and the person who happened to create it is
  /// rarely the one who notices the name is wrong.
  Future<void> _save({String? title, String? avatarPath}) async {
    final id = _conversationId;

    if (id == null || _busy) return;

    setState(() => _busy = true);

    try {
      final res = await _api.updateGroup(
        id,
        title: title,
        avatarPath: avatarPath,
      );

      if (!mounted) return;

      if (res.success) {
        // Pulls the new title, picture and member list back through the
        // store, so the chat header behind this screen updates too.
        await store.refresh();
      } else {
        AppToast.error(context, res.message);
      }
    } catch (_) {
      if (mounted) AppToast.error(context, 'Could not reach the server.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _changePhoto() async {
    try {
      final file = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );

      if (file == null || !mounted) return;

      await _save(avatarPath: file.path);
    } catch (_) {
      if (mounted) AppToast.error(context, 'Could not open your photos.');
    }
  }

  Future<void> _rename(String current) async {
    final controller = TextEditingController(text: current);

    final title = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.canvasRaised,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppColors.glassBorder),
        ),
        title: const Text(
          'Group name',
          style: TextStyle(fontSize: 16, color: AppColors.textPrimary),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 80,
          textCapitalization: TextCapitalization.sentences,
          style: const TextStyle(fontSize: 15, color: AppColors.textPrimary),
          decoration: const InputDecoration(
            counterText: '',
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: AppColors.glassBorder),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: AppColors.mint),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel',
                style: TextStyle(color: AppColors.textMuted)),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Save', style: TextStyle(color: AppColors.mint)),
          ),
        ],
      ),
    );

    controller.dispose();

    if (title == null || title.isEmpty || title == current) return;

    await _save(title: title);
  }

  /// Tapping somebody in the list.
  Future<void> _openMember(ChatPerson member, bool amAdmin) async {
    final action = await showGroupMemberSheet(
      context,
      member: member,
      // An admin can remove anybody but themselves — leaving is a different
      // act, with a different system message.
      canRemove: amAdmin && member.id != meId,
    );

    if (action == null || !mounted) return;

    switch (action) {
      case MemberAction.message:
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ChatScreen(
              // No conversation id: the chat screen resolves or creates the
              // direct thread with this person on open, the same as tapping
              // Message on their profile.
              userId: member.id,
              name: member.name,
              username: member.username,
              avatarUrl: member.avatarUrl,
              initials: member.initials,
            ),
          ),
        );

      case MemberAction.profile:
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => UserProfileScreen(userId: member.id),
          ),
        );

      case MemberAction.remove:
        await _confirmRemove(member);
    }
  }

  Future<void> _confirmRemove(ChatPerson member) async {
    final id = _conversationId;

    if (id == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.canvasRaised,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppColors.glassBorder),
        ),
        title: Text(
          'Remove ${member.name}?',
          style: const TextStyle(fontSize: 16, color: AppColors.textPrimary),
        ),
        // The room is told, and they can see they were removed. Better said
        // here than discovered afterwards.
        content: const Text(
          'They will be removed from the group and everybody in it will see '
          'that you removed them.',
          style: TextStyle(
            fontSize: 13,
            height: 1.45,
            color: AppColors.textMuted,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel',
                style: TextStyle(color: AppColors.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove',
                style: TextStyle(color: AppColors.alertRed)),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);

    try {
      final res = await _api.removeGroupMember(id, member.id);

      if (!mounted) return;

      if (res.success) {
        await store.refresh();

        if (mounted) AppToast.success(context, 'Removed ${member.name}.');
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
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: AuroraBackground(
        child: SafeArea(
          child: AnimatedBuilder(
            animation: store,
            builder: (context, _) {
              final group = store.conversation?.group;

              if (group == null) {
                return const Center(
                  child: Text(
                    'This group is no longer available.',
                    style: TextStyle(fontSize: 13, color: AppColors.textMuted),
                  ),
                );
              }

              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(6, 6, 20, 2),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back_rounded,
                              color: AppColors.textPrimary),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                        const Expanded(
                          child: Text(
                            'Group info',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.only(bottom: 28),
                      children: [
                        _Header(
                          group: group,
                          busy: _busy,
                          onPhoto: _changePhoto,
                          onRename: () => _rename(group.title),
                        ),
                        const SizedBox(height: 22),
                        _SectionLabel(
                          label: group.members.length == 1
                              ? '1 member'
                              : '${group.members.length} members',
                        ),
                        for (final member in group.members)
                          _MemberRow(
                            member: member,
                            admin: group.isAdminOf(member.id),
                            isMe: member.id == meId,
                            // Tapping yourself does nothing: there is no
                            // message to send and nobody to remove.
                            onTap: member.id == meId
                                ? null
                                : () => _openMember(member, group.isAdmin),
                          ),
                        const SizedBox(height: 22),
                        _LeaveRow(
                          onTap: () => _confirmLeave(context, group.title),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _confirmLeave(BuildContext context, String title) async {
    final navigator = Navigator.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.canvasRaised,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppColors.glassBorder),
        ),
        title: Text(
          'Leave $title?',
          style: const TextStyle(fontSize: 16, color: AppColors.textPrimary),
        ),
        // Honest about what the room sees. Leaving a group is not a private
        // act, and finding that out afterwards is worse than being told.
        content: const Text(
          'The group will be told that you left, and you will stop receiving '
          'its messages.',
          style: TextStyle(
            fontSize: 13,
            height: 1.45,
            color: AppColors.textMuted,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel',
                style: TextStyle(color: AppColors.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Leave',
                style: TextStyle(color: AppColors.alertRed)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final ok = await store.deleteThread();

    if (!ok) {
      if (context.mounted) {
        AppToast.error(context, 'Could not leave the group.');
      }

      return;
    }

    // Out of the info screen and out of the thread behind it.
    navigator.popUntil((route) => route.isFirst);
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.group,
    required this.busy,
    required this.onPhoto,
    required this.onRename,
  });

  final GroupInfo group;
  final bool busy;
  final VoidCallback onPhoto;
  final VoidCallback onRename;

  @override
  Widget build(BuildContext context) {
    final initials = group.title.trim().isEmpty
        ? '?'
        : group.title.trim()[0].toUpperCase();

    return Column(
      children: [
        GestureDetector(
          onTap: busy ? null : onPhoto,
          behavior: HitTestBehavior.opaque,
          child: Stack(
            children: [
              PersonAvatar(
                size: 96,
                imageUrl: group.avatarUrl,
                initials: initials,
                fontSize: 34,
              ),
              // The camera badge is the whole affordance. Without it a group
              // photo looks like a fact rather than something you can change.
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  width: 30,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.canvasRaised,
                    border: Border.all(color: AppColors.canvas, width: 2),
                  ),
                  child: busy
                      ? const SizedBox(
                          width: 13,
                          height: 13,
                          child: CircularProgressIndicator(strokeWidth: 1.6),
                        )
                      : const Icon(Icons.photo_camera_outlined,
                          size: 15, color: AppColors.aqua),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        GestureDetector(
          onTap: busy ? null : onRename,
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    group.title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.edit_outlined,
                  size: 16,
                  color: AppColors.textMuted.withValues(alpha: 0.9),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 5),
        Text(
          group.membersCount == 1
              ? 'Group · 1 member'
              : 'Group · ${group.membersCount} members',
          style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.14,
          color: AppColors.textMuted,
        ),
      ),
    );
  }
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({
    required this.member,
    required this.admin,
    required this.isMe,
    required this.onTap,
  });

  final ChatPerson member;
  final bool admin;
  final bool isMe;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 9, 20, 9),
        child: Row(
          children: [
            PersonAvatar(
              size: 42,
              imageUrl: member.avatarUrl,
              initials: member.initials,
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Text(
                isMe ? 'You' : member.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            if (admin)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(9),
                  color: AppColors.aqua.withValues(alpha: 0.16),
                ),
                child: const Text(
                  'Admin',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: AppColors.aqua,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _LeaveRow extends StatelessWidget {
  const _LeaveRow({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
        child: Row(
          children: [
            const Icon(Icons.logout_rounded, size: 20, color: AppColors.alertRed),
            const SizedBox(width: 14),
            const Text(
              'Leave group',
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
                color: AppColors.alertRed,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
