import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../data/chat_models.dart';

/// One run of messages from the same person.
///
/// The timestamp and the delivery ticks appear once, on the last bubble of the
/// run. Repeating them under every line turns a conversation into a table.
class MessageGroupView extends StatelessWidget {
  const MessageGroupView({super.key, required this.group});

  final MessageGroup group;

  @override
  Widget build(BuildContext context) {
    final mine = group.isMine;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment:
            mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < group.messages.length; i++)
            Padding(
              padding: EdgeInsets.only(
                bottom: i == group.messages.length - 1 ? 0 : 3,
              ),
              child: _Bubble(
                message: group.messages[i],
                first: i == 0,
                last: i == group.messages.length - 1,
              ),
            ),
          const SizedBox(height: 5),
          _Meta(message: group.last, mine: mine),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.message,
    required this.first,
    required this.last,
  });

  final ChatMessage message;
  final bool first;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final mine = message.isMine;

    // The corner nearest the sender stays tight through a run and only opens
    // up on the last bubble, so a group reads as one shape rather than a
    // column of separate pills.
    const round = Radius.circular(18);
    const tight = Radius.circular(6);

    final radius = BorderRadius.only(
      topLeft: mine ? round : (first ? round : tight),
      topRight: mine ? (first ? round : tight) : round,
      bottomLeft: mine ? round : (last ? round : tight),
      bottomRight: mine ? (last ? round : tight) : round,
    );

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        // Wide enough for a paragraph, short enough that a one-word reply
        // does not stretch across the screen and lose its shape.
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.78,
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: radius,
            gradient: mine ? AppColors.safeGradient : null,
            color: mine ? null : Colors.white.withValues(alpha: 0.07),
            border: mine
                ? null
                : Border.all(color: Colors.white.withValues(alpha: 0.09)),
          ),
          child: Text(
            message.body,
            style: TextStyle(
              fontSize: 14,
              height: 1.38,
              // Dark ink on the bright gradient; light on the glass. Reversing
              // these is the fastest way to make a chat unreadable.
              color: mine ? const Color(0xFF04121F) : AppColors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

/// Time, and delivery state on your own messages.
class _Meta extends StatelessWidget {
  const _Meta({required this.message, required this.mine});

  final ChatMessage message;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: mine ? 0 : 6, right: mine ? 6 : 0),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            message.timeLabel,
            style: TextStyle(
              fontSize: 10.5,
              color: AppColors.textMuted.withValues(alpha: 0.85),
            ),
          ),
          if (mine) ...[
            const SizedBox(width: 5),
            _Ticks(state: message.state),
          ],
        ],
      ),
    );
  }
}

/// Sending, sent, delivered, read — or failed.
///
/// Two overlapping ticks rather than an icon per state, so the shape stays
/// constant and only the colour changes. A glyph that changes outline on every
/// state makes the whole column twitch as messages land.
class _Ticks extends StatelessWidget {
  const _Ticks({required this.state});

  final DeliveryState state;

  @override
  Widget build(BuildContext context) {
    if (state == DeliveryState.sending) {
      return SizedBox(
        width: 11,
        height: 11,
        child: CircularProgressIndicator(
          strokeWidth: 1.3,
          valueColor:
              AlwaysStoppedAnimation(AppColors.textMuted.withValues(alpha: 0.7)),
        ),
      );
    }

    if (state == DeliveryState.failed) {
      return const Icon(Icons.error_outline_rounded,
          size: 13, color: AppColors.alertRed);
    }

    final read = state == DeliveryState.read;
    final colour = read
        ? AppColors.aqua
        : AppColors.textMuted.withValues(alpha: 0.85);

    return SizedBox(
      width: state == DeliveryState.sent ? 12 : 16,
      height: 11,
      child: Stack(
        children: [
          Icon(Icons.check_rounded, size: 11, color: colour),
          if (state != DeliveryState.sent)
            Positioned(
              left: 5,
              child: Icon(Icons.check_rounded, size: 11, color: colour),
            ),
        ],
      ),
    );
  }
}

/// "Today" / "Yesterday" between runs of messages.
class ChatDateChip extends StatelessWidget {
  const ChatDateChip({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: Colors.white.withValues(alpha: 0.06),
            border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
          ),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}

/// Three dots, for when the other person is typing.
class TypingBubble extends StatefulWidget {
  const TypingBubble({super.key});

  @override
  State<TypingBubble> createState() => _TypingBubbleState();
}

class _TypingBubbleState extends State<TypingBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(18),
            topRight: Radius.circular(18),
            bottomRight: Radius.circular(18),
            bottomLeft: Radius.circular(6),
          ),
          color: Colors.white.withValues(alpha: 0.07),
          border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
        ),
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < 3; i++) ...[
                if (i > 0) const SizedBox(width: 4),
                Opacity(
                  // Staggered thirds, so the dots ripple rather than blink
                  // together.
                  opacity: 0.35 +
                      0.65 *
                          ((((_c.value + i / 3) % 1.0) < 0.5)
                              ? ((_c.value + i / 3) % 1.0) * 2
                              : (1 - ((_c.value + i / 3) % 1.0)) * 2),
                  child: Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.textMuted,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
