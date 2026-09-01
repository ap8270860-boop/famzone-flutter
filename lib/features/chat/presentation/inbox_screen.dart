import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../core/widgets/aurora_background.dart';
import '../../people/presentation/widgets/person_avatar.dart';
import '../data/chat_models.dart';
import '../state/chat_store.dart';
import 'archived_chats_screen.dart';
import 'chat_screen.dart';
import 'widgets/thread_menu.dart';

/// Every conversation, and the requests waiting on a decision.
///
/// Two tabs rather than one list with a divider, because they are two
/// different kinds of attention: an unread message is a conversation waiting,
/// a request is a decision waiting. Mixing them means the badge cannot mean
/// anything precise.
class InboxScreen extends StatefulWidget {
  const InboxScreen({super.key, this.embedded = false});

  /// True when this is the Chats tab rather than a pushed screen.
  ///
  /// Changes two things: no back arrow, because a tab has nowhere to go back
  /// to, and room at the bottom for the floating nav bar, which sits over the
  /// content rather than beside it.
  final bool embedded;

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

/// Height the floating nav bar occupies, so the list can clear it.
///
/// Bar plus the SOS button's overhang plus its bottom margin — kept as one
/// number here rather than derived from the shell, because a list that has to
/// import the navigation to know how tall it is has the dependency the wrong
/// way round.
const double _navBarClearance = 108;

class _InboxScreenState extends State<InboxScreen> {
  final ChatStore _store = ChatStore.instance;

  bool _requestsTab = false;

  @override
  void initState() {
    super.initState();
    _store.refresh();
  }

  Future<void> _open(Conversation thread) async {
    final person = thread.other;

    if (person == null) return;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          conversationId: thread.id,
          userId: person.id,
          name: person.name,
          username: person.username,
          avatarUrl: person.avatarUrl,
          initials: person.initials,
          presence: person.presenceLabel,
        ),
      ),
    );

    // Coming back from a thread, the unread count and the previews have both
    // moved on. Cheaper to refresh once here than to keep the inbox in sync
    // with a screen that is no longer on top of it.
    if (mounted) _store.refresh();
  }

  /// The Archived entry appears only when there is something in there, and
  /// never over the Requests tab — archiving belongs to accepted chats.
  bool get _showArchived => !_requestsTab && _store.archivedCount > 0;

  Future<void> _openArchived() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ArchivedChatsScreen()),
    );

    // Something may have come back out while we were in there.
    if (mounted) _store.refresh();
  }

  /// Long press on a row.
  Future<void> _openThreadMenu(Conversation thread) async {
    final action = await showThreadMenu(context, thread);

    if (action == null || !mounted) return;

    switch (action) {
      case ThreadAction.archive:
      case ThreadAction.unarchive:
        await _store.archive(thread);

      case ThreadAction.pin:
      case ThreadAction.unpin:
        await _store.pinChat(thread);

      case ThreadAction.mute:
      case ThreadAction.unmute:
        await _store.mute(thread);

      case ThreadAction.markUnread:
        await _store.markUnread(thread);

      case ThreadAction.clear:
        await _confirmClear(thread);

      case ThreadAction.delete:
        await _confirmDelete(thread);
    }
  }

  Future<void> _confirmClear(Conversation thread) async {
    final confirmed = await _confirm(
      title: 'Clear this chat?',
      body: 'Every message will be removed from your side. '
          '${thread.other?.name ?? 'They'} will still have the whole '
          'conversation, and the chat stays in your list.',
      action: 'Clear',
    );

    if (confirmed != true || !mounted) return;

    final ok = await _store.clearChat(thread);

    if (!mounted) return;

    if (ok) {
      AppToast.success(context, 'Chat cleared.');
    } else {
      AppToast.error(context, 'Could not clear that chat.');
    }
  }

  Future<void> _confirmDelete(Conversation thread) async {
    final confirmed = await _confirm(
      title: 'Delete this chat?',
      // Honest about what leaving actually does: the thread is not destroyed,
      // and a later message from them reopens it with its history intact.
      body: 'It leaves your list. If '
          '${thread.other?.name ?? 'they'} messages you again, the '
          'conversation comes back.',
      action: 'Delete',
    );

    if (confirmed != true || !mounted) return;

    final ok = await _store.leave(thread);

    if (!mounted) return;

    if (!ok) AppToast.error(context, 'Could not delete that chat.');
  }

  Future<bool?> _confirm({
    required String title,
    required String body,
    required String action,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.canvasRaised,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppColors.glassBorder),
        ),
        title: Text(
          title,
          style: const TextStyle(fontSize: 16, color: AppColors.textPrimary),
        ),
        content: Text(
          body,
          style: const TextStyle(
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
            child: Text(action,
                style: const TextStyle(color: AppColors.alertRed)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: AuroraBackground(
        child: SafeArea(
          child: AnimatedBuilder(
            animation: _store,
            builder: (context, _) {
              final threads = _requestsTab ? _store.requests : _store.threads;

              return Column(
                children: [
                  _TopBar(
                    unread: _store.unread,
                    embedded: widget.embedded,
                  ),
                  _Tabs(
                    requestsTab: _requestsTab,
                    requestCount: _store.requestCount,
                    onChanged: (value) => setState(() => _requestsTab = value),
                  ),
                  Expanded(
                    child: _store.loading
                        ? const Center(
                            child: SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _store.refresh,
                            color: AppColors.mint,
                            backgroundColor: AppColors.canvas,
                            child: threads.isEmpty
                                ? _empty()
                                : ListView.builder(
                                    // The nav bar floats over the content, so
                                    // the last row would otherwise sit behind
                                    // it and be unreachable.
                                    padding: EdgeInsets.fromLTRB(
                                      8,
                                      4,
                                      8,
                                      widget.embedded ? _navBarClearance : 24,
                                    ),
                                    physics:
                                        const AlwaysScrollableScrollPhysics(),
                                    // The Archived entry rides at the top of
                                    // the chats list as row zero, so it
                                    // scrolls away instead of holding a
                                    // permanent strip of the screen for
                                    // something opened once a month.
                                    itemCount: threads.length + (_showArchived ? 1 : 0),
                                    itemBuilder: (context, i) {
                                      if (_showArchived && i == 0) {
                                        return _ArchivedEntry(
                                          count: _store.archivedCount,
                                          onTap: _openArchived,
                                        );
                                      }

                                      final thread =
                                          threads[_showArchived ? i - 1 : i];

                                      return _ThreadRow(
                                        thread: thread,
                                        onTap: () => _open(thread),
                                        onLongPress: () =>
                                            _openThreadMenu(thread),
                                      );
                                    },
                                  ),
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

  Widget _empty() {
    // Still a scroll view, so pull-to-refresh works on an empty inbox — the
    // one screen where a user is most likely to try it.
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(height: MediaQuery.sizeOf(context).height * 0.2),
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 48),
            child: Column(
              children: [
                Icon(
                  _requestsTab
                      ? Icons.mark_email_unread_outlined
                      : Icons.forum_outlined,
                  size: 44,
                  color: AppColors.textMuted.withValues(alpha: 0.45),
                ),
                const SizedBox(height: 16),
                Text(
                  _requestsTab ? 'No requests' : 'No conversations yet',
                  style: const TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _requestsTab
                      ? 'Messages from people you do not follow will wait here.'
                      : 'Open somebody’s profile and tap Message to start one.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12.5,
                    height: 1.45,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.unread, this.embedded = false});

  final int unread;
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(embedded ? 20 : 4, 6, 16, 4),
      child: Row(
        children: [
          if (!embedded)
            IconButton(
              icon: const Icon(Icons.arrow_back_rounded,
                  color: AppColors.textPrimary),
              onPressed: () => Navigator.of(context).pop(),
            ),
          const Text(
            'Messages',
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          if (unread > 0) ...[
            const SizedBox(width: 9),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: AppColors.safeGradient,
              ),
              child: Text(
                '$unread',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF04121F),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Tabs extends StatelessWidget {
  const _Tabs({
    required this.requestsTab,
    required this.requestCount,
    required this.onChanged,
  });

  final bool requestsTab;
  final int requestCount;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
      child: Row(
        children: [
          _Tab(
            label: 'All',
            selected: !requestsTab,
            onTap: () => onChanged(false),
          ),
          const SizedBox(width: 9),
          _Tab(
            label: requestCount > 0 ? 'Requests · $requestCount' : 'Requests',
            selected: requestsTab,
            onTap: () => onChanged(true),
          ),
        ],
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

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
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: selected
              ? AppColors.mint.withValues(alpha: 0.15)
              : Colors.white.withValues(alpha: 0.05),
          border: Border.all(
            color: selected
                ? AppColors.mint.withValues(alpha: 0.5)
                : Colors.white.withValues(alpha: 0.1),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: selected ? AppColors.mint : AppColors.textMuted,
          ),
        ),
      ),
    );
  }
}

/// The way in to the Archived list.
class _ArchivedEntry extends StatelessWidget {
  const _ArchivedEntry({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        child: Row(
          children: [
            // No avatar: this is not a person, and giving it a circle the
            // size of one would make it read as a chat you could open.
            SizedBox(
              width: 50,
              child: Icon(
                Icons.archive_outlined,
                size: 21,
                color: AppColors.textMuted.withValues(alpha: 0.9),
              ),
            ),
            const SizedBox(width: 13),
            const Expanded(
              child: Text(
                'Archived',
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            Text(
              // Plain and grey, not a badge. How many chats are in there is
              // information, not something waiting on you.
              '$count',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AppColors.textMuted.withValues(alpha: 0.9),
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: AppColors.textMuted.withValues(alpha: 0.6),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThreadRow extends StatelessWidget {
  const _ThreadRow({
    required this.thread,
    required this.onTap,
    this.onLongPress,
  });

  final Conversation thread;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final person = thread.other;
    final unread = thread.hasUnread;

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
        child: Row(
          children: [
            Stack(
              children: [
                PersonAvatar(
                  size: 50,
                  imageUrl: person?.avatarUrl,
                  initials: person?.initials ?? '?',
                ),
                // The presence dot only appears when the server actually said
                // somebody is online. Absent means unknown, not offline.
                if (person?.online == true)
                  Positioned(
                    right: 1,
                    bottom: 1,
                    child: Container(
                      width: 13,
                      height: 13,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.mint,
                        border:
                            Border.all(color: AppColors.canvas, width: 2.5),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    person?.name ?? 'Someone',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: unread ? FontWeight.w800 : FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    thread.preview,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.3,
                      // Unread previews carry weight and colour; read ones
                      // recede. The list should be scannable without reading
                      // a single word of it.
                      fontWeight: unread ? FontWeight.w600 : FontWeight.w400,
                      color:
                          unread ? AppColors.textPrimary : AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  thread.timeLabel,
                  style: TextStyle(
                    fontSize: 10.5,
                    color: unread
                        ? AppColors.mint
                        : AppColors.textMuted.withValues(alpha: 0.8),
                  ),
                ),
                const SizedBox(height: 6),
                // Muted and pinned share the row under the timestamp, where
                // the unread badge goes. A muted chat with something waiting
                // shows both: silenced is not the same as ignored.
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (thread.muted) ...[
                      Icon(
                        Icons.notifications_off_rounded,
                        size: 13,
                        color: AppColors.textMuted.withValues(alpha: 0.75),
                      ),
                      const SizedBox(width: 5),
                    ],
                    if (thread.pinned) ...[
                      Icon(
                        Icons.push_pin_rounded,
                        size: 13,
                        color: AppColors.textMuted.withValues(alpha: 0.75),
                      ),
                      const SizedBox(width: 5),
                    ],
                    if (unread)
                      _UnreadBadge(thread: thread)
                    else if (!thread.muted && !thread.pinned)
                      const SizedBox(height: 18),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The count, or a plain dot when a chat was marked unread by hand.
class _UnreadBadge extends StatelessWidget {
  const _UnreadBadge({required this.thread});

  final Conversation thread;

  @override
  Widget build(BuildContext context) {
    // Marked unread on purpose has no number to show — inventing "1" would
    // claim a message arrived that did not.
    if (thread.unreadCount == 0) {
      return Container(
        width: 11,
        height: 11,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: AppColors.safeGradient,
        ),
      );
    }

    return Container(
      constraints: const BoxConstraints(minWidth: 20),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: AppColors.safeGradient,
      ),
      child: Text(
        thread.unreadCount > 99 ? '99+' : '${thread.unreadCount}',
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          color: Color(0xFF04121F),
        ),
      ),
    );
  }
}
