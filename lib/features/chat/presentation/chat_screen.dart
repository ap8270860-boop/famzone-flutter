import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/aurora_background.dart';
import '../../people/presentation/user_profile_screen.dart';
import '../../people/presentation/widgets/person_avatar.dart';
import '../data/chat_models.dart';
import 'widgets/message_bubble.dart';

/// A one-to-one conversation.
///
/// Design only for now: messages live in local state and nothing is sent
/// anywhere. The shapes are the ones the real thing will need though — a
/// delivery state per message, grouping by sender, date separators and a
/// typing indicator — so wiring Reverb underneath is a change to where the
/// data comes from, not to how it is drawn.
class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.userId,
    required this.name,
    this.username,
    this.avatarUrl,
    this.initials = '?',
    this.presence,
  });

  final String userId;
  final String name;
  final String? username;
  final String? avatarUrl;
  final String initials;

  /// "Online", "Last seen 2h ago" — null hides the line entirely rather than
  /// showing a placeholder, since presence is a privacy setting.
  final String? presence;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();

  late List<ChatMessage> _messages = _placeholder();
  bool _canSend = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final canSend = _controller.text.trim().isNotEmpty;
      if (canSend != _canSend) setState(() => _canSend = canSend);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Sample conversation, so the design can be judged with real shapes in it.
  /// Delete this the moment the API lands.
  List<ChatMessage> _placeholder() {
    final now = DateTime.now();

    return [
      ChatMessage(
        id: '1',
        body: 'Hey! Are you home yet?',
        sentAt: now.subtract(const Duration(days: 1, hours: 3)),
        isMine: false,
      ),
      ChatMessage(
        id: '2',
        body: 'Just got in a few minutes ago.',
        sentAt: now.subtract(const Duration(days: 1, hours: 2, minutes: 58)),
        isMine: true,
      ),
      ChatMessage(
        id: '3',
        body: 'Checked in on the app too, so you should see it.',
        sentAt: now.subtract(const Duration(days: 1, hours: 2, minutes: 57)),
        isMine: true,
      ),
      ChatMessage(
        id: '4',
        body: 'Perfect, saw the green tick. Thanks!',
        sentAt: now.subtract(const Duration(hours: 4)),
        isMine: false,
      ),
      ChatMessage(
        id: '5',
        body: 'Are we still on for Sunday lunch?',
        sentAt: now.subtract(const Duration(hours: 3, minutes: 59)),
        isMine: false,
      ),
      ChatMessage(
        id: '6',
        body: 'Yes — I will pick up dad on the way.',
        sentAt: now.subtract(const Duration(minutes: 12)),
        isMine: true,
        state: DeliveryState.read,
      ),
    ];
  }

  void _send() {
    final body = _controller.text.trim();

    if (body.isEmpty) return;

    setState(() {
      _messages = [
        ..._messages,
        ChatMessage(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          body: body,
          sentAt: DateTime.now(),
          isMine: true,
          // Optimistic: the bubble appears immediately and the ticks catch up.
          // That is how it will behave against the real API too.
          state: DeliveryState.sending,
        ),
      ];
      _controller.clear();
    });

    // Stand-in for the server acknowledging. Replaced by the Reverb event.
    Future.delayed(const Duration(milliseconds: 700), () {
      if (!mounted) return;
      setState(() {
        _messages = [
          for (final m in _messages)
            m.state == DeliveryState.sending
                ? m.copyWith(state: DeliveryState.sent)
                : m,
        ];
      });
    });

    _scrollToLatest();
  }

  void _scrollToLatest() {
    // The list is reversed, so "latest" is offset zero.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;

      _scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
      );
    });
  }

  void _openProfile() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => UserProfileScreen(userId: widget.userId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      // The composer must ride above the keyboard rather than hide behind it.
      resizeToAvoidBottomInset: true,
      body: AuroraBackground(
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              _Header(
                name: widget.name,
                username: widget.username,
                avatarUrl: widget.avatarUrl,
                initials: widget.initials,
                presence: widget.presence,
                onTapPerson: _openProfile,
              ),
              Expanded(child: _list()),
              _Composer(
                controller: _controller,
                focus: _focus,
                canSend: _canSend,
                onSend: _send,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _list() {
    if (_messages.isEmpty) return _EmptyThread(name: widget.name);

    // Build the visible rows once: groups, with a date chip wherever the day
    // changes. Done here rather than in the builder so the reversed index
    // maths stays trivial.
    final groups = MessageGroup.from(_messages);
    final rows = <Widget>[];
    DateTime? lastDay;

    for (final group in groups) {
      final day = group.messages.first.sentAt.toLocal();

      if (lastDay == null ||
          day.year != lastDay.year ||
          day.month != lastDay.month ||
          day.day != lastDay.day) {
        rows.add(ChatDateChip(label: chatDateLabel(day)));
        lastDay = day;
      }

      rows.add(MessageGroupView(group: group));
    }

    return ListView.builder(
      controller: _scroll,
      // Reversed so new messages appear at the bottom and the view stays
      // pinned there as the keyboard opens — with a normal list you end up
      // computing scroll offsets on every insert and every resize.
      reverse: true,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      physics: const BouncingScrollPhysics(),
      itemCount: rows.length,
      itemBuilder: (context, i) => rows[rows.length - 1 - i],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.name,
    required this.username,
    required this.avatarUrl,
    required this.initials,
    required this.presence,
    required this.onTapPerson,
  });

  final String name;
  final String? username;
  final String? avatarUrl;
  final String initials;
  final String? presence;
  final VoidCallback onTapPerson;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 6, 12, 10),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_rounded,
                color: AppColors.textPrimary),
            onPressed: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: GestureDetector(
              onTap: onTapPerson,
              behavior: HitTestBehavior.opaque,
              child: Row(
                children: [
                  PersonAvatar(
                    size: 38,
                    imageUrl: avatarUrl,
                    initials: initials,
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        if (presence != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            presence!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: AppColors.mint,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The input row.
///
/// Frosted and pinned to the bottom, so it reads as a surface the keyboard
/// pushes up rather than a widget floating over the conversation.
class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.focus,
    required this.canSend,
    required this.onSend,
  });

  final TextEditingController controller;
  final FocusNode focus;
  final bool canSend;
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
            color: AppColors.canvas.withValues(alpha: 0.72),
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
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(23),
                    color: Colors.white.withValues(alpha: 0.06),
                    border:
                        Border.all(color: Colors.white.withValues(alpha: 0.11)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.add_rounded,
                            size: 22, color: AppColors.textMuted),
                        tooltip: 'Attach',
                        onPressed: () {},
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: TextField(
                            controller: controller,
                            focusNode: focus,
                            // Grows to five lines then scrolls, so a long
                            // message never swallows the conversation.
                            minLines: 1,
                            maxLines: 5,
                            textCapitalization: TextCapitalization.sentences,
                            keyboardType: TextInputType.multiline,
                            textInputAction: TextInputAction.newline,
                            style: const TextStyle(
                              fontSize: 14.5,
                              height: 1.35,
                              color: AppColors.textPrimary,
                            ),
                            decoration: const InputDecoration(
                              isDense: true,
                              border: InputBorder.none,
                              hintText: 'Message…',
                              hintStyle: TextStyle(
                                fontSize: 14.5,
                                color: AppColors.textMuted,
                              ),
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.photo_camera_outlined,
                            size: 20, color: AppColors.textMuted),
                        tooltip: 'Photo',
                        onPressed: () {},
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 9),
              _SendButton(enabled: canSend, onTap: onSend),
            ],
          ),
        ),
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton({required this.enabled, required this.onTap});

  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: enabled ? AppColors.safeGradient : null,
          color: enabled ? null : Colors.white.withValues(alpha: 0.06),
          boxShadow: enabled
              ? [
                  BoxShadow(
                    color: AppColors.mint.withValues(alpha: 0.3),
                    blurRadius: 16,
                    offset: const Offset(0, 5),
                  ),
                ]
              : const [],
        ),
        child: Icon(
          Icons.arrow_upward_rounded,
          size: 21,
          // Dead until there is something to send — a live-looking button that
          // does nothing is worse than one that plainly waits.
          color: enabled
              ? const Color(0xFF04121F)
              : AppColors.textMuted.withValues(alpha: 0.7),
        ),
      ),
    );
  }
}

class _EmptyThread extends StatelessWidget {
  const _EmptyThread({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(44, 0, 44, 60),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.forum_outlined,
                size: 44, color: AppColors.textMuted.withValues(alpha: 0.45)),
            const SizedBox(height: 16),
            Text(
              'Say hello to $name',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 15.5,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Messages are private between the two of you.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.45,
                color: AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
