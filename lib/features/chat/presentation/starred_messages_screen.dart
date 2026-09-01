import 'package:flutter/material.dart';

import '../../../core/session/session.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../core/widgets/aurora_background.dart';
import '../../people/presentation/widgets/person_avatar.dart';
import '../data/chat_api.dart';
import '../data/chat_models.dart';
import 'chat_screen.dart';

/// Everything this person has kept, newest first.
///
/// Reached from the drawer rather than from inside a thread, deliberately:
/// the whole point of a star is that it survives the conversation it was in,
/// so the list that holds them cannot live behind one thread's back button.
///
/// Private. A star is never broadcast and the other person has no way to
/// learn you kept something of theirs.
class StarredMessagesScreen extends StatefulWidget {
  const StarredMessagesScreen({super.key});

  @override
  State<StarredMessagesScreen> createState() => _StarredMessagesScreenState();
}

class _StarredMessagesScreenState extends State<StarredMessagesScreen> {
  final ChatApi _api = ChatApi();
  final ScrollController _scroll = ScrollController();

  final List<_Starred> _items = [];
  final Set<String> _busy = {};

  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  int _page = 1;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();

    _scroll.addListener(() {
      if (!_scroll.hasClients || _loadingMore || !_hasMore) return;

      final position = _scroll.position;

      // Fetched a screenful early, so the next page is usually already here
      // by the time the last row goes past.
      if (position.pixels > position.maxScrollExtent - 400) _loadMore();
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    _api.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final res = await _api.starredMessages();

      if (!mounted) return;

      setState(() {
        if (res.success) {
          _items
            ..clear()
            ..addAll(_parse(res.dataMap));

          _hasMore = res.dataMap['has_more'] as bool? ?? false;
          _page = 1;
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

  Future<void> _loadMore() async {
    if (_loadingMore) return;

    setState(() => _loadingMore = true);

    try {
      final res = await _api.starredMessages(page: _page + 1);

      if (!mounted) return;

      setState(() {
        if (res.success) {
          _items.addAll(_parse(res.dataMap));
          _hasMore = res.dataMap['has_more'] as bool? ?? false;
          _page += 1;
        } else {
          // A failed page is not a failed screen — what is already loaded
          // stays, and scrolling again retries.
          _hasMore = false;
        }

        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loadingMore = false;
          _hasMore = false;
        });
      }
    }
  }

  List<_Starred> _parse(Map<String, dynamic> data) {
    return (data['messages'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(_Starred.fromJson)
        .toList();
  }

  /// Take the star off. The row leaves the list, because the list *is* the
  /// stars — leaving an unstarred row sitting there would be a lie about
  /// what this screen shows.
  Future<void> _unstar(_Starred item) async {
    final id = item.message.remoteId;

    if (id == null || _busy.contains(id)) return;

    setState(() => _busy.add(id));

    try {
      final res = await _api.star(id);

      if (!mounted) return;

      if (res.success) {
        setState(() => _items.removeWhere((i) => i.message.remoteId == id));
        AppToast.success(context, 'Removed from starred.');
      } else {
        AppToast.error(context, res.message);
      }
    } catch (_) {
      if (mounted) AppToast.error(context, 'Could not reach the server.');
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  Future<void> _open(_Starred item) async {
    final person = item.other;

    if (person == null) return;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          conversationId: item.conversationId,
          userId: person.id,
          name: person.name,
          username: person.username,
          avatarUrl: person.avatarUrl,
          initials: person.initials,
          presence: person.presenceLabel,
        ),
      ),
    );

    // Stars can be taken off inside the thread, so the list behind it may be
    // stale by the time we come back.
    if (mounted) _load();
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
                        'Starred messages',
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

    if (_error != null) {
      return _Empty(
        icon: Icons.cloud_off_rounded,
        title: 'Could not load',
        body: _error!,
        onRetry: () {
          setState(() => _loading = true);
          _load();
        },
      );
    }

    if (_items.isEmpty) {
      return const _Empty(
        icon: Icons.star_outline_rounded,
        title: 'Nothing starred yet',
        body: 'Press and hold a message, then tap Star, and it will be kept '
            'here — the address, the date, the thing you keep scrolling back '
            'for.',
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.mint,
      backgroundColor: AppColors.canvas,
      child: ListView.builder(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(14, 6, 14, 20),
        itemCount: _items.length + (_hasMore ? 1 : 0),
        itemBuilder: (context, i) {
          if (i >= _items.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 1.8),
                ),
              ),
            );
          }

          final item = _items[i];

          return _StarredCard(
            item: item,
            busy: _busy.contains(item.message.remoteId),
            onTap: () => _open(item),
            onUnstar: () => _unstar(item),
          );
        },
      ),
    );
  }
}

/// One kept message, and enough of its thread to say where it came from.
@immutable
class _Starred {
  const _Starred({
    required this.message,
    required this.conversationId,
    this.other,
  });

  final ChatMessage message;
  final String conversationId;

  /// Null only for a malformed thread. The row still renders — a starred
  /// message with a missing peer is worth showing rather than dropping.
  final ChatPerson? other;

  factory _Starred.fromJson(Map<String, dynamic> json) {
    final conversation =
        json['conversation'] as Map<String, dynamic>? ?? const {};

    final other = conversation['other'] as Map<String, dynamic>?;

    return _Starred(
      // Passing an empty viewer id would make every message read as somebody
      // else's, so the sender is compared against the signed-in user the same
      // way the thread does it.
      message: ChatMessage.fromJson(json, Session.instance.user?.id ?? ''),
      conversationId: conversation['id'] as String? ?? '',
      other: other == null ? null : ChatPerson.fromJson(other),
    );
  }

  /// What the row shows as the message itself.
  String get preview {
    if (message.deleted) return 'Message deleted';

    if (message.body.isNotEmpty) return message.body;

    return switch (message.type) {
      MessageType.image => 'Photo',
      MessageType.file => message.attachment?.name ?? 'File',
      MessageType.audio => 'Voice message',
      _ => '',
    };
  }
}

class _StarredCard extends StatelessWidget {
  const _StarredCard({
    required this.item,
    required this.busy,
    required this.onTap,
    required this.onUnstar,
  });

  final _Starred item;
  final bool busy;
  final VoidCallback onTap;
  final VoidCallback onUnstar;

  @override
  Widget build(BuildContext context) {
    final person = item.other;
    final message = item.message;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: AppColors.canvasRaised,
          border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PersonAvatar(
              size: 38,
              imageUrl: person?.avatarUrl,
              initials: person?.initials ?? '?',
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          // Whose thread it was, then who wrote it — one line
                          // has to carry both or the quote loses its half of
                          // the conversation.
                          message.isMine
                              ? 'You → ${person?.name ?? 'Someone'}'
                              : person?.name ?? 'Someone',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        chatDateLabel(message.sentAt),
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (message.hasMedia) ...[
                        Padding(
                          padding: const EdgeInsets.only(top: 2, right: 6),
                          child: Icon(
                            message.isImage
                                ? Icons.photo_rounded
                                : Icons.insert_drive_file_rounded,
                            size: 14,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                      Expanded(
                        child: Text(
                          item.preview,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13.5,
                            height: 1.35,
                            fontStyle: message.deleted
                                ? FontStyle.italic
                                : FontStyle.normal,
                            color: message.deleted
                                ? AppColors.textMuted
                                : AppColors.textPrimary
                                    .withValues(alpha: 0.86),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // The star is the affordance to remove it. There is nowhere else
            // to unstar from without opening the thread and finding the
            // message again, which for something months old is not a route.
            IconButton(
              onPressed: busy ? null : onUnstar,
              icon: busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 1.8),
                    )
                  : const Icon(Icons.star_rounded,
                      size: 20, color: AppColors.warmGold),
              tooltip: 'Remove from starred',
            ),
          ],
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({
    required this.icon,
    required this.title,
    required this.body,
    this.onRetry,
  });

  final IconData icon;
  final String title;
  final String body;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(height: MediaQuery.sizeOf(context).height * 0.16),
        Icon(icon, size: 44, color: AppColors.textMuted),
        const SizedBox(height: 14),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 15.5,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 44),
          child: Text(
            body,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13,
              height: 1.45,
              color: AppColors.textMuted,
            ),
          ),
        ),
        if (onRetry != null) ...[
          const SizedBox(height: 16),
          Center(
            child: TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(foregroundColor: AppColors.mint),
              child: const Text('Try again'),
            ),
          ),
        ],
      ],
    );
  }
}
