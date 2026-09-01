import 'dart:math';

import 'package:flutter/foundation.dart';

/// How far a message has got.
///
/// Ordered deliberately: every later state implies the ones before it, so a
/// tick row can be drawn from a single comparison rather than a switch.
enum DeliveryState { sending, sent, delivered, read, failed }

/// A v4 identifier, generated on the device before a message has a server id.
///
/// Hand-rolled rather than pulling in a package for eleven lines. It is what
/// makes sending idempotent: a request that times out is retried with the
/// same id, and the server returns the original message instead of creating
/// a second one.
String newClientId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));

  bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
  bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant 1

  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).toList();

  return '${hex.sublist(0, 4).join()}-${hex.sublist(4, 6).join()}-'
      '${hex.sublist(6, 8).join()}-${hex.sublist(8, 10).join()}-'
      '${hex.sublist(10).join()}';
}

/// What a message carries.
class MessageType {
  const MessageType._();

  static const String text = 'text';
  static const String image = 'image';
  static const String file = 'file';
  static const String audio = 'audio';
  static const String system = 'system';
}

/// A file hanging off a message.
@immutable
class Attachment {
  const Attachment({
    required this.id,
    required this.mime,
    this.name,
    this.sizeBytes = 0,
    this.width,
    this.height,
    this.url,
  });

  final String id;
  final String mime;

  /// The name the sender's device gave it. What a document bubble shows.
  final String? name;

  final int sizeBytes;

  /// Recorded at upload so a bubble can reserve the right box before the
  /// bytes arrive — without it every image pops the list as it loads.
  final int? width;
  final int? height;

  /// A signed, expiring link. Null only if the server declined to issue one.
  final String? url;

  bool get isImage => mime.startsWith('image/');

  /// Width over height, or 1 when the server did not record them.
  double get aspect {
    final w = width;
    final h = height;

    if (w == null || h == null || w <= 0 || h <= 0) return 1;

    // Clamped so a panorama or a very tall screenshot still fits a bubble
    // rather than taking over the whole conversation.
    return (w / h).clamp(0.6, 1.9);
  }

  String get sizeLabel {
    if (sizeBytes >= 1048576) {
      return '${(sizeBytes / 1048576).toStringAsFixed(1)} MB';
    }

    if (sizeBytes >= 1024) return '${(sizeBytes / 1024).round()} KB';

    return '$sizeBytes B';
  }

  factory Attachment.fromJson(Map<String, dynamic> json) => Attachment(
        id: json['id'] as String? ?? '',
        mime: json['mime'] as String? ?? 'application/octet-stream',
        name: json['name'] as String?,
        sizeBytes: json['size_bytes'] as int? ?? 0,
        width: json['width'] as int?,
        height: json['height'] as int?,
        url: json['url'] as String?,
      );
}

/// One emoji on a message, and who put it there.
@immutable
class Reaction {
  const Reaction({
    required this.emoji,
    required this.count,
    required this.userIds,
  });

  final String emoji;
  final int count;

  /// Public ids of everyone who reacted with this emoji.
  ///
  /// Sent instead of a `mine` flag so one payload serves both people — the
  /// client works out which reaction is its own. A per-viewer payload would
  /// mean one broadcast per participant for a fact anybody can derive.
  final List<String> userIds;

  bool mine(String meId) => userIds.contains(meId);

  factory Reaction.fromJson(Map<String, dynamic> json) => Reaction(
        emoji: json['emoji'] as String? ?? '',
        count: json['count'] as int? ?? 0,
        userIds: (json['user_ids'] as List<dynamic>? ?? const [])
            .map((id) => '$id')
            .toList(),
      );
}

/// The emoji the long-press row offers.
///
/// Fixed and short on purpose. Six covers nearly every reaction anybody
/// sends, and a full picker turns a one-tap gesture into a search. Kept in
/// step with ReactionService::QUICK on the server.
const List<String> kQuickReactions = ['👍', '❤️', '😂', '😮', '😢', '🙏'];

/// The message a reply is answering, in the compact form a quote needs.
///
/// Not a full [ChatMessage] on purpose: a quote needs enough to recognise the
/// original and nothing more, and nesting whole messages would let one deep
/// reply chain drag half a conversation onto the wire.
@immutable
class QuotedMessage {
  const QuotedMessage({
    required this.id,
    required this.isMine,
    this.body,
    this.type = MessageType.text,
    this.deleted = false,
  });

  final String id;
  final bool isMine;
  final String? body;
  final String type;
  final bool deleted;

  /// One line describing what was quoted.
  String get preview {
    if (deleted) return 'Message deleted';

    final text = body ?? '';

    if (text.isNotEmpty) return text;

    return switch (type) {
      MessageType.image => 'Photo',
      MessageType.file => 'File',
      MessageType.audio => 'Voice message',
      _ => '',
    };
  }

  factory QuotedMessage.fromJson(Map<String, dynamic> json, String meId) =>
      QuotedMessage(
        id: json['id'] as String? ?? '',
        isMine: json['sender_id'] == meId,
        body: json['body'] as String?,
        type: json['type'] as String? ?? MessageType.text,
        deleted: json['deleted'] as bool? ?? false,
      );
}

/// One message in a conversation.
@immutable
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.body,
    required this.sentAt,
    required this.isMine,
    this.remoteId,
    this.seq = 0,
    this.deleted = false,
    this.state = DeliveryState.sent,
    this.type = MessageType.text,
    this.attachment,
    this.localPath,
    this.replyTo,
    this.reactions = const [],
    this.starred = false,
    this.forwarded = false,
  });

  /// The client-generated id, stable from the moment the message is typed.
  ///
  /// Identity through the whole life of the message, which is why the list
  /// can swap an optimistic bubble for the saved one without flicker: it is
  /// the same row, not a removal and an insert.
  final String id;

  /// The server's uuid. Null until the send comes back.
  final String? remoteId;

  /// Position in the thread, starting at 1. Zero while still unsent.
  ///
  /// Also the sort key. Arrival order is never trusted — a message that
  /// overtakes another on the way in still lands in the right place.
  final int seq;

  final String body;
  final DateTime sentAt;

  /// Whether the signed-in user wrote it. Decides which side it sits on and
  /// whether ticks are drawn at all — you never see delivery state on
  /// somebody else's message.
  final bool isMine;

  /// Deleted for everyone. The row survives so the bubble can say so, rather
  /// than a line vanishing out of the middle of the conversation.
  final bool deleted;

  /// Resolved by [ConversationStore] from the other person's watermarks
  /// rather than stored per message — see [resolve].
  final DeliveryState state;

  /// text | image | file | audio | system.
  final String type;

  final Attachment? attachment;

  /// What this message is answering, if anything.
  final QuotedMessage? replyTo;

  /// Emoji on this message, most-reacted first.
  final List<Reaction> reactions;

  /// Whether *you* kept it. Private — the other person cannot tell.
  final bool starred;

  /// Whether it arrived here from another conversation. A flag, not a
  /// pointer: the label only needs to say so, and recording where it came
  /// from would leak a thread the reader is not in.
  final bool forwarded;

  /// The file on this device, for something we sent ourselves.
  ///
  /// Held so an outgoing photo renders instantly from disk instead of waiting
  /// for the upload and then downloading back the copy we just sent.
  final String? localPath;

  bool get hasMedia =>
      type == MessageType.image ||
      type == MessageType.file ||
      type == MessageType.audio;

  bool get isImage => type == MessageType.image;

  bool get pending => state == DeliveryState.sending;
  bool get failed => state == DeliveryState.failed;

  /// "7:29 PM", in the device's own timezone.
  String get timeLabel {
    final at = sentAt.toLocal();
    final hour = at.hour % 12 == 0 ? 12 : at.hour % 12;
    final minute = at.minute.toString().padLeft(2, '0');

    return '$hour:$minute ${at.hour < 12 ? 'AM' : 'PM'}';
  }

  /// What the ticks should show, given how far the other person has got.
  ///
  /// Two integers decide the state of every bubble in the thread. That is
  /// what makes a whole run turn blue at once when somebody opens the
  /// conversation, instead of rippling upward one tick at a time.
  ChatMessage resolve({required int theirRead, required int theirDelivered}) {
    // Local states are the client's own business and are never overridden by
    // a watermark: a message that failed to send has no delivery state to
    // read off the server, because the server never saw it.
    if (!isMine || pending || failed) return this;


    final resolved = theirRead >= seq
        ? DeliveryState.read
        : theirDelivered >= seq
            ? DeliveryState.delivered
            : DeliveryState.sent;

    return resolved == state ? this : copyWith(state: resolved);
  }

  factory ChatMessage.fromJson(Map<String, dynamic> json, String meId) {
    final deleted = json['deleted'] as bool? ?? false;

    return ChatMessage(
      // Falls back to the server uuid for anything this device did not send,
      // which has no client id of its own.
      id: json['client_id'] as String? ?? json['id'] as String,
      remoteId: json['id'] as String?,
      seq: json['seq'] as int? ?? 0,
      // The server never sends the body of a deleted message again, so the
      // tombstone text is written here rather than left as an empty bubble
      // the reader has to interpret.
      body: deleted
          ? 'This message was deleted'
          : json['body'] as String? ?? '',
      sentAt: DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.now(),
      isMine: json['sender_id'] == meId,
      deleted: deleted,
      type: deleted
          ? MessageType.text
          : json['type'] as String? ?? MessageType.text,
      attachment: json['attachment'] is Map<String, dynamic>
          ? Attachment.fromJson(json['attachment'] as Map<String, dynamic>)
          : null,
      replyTo: json['reply_to'] is Map<String, dynamic>
          ? QuotedMessage.fromJson(
              json['reply_to'] as Map<String, dynamic>, meId)
          : null,
      reactions: (json['reactions'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(Reaction.fromJson)
          .toList(),
      starred: json['starred'] as bool? ?? false,
      forwarded: json['forwarded'] as bool? ?? false,
    );
  }

  ChatMessage copyWith({
    String? remoteId,
    int? seq,
    DeliveryState? state,
    bool? deleted,
    Attachment? attachment,
    String? localPath,
    QuotedMessage? replyTo,
    List<Reaction>? reactions,
    bool? starred,
  }) =>
      ChatMessage(
        id: id,
        remoteId: remoteId ?? this.remoteId,
        seq: seq ?? this.seq,
        body: body,
        sentAt: sentAt,
        isMine: isMine,
        deleted: deleted ?? this.deleted,
        state: state ?? this.state,
        type: type,
        attachment: attachment ?? this.attachment,
        // Kept through every copy: once the server round trip completes we
        // still want to render our own photo from disk rather than fetch it
        // back over the network.
        localPath: localPath ?? this.localPath,
        replyTo: replyTo ?? this.replyTo,
        reactions: reactions ?? this.reactions,
        starred: starred ?? this.starred,
        forwarded: forwarded,
      );
}

/// The other person in a thread, and what may be known about their presence.
@immutable
class ChatPerson {
  const ChatPerson({
    required this.id,
    required this.name,
    this.username,
    this.avatarUrl,
    this.isPrivate = false,
    this.state = 'accepted',
    this.lastReadSeq = 0,
    this.lastDeliveredSeq = 0,
    this.online,
    this.lastSeenAt,
  });

  final String id;
  final String name;
  final String? username;
  final String? avatarUrl;
  final bool isPrivate;

  /// Their side of the thread. `pending` means they have not accepted the
  /// request yet, which is why the composer warns before a fourth message.
  final String state;

  /// How far they have got. The two numbers every tick in the thread is
  /// drawn from.
  final int lastReadSeq;
  final int lastDeliveredSeq;

  /// Null when the account hides it — not false, which would be a claim the
  /// server never made.
  final bool? online;
  final DateTime? lastSeenAt;

  bool get hasAccepted => state == 'accepted';

  /// Up to two initials, for the avatar fallback.
  String get initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);

    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();

    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  /// "Online", "Last seen 2h ago" — or null, which hides the line.
  String? get presenceLabel {
    if (online == true) return 'Online';

    final at = lastSeenAt?.toLocal();

    if (at == null) return null;

    final since = DateTime.now().difference(at);

    if (since.inMinutes < 2) return 'Active just now';
    if (since.inMinutes < 60) return 'Last seen ${since.inMinutes}m ago';
    if (since.inHours < 24) return 'Last seen ${since.inHours}h ago';
    if (since.inDays < 7) return 'Last seen ${since.inDays}d ago';

    return 'Last seen a while ago';
  }

  ChatPerson copyWith({
    String? state,
    int? lastReadSeq,
    int? lastDeliveredSeq,
    bool? online,
    DateTime? lastSeenAt,
  }) =>
      ChatPerson(
        id: id,
        name: name,
        username: username,
        avatarUrl: avatarUrl,
        isPrivate: isPrivate,
        state: state ?? this.state,
        lastReadSeq: lastReadSeq ?? this.lastReadSeq,
        lastDeliveredSeq: lastDeliveredSeq ?? this.lastDeliveredSeq,
        online: online ?? this.online,
        lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      );

  factory ChatPerson.fromJson(Map<String, dynamic> json) {
    return ChatPerson(
      id: json['user_id'] as String? ?? '',
      name: json['name'] as String? ?? 'Someone',
      username: json['username'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      isPrivate: json['is_private'] as bool? ?? false,
      state: json['state'] as String? ?? 'accepted',
      lastReadSeq: json['last_read_seq'] as int? ?? 0,
      lastDeliveredSeq: json['last_delivered_seq'] as int? ?? 0,
      online: json['online'] as bool?,
      lastSeenAt: DateTime.tryParse(json['last_seen_at'] as String? ?? ''),
    );
  }
}

/// A thread, as the inbox and the chat header need it.
@immutable
class Conversation {
  const Conversation({
    required this.id,
    required this.other,
    this.state = 'accepted',
    this.unreadCount = 0,
    this.muted = false,
    this.blocked = false,
    this.lastMessage,
    this.lastMessageAt,
    this.myReadSeq = 0,
    this.myDeliveredSeq = 0,
    this.pinnedMessage,
    this.pinned = false,
    this.markedUnread = false,
    this.archived = false,
  });

  final String id;

  /// Null only for a malformed thread — every direct conversation has two
  /// people in it by definition.
  final ChatPerson? other;

  /// My side of it: `pending` puts the thread in the Requests tab.
  final String state;

  final int unreadCount;
  final bool muted;

  /// A wall stands between the two of you, in one direction or the other.
  ///
  /// Deliberately not "blocked by me": somebody who has been blocked must not
  /// be able to tell the difference between that and the other account having
  /// simply gone quiet.
  final bool blocked;

  final ChatMessage? lastMessage;
  final DateTime? lastMessageAt;

  /// Shared by both people, unlike a star — either can set or clear it and
  /// both banners move together.
  final ChatMessage? pinnedMessage;

  /// Held at the top of *my* inbox. Mine alone: it says nothing about where
  /// this thread sits in theirs, unlike [pinnedMessage].
  final bool pinned;

  /// "I have read this but I want it to look unread." A flag of my own —
  /// the read watermark never moves backwards, so their ticks stay put.
  final bool markedUnread;

  /// Put away in the Archived list. Not deleted and not muted: every message
  /// is still there and it still notifies — it is only somewhere else.
  final bool archived;

  final int myReadSeq;
  final int myDeliveredSeq;

  bool get isRequest => state == 'pending';

  /// Either genuinely unread, or marked so on purpose. The row cannot tell
  /// the difference and should not try to — both mean "come back to this".
  bool get hasUnread => unreadCount > 0 || markedUnread;

  /// One line of preview for the inbox row.
  String get preview {
    final message = lastMessage;

    if (message == null) return 'Say hello';
    if (message.deleted) return 'Message deleted';

    // A caption if there is one, otherwise the kind of thing it is. An inbox
    // row showing an empty string because somebody sent a photo without a
    // caption reads as a bug.
    final text = message.body.isNotEmpty
        ? message.body
        : switch (message.type) {
            MessageType.image => 'Photo',
            MessageType.file => message.attachment?.name ?? 'File',
            MessageType.audio => 'Voice message',
            _ => '',
          };

    return message.isMine ? 'You: $text' : text;
  }

  factory Conversation.fromJson(Map<String, dynamic> json, String meId) {
    final me = json['me'] as Map<String, dynamic>? ?? const {};
    final other = json['other'] as Map<String, dynamic>?;
    final last = json['last_message'] as Map<String, dynamic>?;

    return Conversation(
      id: json['id'] as String? ?? '',
      other: other == null ? null : ChatPerson.fromJson(other),
      state: json['state'] as String? ?? 'accepted',
      unreadCount: json['unread_count'] as int? ?? 0,
      muted: json['muted'] as bool? ?? false,
      blocked: json['blocked'] as bool? ?? false,
      lastMessage: last == null ? null : ChatMessage.fromJson(last, meId),
      lastMessageAt:
          DateTime.tryParse(json['last_message_at'] as String? ?? ''),
      myReadSeq: me['last_read_seq'] as int? ?? 0,
      myDeliveredSeq: me['last_delivered_seq'] as int? ?? 0,
      pinnedMessage: json['pinned_message'] is Map<String, dynamic>
          ? ChatMessage.fromJson(
              json['pinned_message'] as Map<String, dynamic>, meId)
          : null,
      pinned: json['pinned'] as bool? ?? false,
      markedUnread: json['marked_unread'] as bool? ?? false,
      archived: json['archived'] as bool? ?? false,
    );
  }

  Conversation copyWith({
    ChatPerson? other,
    String? state,
    int? unreadCount,
    bool? blocked,
    bool? muted,
    bool? pinned,
    bool? markedUnread,
    bool? archived,
    ChatMessage? lastMessage,
    DateTime? lastMessageAt,
    int? myReadSeq,
    ChatMessage? pinnedMessage,
    bool clearPin = false,
    bool clearLastMessage = false,
  }) =>
      Conversation(
        id: id,
        other: other ?? this.other,
        state: state ?? this.state,
        unreadCount: unreadCount ?? this.unreadCount,
        muted: muted ?? this.muted,
        blocked: blocked ?? this.blocked,
        // Cleared outright when a chat is emptied: the thread stays in the
        // list with nothing left to preview.
        lastMessage: clearLastMessage ? null : (lastMessage ?? this.lastMessage),
        lastMessageAt: lastMessageAt ?? this.lastMessageAt,
        myReadSeq: myReadSeq ?? this.myReadSeq,
        myDeliveredSeq: myDeliveredSeq,
        // An explicit flag, because null means "unchanged" everywhere else
        // in this method and unpinning has to be expressible.
        pinnedMessage: clearPin ? null : (pinnedMessage ?? this.pinnedMessage),
        pinned: pinned ?? this.pinned,
        markedUnread: markedUnread ?? this.markedUnread,
        archived: archived ?? this.archived,
      );

  /// "19:04", "Yesterday", "12 Aug" — the right-hand column of an inbox row.
  String get timeLabel {
    final at = lastMessageAt?.toLocal();

    if (at == null) return '';

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final that = DateTime(at.year, at.month, at.day);
    final days = today.difference(that).inDays;

    if (days == 0) {
      final hour = at.hour % 12 == 0 ? 12 : at.hour % 12;

      return '$hour:${at.minute.toString().padLeft(2, '0')} '
          '${at.hour < 12 ? 'AM' : 'PM'}';
    }

    if (days == 1) return 'Yesterday';
    if (days < 7) return '${days}d';

    return '${at.day} ${_shortMonths[at.month - 1]}';
  }
}

const _shortMonths = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// A run of messages from the same person, close together in time.
///
/// Grouping is what stops a conversation reading as a stack of identical
/// cards: the avatar and the timestamp appear once per run rather than once
/// per message, so the eye follows the exchange instead of the furniture.
@immutable
class MessageGroup {
  const MessageGroup({required this.messages});

  final List<ChatMessage> messages;

  bool get isMine => messages.first.isMine;
  ChatMessage get last => messages.last;

  /// Consecutive messages from one sender within this window are one group.
  static const Duration window = Duration(minutes: 5);

  /// Split a chronological list into groups, inserting nothing — callers add
  /// date separators themselves, because those belong to the list, not to a
  /// group.
  static List<MessageGroup> from(List<ChatMessage> messages) {
    final groups = <MessageGroup>[];
    var current = <ChatMessage>[];

    for (final message in messages) {
      if (current.isEmpty) {
        current.add(message);
        continue;
      }

      final previous = current.last;
      final sameSender = previous.isMine == message.isMine;
      final closeInTime =
          message.sentAt.difference(previous.sentAt).abs() <= window;
      final sameDay = _sameDay(previous.sentAt, message.sentAt);

      if (sameSender && closeInTime && sameDay) {
        current.add(message);
      } else {
        groups.add(MessageGroup(messages: current));
        current = [message];
      }
    }

    if (current.isNotEmpty) groups.add(MessageGroup(messages: current));

    return groups;
  }

  static bool _sameDay(DateTime a, DateTime b) {
    final x = a.toLocal();
    final y = b.toLocal();

    return x.year == y.year && x.month == y.month && x.day == y.day;
  }
}

/// "Today", "Yesterday", "12 August" — the separator between days.
String chatDateLabel(DateTime date) {
  final local = date.toLocal();
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final that = DateTime(local.year, local.month, local.day);
  final difference = today.difference(that).inDays;

  if (difference == 0) return 'Today';
  if (difference == 1) return 'Yesterday';

  const months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  final month = months[local.month - 1];

  return difference < 365
      ? '${local.day} $month'
      : '${local.day} $month ${local.year}';
}
