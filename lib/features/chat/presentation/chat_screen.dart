import 'dart:ui';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../core/widgets/aurora_background.dart';
import '../../people/data/people_api.dart';
import '../../people/presentation/user_profile_screen.dart';
import '../../people/presentation/widgets/block_sheet.dart';
import '../../people/presentation/widgets/person_avatar.dart';
import '../data/chat_models.dart';
import '../state/conversation_store.dart';
import '../state/realtime_client.dart';
import 'widgets/attach_sheet.dart';
import 'widgets/message_bubble.dart';

/// A one-to-one conversation.
///
/// Backed by [ConversationStore], which is created here and disposed with the
/// screen. That lifetime is deliberate: from the next phase the store owns
/// this thread's websocket subscription, so a message in another conversation
/// cannot reach this screen — the subscription simply does not exist while
/// the screen is closed.
///
/// Nothing here polls. Messages arrive on open, on pull-to-refresh, and on
/// returning to the foreground; the socket replaces those triggers rather
/// than the code paths behind them.
class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.userId,
    required this.name,
    this.conversationId,
    this.username,
    this.avatarUrl,
    this.initials = '?',
    this.presence,
  });

  final String userId;
  final String name;

  /// Known when opening from the inbox; null from a profile, where the
  /// thread is resolved or created on open.
  final String? conversationId;

  final String? username;
  final String? avatarUrl;
  final String initials;

  /// What the caller already knew about presence, shown until the server
  /// says otherwise. Null hides the line rather than showing a placeholder,
  /// since presence is a privacy setting.
  final String? presence;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();

  late final ConversationStore _store = ConversationStore(
    peerId: widget.userId,
    conversationId: widget.conversationId,
  );

  final PeopleApi _people = PeopleApi();
  final ImagePicker _picker = ImagePicker();

  bool _canSend = false;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);

    _controller.addListener(() {
      final canSend = _controller.text.trim().isNotEmpty;

      if (canSend != _canSend) setState(() => _canSend = canSend);

      // Only while there is something to say. The listener also fires when
      // the field is cleared on send, and whispering "typing" at the exact
      // moment a message goes out is how an indicator gets stuck on.
      if (canSend) _store.noteTyping();
    });

    // The list is reversed, so its scroll extent runs backwards in time and
    // reaching the end means reaching the oldest message.
    _scroll.addListener(() {
      if (!_scroll.hasClients) return;

      final position = _scroll.position;

      if (position.pixels >= position.maxScrollExtent - 320) {
        _store.loadOlder();
      }
    });

    _store.open();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    _focus.dispose();
    _scroll.dispose();
    _store.dispose();
    _people.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Anything that happened while the app was away is fetched rather than
    // assumed. The same call fills the gap left by a dropped socket once
    // there is one.
    if (state == AppLifecycleState.resumed) _store.refresh();
  }

  Future<void> _send() async {
    final body = _controller.text.trim();

    if (body.isEmpty) return;

    _controller.clear();
    _scrollToLatest();

    await _store.send(body);

    final error = _store.error;

    if (mounted && error != null && _store.messages.any((m) => m.failed)) {
      AppToast.error(context, error);
    }
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

  /// Pick a photo and send it, with whatever is already in the composer as
  /// its caption.
  ///
  /// Downscaled and re-encoded on the way out. A modern phone camera produces
  /// 6–12 MB files, and nobody looking at a chat bubble can tell the
  /// difference between that and 1600px of JPEG — but the person on mobile
  /// data certainly can.
  /// The + button: ask what kind of thing, then go and get it.
  Future<void> _attach() async {
    final choice = await showAttachSheet(context);

    if (choice == null || !mounted) return;

    switch (choice) {
      case AttachChoice.camera:
        await _pickImage(ImageSource.camera);
      case AttachChoice.gallery:
        await _pickImage(ImageSource.gallery);
      case AttachChoice.document:
        await _pickDocument();
    }
  }

  /// Pick any file and send it.
  ///
  /// Deliberately unfiltered by extension. A parent sending a school PDF, a
  /// ticket, a .docx — guessing a whitelist here just means somebody cannot
  /// send the one thing they needed to. The server enforces the size cap and
  /// stores it as an opaque blob either way.
  Future<void> _pickDocument() async {
    try {
      // `.platform` is the v8 API. v11 moved pickFiles onto the class
      // itself and v12 changed the return type again — check the installed
      // version before touching this line.
      //
      // withData stays false so a 20 MB file is not read into memory just to
      // be uploaded from disk.
      final result = await FilePicker.platform.pickFiles(withData: false);

      if (result == null || result.files.isEmpty || !mounted) return;

      final path = result.files.first.path;

      // Null on web, where there is no filesystem path — nothing to send
      // from here until that platform is actually supported.
      if (path == null) return;

      final caption = _controller.text.trim();

      _controller.clear();
      _scrollToLatest();

      await _store.sendFile(path, caption: caption);
    } catch (_) {
      if (mounted) AppToast.error(context, 'Could not open that file.');
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picked = await _picker.pickImage(
        source: source,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 82,
      );

      if (picked == null || !mounted) return;

      final caption = _controller.text.trim();

      _controller.clear();
      _scrollToLatest();

      await _store.sendImage(picked.path, caption: caption);
    } catch (_) {
      if (mounted) AppToast.error(context, 'Could not open that photo.');
    }
  }

  /// The overflow menu.
  ///
  /// A bottom sheet rather than a popup menu: a popup anchored to the top-right
  /// corner puts destructive actions under the thumb's least accurate reach,
  /// and every other menu in the app is a sheet.
  Future<void> _openMenu() async {
    final choice = await showModalBottomSheet<_ChatAction>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _ChatMenuSheet(
        name: _store.person?.name ?? widget.name,
        blocked: _store.blocked,
      ),
    );

    if (choice == null || !mounted) return;

    switch (choice) {
      case _ChatAction.profile:
        _openProfile();
      case _ChatAction.block:
        await _block();
      case _ChatAction.unblock:
        await _unblock();
      case _ChatAction.delete:
        await _deleteThread();
    }
  }

  Future<void> _block() async {
    final person = _store.person;

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => BlockSheet(
        name: person?.name ?? widget.name,
        username: person?.username ?? widget.username,
        avatarUrl: person?.avatarUrl ?? widget.avatarUrl,
        initials: person?.initials ?? widget.initials,
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await _people.block(widget.userId);

      // The server broadcasts conversation.closed, which is what actually
      // updates this screen. Refreshing as well covers the case where the
      // socket is down — the block still has to take visible effect.
      await _store.refresh();

      if (mounted) AppToast.success(context, 'Blocked.');
    } catch (_) {
      if (mounted) AppToast.error(context, 'Could not block right now.');
    }
  }

  Future<void> _unblock() async {
    try {
      await _people.unblock(widget.userId);
      await _store.refresh();

      if (mounted) AppToast.success(context, 'Unblocked.');
    } catch (_) {
      if (mounted) AppToast.error(context, 'Could not unblock right now.');
    }
  }

  Future<void> _deleteThread() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.canvasRaised,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        title: const Text(
          'Delete conversation?',
          style: TextStyle(fontSize: 16, color: AppColors.textPrimary),
        ),
        content: const Text(
          'It disappears from your list. If they message you again it comes '
          'back with its history — this does not delete anything for them.',
          style: TextStyle(
            fontSize: 13,
            height: 1.45,
            color: AppColors.textMuted,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel',
                style: TextStyle(color: AppColors.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete',
                style: TextStyle(color: AppColors.alertRed)),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final ok = await _store.deleteThread();

    if (!mounted) return;

    if (!ok) {
      AppToast.error(context, 'Could not delete that conversation.');

      return;
    }

    Navigator.of(context).pop();
  }

  Future<void> _accept() async {
    final ok = await _store.acceptRequest();

    if (!mounted) return;

    AppToast.success(context, ok ? 'Request accepted.' : 'Could not accept.');
  }

  Future<void> _decline() async {
    final ok = await _store.deleteThread();

    if (!mounted) return;

    if (!ok) {
      AppToast.error(context, 'Could not delete that request.');

      return;
    }

    // Nothing left to look at — the thread is gone from the list behind this
    // screen, so staying on it would be a dead end.
    Navigator.of(context).pop();
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
          child: AnimatedBuilder(
            animation: _store,
            builder: (context, _) {
              final person = _store.person;

              return Column(
                children: [
                  _Header(
                    name: person?.name ?? widget.name,
                    username: person?.username ?? widget.username,
                    avatarUrl: person?.avatarUrl ?? widget.avatarUrl,
                    initials: person?.initials ?? widget.initials,
                    // Live presence beats whatever the caller knew: typing,
                    // then "Active now", then last seen.
                    presence: _store.peerPresenceLabel ?? widget.presence,
                    typing: _store.peerTyping,
                    onMenu: _openMenu,
                    onTapPerson: _openProfile,
                  ),
                  const _ConnectionStrip(),
                  if (_store.isRequest && !_store.blocked)
                    _RequestBanner(
                      name: person?.name ?? widget.name,
                      onAccept: _accept,
                      onDecline: _decline,
                    ),
                  Expanded(child: _body()),
                  if (_store.awaitingAcceptance &&
                      !_store.isRequest &&
                      !_store.blocked)
                    const _PendingNotice(),

                  // No composer at all when blocked. A text field that takes
                  // input and then fails with a 403 is a worse way to find
                  // out than a line of text that says so up front.
                  if (_store.blocked)
                    const _BlockedNotice()
                  else
                    _Composer(
                      controller: _controller,
                      focus: _focus,
                      canSend: _canSend,
                      onSend: _send,
                      onAttach: _attach,
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _body() {
    if (_store.loading) {
      return const Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    final messages = _store.messages;

    // A typing indicator in an empty thread is not an empty thread — it is
    // the most interesting thing that has ever happened in it.
    if (messages.isEmpty && !_store.peerTyping) {
      return RefreshIndicator(
        onRefresh: _store.refresh,
        color: AppColors.mint,
        backgroundColor: AppColors.canvas,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(height: MediaQuery.sizeOf(context).height * 0.18),
            _EmptyThread(name: _store.person?.name ?? widget.name),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _store.refresh,
      color: AppColors.mint,
      backgroundColor: AppColors.canvas,
      child: _list(messages),
    );
  }

  Widget _list(List<ChatMessage> messages) {
    // Build the visible rows once: groups, with a date chip wherever the day
    // changes. Done here rather than in the builder so the reversed index
    // maths stays trivial.
    final groups = MessageGroup.from(messages);
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

      final failed = group.last.failed;

      rows.add(
        failed
            // A failed message keeps its bubble and gains a way back. Tapping
            // resends with the same client id, so if the first attempt did
            // reach the server this returns that message rather than posting
            // a second copy.
            ? GestureDetector(
                onTap: () => _store.retry(group.last),
                behavior: HitTestBehavior.opaque,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    MessageGroupView(group: group),
                    const Padding(
                      padding: EdgeInsets.only(right: 6, bottom: 10),
                      child: Text(
                        'Not sent · tap to try again',
                        style: TextStyle(
                          fontSize: 10.5,
                          color: AppColors.alertRed,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            : MessageGroupView(group: group),
      );
    }

    // Last row, which the reversed list puts at the bottom — directly above
    // the composer, where the next message will land.
    if (_store.peerTyping) rows.add(const TypingBubble());

    if (_store.loadingOlder) {
      rows.insert(
        0,
        const Padding(
          padding: EdgeInsets.only(bottom: 14),
          child: Center(
            child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 1.8),
            ),
          ),
        ),
      );
    }

    return ListView.builder(
      controller: _scroll,
      // Reversed so new messages appear at the bottom and the view stays
      // pinned there as the keyboard opens — with a normal list you end up
      // computing scroll offsets on every insert and every resize.
      reverse: true,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      itemCount: rows.length,
      itemBuilder: (context, i) => rows[rows.length - 1 - i],
    );
  }
}

/// A thin line while the socket is away.
///
/// A strip and not a dialog, deliberately: messages still send over HTTP
/// while it shows, so nothing is actually blocked and interrupting the user
/// would be a lie about the severity.
class _ConnectionStrip extends StatelessWidget {
  const _ConnectionStrip();

  @override
  Widget build(BuildContext context) {
    final realtime = RealtimeClient.instance;

    return AnimatedBuilder(
      animation: realtime,
      builder: (context, _) {
        if (!realtime.reconnecting) return const SizedBox.shrink();

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 4),
          color: Colors.white.withValues(alpha: 0.05),
          child: Text(
            'Connecting…',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              color: AppColors.textMuted.withValues(alpha: 0.9),
            ),
          ),
        );
      },
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
    required this.onMenu,
    this.typing = false,
  });

  final String name;
  final String? username;
  final String? avatarUrl;
  final String initials;
  final String? presence;
  final VoidCallback onTapPerson;
  final VoidCallback onMenu;

  /// Tints the presence line while they are typing, so the header carries the
  /// same signal as the bubble without needing a second widget.
  final bool typing;

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
                            style: TextStyle(
                              fontSize: 11.5,
                              fontStyle:
                                  typing ? FontStyle.italic : FontStyle.normal,
                              color: typing ? AppColors.aqua : AppColors.mint,
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
          IconButton(
            icon: const Icon(Icons.more_vert_rounded,
                color: AppColors.textPrimary),
            tooltip: 'More',
            onPressed: onMenu,
          ),
        ],
      ),
    );
  }
}

enum _ChatAction { profile, block, unblock, delete }

/// The overflow menu's contents.
///
/// Three actions, not a long list. Mute and Search belong here eventually but
/// have no endpoint behind them yet, and a menu item that does nothing is
/// worse than one that is missing.
class _ChatMenuSheet extends StatelessWidget {
  const _ChatMenuSheet({required this.name, required this.blocked});

  final String name;
  final bool blocked;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.fromLTRB(
        12, 0, 12, 12 + MediaQuery.viewPaddingOf(context).bottom,
      ),
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        color: AppColors.canvasRaised,
        border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // A grab handle, so the sheet reads as dismissable by dragging as
          // well as by tapping away.
          Container(
            width: 38,
            height: 4,
            margin: const EdgeInsets.only(top: 4, bottom: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              color: Colors.white.withValues(alpha: 0.16),
            ),
          ),
          _MenuRow(
            icon: Icons.person_outline_rounded,
            label: 'View profile',
            onTap: () => Navigator.of(context).pop(_ChatAction.profile),
          ),
          if (blocked)
            _MenuRow(
              icon: Icons.lock_open_rounded,
              label: 'Unblock $name',
              onTap: () => Navigator.of(context).pop(_ChatAction.unblock),
            )
          else
            _MenuRow(
              icon: Icons.block_rounded,
              label: 'Block $name',
              danger: true,
              onTap: () => Navigator.of(context).pop(_ChatAction.block),
            ),
          _MenuRow(
            icon: Icons.delete_outline_rounded,
            label: 'Delete conversation',
            danger: true,
            onTap: () => Navigator.of(context).pop(_ChatAction.delete),
          ),
        ],
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final tint = danger ? AppColors.alertRed : AppColors.textPrimary;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
        child: Row(
          children: [
            Icon(icon, size: 20, color: danger ? tint : AppColors.aqua),
            const SizedBox(width: 15),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                  color: tint,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown to the person who received a message request.
class _RequestBanner extends StatelessWidget {
  const _RequestBanner({
    required this.name,
    required this.onAccept,
    required this.onDecline,
  });

  final String name;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: Colors.white.withValues(alpha: 0.06),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      // Stacked rather than a single row: three things across a phone leaves
      // the message truncated and both buttons too small to hit confidently.
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$name wants to send you a message. They will not know you have '
            'seen it unless you accept.',
            style: const TextStyle(
              fontSize: 12.5,
              height: 1.4,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: onDecline,
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(11),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.14),
                      ),
                    ),
                    child: const Text(
                      'Delete',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GestureDetector(
                  onTap: onAccept,
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(11),
                      gradient: AppColors.safeGradient,
                    ),
                    child: const Text(
                      'Accept',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF04121F),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Replaces the composer when a wall stands between the two people.
///
/// Says nothing about who blocked whom. Somebody who has been blocked must
/// not be able to tell the difference between that and the other account
/// having gone quiet — otherwise the block itself becomes a message.
class _BlockedNotice extends StatelessWidget {
  const _BlockedNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        24, 16, 24, 16 + MediaQuery.viewPaddingOf(context).bottom,
      ),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.07)),
        ),
      ),
      child: const Text(
        'You can’t send messages in this conversation.',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 12.5,
          height: 1.4,
          color: AppColors.textMuted,
        ),
      ),
    );
  }
}

/// Shown to the sender while the other person has not accepted.
class _PendingNotice extends StatelessWidget {
  const _PendingNotice();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Text(
        'They have not accepted your message request yet.',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 11.5,
          color: AppColors.textMuted.withValues(alpha: 0.85),
        ),
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
    required this.onAttach,
  });

  final TextEditingController controller;
  final FocusNode focus;
  final bool canSend;
  final VoidCallback onSend;
  final VoidCallback onAttach;

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
                        onPressed: onAttach,
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
                      // No second camera button in the field. Everything that
                      // attaches now lives behind +, so the text field is for
                      // typing and nothing else.
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
