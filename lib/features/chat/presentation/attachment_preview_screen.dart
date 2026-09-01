import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../data/chat_models.dart';

/// What comes back when somebody confirms an attachment.
///
/// A class rather than a bare `String?`, because an empty caption and a
/// discarded attachment are different answers and both would be null.
@immutable
class AttachmentDraft {
  const AttachmentDraft({required this.caption});

  final String caption;
}

/// Review an attachment before it goes.
///
/// Picking a file is not the same as deciding to send it — you tap the wrong
/// photo, you want to say what it is first, you change your mind. Sending on
/// selection turns every one of those into a message the other person has
/// already seen.
///
/// Returns an [AttachmentDraft] on send, or null on discard.
Future<AttachmentDraft?> openAttachmentPreview(
  BuildContext context, {
  required String filePath,
  required String type,
  String initialCaption = '',
}) {
  return Navigator.of(context).push<AttachmentDraft>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => AttachmentPreviewScreen(
        filePath: filePath,
        type: type,
        initialCaption: initialCaption,
      ),
    ),
  );
}

class AttachmentPreviewScreen extends StatefulWidget {
  const AttachmentPreviewScreen({
    super.key,
    required this.filePath,
    required this.type,
    this.initialCaption = '',
  });

  final String filePath;
  final String type;
  final String initialCaption;

  @override
  State<AttachmentPreviewScreen> createState() =>
      _AttachmentPreviewScreenState();
}

class _AttachmentPreviewScreenState extends State<AttachmentPreviewScreen> {
  late final TextEditingController _caption =
      TextEditingController(text: widget.initialCaption);

  final _focus = FocusNode();

  @override
  void dispose() {
    _caption.dispose();
    _focus.dispose();
    super.dispose();
  }

  String get _name => widget.filePath.split(RegExp(r'[/\\]')).last;

  String get _sizeLabel {
    try {
      final bytes = File(widget.filePath).lengthSync();

      if (bytes >= 1048576) return '${(bytes / 1048576).toStringAsFixed(1)} MB';
      if (bytes >= 1024) return '${(bytes / 1024).round()} KB';

      return '$bytes B';
    } catch (_) {
      return '';
    }
  }

  void _send() {
    Navigator.of(context).pop(
      AttachmentDraft(caption: _caption.text.trim()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isImage = widget.type == MessageType.image;

    return Scaffold(
      // Black rather than the app canvas: a photo should be judged against
      // nothing, and a tint underneath it changes how it reads.
      backgroundColor: isImage ? Colors.black : AppColors.canvas,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _TopBar(
              title: isImage ? null : _name,
              onDiscard: () => Navigator.of(context).pop(),
            ),
            Expanded(
              child: isImage
                  ? _ImagePreview(path: widget.filePath)
                  : _FilePreview(name: _name, size: _sizeLabel),
            ),
            _CaptionBar(
              controller: _caption,
              focus: _focus,
              onSend: _send,
            ),
          ],
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.title, required this.onDiscard});

  final String? title;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 16, 4),
      child: Row(
        children: [
          IconButton(
            // A cross, not a back arrow. Back suggests the file survives the
            // journey; this throws it away.
            icon: const Icon(Icons.close_rounded, color: Colors.white),
            tooltip: 'Discard',
            onPressed: onDiscard,
          ),
          if (title != null)
            Expanded(
              child: Text(
                title!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ImagePreview extends StatelessWidget {
  const _ImagePreview({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    return InteractiveViewer(
      minScale: 1,
      maxScale: 4,
      child: Center(
        child: Image.file(
          File(path),
          fit: BoxFit.contain,
          errorBuilder: (context, _, __) => const Icon(
            Icons.broken_image_outlined,
            size: 44,
            color: AppColors.textMuted,
          ),
        ),
      ),
    );
  }
}

/// Documents have nothing to show, so the card states plainly what is being
/// sent rather than pretending to a preview it cannot produce.
class _FilePreview extends StatelessWidget {
  const _FilePreview({required this.name, required this.size});

  final String name;
  final String size;

  IconData get _icon {
    final lower = name.toLowerCase();

    if (lower.endsWith('.pdf')) return Icons.picture_as_pdf_rounded;
    if (RegExp(r'\.(doc|docx|rtf|txt)$').hasMatch(lower)) {
      return Icons.article_rounded;
    }
    if (RegExp(r'\.(xls|xlsx|csv)$').hasMatch(lower)) {
      return Icons.table_chart_rounded;
    }
    if (RegExp(r'\.(zip|rar|7z|tar|gz)$').hasMatch(lower)) {
      return Icons.folder_zip_rounded;
    }
    if (RegExp(r'\.(png|jpe?g|gif|webp|heic)$').hasMatch(lower)) {
      return Icons.image_rounded;
    }
    if (RegExp(r'\.(mp4|mov|mkv|avi)$').hasMatch(lower)) {
      return Icons.movie_rounded;
    }

    return Icons.insert_drive_file_rounded;
  }

  String get _kind {
    final dot = name.lastIndexOf('.');

    return dot == -1 || dot == name.length - 1
        ? 'FILE'
        : name.substring(dot + 1).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 260,
        padding: const EdgeInsets.symmetric(vertical: 44),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: Colors.white.withValues(alpha: 0.05),
          border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_icon, size: 62, color: AppColors.aqua),
            const SizedBox(height: 18),
            const Text(
              'No preview available',
              style: TextStyle(fontSize: 14, color: AppColors.textMuted),
            ),
            const SizedBox(height: 6),
            Text(
              size.isEmpty ? _kind : '$size · $_kind',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textMuted.withValues(alpha: 0.75),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Caption field and the send button.
///
/// The send button is always live here, unlike the chat composer — an
/// attachment with no caption is a perfectly ordinary message, and the thing
/// being sent is already chosen.
class _CaptionBar extends StatelessWidget {
  const _CaptionBar({
    required this.controller,
    required this.focus,
    required this.onSend,
  });

  final TextEditingController controller;
  final FocusNode focus;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: EdgeInsets.fromLTRB(
            12, 10, 12, 10 + MediaQuery.viewPaddingOf(context).bottom,
          ),
          decoration: BoxDecoration(
            color: AppColors.canvas.withValues(alpha: 0.8),
            border: Border(
              top: BorderSide(color: Colors.white.withValues(alpha: 0.07)),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Container(
                  constraints: const BoxConstraints(minHeight: 46),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(23),
                    color: Colors.white.withValues(alpha: 0.06),
                    border:
                        Border.all(color: Colors.white.withValues(alpha: 0.11)),
                  ),
                  child: TextField(
                    controller: controller,
                    focusNode: focus,
                    minLines: 1,
                    maxLines: 4,
                    textCapitalization: TextCapitalization.sentences,
                    keyboardType: TextInputType.multiline,
                    style: const TextStyle(
                      fontSize: 14.5,
                      height: 1.35,
                      color: AppColors.textPrimary,
                    ),
                    decoration: const InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(vertical: 13),
                      hintText: 'Add a caption…',
                      hintStyle: TextStyle(
                        fontSize: 14.5,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 9),
              GestureDetector(
                onTap: onSend,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: AppColors.safeGradient,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.mint.withValues(alpha: 0.3),
                        blurRadius: 16,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.arrow_upward_rounded,
                    size: 21,
                    color: Color(0xFF04121F),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
