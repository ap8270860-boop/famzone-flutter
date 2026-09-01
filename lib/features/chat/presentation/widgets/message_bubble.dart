import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/theme/app_colors.dart';
import '../../data/chat_models.dart';
import '../image_viewer.dart';

/// One run of messages from the same person.
///
/// The timestamp and the delivery ticks appear once, on the last bubble of the
/// run. Repeating them under every line turns a conversation into a table.
class MessageGroupView extends StatelessWidget {
  const MessageGroupView({
    super.key,
    required this.group,
    required this.meId,
    this.onLongPress,
    this.onReactionTap,
    this.onQuoteTap,
    this.highlightedId,
  });

  final MessageGroup group;

  /// Needed to tell your own reaction from theirs.
  final String meId;

  /// Tapping a pill toggles that emoji.
  final void Function(ChatMessage message, String emoji)? onReactionTap;

  /// Tapping the quoted strip inside a reply jumps to what it answers.
  final void Function(QuotedMessage quote)? onQuoteTap;

  /// The message the thread has just jumped to, tinted for a moment so the
  /// eye can find it. Landing on a wall of bubbles with no idea which one
  /// was the destination defeats the point of jumping.
  final String? highlightedId;

  /// Long press on one bubble. Carries the global position so the menu can
  /// be anchored to the message rather than to the screen.
  final void Function(ChatMessage message, Offset at)? onLongPress;

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
              // The tint sits on a wrapper whose padding never changes, so
              // highlighting a message fades a colour in and out rather than
              // nudging the whole conversation sideways.
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 240),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  color: highlightedId != null &&
                          group.messages[i].remoteId == highlightedId
                      ? AppColors.aqua.withValues(alpha: 0.17)
                      : Colors.transparent,
                ),
                child: Column(
                  crossAxisAlignment:
                      mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                  children: [
                    _Bubble(
                      message: group.messages[i],
                      first: i == 0,
                      last: i == group.messages.length - 1,
                      onLongPress: onLongPress,
                      onQuoteTap: onQuoteTap,
                    ),
                    if (group.messages[i].reactions.isNotEmpty)
                      ReactionPills(
                        message: group.messages[i],
                        meId: meId,
                        onTap: onReactionTap,
                      ),
                  ],
                ),
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
    this.onLongPress,
    this.onQuoteTap,
  });

  final ChatMessage message;
  final bool first;
  final bool last;
  final void Function(ChatMessage message, Offset at)? onLongPress;
  final void Function(QuotedMessage quote)? onQuoteTap;

  @override
  Widget build(BuildContext context) {
    final handler = onLongPress;

    // Deleted messages stay pressable: the menu narrows itself to Delete, so
    // a tombstone can still be cleared from your own side.
    if (handler == null) return _body(context);

    return GestureDetector(
      // onLongPressStart rather than onLongPress: the details carry the global
      // position, which is what lets the menu open beside the bubble instead
      // of somewhere generic.
      onLongPressStart: (details) => handler(message, details.globalPosition),
      behavior: HitTestBehavior.opaque,
      child: _body(context),
    );
  }

  Widget _body(BuildContext context) {
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

    if (message.isImage) {
      return Align(
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: _ImageBubble(message: message, radius: radius),
      );
    }

    if (message.type == MessageType.file) {
      return Align(
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: _FileBubble(message: message, radius: radius, mine: mine),
      );
    }

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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (message.forwarded) ...[
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.shortcut_rounded,
                      size: 13,
                      color: (mine
                              ? const Color(0xFF04121F)
                              : AppColors.textMuted)
                          .withValues(alpha: 0.7),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Forwarded',
                      style: TextStyle(
                        fontSize: 11,
                        fontStyle: FontStyle.italic,
                        color: (mine
                                ? const Color(0xFF04121F)
                                : AppColors.textMuted)
                            .withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
              ],
              if (message.replyTo != null) ...[
                QuotedStrip(
                  quote: message.replyTo!,
                  onDark: mine,
                  // Tapping the quote jumps to what it answers — the reply
                  // is only half a sentence without the line above it.
                  onTap: onQuoteTap == null
                      ? null
                      : () => onQuoteTap!(message.replyTo!),
                ),
                const SizedBox(height: 7),
              ],
              Text(
                // Never the stored body once deleted. The server already
                // withholds it, and this makes the client incapable of
                // showing it even if a stale copy is lying around.
                message.deleted ? 'This message was deleted' : message.body,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.38,
                  fontStyle:
                      message.deleted ? FontStyle.italic : FontStyle.normal,
                  // Dark ink on the bright gradient; light on the glass.
                  // Reversing these is the fastest way to make a chat
                  // unreadable.
                  color: message.deleted
                      ? (mine
                          ? const Color(0xFF04121F).withValues(alpha: 0.6)
                          : AppColors.textMuted)
                      : (mine
                          ? const Color(0xFF04121F)
                          : AppColors.textPrimary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A photo, with its caption underneath if there is one.
///
/// The image is the bubble rather than sitting inside one — padding around a
/// photo wastes the width that makes it worth looking at. A caption gets a
/// glass strip below it, which also gives the ticks somewhere legible to sit.
class _ImageBubble extends StatelessWidget {
  const _ImageBubble({required this.message, required this.radius});

  final ChatMessage message;
  final BorderRadius radius;

  @override
  Widget build(BuildContext context) {
    final attachment = message.attachment;
    final path = message.localPath;
    final width = MediaQuery.sizeOf(context).width * 0.66;
    final hasCaption = message.body.isNotEmpty;

    return GestureDetector(
      onTap: attachment?.url == null && path == null
          ? null
          : () => openImageViewer(
                context,
                url: attachment?.url,
                localPath: path,
                caption: hasCaption ? message.body : null,
              ),
      child: ClipRRect(
        borderRadius: radius,
        child: Container(
          width: width,
          color: Colors.white.withValues(alpha: 0.07),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              AspectRatio(
                // Reserved from the dimensions the server recorded, so the
                // list does not jump as each image finishes loading.
                aspectRatio: attachment?.aspect ?? 1,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _image(path, attachment?.url),
                    if (message.pending)
                      // Dimmed while it uploads. A spinner alone over a bright
                      // photo is hard to see, and the dimming is what says
                      // "not finished" at a glance.
                      Container(
                        color: Colors.black.withValues(alpha: 0.35),
                        alignment: Alignment.center,
                        child: const SizedBox(
                          width: 26,
                          height: 26,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            valueColor:
                                AlwaysStoppedAnimation(Colors.white),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (hasCaption)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 9, 12, 10),
                  child: Text(
                    message.body,
                    style: const TextStyle(
                      fontSize: 14,
                      height: 1.35,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _image(String? path, String? url) {
    // Our own photo comes off the disk. Downloading back a copy of the file
    // we just uploaded would be slower and cost the user data for nothing.
    if (path != null && File(path).existsSync()) {
      return Image.file(File(path), fit: BoxFit.cover);
    }

    if (url == null) return const _ImagePlaceholder();

    return Image.network(
      url,
      fit: BoxFit.cover,
      loadingBuilder: (context, child, progress) =>
          progress == null ? child : const _ImagePlaceholder(),
      // A signed link that has expired, or a file that has gone. Says so
      // rather than showing Flutter's default broken-image glyph.
      errorBuilder: (context, _, __) => const _ImagePlaceholder(failed: true),
    );
  }
}

/// A document: icon, name, size — and a caption underneath if there is one.
class _FileBubble extends StatelessWidget {
  const _FileBubble({
    required this.message,
    required this.radius,
    required this.mine,
  });

  final ChatMessage message;
  final BorderRadius radius;
  final bool mine;

  /// A glyph per family. Not decoration — it is what makes a list of
  /// attachments scannable without reading every filename.
  IconData get _icon {
    final name = (message.attachment?.name ?? '').toLowerCase();

    if (name.endsWith('.pdf')) return Icons.picture_as_pdf_rounded;
    if (RegExp(r'\.(doc|docx|rtf|txt)$').hasMatch(name)) {
      return Icons.article_rounded;
    }
    if (RegExp(r'\.(xls|xlsx|csv)$').hasMatch(name)) {
      return Icons.table_chart_rounded;
    }
    if (RegExp(r'\.(zip|rar|7z|tar|gz)$').hasMatch(name)) {
      return Icons.folder_zip_rounded;
    }
    if (RegExp(r'\.(mp3|m4a|wav|aac)$').hasMatch(name)) {
      return Icons.audiotrack_rounded;
    }
    if (RegExp(r'\.(mp4|mov|mkv|avi)$').hasMatch(name)) {
      return Icons.movie_rounded;
    }

    return Icons.insert_drive_file_rounded;
  }

  Future<void> _open() async {
    final url = message.attachment?.url;

    if (url == null) return;

    // Handed to the OS rather than rendered in-app. A chat should not try to
    // be a document viewer, and every phone already has better ones.
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final attachment = message.attachment;
    final hasCaption = message.body.isNotEmpty;
    final ink = mine ? const Color(0xFF04121F) : AppColors.textPrimary;

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width * 0.78,
      ),
      child: GestureDetector(
        onTap: message.pending || attachment?.url == null ? null : _open,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 11, 14, 11),
          decoration: BoxDecoration(
            borderRadius: radius,
            gradient: mine ? AppColors.safeGradient : null,
            color: mine ? null : Colors.white.withValues(alpha: 0.07),
            border: mine
                ? null
                : Border.all(color: Colors.white.withValues(alpha: 0.09)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 38,
                    height: 38,
                    child: message.pending
                        ? Center(
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation(
                                  ink.withValues(alpha: 0.7),
                                ),
                              ),
                            ),
                          )
                        : Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              color: ink.withValues(alpha: 0.12),
                            ),
                            child: Icon(_icon, size: 21, color: ink),
                          ),
                  ),
                  const SizedBox(width: 11),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          attachment?.name ?? 'File',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13.5,
                            height: 1.25,
                            fontWeight: FontWeight.w600,
                            color: ink,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          message.pending
                              ? 'Sending…'
                              : (attachment?.sizeLabel ?? ''),
                          style: TextStyle(
                            fontSize: 11,
                            color: ink.withValues(alpha: 0.65),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (hasCaption) ...[
                const SizedBox(height: 9),
                Text(
                  message.body,
                  style: TextStyle(fontSize: 14, height: 1.35, color: ink),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ImagePlaceholder extends StatelessWidget {
  const _ImagePlaceholder({this.failed = false});

  final bool failed;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white.withValues(alpha: 0.04),
      alignment: Alignment.center,
      child: Icon(
        failed ? Icons.broken_image_outlined : Icons.image_outlined,
        size: 30,
        color: AppColors.textMuted.withValues(alpha: 0.5),
      ),
    );
  }
}

/// The emoji pills under a message.
///
/// Overlapping the bubble's bottom edge slightly, the way every chat app
/// draws them: it ties the reaction to the message rather than letting it
/// float as a separate row.
class ReactionPills extends StatelessWidget {
  const ReactionPills({
    super.key,
    required this.message,
    required this.meId,
    this.onTap,
  });

  final ChatMessage message;
  final String meId;
  final void Function(ChatMessage message, String emoji)? onTap;

  @override
  Widget build(BuildContext context) {
    return Transform.translate(
      offset: const Offset(0, -6),
      child: Wrap(
        spacing: 4,
        children: [
          for (final reaction in message.reactions)
            GestureDetector(
              onTap: onTap == null
                  ? null
                  : () => onTap!(message, reaction.emoji),
              behavior: HitTestBehavior.opaque,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  color: AppColors.canvasRaised,
                  border: Border.all(
                    // Yours is outlined, so you can see at a glance which
                    // one you added without counting.
                    color: reaction.mine(meId)
                        ? AppColors.aqua
                        : Colors.white.withValues(alpha: 0.14),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(reaction.emoji,
                        style: const TextStyle(fontSize: 13)),
                    if (reaction.count > 1) ...[
                      const SizedBox(width: 3),
                      Text(
                        '${reaction.count}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The quoted message shown above a reply.
///
/// A coloured rail down the left rather than a box: it reads as "attached to
/// what follows" instead of as a separate message, which is exactly the
/// relationship. Used both inside a bubble and above the composer while a
/// reply is being written, so the two always look like the same thing.
class QuotedStrip extends StatelessWidget {
  const QuotedStrip({
    super.key,
    required this.quote,
    this.onDark = false,
    this.onClose,
    this.onTap,
  });

  final QuotedMessage quote;

  /// True inside your own bubble, where the background is the bright
  /// gradient and light-on-dark would disappear.
  final bool onDark;

  /// Shows a dismiss button. Only the composer passes this.
  final VoidCallback? onClose;

  /// Jump to the quoted message. Null in the composer, where the original is
  /// the message you are already looking at.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ink = onDark ? const Color(0xFF04121F) : AppColors.textPrimary;
    final rail = onDark ? const Color(0xFF04121F) : AppColors.aqua;

    final strip = Container(
      padding: const EdgeInsets.fromLTRB(9, 6, 9, 7),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: (onDark ? Colors.black : Colors.white).withValues(alpha: 0.09),
        border: Border(left: BorderSide(color: rail, width: 3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  quote.isMine ? 'You' : 'Them',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: rail.withValues(alpha: onDark ? 0.85 : 1),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  quote.preview,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.3,
                    fontStyle:
                        quote.deleted ? FontStyle.italic : FontStyle.normal,
                    color: ink.withValues(alpha: 0.75),
                  ),
                ),
              ],
            ),
          ),
          if (onClose != null)
            GestureDetector(
              onTap: onClose,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.only(left: 8, top: 2),
                child: Icon(Icons.close_rounded,
                    size: 17, color: ink.withValues(alpha: 0.6)),
              ),
            ),
        ],
      ),
    );

    if (onTap == null) return strip;

    // The bubble around this already has a long-press handler. A tap and a
    // long press do not collide, so the quote can own the tap without taking
    // the menu away from the message it sits in.
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: strip,
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
          if (message.starred) ...[
            Icon(Icons.star_rounded,
                size: 11, color: AppColors.warmGold.withValues(alpha: 0.9)),
            const SizedBox(width: 4),
          ],
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
