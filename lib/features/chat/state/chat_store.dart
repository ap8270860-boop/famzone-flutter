import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/api/api_response.dart';
import '../../../core/session/session.dart';
import '../data/chat_api.dart';
import '../data/chat_models.dart';

/// The inbox, and the unread badge.
///
/// A [ChangeNotifier] singleton, matching [Session] and `SafetyStore` — the
/// Riverpod-vs-Bloc decision is still open, and keeping the stores shaped
/// alike means moving them later is one mechanical pass rather than three
/// arguments.
///
/// Lives for as long as somebody is signed in, which is why the badge is
/// correct whether or not a chat screen is open. From the next phase this is
/// the object that holds the `private-user` subscription; today it is the
/// same shape, fed by refreshes instead of by frames.
class ChatStore extends ChangeNotifier {
  ChatStore._() {
    // The next account must never see the last one's threads flash past.
    Session.instance.onSignOut(clear);
  }

  static final ChatStore instance = ChatStore._();

  final ChatApi _api = ChatApi();

  List<Conversation> _threads = const [];
  List<Conversation> _requests = const [];

  int _unread = 0;
  int _requestCount = 0;

  /// How many threads are put away. Only a count — the Archived screen
  /// fetches its own page, because a list nobody is looking at has no
  /// business being held in memory for the whole session.
  int _archivedCount = 0;

  bool _loading = false;
  bool _loaded = false;
  String? _error;

  List<Conversation> get threads => _threads;
  List<Conversation> get requests => _requests;

  int get unread => _unread;

  /// Unread messages in my direct thread with one person.
  ///
  /// Group threads are skipped: the badge this feeds sits on somebody's face
  /// on the family map, and "3 unread" there has to mean three messages from
  /// *them*, not three in a group they happen to be in.
  ///
  /// Zero when we have never spoken — an absent thread and an empty one are
  /// the same answer to this question.
  int unreadWith(String userId) {
    for (final thread in _threads) {
      if (thread.group != null) continue;
      if (thread.other?.id != userId) continue;

      return thread.unreadCount;
    }

    return 0;
  }
  int get requestCount => _requestCount;
  int get archivedCount => _archivedCount;

  /// True only for the very first load. A refresh over existing threads must
  /// not blank the list out.
  bool get loading => _loading && !_loaded;

  bool get loaded => _loaded;
  String? get error => _error;

  String get _meId => Session.instance.user?.id ?? '';

  /*
  |----------------------------------------------------------------------------
  | Loading
  |----------------------------------------------------------------------------
  */

  /// Fetch the inbox, the requests tab and the badge counts.
  Future<void> refresh() async {
    if (!Session.instance.isAuthenticated || _loading) return;

    _loading = true;

    try {
      final results = await Future.wait([
        _api.conversations(),
        _api.conversations(state: 'pending'),
        _api.unreadCount(),
      ]);

      _threads = _parse(results[0]);
      _requests = _parse(results[1]);

      final counts = results[2].dataMap;

      _unread = counts['unread'] as int? ?? 0;
      _requestCount = counts['requests'] as int? ?? _requests.length;

      _error = null;
      _loaded = true;

      await _acknowledgeDelivery();
    } on ApiException catch (e) {
      _error = e.message;
    } catch (_) {
      _error = 'Could not reach the server.';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Just the counts, for the badge on a screen that is not the inbox.
  /// Make sure the thread list is actually in memory.
  ///
  /// The bug this fixes: `_threads` was only ever filled by [refresh], and
  /// [refresh] only ran when somebody tapped the Chats tab. Anyone who opened
  /// the app and went straight to the family map therefore had an *empty*
  /// thread list, so [unreadWith] answered zero for every person on it and no
  /// badge appeared — on some devices and not others, purely according to
  /// whether that person had visited Chats since launch.
  ///
  /// `refreshBadge` was not enough on its own. It fetches the *total* unread
  /// count for the nav bar, which is one number and says nothing about who
  /// the messages are from.
  ///
  /// Cheap to call: it does nothing once loaded, and the socket keeps the
  /// list current from then on.
  Future<void> ensureLoaded() async {
    if (_loaded || _loading) return;

    await refresh();
  }

  Future<void> refreshBadge() async {
    if (!Session.instance.isAuthenticated) return;

    try {
      final res = await _api.unreadCount();

      if (!res.success) return;

      _unread = res.dataMap['unread'] as int? ?? 0;
      _requestCount = res.dataMap['requests'] as int? ?? 0;
      _archivedCount = res.dataMap['archived'] as int? ?? 0;

      notifyListeners();
    } catch (_) {
      // A stale badge is not worth an error state.
    }
  }

  List<Conversation> _parse(ApiResponse res) {
    if (!res.success) return const [];

    return (res.dataMap['conversations'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map((json) => Conversation.fromJson(json, _meId))
        .toList();
  }

  /// Report the arrival of anything new, so the sender gets a second tick.
  ///
  /// This is why delivery is reported from the inbox and not from the chat
  /// screen: "delivered" means the message reached the device, which happens
  /// whether or not the recipient has opened the thread. Doing it here is
  /// what makes the two grey ticks mean what they say.
  Future<void> _acknowledgeDelivery() async {
    for (final thread in _threads) {
      final last = thread.lastMessage;

      if (last == null || last.isMine || last.remoteId == null) continue;
      if (thread.myDeliveredSeq >= last.seq) continue;

      try {
        await _api.markDelivered(thread.id, last.remoteId!);
      } catch (_) {
        // Best effort by definition. The next refresh tries again.
      }
    }
  }

  /*
  |----------------------------------------------------------------------------
  | Local updates
  |----------------------------------------------------------------------------
  */

  /// Fold an updated thread into the list without a round trip.
  ///
  /// Called by [ConversationStore] after a send, so the inbox reorders and
  /// the preview changes the moment the message lands rather than on the
  /// next refresh.
  void absorb(Conversation conversation) {
    _threads = _sorted([
      conversation,
      ..._threads.where((t) => t.id != conversation.id),
    ]);

    _recount();
    notifyListeners();
  }

  /// Pinned chats first, then newest.
  ///
  /// The same order the server sorts by, repeated here because the list is
  /// rearranged locally on every send and every socket frame — if the two
  /// disagreed, a pinned chat would fall down the list until the next
  /// refresh put it back, which looks like a bug on both ends.
  List<Conversation> _sorted(List<Conversation> threads) {
    return [...threads]..sort((a, b) {
        if (a.pinned != b.pinned) return a.pinned ? -1 : 1;

        final at = a.lastMessageAt;
        final bt = b.lastMessageAt;

        if (at == null && bt == null) return 0;
        if (at == null) return 1;
        if (bt == null) return -1;

        return bt.compareTo(at);
      });
  }

  /// Swap one thread for an edited copy of itself, keeping the order right.
  void _replace(String id, Conversation Function(Conversation) edit) {
    _threads = _sorted([
      for (final thread in _threads) thread.id == id ? edit(thread) : thread,
    ]);

    _recount();
    notifyListeners();
  }

  /*
  |----------------------------------------------------------------------------
  | My own view of a thread
  |----------------------------------------------------------------------------
  |
  | Each one flips the row first and asks the server second. They are all
  | small, private, reversible writes — waiting on a round trip to move a
  | chat to the top of a list makes the tap feel broken.
  */

  Future<bool> pinChat(Conversation thread) =>
      _apply(thread, (t) => t.copyWith(pinned: !t.pinned),
          () => _api.pinChat(thread.id));

  Future<bool> mute(Conversation thread, {int? hours}) => _apply(
        thread,
        (t) => t.copyWith(muted: !t.muted),
        () => _api.mute(thread.id, muted: !thread.muted, hours: hours),
      );

  Future<bool> markUnread(Conversation thread) => _apply(
        thread,
        (t) => t.copyWith(markedUnread: true),
        () => _api.markUnread(thread.id),
      );

  /// Empty a thread on this side. The row stays, with nothing to preview.
  Future<bool> clearChat(Conversation thread) => _apply(
        thread,
        (t) => t.copyWith(
          unreadCount: 0,
          markedUnread: false,
          clearLastMessage: true,
        ),
        () => _api.clearChat(thread.id),
      );

  /// Put a thread away, or bring it back.
  ///
  /// The row leaves the list it is in either way, so this cannot go through
  /// [_apply] — there is nothing left in the list to edit. Archiving from
  /// the inbox removes it; unarchiving from the Archived screen is the same
  /// call and the inbox picks it up on its next refresh.
  Future<bool> archive(Conversation thread) async {
    final threads = [..._threads];
    final count = _archivedCount;

    _threads = _threads.where((t) => t.id != thread.id).toList();
    _archivedCount = thread.archived ? count - 1 : count + 1;

    _recount();
    notifyListeners();

    try {
      final res = await _api.archiveChat(thread.id);

      if (!res.success) {
        _threads = threads;
        _archivedCount = count;

        _recount();
        notifyListeners();
      }

      return res.success;
    } catch (_) {
      _threads = threads;
      _archivedCount = count;

      _recount();
      notifyListeners();

      return false;
    }
  }

  /// Leave a thread from the inbox — the same endpoint that declines a
  /// request, because they are the same act.
  ///
  /// The membership row survives on the server with `left_at` set, so a
  /// later message from them reopens this same conversation rather than
  /// starting a second one beside it with half the history missing.
  Future<bool> leave(Conversation thread) async {
    final threads = [..._threads];
    final requests = [..._requests];

    removeThread(thread.id);

    try {
      final res = await _api.leave(thread.id);

      if (!res.success) _restore(threads, requests);

      return res.success;
    } catch (_) {
      _restore(threads, requests);

      return false;
    }
  }

  void _restore(List<Conversation> threads, List<Conversation> requests) {
    _threads = threads;
    _requests = requests;
    _requestCount = requests.length;

    _recount();
    notifyListeners();
  }

  /// Apply a local edit, call the server, and put it back if it refused.
  Future<bool> _apply(
    Conversation thread,
    Conversation Function(Conversation) edit,
    Future<ApiResponse> Function() call,
  ) async {
    final before = _threads.firstWhere(
      (t) => t.id == thread.id,
      orElse: () => thread,
    );

    _replace(thread.id, edit);

    try {
      final res = await call();

      if (!res.success) _replace(thread.id, (_) => before);

      return res.success;
    } catch (_) {
      _replace(thread.id, (_) => before);

      return false;
    }
  }

  /// Drop a thread from both lists.
  ///
  /// Called when a block closes it, or when a request is declined. The thread
  /// still exists on the server — this is the local view catching up, not a
  /// deletion.
  void removeThread(String conversationId) {
    _threads = _threads.where((t) => t.id != conversationId).toList();
    _requests = _requests.where((t) => t.id != conversationId).toList();

    _requestCount = _requests.length;

    _recount();
    notifyListeners();
  }

  /// A thread has been opened and read.
  void clearUnread(String conversationId) {
    _threads = [
      for (final thread in _threads)
        thread.id == conversationId
            // Opening it undoes "mark as unread" as well, the same way the
            // receipt endpoint does on the server.
            ? thread.copyWith(unreadCount: 0, markedUnread: false)
            : thread,
    ];

    _recount();
    notifyListeners();
  }

  void _recount() {
    // A thread marked unread counts as one, matching how the server totals
    // the badge — otherwise the dot on the row and the number on the tab
    // disagree until the next refresh.
    _unread = _threads.fold(
      0,
      (sum, thread) =>
          sum +
          (thread.unreadCount > 0
              ? thread.unreadCount
              : thread.markedUnread
                  ? 1
                  : 0),
    );
  }

  /// Fold a live `inbox.updated` frame into the list.
  ///
  /// The payload is the same conversation summary the inbox endpoint
  /// returns, so this is the socket doing what a refresh would have done —
  /// without the refresh.
  void applyInboxEvent(Map<String, dynamic> json) {
    final conversation = Conversation.fromJson(json, _meId);

    if (conversation.id.isEmpty) return;

    if (conversation.isRequest) {
      // A request belongs in the other tab, and must not be counted as
      // unread — it is a decision waiting, not a conversation waiting.
      _requests = [
        conversation,
        ..._requests.where((t) => t.id != conversation.id),
      ];

      _threads = _threads.where((t) => t.id != conversation.id).toList();
      _requestCount = _requests.length;

      notifyListeners();

      return;
    }

    absorb(conversation);

    // Report the arrival straight away, so the sender's second tick appears
    // without the recipient touching their phone.
    unawaited(_acknowledge(conversation));
  }

  Future<void> _acknowledge(Conversation thread) async {
    final last = thread.lastMessage;

    if (last == null || last.isMine || last.remoteId == null) return;
    if (thread.myDeliveredSeq >= last.seq) return;

    try {
      await _api.markDelivered(thread.id, last.remoteId!);
    } catch (_) {
      // Best effort. The next refresh tries again.
    }
  }

  /// Drop everything on sign-out.
  void clear() {
    _threads = const [];
    _requests = const [];
    _unread = 0;
    _requestCount = 0;
    _loaded = false;
    _loading = false;
    _error = null;
    notifyListeners();
  }
}
