import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/api/api_response.dart';
import '../../../core/session/session.dart';
import '../data/chat_api.dart';
import '../data/chat_models.dart';
import 'chat_store.dart';
import 'realtime_client.dart';
import 'voice_recorder.dart';

/// One open conversation.
///
/// Created when a chat screen opens and disposed when it closes. That
/// lifetime is the whole point: from the next phase this object owns the
/// websocket subscription for its thread, so a message in one conversation
/// cannot reach the screen showing another. Nothing else in the app holds a
/// reference to it.
///
/// Two lists rather than one. Sent messages are ordered by the server's
/// sequence number, which is the only ordering anyone can agree on; messages
/// still in flight have no sequence yet and simply sit after them in the
/// order they were typed. Merging the two on read avoids ever sorting a list
/// where half the keys are zero.
class ConversationStore extends ChangeNotifier {
  ConversationStore({required this.peerId, this.conversationId});

  /// The other person. Always known — a chat is opened either from their
  /// profile or from an inbox row.
  final String peerId;

  /// Null when opening from a profile, in which case the first call resolves
  /// or creates it.
  String? conversationId;

  final ChatApi _api = ChatApi();

  final List<ChatMessage> _sent = [];
  final List<ChatMessage> _pending = [];
  List<ChatMessage> _view = const [];

  Conversation? _conversation;
  bool _loading = true;
  bool _loadingOlder = false;
  bool _hasMore = false;
  bool _disposed = false;
  String? _error;

  /// Whether the other person is typing, and the deadline for believing it.
  ///
  /// The timer is not a nicety. A `stopped` whisper is a single UDP-ish frame
  /// over a socket that may be about to die, and if it never arrives the
  /// other person appears to be typing forever. Expiring locally means the
  /// indicator is always wrong for at most four seconds.
  bool _peerTyping = false;
  Timer? _typingExpiry;

  /// Our own outgoing throttle, so a fast typist sends one frame every two
  /// seconds rather than one per keystroke.
  DateTime? _typingSentAt;
  Timer? _typingIdle;

  /// Whether they are looking at this thread right now, from the presence
  /// channel. Distinct from being online: a person can have the app open on
  /// another screen entirely.
  bool _peerInRoom = false;

  /// Set when a block closes this thread while it is open.
  bool _closed = false;

  /// The message being replied to, while the composer holds a reply.
  ChatMessage? _replyingTo;

  Conversation? get conversation => _conversation;
  ChatPerson? get person => _conversation?.other;
  List<ChatMessage> get messages => _view;

  bool get loading => _loading;
  bool get loadingOlder => _loadingOlder;
  bool get hasMore => _hasMore;
  String? get error => _error;
  bool get isRequest => _conversation?.isRequest ?? false;

  /// Whether the other person still has to accept before more can be sent.
  bool get awaitingAcceptance => _conversation?.other?.hasAccepted == false;

  bool get peerTyping => _peerTyping;

  ChatMessage? get replyingTo => _replyingTo;

  void startReply(ChatMessage message) {
    if (message.deleted) return;

    _replyingTo = message;
    _rebuild();
  }

  void cancelReply() {
    if (_replyingTo == null) return;

    _replyingTo = null;
    _rebuild();
  }

  /// Whether a wall stands between the two of you.
  ///
  /// True from the server on load, or the moment a block lands while the
  /// screen is open. The composer goes away either way — a text field that
  /// accepts input and then fails with a 403 is a worse way to find out.
  bool get blocked => _closed || (_conversation?.blocked ?? false);

  /// What the header should say under their name.
  ///
  /// Being in the thread beats being online, because it is both more specific
  /// and more useful: "Active now" tells you they will see this immediately,
  /// where "Online" only says the app is open somewhere.
  ///
  /// Null hides the line rather than showing a placeholder — presence is a
  /// privacy setting, and inventing a value the server declined to state
  /// would be worse than saying nothing.
  String? get peerPresenceLabel {
    if (_peerTyping) return 'typing…';
    if (_peerInRoom) return 'Active now';

    return _conversation?.other?.presenceLabel;
  }

  String get _meId => Session.instance.user?.id ?? '';

  /// Exposed so the list can tell your own reaction from theirs.
  String get meId => _meId;

  int get _newestSeq => _sent.isEmpty ? 0 : _sent.last.seq;
  int get _oldestSeq => _sent.isEmpty ? 0 : _sent.first.seq;

  /*
  |----------------------------------------------------------------------------
  | Loading
  |----------------------------------------------------------------------------
  */

  /// Resolve the thread and fetch the newest page.
  Future<void> open() async {
    _loading = true;
    _error = null;

    try {
      final id = conversationId;

      final res =
          id == null ? await _api.startWith(peerId) : await _api.conversation(id);

      if (!res.success) {
        _error = res.message;
        return;
      }

      _conversation = Conversation.fromJson(res.dataMap, _meId);
      conversationId = _conversation!.id;

      // Subscribe before the first fetch, not after. Anything that lands in
      // the gap between them arrives on the socket and is merged by sequence
      // number; the other order drops it silently.
      unawaited(
        RealtimeClient.instance.joinConversation(conversationId!, _onRealtime),
      );

      // The presence channel is separate from the message channel and joined
      // alongside it. Two channels rather than one because they answer
      // different questions with different costs: the message channel is
      // silent until somebody writes, while presence churns on every open and
      // close of the screen.
      unawaited(
        RealtimeClient.instance.joinRoom(conversationId!, _onRoom),
      );

      await _fetch();
      await _markRead();
    } on ApiException catch (e) {
      _error = e.message;
    } catch (_) {
      _error = 'Could not reach the server.';
    } finally {
      _loading = false;
      _rebuild();
    }
  }

  /// Pull to refresh, and what the app does on returning to the foreground.
  ///
  /// Re-reads the conversation before the messages, deliberately. The
  /// conversation carries the other person's watermarks, so this is what
  /// turns the ticks blue until the socket arrives to do it live.
  Future<void> refresh() async {
    final id = conversationId;

    if (id == null) return open();

    try {
      final head = await _api.conversation(id);

      if (head.success) {
        _conversation = Conversation.fromJson(head.dataMap, _meId);
      }

      await _fetch(after: _newestSeq > 0 ? _newestSeq : null);
      await _markRead();

      _error = null;
    } on ApiException catch (e) {
      _error = e.message;
    } catch (_) {
      _error = 'Could not reach the server.';
    } finally {
      _rebuild();
    }
  }

  /// Older history, as the user scrolls up.
  Future<void> loadOlder() async {
    final id = conversationId;

    if (id == null || _loadingOlder || !_hasMore || _sent.isEmpty) return;

    _loadingOlder = true;
    _rebuild();

    try {
      await _fetch(before: _oldestSeq);
    } on ApiException catch (e) {
      _error = e.message;
    } catch (_) {
      // A failed page of history is not worth an error banner over a
      // conversation the user can already read. They can scroll again.
    } finally {
      _loadingOlder = false;
      _rebuild();
    }
  }

  Future<void> _fetch({int? before, int? after}) async {
    final id = conversationId;

    if (id == null) return;

    final res = await _api.messages(id, before: before, after: after);

    if (!res.success) {
      _error = res.message;
      return;
    }

    final data = res.dataMap;
    final incoming = (data['messages'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map((json) => ChatMessage.fromJson(json, _meId));

    for (final message in incoming) {
      _upsert(message);

      // A message that came back from the server is no longer in flight.
      // This also covers the case where a send succeeded but its response
      // never arrived — the message is real, and the optimistic copy of it
      // should not linger as a second bubble.
      _pending.removeWhere((p) => p.id == message.id);
    }

    // Only the backwards walk can run out of history. A forward fetch is
    // filling a gap above messages the client already holds.
    if (after == null) {
      _hasMore = data['has_more'] as bool? ?? false;
    }
  }

  /*
  |----------------------------------------------------------------------------
  | Sending
  |----------------------------------------------------------------------------
  */

  /// Post a message, showing it immediately.
  ///
  /// The bubble appears before the request leaves, and the ticks catch up.
  /// If the send fails the bubble stays with a retry affordance rather than
  /// disappearing — a message that vanishes is worse than one that visibly
  /// did not go.
  Future<void> send(String body) async {
    final text = body.trim();
    final id = conversationId;

    if (text.isEmpty || id == null) return;

    // Captured before the bubble is built and cleared straight away: the
    // reply belongs to this message, and leaving the strip up would silently
    // attach it to the next one as well.
    final replyTo = _replyingTo;

    _replyingTo = null;

    final local = ChatMessage(
      id: newClientId(),
      body: text,
      sentAt: DateTime.now(),
      isMine: true,
      state: DeliveryState.sending,
      // Quoted locally too, so the reply reads correctly the instant it
      // appears rather than only once the server echoes it back.
      replyTo: replyTo == null
          ? null
          : QuotedMessage(
              id: replyTo.remoteId ?? '',
              isMine: replyTo.isMine,
              body: replyTo.body,
              type: replyTo.type,
              deleted: replyTo.deleted,
            ),
    );

    // Sending ends typing. Without this the indicator lingers on the other
    // screen for three seconds *after* the message they were waiting for has
    // already arrived, which looks like a stuck UI.
    _sendStoppedTyping();

    _pending.add(local);
    _rebuild();

    await _deliver(local, id, replyToId: replyTo?.remoteId);
  }

  /// Send a photo, with an optional caption.
  ///
  /// The bubble appears immediately, drawn from the file on disk, and the
  /// upload happens underneath it. That matters more here than for text: an
  /// upload can take seconds, and a composer that simply freezes for that
  /// long looks broken.
  ///
  /// Two round trips, in order — upload, then send. The message is only
  /// created once the bytes have landed, so a recipient never receives a
  /// message pointing at a file that does not exist.
  Future<void> sendImage(String filePath, {String caption = ''}) async {
    final id = conversationId;

    if (id == null) return;

    _sendStoppedTyping();

    final local = ChatMessage(
      id: newClientId(),
      body: caption.trim(),
      sentAt: DateTime.now(),
      isMine: true,
      state: DeliveryState.sending,
      type: MessageType.image,
      // Rendered from disk while it uploads, and afterwards too — there is no
      // sense downloading back a copy of the photo we just sent.
      localPath: filePath,
    );

    _pending.add(local);
    _rebuild();

    await _deliverMedia(local, id, filePath, MessageType.image);
  }

  /// Send a document.
  ///
  /// Same pipeline as a photo — upload, then send — but no local preview to
  /// draw, so the bubble shows its name and a spinner instead.
  Future<void> sendFile(String filePath, {String caption = ''}) async {
    final id = conversationId;

    if (id == null) return;

    _sendStoppedTyping();

    final local = ChatMessage(
      id: newClientId(),
      body: caption.trim(),
      sentAt: DateTime.now(),
      isMine: true,
      state: DeliveryState.sending,
      type: MessageType.file,
      localPath: filePath,
      // Named from the path so the bubble reads correctly while it uploads.
      // Replaced by the server's copy the moment the send returns.
      attachment: Attachment(
        id: '',
        mime: 'application/octet-stream',
        name: filePath.split(RegExp(r'[/\\]')).last,
      ),
    );

    _pending.add(local);
    _rebuild();

    await _deliverMedia(local, id, filePath, MessageType.file);
  }

  /// Send a voice note.
  ///
  /// The duration and waveform were measured while recording and travel with
  /// the upload, so the receiving bubble is complete the moment the message
  /// lands — no downloading, no decoding, nothing to compute on either
  /// server or client.
  Future<void> sendVoice(VoiceNote note) async {
    final id = conversationId;

    if (id == null) return;

    _sendStoppedTyping();

    final local = ChatMessage(
      id: newClientId(),
      body: '',
      sentAt: DateTime.now(),
      isMine: true,
      state: DeliveryState.sending,
      type: MessageType.audio,
      localPath: note.path,
      // Carries its own measurements from the start, so the bubble draws the
      // real waveform while it uploads rather than a placeholder that jumps
      // when the server answers.
      attachment: Attachment(
        id: '',
        mime: 'audio/mp4',
        durationMs: note.durationMs,
        waveform: note.waveform,
      ),
    );

    _pending.add(local);
    _rebuild();

    await _deliverMedia(
      local,
      id,
      note.path,
      MessageType.audio,
      durationMs: note.durationMs,
      waveform: note.waveform,
    );
  }

  Future<void> _deliverMedia(
    ChatMessage local,
    String conversationId,
    String filePath,
    String type, {
    int? durationMs,
    List<int>? waveform,
  }) async {
    try {
      final upload = await _api.uploadAttachment(
        filePath: filePath,
        type: type,
        durationMs: durationMs,
        waveform: waveform,
      );

      if (!upload.success) {
        _markFailed(local, upload.message);
        _rebuild();

        return;
      }

      final uploadId = upload.dataMap['id'] as String?;

      if (uploadId == null) {
        _markFailed(local, 'That file could not be stored.');
        _rebuild();

        return;
      }

      final res = await _api.send(
        conversationId,
        clientId: local.id,
        body: local.body,
        type: type,
        uploadId: uploadId,
      );

      if (!res.success) {
        _markFailed(local, res.message);

        return;
      }

      final saved = ChatMessage.fromJson(res.dataMap, _meId).copyWith(
        state: DeliveryState.sent,
        localPath: filePath,
      );

      _pending.removeWhere((m) => m.id == local.id);
      _upsert(saved);

      _conversation = _conversation?.copyWith(
        lastMessage: saved,
        lastMessageAt: saved.sentAt,
        myReadSeq: saved.seq,
      );

      final updated = _conversation;

      if (updated != null) ChatStore.instance.absorb(updated);

      _error = null;
    } on ApiException catch (e) {
      _markFailed(local, e.message);
    } catch (_) {
      _markFailed(local, 'Could not send that photo.');
    } finally {
      _rebuild();
    }
  }

  /// Try a failed message again, with the same client id.
  ///
  /// Reusing the id is what makes this safe: if the first attempt actually
  /// reached the server before the connection dropped, the retry returns that
  /// message rather than posting a duplicate.
  Future<void> retry(ChatMessage message) async {
    final id = conversationId;

    if (id == null || !message.failed) return;

    final index = _pending.indexWhere((m) => m.id == message.id);

    if (index < 0) return;

    _pending[index] = message.copyWith(state: DeliveryState.sending);
    _rebuild();

    final retry = _pending[index];
    final path = retry.localPath;

    // A media retry starts again from the file, because the upload is the
    // half most likely to have failed. The client id is unchanged, so if the
    // send did land last time the server returns that message rather than a
    // duplicate — only the bytes are re-sent.
    if (retry.hasMedia && path != null) {
      await _deliverMedia(retry, id, path, retry.type);

      return;
    }

    await _deliver(retry, id, replyToId: retry.replyTo?.id);
  }

  Future<void> _deliver(
    ChatMessage local,
    String conversationId, {
    String? replyToId,
  }) async {
    try {
      final res = await _api.send(
        conversationId,
        clientId: local.id,
        body: local.body,
        replyToId: replyToId,
      );

      if (!res.success) {
        _markFailed(local, res.message);
        return;
      }

      final saved = ChatMessage.fromJson(res.dataMap, _meId)
          .copyWith(state: DeliveryState.sent);

      _pending.removeWhere((m) => m.id == local.id);
      _upsert(saved);

      _conversation = _conversation?.copyWith(
        lastMessage: saved,
        lastMessageAt: saved.sentAt,
        myReadSeq: saved.seq,
      );

      // Keep the inbox in step without it having to refetch.
      final updated = _conversation;

      if (updated != null) ChatStore.instance.absorb(updated);

      _error = null;
    } on ApiException catch (e) {
      _markFailed(local, e.message);
    } catch (_) {
      _markFailed(local, 'Could not reach the server.');
    } finally {
      _rebuild();
    }
  }

  void _markFailed(ChatMessage local, String? message) {
    final index = _pending.indexWhere((m) => m.id == local.id);

    if (index >= 0) {
      _pending[index] = _pending[index].copyWith(state: DeliveryState.failed);
    }

    _error = message;
  }

  /*
  |----------------------------------------------------------------------------
  | Requests
  |----------------------------------------------------------------------------
  */

  /// Add, change or remove your reaction.
  ///
  /// Applied locally first. A tap on an emoji has to feel instant — waiting
  /// on a round trip before the pill appears makes the gesture feel broken
  /// even when it is working.
  Future<void> react(ChatMessage message, String emoji) async {
    final remoteId = message.remoteId;

    if (remoteId == null) return;

    final before = message;

    _upsert(message.copyWith(
      reactions: _toggled(message.reactions, emoji),
    ));

    _rebuild();

    try {
      final res = await _api.react(remoteId, emoji);

      if (res.success && res.dataMap.isNotEmpty) {
        // Reconciled from the server, which is the only party that knows
        // what the other person did in the meantime.
        _upsert(
          ChatMessage.fromJson(res.dataMap, _meId)
              .copyWith(localPath: before.localPath),
        );
      } else {
        _upsert(before);
      }
    } catch (_) {
      _upsert(before);
    } finally {
      _rebuild();
    }
  }

  /// One reaction per person: adding one removes whatever you had, and
  /// tapping the one you already have takes it off.
  List<Reaction> _toggled(List<Reaction> current, String emoji) {
    final removing = current.any((r) => r.emoji == emoji && r.mine(_meId));

    // Strip yourself out of everything first — the server enforces one row
    // per person, so any local state showing you twice is already wrong.
    final stripped = current
        .map((r) => Reaction(
              emoji: r.emoji,
              count: r.userIds.contains(_meId) ? r.count - 1 : r.count,
              userIds: r.userIds.where((id) => id != _meId).toList(),
            ))
        .where((r) => r.count > 0)
        .toList();

    if (removing) return stripped;

    final index = stripped.indexWhere((r) => r.emoji == emoji);

    if (index >= 0) {
      final existing = stripped[index];

      stripped[index] = Reaction(
        emoji: emoji,
        count: existing.count + 1,
        userIds: [...existing.userIds, _meId],
      );
    } else {
      stripped.add(Reaction(emoji: emoji, count: 1, userIds: [_meId]));
    }

    return stripped;
  }

  /// Keep a message, or stop keeping it.
  ///
  /// Private: nothing is broadcast, and the other person has no way to learn
  /// you kept something of theirs.
  Future<void> toggleStar(ChatMessage message) async {
    final remoteId = message.remoteId;

    if (remoteId == null) return;

    // Flipped locally first — a star is a one-tap gesture and waiting on a
    // round trip makes it feel like it did not register.
    _upsert(message.copyWith(starred: !message.starred));
    _rebuild();

    try {
      final res = await _api.star(remoteId);

      if (res.success) {
        _upsert(message.copyWith(
          starred: res.dataMap['starred'] as bool? ?? !message.starred,
        ));
      } else {
        _upsert(message);
      }
    } catch (_) {
      _upsert(message);
    } finally {
      _rebuild();
    }
  }

  /// Pin a message in this thread, or clear the pin.
  ///
  /// Shared by both people. The server broadcasts the change, but the local
  /// update happens straight away so the banner does not wait on the socket.
  Future<bool> pin(ChatMessage? message) async {
    final id = conversationId;

    if (id == null) return false;

    final before = _conversation;

    _conversation = _conversation?.copyWith(
      pinnedMessage: message,
      clearPin: message == null,
    );

    _rebuild();

    try {
      final res = await _api.pin(id, message?.remoteId);

      if (!res.success) {
        _conversation = before;
        _rebuild();
      }

      return res.success;
    } catch (_) {
      _conversation = before;
      _rebuild();

      return false;
    }
  }

  /// Send a copy of a message into other conversations.
  ///
  /// Returns how many landed. Nothing changes in *this* thread, so there is
  /// no local state to update — the forwarded copies arrive in their own
  /// conversations over the socket.
  Future<int> forward(ChatMessage message, List<String> conversationIds) async {
    final remoteId = message.remoteId;

    if (remoteId == null || conversationIds.isEmpty) return 0;

    try {
      final res = await _api.forward(remoteId, conversationIds);

      if (!res.success) return 0;

      return res.dataMap['count'] as int? ?? conversationIds.length;
    } catch (_) {
      return 0;
    }
  }

  /// Delete a message for me alone.
  ///
  /// The row leaves this device's list and never comes back, because the
  /// server filters it out of every future page. The other person keeps
  /// their copy and is told nothing.
  Future<bool> hideMessage(ChatMessage message) async {
    final remoteId = message.remoteId;

    // Never sent, so there is nothing on the server to hide — dropping the
    // bubble is the whole job.
    if (remoteId == null) {
      _pending.removeWhere((m) => m.id == message.id);

      if (_replyingTo?.id == message.id) _replyingTo = null;

      _rebuild();

      return true;
    }

    // Removed first. Unlike delete-for-everyone there is nothing for the
    // other side to disagree with, and a bubble that lingers for a round
    // trip after you chose to delete it reads as a failure.
    final index = _sent.indexWhere((m) => m.id == message.id);
    final removed = index >= 0 ? _sent.removeAt(index) : null;

    if (_replyingTo?.id == message.id) _replyingTo = null;

    _rebuild();

    try {
      final res = await _api.hideMessage(remoteId);

      if (!res.success && removed != null) {
        _upsert(removed);
        _rebuild();
      }

      return res.success;
    } catch (_) {
      if (removed != null) {
        _upsert(removed);
        _rebuild();
      }

      return false;
    }
  }

  /// Delete a message for everyone.
  ///
  /// Soft on the server, so the other person's bubble becomes a tombstone
  /// rather than a line vanishing out of the middle of their conversation.
  Future<bool> deleteMessage(ChatMessage message) async {
    final remoteId = message.remoteId;

    // Nothing was ever sent, so there is nothing to delete — just drop the
    // failed bubble off the end of the list.
    if (remoteId == null) {
      _pending.removeWhere((m) => m.id == message.id);
      _rebuild();

      return true;
    }

    try {
      final res = await _api.deleteMessage(remoteId);

      if (res.success) {
        _upsert(message.copyWith(deleted: true));

        if (_replyingTo?.id == message.id) _replyingTo = null;

        _rebuild();
      }

      return res.success;
    } catch (_) {
      return false;
    }
  }

  /// Delete the thread — declining a request and leaving a conversation are
  /// the same action against the same endpoint.
  ///
  /// The membership row survives on the server with `left_at` set, so a later
  /// message from them reopens this same conversation rather than starting a
  /// second one beside it with half the history missing.
  Future<bool> deleteThread() async {
    final id = conversationId;

    if (id == null) return false;

    try {
      final res = await _api.leave(id);

      if (res.success) {
        _closed = true;
        ChatStore.instance.removeThread(id);
        _rebuild();
      }

      return res.success;
    } catch (_) {
      _error = 'Could not reach the server.';

      return false;
    }
  }

  Future<bool> acceptRequest() async {
    final id = conversationId;

    if (id == null) return false;

    try {
      final res = await _api.accept(id);

      if (!res.success) {
        _error = res.message;
        return false;
      }

      _conversation = Conversation.fromJson(res.dataMap, _meId);
      ChatStore.instance.refresh();

      return true;
    } catch (_) {
      _error = 'Could not reach the server.';

      return false;
    } finally {
      _rebuild();
    }
  }

  /*
  |----------------------------------------------------------------------------
  | Receipts
  |----------------------------------------------------------------------------
  */

  /// Tell the server everything visible has been read.
  ///
  /// Fired on open and after every fetch. Idempotent and monotonic on the
  /// server, so calling it with a message that is already behind the
  /// watermark costs one indexed lookup and changes nothing.
  Future<void> _markRead() async {
    final id = conversationId;

    if (id == null) return;

    ChatMessage? newest;

    for (final message in _sent) {
      if (!message.isMine && message.remoteId != null) newest = message;
    }

    if (newest == null) return;
    if ((_conversation?.myReadSeq ?? 0) >= newest.seq) return;

    try {
      final res = await _api.markRead(id, newest.remoteId!);

      if (res.success) {
        _conversation = _conversation?.copyWith(
          myReadSeq: newest.seq,
          unreadCount: 0,
        );

        ChatStore.instance.clearUnread(id);
      }
    } catch (_) {
      // A receipt that does not land is a cosmetic loss on the other
      // person's screen, and the next open will send it again. Never worth
      // interrupting the reader for.
    }
  }

  /*
  |----------------------------------------------------------------------------
  | Internals
  |----------------------------------------------------------------------------
  */

  /*
  |----------------------------------------------------------------------------
  | Realtime
  |----------------------------------------------------------------------------
  */

  /// Handle a frame on this conversation's channel.
  ///
  /// Subscribed for exactly as long as the screen is open, which is what
  /// keeps one thread's traffic out of every other screen: a conversation
  /// nobody is looking at has no subscription to deliver anything to.
  void _onRealtime(String event, Map<String, dynamic> data) {
    /*
     | Re-subscribing *is* the reconnect signal.
     |
     | This fires once when the screen opens and again after every reconnect,
     | which is exactly when a gap needs filling. No separate connection
     | listener, no reconnect callback to wire up and forget — the frame that
     | says "you are back on this channel" is the frame that triggers the
     | catch-up.
     |
     | Without it, a socket that drops and recovers while the app is in the
     | foreground silently loses everything sent in between. The app-resume
     | path does not cover this: nobody backgrounded anything.
     */
    if (event == 'subscription_succeeded') {
      if (!_loading) unawaited(refresh());

      return;
    }

    if (event == 'conversation.closed') {
      _closed = true;

      _rebuild();

      return;
    }

    if (event == 'receipts.updated') {
      _applyReceipts(data);

      return;
    }

    if (event == 'message.reacted') {
      _applyReactions(data);

      return;
    }

    if (event == 'conversation.pinned') {
      // A pin is shared, so both banners move together. Null clears it.
      final pinned = data['pinned_message'];

      _conversation = _conversation?.copyWith(
        pinnedMessage: pinned is Map<String, dynamic>
            ? ChatMessage.fromJson(pinned, _meId)
            : null,
        clearPin: pinned == null,
      );

      _rebuild();

      return;
    }

    if (event != 'message.sent') return;

    final message = ChatMessage.fromJson(data, _meId)
        .copyWith(state: DeliveryState.sent);

    // Ignore anything without a sequence number — it cannot be placed.
    if (message.seq <= 0) return;

    // Our own echo comes back too. It is keyed on the same client id as the
    // optimistic bubble already on screen, so this resolves to that bubble
    // rather than adding a second one. Broadcasting to everyone and letting
    // the client key on client_uuid is what makes multi-device support a
    // change of mind rather than a rewrite.
    _pending.removeWhere((p) => p.id == message.id);
    _upsert(message);

    // A message ends whatever they were typing.
    if (!message.isMine) _clearTyping();

    // The screen is open, so anything arriving on it has been seen.
    if (!message.isMine) unawaited(_markRead());

    _rebuild();
  }

  /// Somebody reacted. The payload carries the whole set for that message,
  /// not a delta — two people reacting at once would otherwise leave the two
  /// screens disagreeing with no way to notice.
  void _applyReactions(Map<String, dynamic> data) {
    final messageId = data['message_id'] as String?;

    if (messageId == null) return;

    final index = _sent.indexWhere((m) => m.remoteId == messageId);

    if (index < 0) return;

    _sent[index] = _sent[index].copyWith(
      reactions: (data['reactions'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(Reaction.fromJson)
          .toList(),
    );

    _rebuild();
  }

  /// Their watermarks moved: repaint every tick at or below them.
  void _applyReceipts(Map<String, dynamic> data) {
    final other = _conversation?.other;

    if (other == null) return;

    // Our own receipts come back on this channel too. Applying them would
    // overwrite their watermarks with ours and turn every tick blue.
    if (data['user_id'] != other.id) return;

    final read = data['last_read_seq'] as int? ?? 0;
    final delivered = data['last_delivered_seq'] as int? ?? 0;

    // Applied as a maximum, never a replacement. Two receipt jobs can finish
    // out of order, and a lower value landing last would walk the ticks
    // backwards — which reads as the other person un-reading your message.
    _conversation = _conversation!.copyWith(
      other: other.copyWith(
        lastReadSeq: read > other.lastReadSeq ? read : other.lastReadSeq,
        lastDeliveredSeq: delivered > other.lastDeliveredSeq
            ? delivered
            : other.lastDeliveredSeq,
      ),
    );

    _rebuild();
  }

  /*
  |----------------------------------------------------------------------------
  | Presence and typing
  |----------------------------------------------------------------------------
  */

  /// Frames on the presence channel: who is here, and who is typing.
  void _onRoom(String event, Map<String, dynamic> data) {
    switch (event) {
      case 'subscription_succeeded':
        // Carries everyone already in the room, so a screen opened second
        // knows immediately rather than waiting for the other person to move.
        final presence = data['presence'] as Map<String, dynamic>?;
        final ids = (presence?['ids'] as List<dynamic>? ?? const [])
            .map((id) => '$id');

        _peerInRoom = ids.any((id) => id != _meId);
        break;

      case 'member_added':
        if (_memberId(data) != _meId) _peerInRoom = true;
        break;

      case 'member_removed':
        if (_memberId(data) == _meId) return;

        _peerInRoom = false;

        // Somebody who closed the screen is not still typing on it.
        _typingExpiry?.cancel();
        _peerTyping = false;
        break;

      case 'client-typing':
        _peerTyping = data['state'] == 'typing';

        _typingExpiry?.cancel();

        if (_peerTyping) {
          _typingExpiry = Timer(
            const Duration(seconds: 4),
            _clearTyping,
          );
        }
        break;

      default:
        return;
    }

    _rebuild();
  }

  String? _memberId(Map<String, dynamic> data) {
    final id = data['user_id'];

    return id == null ? null : '$id';
  }

  /// Call on every keystroke. Sends at most one frame every two seconds.
  ///
  /// A whisper, not a request: Reverb relays it straight to the other
  /// subscriber without waking PHP or touching the database. Routing this
  /// through HTTP would cost several requests per second per typing user,
  /// for information that is worthless one second later.
  void noteTyping() {
    final id = conversationId;

    if (id == null) return;

    final now = DateTime.now();
    final last = _typingSentAt;

    if (last == null || now.difference(last) > const Duration(seconds: 2)) {
      _typingSentAt = now;
      RealtimeClient.instance.whisperTyping(id, typing: true);
    }

    // Three seconds after the last keystroke, say so. The receiver expires it
    // at four regardless, so this only makes the indicator disappear sooner
    // than it otherwise would.
    _typingIdle?.cancel();
    _typingIdle = Timer(const Duration(seconds: 3), _sendStoppedTyping);
  }

  void _sendStoppedTyping() {
    final id = conversationId;

    _typingIdle?.cancel();
    _typingIdle = null;
    _typingSentAt = null;

    if (id == null) return;

    RealtimeClient.instance.whisperTyping(id, typing: false);
  }

  void _clearTyping() {
    _typingExpiry?.cancel();
    _typingExpiry = null;

    if (!_peerTyping) return;

    _peerTyping = false;

    _rebuild();
  }

  /// Insert or replace by sequence number, keeping the list ordered.
  ///
  /// Ordered by seq rather than by arrival: a message that overtakes another
  /// on the way in still lands where the server put it.
  void _upsert(ChatMessage message) {
    final existing = _sent.indexWhere((m) => m.seq == message.seq);

    if (existing >= 0) {
      _sent[existing] = message;

      return;
    }

    var at = _sent.length;

    while (at > 0 && _sent[at - 1].seq > message.seq) {
      at--;
    }

    _sent.insert(at, message);
  }

  /// Resolve every tick from the other person's two watermarks, then notify.
  void _rebuild() {
    final other = _conversation?.other;
    final read = other?.lastReadSeq ?? 0;
    final delivered = other?.lastDeliveredSeq ?? 0;

    _view = [
      for (final message in _sent)
        message.resolve(theirRead: read, theirDelivered: delivered),
      ..._pending,
    ];

    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;

    _typingExpiry?.cancel();
    _typingIdle?.cancel();

    final id = conversationId;

    if (id != null) {
      // Tell them we stopped before the channel goes away — leaving is
      // reported by presence, but the typing indicator would otherwise sit
      // there until its own expiry.
      RealtimeClient.instance.whisperTyping(id, typing: false);

      unawaited(RealtimeClient.instance.leaveConversation(id));
      unawaited(RealtimeClient.instance.leaveRoom(id));
    }

    _api.dispose();
    super.dispose();
  }
}
