import 'package:flutter/foundation.dart';

/// How far a message has got.
///
/// Ordered deliberately: every later state implies the ones before it, so a
/// tick row can be drawn from a single comparison rather than a switch.
enum DeliveryState { sending, sent, delivered, read, failed }

/// One message in a conversation.
///
/// Shaped for the API that will replace the placeholder data — ids, an author
/// flag and a delivery state are all things the server will own, so screens
/// built against this model will not need rewriting when it does.
@immutable
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.body,
    required this.sentAt,
    required this.isMine,
    this.state = DeliveryState.read,
  });

  final String id;
  final String body;
  final DateTime sentAt;

  /// Whether the signed-in user wrote it. Decides which side it sits on and
  /// whether ticks are drawn at all — you never see delivery state on
  /// somebody else's message.
  final bool isMine;

  final DeliveryState state;

  /// "7:29 PM", in the device's own timezone.
  String get timeLabel {
    final at = sentAt.toLocal();
    final hour = at.hour % 12 == 0 ? 12 : at.hour % 12;
    final minute = at.minute.toString().padLeft(2, '0');

    return '$hour:$minute ${at.hour < 12 ? 'AM' : 'PM'}';
  }

  ChatMessage copyWith({DeliveryState? state}) => ChatMessage(
        id: id,
        body: body,
        sentAt: sentAt,
        isMine: isMine,
        state: state ?? this.state,
      );
}

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
