import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../data/chat_models.dart';

/// What a long press on an inbox row can do.
enum ThreadAction {
  archive,
  unarchive,
  pin,
  unpin,
  mute,
  unmute,
  markUnread,
  clear,
  delete,
}

/// The inbox long-press menu.
///
/// A bottom sheet rather than a menu anchored to the row, unlike the one in
/// the thread. The difference is what the actions apply to: these act on a
/// whole conversation, which the sheet names in its header, so there is
/// nothing to stay visually attached to — and reaching the bottom of the
/// screen beats reaching the top of it on a phone this size.
Future<ThreadAction?> showThreadMenu(
  BuildContext context,
  Conversation thread,
) {
  return showModalBottomSheet<ThreadAction>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (_) => _ThreadMenu(thread: thread),
  );
}

class _ThreadMenu extends StatelessWidget {
  const _ThreadMenu({required this.thread});

  final Conversation thread;

  @override
  Widget build(BuildContext context) {
    final name = thread.other?.name ?? 'this chat';

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
          children: [
            Container(
              width: 38,
              height: 4,
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                color: Colors.white.withValues(alpha: 0.16),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      // Named, because two of these are destructive and the
                      // sheet covers the row you pressed — by the time it is
                      // open you can no longer see which chat you picked.
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Divider(
              height: 1,
              color: Colors.white.withValues(alpha: 0.07),
            ),
            const SizedBox(height: 4),

            // Labels say which way the toggle will go, rather than naming
            // the feature: "Pin chat" on something already pinned leaves you
            // guessing what the tap does.
            _Row(
              icon: thread.archived
                  ? Icons.unarchive_outlined
                  : Icons.archive_outlined,
              label: thread.archived ? 'Move to chats' : 'Archive chat',
              action: thread.archived
                  ? ThreadAction.unarchive
                  : ThreadAction.archive,
            ),

            // Pinning an archived chat is two contradictory instructions —
            // hold it at the top of a list it is not in — so the option only
            // appears where it means something.
            if (!thread.archived)
              _Row(
                icon: thread.pinned
                    ? Icons.push_pin_rounded
                    : Icons.push_pin_outlined,
                label: thread.pinned ? 'Unpin chat' : 'Pin chat',
                action: thread.pinned ? ThreadAction.unpin : ThreadAction.pin,
              ),
            _Row(
              icon: thread.muted
                  ? Icons.notifications_active_outlined
                  : Icons.notifications_off_outlined,
              label: thread.muted ? 'Unmute notifications' : 'Mute notifications',
              action: thread.muted ? ThreadAction.unmute : ThreadAction.mute,
            ),

            // Only when there is nothing already waiting. Marking an unread
            // chat unread is a no-op dressed up as a choice.
            if (!thread.hasUnread)
              const _Row(
                icon: Icons.mark_chat_unread_outlined,
                label: 'Mark as unread',
                action: ThreadAction.markUnread,
              ),

            Divider(
              height: 9,
              indent: 18,
              endIndent: 18,
              color: Colors.white.withValues(alpha: 0.07),
            ),

            const _Row(
              icon: Icons.remove_circle_outline_rounded,
              label: 'Clear chat',
              note: 'Empties it for you. They keep their copy.',
              action: ThreadAction.clear,
              danger: true,
            ),
            const _Row(
              icon: Icons.delete_outline_rounded,
              label: 'Delete chat',
              note: 'Removes it from your list.',
              action: ThreadAction.delete,
              danger: true,
            ),
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
    this.note,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final String? note;
  final ThreadAction action;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final tint = danger ? AppColors.alertRed : AppColors.textPrimary;

    return InkWell(
      onTap: () => Navigator.of(context).pop(action),
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, note == null ? 13 : 11, 20, 11),
        child: Row(
          children: [
            Icon(icon, size: 19, color: danger ? tint : AppColors.aqua),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      color: tint,
                    ),
                  ),
                  if (note != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      note!,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: AppColors.textMuted.withValues(alpha: 0.9),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
