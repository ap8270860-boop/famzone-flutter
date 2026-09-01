import 'package:flutter/material.dart';

import '../../../core/session/session.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../core/widgets/aurora_background.dart';
import '../../people/presentation/widgets/person_avatar.dart';
import '../data/chat_api.dart';
import '../data/chat_models.dart';
import '../state/chat_store.dart';
import 'chat_screen.dart';
import 'widgets/thread_menu.dart';

/// Chats that have been put away.
///
/// Fetches its own page rather than reading a third list off [ChatStore].
/// The inbox store lives for the whole session and this list is looked at
/// rarely — holding it in memory the rest of the time buys nothing.
class ArchivedChatsScreen extends StatefulWidget {
  const ArchivedChatsScreen({super.key});

  @override
  State<ArchivedChatsScreen> createState() => _ArchivedChatsScreenState();
}

class _ArchivedChatsScreenState extends State<ArchivedChatsScreen> {
  final ChatApi _api = ChatApi();

  List<Conversation> _threads = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _api.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final res = await _api.conversations(archived: true);

      if (!mounted) return;

      setState(() {
        if (res.success) {
          _threads = (res.dataMap['conversations'] as List<dynamic>? ??
                  const [])
              .whereType<Map<String, dynamic>>()
              .map((json) =>
                  Conversation.fromJson(json, Session.instance.user?.id ?? ''))
              .toList();

          _error = null;
        } else {
          _error = res.message;
        }

        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _error = 'Could not reach the server.';
        _loading = false;
      });
    }
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

    // Reading an archived chat leaves it archived — that is the point of
    // having put it here — but its preview and unread count have moved on.
    if (mounted) _load();
  }

  Future<void> _menu(Conversation thread) async {
    final action = await showThreadMenu(context, thread);

    if (action == null || !mounted) return;

    switch (action) {
      case ThreadAction.unarchive:
      case ThreadAction.archive:
        await _unarchive(thread);

      case ThreadAction.mute:
      case ThreadAction.unmute:
        await ChatStore.instance.mute(thread);

        if (mounted) _load();

      case ThreadAction.markUnread:
        await ChatStore.instance.markUnread(thread);

        if (mounted) _load();

      case ThreadAction.clear:
        await ChatStore.instance.clearChat(thread);

        if (mounted) _load();

      case ThreadAction.delete:
        await ChatStore.instance.leave(thread);

        if (mounted) {
          setState(() =>
              _threads = _threads.where((t) => t.id != thread.id).toList());
        }

      // Pinning is not offered on an archived chat, so this cannot arrive.
      case ThreadAction.pin:
      case ThreadAction.unpin:
        break;
    }
  }

  Future<void> _unarchive(Conversation thread) async {
    final ok = await ChatStore.instance.archive(thread);

    if (!mounted) return;

    if (ok) {
      setState(
          () => _threads = _threads.where((t) => t.id != thread.id).toList());

      // The inbox has a row back that it does not know about yet.
      ChatStore.instance.refresh();

      AppToast.success(context, 'Moved back to your chats.');
    } else {
      AppToast.error(context, 'Could not move that chat.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: AuroraBackground(
        child: SafeArea(
          child: Column(
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
                        'Archived',
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
              Expanded(child: _body()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    if (_threads.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(height: MediaQuery.sizeOf(context).height * 0.18),
          Icon(
            _error == null ? Icons.archive_outlined : Icons.cloud_off_rounded,
            size: 44,
            color: AppColors.textMuted.withValues(alpha: 0.45),
          ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 44),
            child: Text(
              _error ??
                  'Chats you archive are kept here. They still receive '
                      'messages — they just stay out of your main list.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                height: 1.45,
                color: AppColors.textMuted,
              ),
            ),
          ),
        ],
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.mint,
      backgroundColor: AppColors.canvas,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 24),
        itemCount: _threads.length,
        itemBuilder: (context, i) => _ArchivedRow(
          thread: _threads[i],
          onTap: () => _open(_threads[i]),
          onLongPress: () => _menu(_threads[i]),
        ),
      ),
    );
  }
}

/// Deliberately plainer than an inbox row.
///
/// No presence dot and no unread badge: an archived chat is one you have
/// decided should stop asking for attention, and a list of them covered in
/// green would be arguing with that decision.
class _ArchivedRow extends StatelessWidget {
  const _ArchivedRow({
    required this.thread,
    required this.onTap,
    required this.onLongPress,
  });

  final Conversation thread;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final person = thread.other;

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
        child: Row(
          children: [
            PersonAvatar(
              size: 46,
              imageUrl: person?.avatarUrl,
              initials: person?.initials ?? '?',
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
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    thread.preview,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12.5,
                      height: 1.3,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              thread.timeLabel,
              style: TextStyle(
                fontSize: 10.5,
                color: AppColors.textMuted.withValues(alpha: 0.8),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
