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
