import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../data/chat_api.dart';
import '../../data/chat_models.dart';

/// When a message reached them, and when they read it.
///
/// Only offered on your own messages. "When did they read mine" is a question
/// about the other person, and the answer belongs to whoever wrote the
/// message — the server refuses it for anybody else.
Future<void> showMessageInfoSheet(BuildContext context, ChatMessage message) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _MessageInfoSheet(message: message),
  );
}

class _MessageInfoSheet extends StatefulWidget {
  const _MessageInfoSheet({required this.message});

  final ChatMessage message;

  @override
  State<_MessageInfoSheet> createState() => _MessageInfoSheetState();
}

class _MessageInfoSheetState extends State<_MessageInfoSheet> {
  final ChatApi _api = ChatApi();

  Map<String, dynamic>? _info;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _api.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final id = widget.message.remoteId;

    if (id == null) {
      setState(() {
        _error = 'This message has not been sent yet.';
        _loading = false;
      });

      return;
    }

    try {
      final res = await _api.messageInfo(id);

      if (!mounted) return;

      setState(() {
        if (res.success) {
          _info = res.dataMap;
          _error = null;
        } else {
          _error = res.message;
        }

        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _error = 'Could not reach the server.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        color: AppColors.canvasRaised,
        border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                margin: const EdgeInsets.only(top: 10, bottom: 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  color: Colors.white.withValues(alpha: 0.16),
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 6, 20, 12),
              child: Text(
                'Message info',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ),

            // The message itself, so the sheet is about something you can
            // see. Opening this from a long press covers the bubble you
            // pressed, and a list of timestamps with no message above it
            // leaves you guessing which one you picked.
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: _Preview(message: widget.message),
            ),

            const SizedBox(height: 8),
            Divider(height: 1, color: Colors.white.withValues(alpha: 0.07)),

            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 34),
                child: Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            else if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 26),
                child: Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textMuted,
                  ),
                ),
              )
            else
              ..._rows(),

            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  List<Widget> _rows() {
    final info = _info ?? const {};

    final hidden = info['read_receipts_hidden'] as bool? ?? false;

    return [
      // Read first, then Delivered — newest event at the top, which is also
      // the one people open this sheet to see.
      _InfoRow(
        icon: Icons.done_all_rounded,
        tint: AppColors.aqua,
        label: 'Read',
        value: _stamp(
          at: info['read_at'] as String?,
          happened: info['read'] as bool? ?? false,
          pending: hidden
              // Said plainly rather than left blank. A permanently empty row
              // reads as a bug in our app rather than as their setting.
              ? 'Read receipts are off'
              : 'Not yet',
        ),
        muted: hidden || (info['read'] as bool? ?? false) == false,
      ),
      _InfoRow(
        icon: Icons.done_all_rounded,
        tint: AppColors.textMuted,
        label: 'Delivered',
        value: _stamp(
          at: info['delivered_at'] as String?,
          happened: info['delivered'] as bool? ?? false,
          pending: 'Not yet',
        ),
        muted: (info['delivered'] as bool? ?? false) == false,
      ),
      _InfoRow(
        icon: Icons.check_rounded,
        tint: AppColors.textMuted,
        label: 'Sent',
        value: _stamp(
          at: info['sent_at'] as String?,
          happened: true,
          pending: '—',
        ),
        muted: false,
      ),
    ];
  }

  /// "April 26, 10:57 AM", or a plain reason there is no time.
  String _stamp({
    required String? at,
    required bool happened,
    required String pending,
  }) {
    if (at != null) {
      final parsed = DateTime.tryParse(at);

      if (parsed != null) return formatStamp(parsed);
    }

    // The watermark says it happened but no mark records the moment —
    // messages sent before this feature existed. Better to admit that than
    // to claim it never happened.
    if (happened) return 'No exact time';

    return pending;
  }
}

/// "April 26, 10:57 AM". The year is added only when it is not this one.
String formatStamp(DateTime utc) {
  final at = utc.toLocal();

  const months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  final hour = at.hour % 12 == 0 ? 12 : at.hour % 12;
  final minute = at.minute.toString().padLeft(2, '0');
  final meridiem = at.hour < 12 ? 'AM' : 'PM';

  final year = at.year == DateTime.now().year ? '' : ', ${at.year}';

  return '${months[at.month - 1]} ${at.day}$year, $hour:$minute $meridiem';
}

class _Preview extends StatelessWidget {
  const _Preview({required this.message});

  final ChatMessage message;

  String get _text {
    if (message.deleted) return 'This message was deleted';

    if (message.body.isNotEmpty) return message.body;

    return switch (message.type) {
      MessageType.image => 'Photo',
      MessageType.file => message.attachment?.name ?? 'File',
      MessageType.audio => 'Voice message',
      _ => 'Message',
    };
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.7,
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(16),
              topRight: Radius.circular(16),
              bottomLeft: Radius.circular(16),
              bottomRight: Radius.circular(6),
            ),
            gradient: AppColors.safeGradient,
          ),
          child: Text(
            _text,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13.5,
              height: 1.35,
              color: Color(0xFF04121F),
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.tint,
    required this.label,
    required this.value,
    required this.muted,
  });

  final IconData icon;
  final Color tint;
  final String label;
  final String value;

  /// Whether this has not happened yet — the tick greys out with the time.
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 13, 20, 13),
      child: Row(
        children: [
          Icon(
            icon,
            size: 19,
            color: muted ? AppColors.textMuted.withValues(alpha: 0.45) : tint,
          ),
          const SizedBox(width: 14),
          Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const Spacer(),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: muted
                    ? AppColors.textMuted.withValues(alpha: 0.75)
                    : AppColors.textPrimary.withValues(alpha: 0.9),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
