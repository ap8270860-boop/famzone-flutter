import 'dart:convert';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_response.dart';

/// Conversations, messages, receipts and presence.
class ChatApi {
  ChatApi({ApiClient? client}) : _api = client ?? ApiClient();

  final ApiClient _api;

  // --- Conversations -----------------------------------------------------

  /// The inbox. `state: 'pending'` is the Requests tab, `archived: true` the
  /// Archived screen — the same list filtered the other way, rather than a
  /// second endpoint whose rules would drift from this one's.
  Future<ApiResponse> conversations({
    String state = 'accepted',
    int page = 1,
    bool archived = false,
  }) =>
      _api.get(
        'conversations?state=$state&page=$page${archived ? '&archived=1' : ''}',
      );

  /// Badge counts, cheap enough to call on every foreground.
  Future<ApiResponse> unreadCount() => _api.get('conversations/unread-count');

  /// Open the thread with somebody, creating it only if there is not one.
  ///
  /// Safe to call every time the Message button is tapped — the server keys
  /// direct threads on the pair, so a second call returns the first one.
  Future<ApiResponse> startWith(String userId) =>
      _api.post('conversations', body: {'user_id': userId});

  Future<ApiResponse> conversation(String conversationId) =>
      _api.get('conversations/$conversationId');

  Future<ApiResponse> accept(String conversationId) =>
      _api.post('conversations/$conversationId/accept');

  /// Leave the thread, or decline a request.
  Future<ApiResponse> leave(String conversationId) =>
      _api.delete('conversations/$conversationId');

  // --- My own view of a thread -------------------------------------------
  //
  // None of these are broadcast and none are visible to the other person.
  // Each writes a column on my own participant row.

  /// Hold the chat at the top of my inbox, or let it go. Toggles.
  ///
  /// `pin-chat`, deliberately not `pin` — that one is the shared pinned
  /// message inside the thread, which is a different feature entirely.
  Future<ApiResponse> pinChat(String conversationId) =>
      _api.post('conversations/$conversationId/pin-chat');

  /// Put it away, or bring it back. Toggles.
  Future<ApiResponse> archiveChat(String conversationId) =>
      _api.post('conversations/$conversationId/archive');

  /// Silence it. [hours] of null means indefinitely.
  Future<ApiResponse> mute(
    String conversationId, {
    required bool muted,
    int? hours,
  }) =>
      _api.post('conversations/$conversationId/mute', body: {
        'muted': muted,
        if (hours != null) 'hours': hours,
      });

  /// Make it look unread again. Cleared the next time it is actually read.
  Future<ApiResponse> markUnread(String conversationId) =>
      _api.post('conversations/$conversationId/unread');

  /// Empty it on my side. The thread stays; the other person keeps
  /// everything.
  Future<ApiResponse> clearChat(String conversationId) =>
      _api.post('conversations/$conversationId/clear');

  // --- Messages ----------------------------------------------------------

  /// Scrollback and gap-filling.
  ///
  /// [before] walks back through history as the user scrolls up. [after]
  /// fetches everything since a sequence number the client already holds,
  /// which is how a screen recovers whatever it missed while the app was in
  /// the background — and, from the next phase, while the socket was down.
  Future<ApiResponse> messages(
    String conversationId, {
    int? before,
    int? after,
    int limit = 40,
  }) {
    final query = <String>[
      'limit=$limit',
      if (before != null) 'before=$before',
      if (after != null) 'after=$after',
    ];

    return _api.get('conversations/$conversationId/messages?${query.join('&')}');
  }

  /// Step one of sending a file.
  ///
  /// Separate from [send] on purpose: a large file has no business holding a
  /// chat request open, and the message row must not exist before the bytes
  /// do — a message broadcast ahead of its file shows every recipient a
  /// broken attachment.
  Future<ApiResponse> uploadAttachment({
    required String filePath,
    required String type,
    int? durationMs,
    List<int>? waveform,
  }) =>
      _api.upload(
        'uploads',
        field: 'file',
        filePath: filePath,
        fields: {
          'type': type,
          // Voice notes carry their own measurements. Multipart fields are
          // strings, so the waveform travels as JSON and the server decodes
          // it before validating.
          if (durationMs != null) 'duration_ms': '$durationMs',
          if (waveform != null && waveform.isNotEmpty)
            'waveform': jsonEncode(waveform),
        },
      );

  /// Send. [clientId] is what makes a retry safe — the same id twice returns
  /// the first message rather than creating a second one.
  ///
  /// [uploadId] carries a file across from [uploadAttachment]; [body] is the
  /// caption when it does.
  Future<ApiResponse> send(
    String conversationId, {
    required String clientId,
    required String body,
    String type = 'text',
    String? uploadId,
    String? replyToId,
  }) =>
      _api.post('conversations/$conversationId/messages', body: {
        'client_uuid': clientId,
        'type': type,
        if (body.isNotEmpty || type == 'text') 'body': body,
        if (uploadId != null) 'upload_id': uploadId,
        if (replyToId != null) 'reply_to_id': replyToId,
      });

  Future<ApiResponse> deleteMessage(String messageId) =>
      _api.delete('messages/$messageId');

  /// Add, change or remove a reaction.
  ///
  /// One endpoint for all three: a null emoji removes yours, and sending the
  /// same one twice does the same thing. The server keeps one row per person
  /// per message, so there is nothing else it could mean.
  Future<ApiResponse> react(String messageId, String? emoji) =>
      _api.post('messages/$messageId/react', body: {'emoji': emoji});

  /// Delete for me.
  ///
  /// A separate endpoint from [deleteMessage], not a flag on it, because they
  /// are different acts: this hides one person's copy and is allowed on
  /// anybody's message, while deleting for everyone edits the thread itself
  /// and is only ever allowed on your own.
  Future<ApiResponse> hideMessage(String messageId) =>
      _api.post('messages/$messageId/hide');

  /// Star or unstar. Toggles, and is private to the caller — nothing about a
  /// star is broadcast and the other person cannot tell.
  Future<ApiResponse> star(String messageId) =>
      _api.post('messages/$messageId/star');

  Future<ApiResponse> starredMessages({int page = 1}) =>
      _api.get('starred-messages?page=$page');

  /// Send a copy into other conversations. A new message in each, never a
  /// reference to the original.
  Future<ApiResponse> forward(
    String messageId,
    List<String> conversationIds,
  ) =>
      _api.post('messages/$messageId/forward', body: {
        'conversation_ids': conversationIds,
      });

  /// Pin a message in a thread, or pass null to clear it. Shared by both
  /// people, so either can change it.
  Future<ApiResponse> pin(String conversationId, String? messageId) =>
      _api.post('conversations/$conversationId/pin', body: {
        'message_id': messageId,
      });

  // --- Receipts ----------------------------------------------------------

  /// Both move a watermark forward and are no-ops when it is already ahead,
  /// so neither needs to be debounced for correctness — only for politeness.
  Future<ApiResponse> markRead(String conversationId, String messageId) =>
      _api.post('conversations/$conversationId/read',
          body: {'message_id': messageId});

  Future<ApiResponse> markDelivered(String conversationId, String messageId) =>
      _api.post('conversations/$conversationId/delivered',
          body: {'message_id': messageId});

  // --- Presence ----------------------------------------------------------

  Future<ApiResponse> ping() => _api.post('presence/ping');

  void dispose() => _api.dispose();
}
