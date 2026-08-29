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

  bool _loading = false;
  bool _loaded = false;
  String? _error;

  List<Conversation> get threads => _threads;
  List<Conversation> get requests => _requests;

  int get unread => _unread;
  int get requestCount => _requestCount;

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
  Future<void> refreshBadge() async {
    if (!Session.instance.isAuthenticated) return;

    try {
      final res = await _api.unreadCount();

      if (!res.success) return;

      _unread = res.dataMap['unread'] as int? ?? 0;
      _requestCount = res.dataMap['requests'] as int? ?? 0;

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
    final next = [
      conversation,
      ..._threads.where((t) => t.id != conversation.id),
    ]..sort((a, b) {
        final at = a.lastMessageAt;
        final bt = b.lastMessageAt;

        if (at == null && bt == null) return 0;
        if (at == null) return 1;
        if (bt == null) return -1;

        return bt.compareTo(at);
      });

    _threads = next;
    _recount();
    notifyListeners();
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
        thread.id == conversationId ? thread.copyWith(unreadCount: 0) : thread,
    ];

    _recount();
    notifyListeners();
  }

  void _recount() {
    _unread = _threads.fold(0, (sum, thread) => sum + thread.unreadCount);
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
