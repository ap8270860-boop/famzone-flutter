import 'dart:async';
import 'dart:ui';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import '../state/voice_player.dart';
import '../state/voice_recorder.dart';
import 'attachment_preview_screen.dart';
import 'forward_sheet.dart';
import 'group_info_screen.dart';
import 'widgets/attach_sheet.dart';
import 'widgets/message_info_sheet.dart';
import 'widgets/message_menu.dart';
import 'widgets/message_bubble.dart';
import 'widgets/voice_recorder_bar.dart';

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

  /// One key per run of messages, kept across rebuilds and keyed on the first
  /// message in the run — a new key every frame would rebuild the row and
  /// leave nothing for [Scrollable.ensureVisible] to aim at.
  final Map<String, GlobalKey> _groupKeys = {};

  /// Server id → the key of the row that message is drawn in, and that row's
  /// position in the list. Rebuilt whenever the list is.
  final Map<String, GlobalKey> _messageKeys = {};
  final Map<String, int> _messageRows = {};
  int _rowCount = 0;

  /// The message just jumped to, tinted briefly.
  String? _highlightedId;
  Timer? _highlight;

  /// Recording a voice note. One per screen, disposed with it — leaving mid
  /// recording has to release the microphone.
  final VoiceRecorder _voice = VoiceRecorder();

  /// How far the finger has slid from the microphone, 0–1 of the way to
  /// cancelling (left) and to locking (up).
  double _slide = 0;
  double _lockProgress = 0;

  /// How far the finger must travel for each. Cancel is the longer of the
  /// two on purpose: it is the one that destroys something.
  static const double _cancelDistance = 110;
  static const double _lockDistance = 70;

  /// Whether the thread is parked at the newest message. Drives the jump
  /// button, which has no reason to exist while you are already there.
  bool _atBottom = true;

  /// How many messages have arrived from the other person while you were
  /// reading further up. Derived from the sequence numbers rather than
  /// counted as they land, so it cannot drift out of step.
  int _unseen = 0;
  int _seenSeq = 0;

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

      // Offset zero is the newest message, the list being reversed. The
      // threshold is a screenful-ish rather than exact: a button that
      // flickers in and out over the last few pixels of a rubber-band bounce
      // is worse than one that waits until you have actually left.
      _setAtBottom(position.pixels < 220);
    });

    // New arrivals while you are reading history are the whole reason the
    // button carries a count.
    _store.addListener(_syncUnseen);

    _store.open();
  }

  void _setAtBottom(bool atBottom) {
    if (atBottom == _atBottom) return;

    setState(() => _atBottom = atBottom);

    _syncUnseen();
  }

  /// Recount what has arrived since the thread was last at the bottom.
  void _syncUnseen() {
    final messages = _store.messages;

    // The highest sequence number, not the last message: an unsent bubble
    // sits at the end of the list with a sequence of zero, and reading that
    // as "the newest" would mark the whole thread unseen the moment a send
    // failed.
    final latest = messages.fold<int>(0, (max, m) => m.seq > max ? m.seq : max);

    // Sitting at the bottom means everything is seen by definition.
    if (_atBottom) {
      if (_unseen != 0 || _seenSeq != latest) {
        _seenSeq = latest;

        if (_unseen != 0 && mounted) setState(() => _unseen = 0);
      }

      return;
    }

    // Your own messages never count: sending one scrolls you down anyway,
    // and a badge telling you about your own message is noise.
    final unseen = messages
        .where((m) => !m.isMine && m.seq > _seenSeq)
        .length;

    if (unseen != _unseen && mounted) setState(() => _unseen = unseen);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _highlight?.cancel();
    _store.removeListener(_syncUnseen);

    // Both matter on the way out: a recorder left running holds the
    // microphone, and a voice note left playing follows you to the next
    // screen with no way to stop it.
    _voice.dispose();
    VoicePlayer.instance.stop();

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
    // Marked before the animation rather than after it: the button should go
    // the moment it is tapped, not a quarter of a second later.
    _setAtBottom(true);

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
    // Tapping the header of a group opens the group, not a person.
    if (_isGroup) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => GroupInfoScreen(store: _store, meId: _store.meId),
        ),
      );

      return;
    }

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
  /// Long press on a message.
  ///
  /// Copy is offered only for text — copying "Photo" to the clipboard would
  /// be a lie about what was copied. Delete only for your own messages,
  /// because the endpoint refuses anybody else's and offering an action that
  /// always fails is worse than not offering it.
  Future<void> _onMessageLongPress(ChatMessage message, Offset at) async {
    final result = await showMessageMenu(
      context,
      at: at,
      canCopy: message.body.isNotEmpty && !message.deleted,
      // Info answers "when did they read this", which only makes sense about
      // something you sent and which the server refuses for anything else.
      canInfo: message.isMine && message.remoteId != null,
      // A tombstone gets a menu of one: clear it from your own side.
      deleted: message.deleted,
      // Both are toggles, so the menu needs to know which way round to draw
      // them — offering "Pin" on the message already pinned would leave the
      // reader guessing what the tap does.
      pinned: _isPinned(message),
      starred: message.starred,
      myReaction: _myReaction(message),
    );

    if (result == null || !mounted) return;

    final emoji = result.emoji;

    if (emoji != null) {
      await _store.react(message, emoji);

      return;
    }

    switch (result.action!) {
      case MessageAction.reply:
        _store.startReply(message);
        _focus.requestFocus();

      case MessageAction.copy:
        await Clipboard.setData(ClipboardData(text: message.body));

        if (mounted) AppToast.success(context, 'Copied.');

      case MessageAction.forward:
        await _forward(message);

      case MessageAction.pin:
        await _pin(message);

      case MessageAction.unpin:
        await _pin(null);

      case MessageAction.star:
      case MessageAction.unstar:
        await _store.toggleStar(message);

      case MessageAction.info:
        await showMessageInfoSheet(context, message);

      case MessageAction.delete:
        await _confirmDelete(message);
    }
  }

  /// Whether this is the message pinned in the thread.
  ///
  /// Compared on the server id, not the client one: the pinned copy comes
  /// back from a different endpoint and carries no client id, so the two
  /// objects are never the same instance.
  bool _isPinned(ChatMessage message) {
    final pinned = _store.conversation?.pinnedMessage?.remoteId;

    return pinned != null && pinned == message.remoteId;
  }

  /// Pin a message, or pass null to clear it.
  Future<void> _pin(ChatMessage? message) async {
    // A message that never reached the server has no id to pin.
    if (message != null && message.remoteId == null) {
      AppToast.error(context, 'Wait for it to send first.');

      return;
    }

    final ok = await _store.pin(message);

    if (!mounted) return;

    if (ok) {
      AppToast.success(context, message == null ? 'Unpinned.' : 'Pinned.');
    } else {
      AppToast.error(context, 'Could not change the pin.');
    }
  }

  /// Send a copy of a message into other conversations.
  Future<void> _forward(ChatMessage message) async {
    if (message.remoteId == null) {
      AppToast.error(context, 'Wait for it to send first.');

      return;
    }

    final targets = await showForwardSheet(context);

    if (targets == null || targets.isEmpty || !mounted) return;

    final sent = await _store.forward(message, targets);

    if (!mounted) return;

    if (sent > 0) {
      AppToast.success(
        context,
        sent == 1 ? 'Forwarded.' : 'Forwarded to $sent chats.',
      );
    } else {
      AppToast.error(context, 'Could not forward that.');
    }
  }

  /*
  |----------------------------------------------------------------------------
  | Voice notes
  |----------------------------------------------------------------------------
  |
  | Hold to record, release to send. Slide left to cancel, slide up to lock
  | into hands-free. The gesture lives on the microphone button, which is why
  | the composer keeps that button mounted while recording — a GestureDetector
  | disposed mid-press never delivers its end event, and the recording would
  | run until the screen closed.
  */

  Future<void> _startRecording() async {
    // Nothing to record over: a half-typed message means they meant to type.
    if (_canSend) return;

    setState(() {
      _slide = 0;
      _lockProgress = 0;
    });

    final started = await _voice.start();

    if (!started && mounted) {
      AppToast.error(
        context,
        'SFamily needs microphone access to record a voice note.',
      );
    }
  }

  /// The finger moving while the note records.
  void _onMicMove(Offset offset) {
    if (!_voice.isActive || _voice.isLocked) return;

    final slide = (-offset.dx / _cancelDistance).clamp(0.0, 1.0);
    final lock = (-offset.dy / _lockDistance).clamp(0.0, 1.0);

    if (slide >= 1) {
      _cancelRecording();

      return;
    }

    if (lock >= 1) {
      _voice.lock();

      setState(() {
        _slide = 0;
        _lockProgress = 0;
      });

      return;
    }

    setState(() {
      _slide = slide;
      _lockProgress = lock;
    });
  }

  /// Finger lifted. Locked recordings keep going; everything else is sent.
  Future<void> _finishRecording() async {
    if (!_voice.isActive || _voice.isLocked) return;

    await _sendRecording();
  }

  Future<void> _sendRecording() async {
    final note = await _voice.stop();

    if (!mounted) return;

    setState(() {
      _slide = 0;
      _lockProgress = 0;
    });

    if (note == null) {
      // Too short to be a message. Said out loud, because a press that
      // produces nothing otherwise reads as a broken button.
      AppToast.error(context, 'Hold the microphone to record.');

      return;
    }

    _scrollToLatest();

    await _store.sendVoice(note);
  }

  Future<void> _cancelRecording() async {
    await _voice.cancel();

    if (!mounted) return;

    setState(() {
      _slide = 0;
      _lockProgress = 0;
    });
  }

  void _micHint() {
    if (_voice.isActive) return;

    AppToast.error(context, 'Hold the microphone to record.');
  }

  /// Tapping the quoted strip inside a reply.
  void _onQuoteTap(QuotedMessage quote) => _jumpToMessage(quote.id);

  /// Jump to the message a reply is answering.
  ///
  /// Three problems, in order. The message may be older than anything loaded,
  /// so history is walked back until it turns up. It may be loaded but not
  /// built — a lazy list only builds what is near the viewport, and a widget
  /// that does not exist has no position to scroll to. Only once it is built
  /// can the framework place it exactly.
  Future<void> _jumpToMessage(String messageId) async {
    if (messageId.isEmpty) return;

    var key = _messageKeys[messageId];

    // Bounded. A reply to something a thousand messages back is not worth
    // pulling the whole thread down the wire for.
    for (var page = 0; key == null && page < 5 && _store.hasMore; page++) {
      await _store.loadOlder();

      if (!mounted) return;

      await WidgetsBinding.instance.endOfFrame;

      if (!mounted) return;

      key = _messageKeys[messageId];
    }

    if (key == null) {
      if (mounted) AppToast.error(context, 'That message is too far back.');

      return;
    }

    /*
     | Walk toward it until it exists.
     |
     | The offset is estimated from the row's position in the list, which is
     | only a guess while rows have different heights — but each jump makes
     | the list measure more of itself, so the next guess is better than the
     | last. Two or three passes is normally enough for the row to be built,
     | and then ensureVisible does the precise part.
     */
    for (var attempt = 0; attempt < 6 && key.currentContext == null; attempt++) {
      final row = _messageRows[messageId];

      if (row == null || !_scroll.hasClients || _rowCount < 2) return;

      final position = _scroll.position;

      // Reversed list: row zero is the oldest and sits at the far end of the
      // scroll extent, so the fraction counts backwards.
      final fraction = (_rowCount - 1 - row) / (_rowCount - 1);

      _scroll.jumpTo(
        (fraction * position.maxScrollExtent).clamp(
          position.minScrollExtent,
          position.maxScrollExtent,
        ),
      );

      await WidgetsBinding.instance.endOfFrame;

      if (!mounted) return;
    }

    final target = key.currentContext;

    if (target == null || !mounted) return;

    await Scrollable.ensureVisible(
      target,
      // A third of the way down rather than at the very top: a reply usually
      // needs the line or two above it to make sense.
      alignment: 0.35,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );

    if (!mounted) return;

    setState(() => _highlightedId = messageId);

    _highlight?.cancel();
    _highlight = Timer(const Duration(milliseconds: 1700), () {
      if (mounted) setState(() => _highlightedId = null);
    });
  }

  /// The emoji this person already has on a message, if any.
  String? _myReaction(ChatMessage message) {
    for (final reaction in message.reactions) {
      if (reaction.mine(_store.meId)) return reaction.emoji;
    }

    return null;
  }

  /// Ask which kind of delete, then do it.
  ///
  /// Two genuinely different acts behind one word, so the dialog names them
  /// rather than asking "are you sure": one edits the conversation both
  /// people are in, the other only takes it off this screen.
  Future<void> _confirmDelete(ChatMessage message) async {
    // Deleting for everyone is only ever offered on your own message — the
    // endpoint refuses anybody else's, and an option that always fails is
    // worse than one that is not there. A tombstone has nothing left to
    // remove for everyone either.
    final canDeleteForEveryone =
        message.isMine && !message.deleted && message.remoteId != null;

    final choice = await showDialog<_DeleteChoice>(
      context: context,
      builder: (context) => _DeleteDialog(forEveryone: canDeleteForEveryone),
    );

    if (choice == null || !mounted) return;

    final ok = switch (choice) {
      _DeleteChoice.everyone => await _store.deleteMessage(message),
      _DeleteChoice.me => await _store.hideMessage(message),
    };

    if (!ok && mounted) AppToast.error(context, 'Could not delete that.');
  }

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

      await _confirmAndSend(path, MessageType.file);
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

      await _confirmAndSend(picked.path, MessageType.image);
    } catch (_) {
      if (mounted) AppToast.error(context, 'Could not open that photo.');
    }
  }

  /// Show the attachment, take a caption, and only then send.
  ///
  /// Picking a file is not the same as deciding to send it — a wrong tap, a
  /// second thought, something you wanted to say first. Sending on selection
  /// turns every one of those into a message the other person has already
  /// read.
  ///
  /// Whatever is already in the composer travels across as the starting
  /// caption, and is only cleared once the send is confirmed. Discarding
  /// leaves the draft exactly where it was.
  Future<void> _confirmAndSend(String path, String type) async {
    final draft = await openAttachmentPreview(
      context,
      filePath: path,
      type: type,
      initialCaption: _controller.text.trim(),
    );

    if (draft == null || !mounted) return;

    _controller.clear();
    _scrollToLatest();

    if (type == MessageType.image) {
      await _store.sendImage(path, caption: draft.caption);
    } else {
      await _store.sendFile(path, caption: draft.caption);
    }
  }

  /// The overflow menu.
  ///
  /// A bottom sheet rather than a popup menu: a popup anchored to the top-right
  /// corner puts destructive actions under the thumb's least accurate reach,
  /// and every other menu in the app is a sheet.
  /// Set while this thread is a group, and the switch behind most of what
  /// this screen renders differently.
  GroupInfo? get _group => _store.conversation?.group;

  /*
  | Whether this thread is a group, answerable before it has loaded.
  |
  | [_group] is null for the first moment of every group screen, while the
  | conversation is still being fetched. Tapping the title in that window used
  | to fall through to a user profile for an empty id — the "not found" page
  | that went away if you came back and tapped again. A group is opened
  | without a peer id, so the absence of one settles it immediately.
  */
  bool get _isGroup => _group != null || widget.userId.isEmpty;

  Future<void> _openMenu() async {
    // A group has no profile to view and nobody to block: those are acts
    // against a person, and the menu offers what the thread actually has.
    if (_isGroup) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => GroupInfoScreen(store: _store, meId: _store.meId),
        ),
      );

      return;
    }

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
                    name: _store.conversation?.displayName ??
                        person?.name ??
                        widget.name,
                    username: person?.username ?? widget.username,
                    avatarUrl: _store.conversation?.displayAvatarUrl ??
                        person?.avatarUrl ??
                        widget.avatarUrl,
                    initials: _store.conversation?.displayInitials ??
                        person?.initials ??
                        widget.initials,
                    // A group says how many are in it where a direct thread
                    // says whether one person is online — presence is about a
                    // person, and a room does not have one.
                    // Typing wins over both, and names who it is in a group.
                    presence: _group == null
                        ? (_store.peerPresenceLabel ?? widget.presence)
                        : (_store.typingLabel ??
                            (_group!.membersCount == 1
                                ? '1 member'
                                : '${_group!.membersCount} members')),
                    typing: _store.peerTyping,
                    onMenu: _openMenu,
                    onTapPerson: _openProfile,
                  ),
                  const _ConnectionStrip(),

                  // Directly under the header, above everything else in the
                  // thread — a pin that scrolls away with the messages is
                  // not a pin.
                  if (_store.conversation?.pinnedMessage != null)
                    _PinnedBanner(
                      message: _store.conversation!.pinnedMessage!,
                      onUnpin: () => _pin(null),
                      // The banner is a shortcut back to the message, not
                      // just a copy of it.
                      onTap: () => _jumpToMessage(
                        _store.conversation!.pinnedMessage!.remoteId ?? '',
                      ),
                    ),
                  if (_store.isRequest && !_store.blocked)
                    _RequestBanner(
                      name: person?.name ?? widget.name,
                      onAccept: _accept,
                      onDecline: _decline,
                    ),
                  Expanded(
                    child: Stack(
                      // The list takes the whole area; only the button floats.
                      fit: StackFit.expand,
                      children: [
                        _body(),
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 10,
                          child: Center(
                            child: _JumpToLatest(
                              visible: !_atBottom && !_store.loading,
                              unseen: _unseen,
                              onTap: _scrollToLatest,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_store.awaitingAcceptance &&
                      !_store.isRequest &&
                      !_store.blocked)
                    const _PendingNotice(),

                  // No composer at all when blocked. A text field that takes
                  // input and then fails with a 403 is a worse way to find
                  // out than a line of text that says so up front.
                  if (_store.blocked)
                    const _BlockedNotice()
                  else ...[
                    if (_store.replyingTo != null)
                      _ReplyStrip(
                        message: _store.replyingTo!,
                        onCancel: _store.cancelReply,
                      ),
                    AnimatedBuilder(
                      animation: _voice,
                      builder: (context, _) => _Composer(
                        controller: _controller,
                        focus: _focus,
                        canSend: _canSend,
                        onSend: _send,
                        onAttach: _attach,
                        recorder: _voice,
                        slide: _slide,
                        lockProgress: _lockProgress,
                        onMicDown: _startRecording,
                        onMicMove: _onMicMove,
                        onMicUp: _finishRecording,
                        onMicTap: _micHint,
                        onCancel: _cancelRecording,
                        onStopLocked: _sendRecording,
                      ),
                    ),
                  ],
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

    /*
     | Who wrote what, in a group.
     |
     | Built once per list rather than looked up per bubble, and empty in a
     | direct thread — where there is only one person it could be, and naming
     | them above every message would be noise.
     */
    final senders = <String, ChatPerson>{
      for (final member in _group?.members ?? const <ChatPerson>[])
        member.id: member,
    };

    // Rebuilt from scratch: a message that has left the window must not keep
    // a row index pointing at whatever now sits there.
    _messageKeys.clear();
    _messageRows.clear();

    for (final group in groups) {
      final day = group.messages.first.sentAt.toLocal();

      final newDay = lastDay == null ||
          day.year != lastDay.year ||
          day.month != lastDay.month ||
          day.day != lastDay.day;

      if (newDay) {
        rows.add(ChatDateChip(label: chatDateLabel(day)));
        lastDay = day;
      }

      // Keyed on the first message of the run, which is stable — the run can
      // grow as more arrive without the key changing underneath it.
      final key =
          _groupKeys.putIfAbsent(group.messages.first.id, () => GlobalKey());

      // Every message in the run points at the row it is drawn in: the key
      // for the precise scroll, the index for the estimate that gets the row
      // built in the first place.
      for (final message in group.messages) {
        final id = message.remoteId;

        if (id == null) continue;

        _messageKeys[id] = key;
        _messageRows[id] = rows.length;
      }

      // A system line is scenery, not conversation: no bubble, no avatar, no
      // long-press menu.
      if (group.messages.first.isSystem) {
        for (final message in group.messages) {
          rows.add(SystemNote(message: message));
        }

        continue;
      }

      final failed = group.last.failed;
      final sender = senders[group.messages.first.senderId ?? ''];

      rows.add(
        failed
            // A failed message keeps its bubble and gains a way back. Tapping
            // resends with the same client id, so if the first attempt did
            // reach the server this returns that message rather than posting
            // a second copy.
            ? GestureDetector(
                key: key,
                onTap: () => _store.retry(group.last),
                behavior: HitTestBehavior.opaque,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    MessageGroupView(
                      group: group,
                      meId: _store.meId,
                      onLongPress: _onMessageLongPress,
                      onReactionTap: _store.react,
                      onQuoteTap: _onQuoteTap,
                      highlightedId: _highlightedId,
                      sender: sender,
                    ),
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
            : MessageGroupView(
                key: key,
                group: group,
                meId: _store.meId,
                onLongPress: _onMessageLongPress,
                onReactionTap: _store.react,
                onQuoteTap: _onQuoteTap,
                highlightedId: _highlightedId,
                sender: sender,
              ),
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

    // The loading row at the top shifts everything below it, so the recorded
    // indices are only right once the whole list is assembled.
    if (_store.loadingOlder) {
      for (final id in _messageRows.keys.toList()) {
        _messageRows[id] = _messageRows[id]! + 1;
      }
    }

    _rowCount = rows.length;

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

enum _DeleteChoice { everyone, me }

/// Which kind of delete.
///
/// Stacked full-width rows rather than the usual pair of text buttons in the
/// corner: three choices where two of them start with the same word need
/// room to be read, and "Delete for everyone" squeezed beside "Delete for me"
/// is how people tap the wrong one.
class _DeleteDialog extends StatelessWidget {
  const _DeleteDialog({required this.forEveryone});

  /// Whether deleting for everyone is on the table at all.
  final bool forEveryone;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.canvasRaised,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: AppColors.glassBorder),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 34),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(22, 22, 22, 6),
            child: Text(
              'Delete message?',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 16),
            child: Text(
              forEveryone
                  ? 'Delete it for both of you, or just take it off your own '
                      'screen.'
                  : 'It will be removed from your screen only. They keep '
                      'their copy.',
              style: const TextStyle(
                fontSize: 13,
                height: 1.45,
                color: AppColors.textMuted,
              ),
            ),
          ),
          if (forEveryone)
            _DeleteOption(
              label: 'Delete for everyone',
              // Said plainly, because it cannot be undone and the other
              // person will see that something was there.
              note: 'They will see that a message was deleted',
              danger: true,
              onTap: () =>
                  Navigator.of(context).pop(_DeleteChoice.everyone),
            ),
          _DeleteOption(
            label: 'Delete for me',
            note: 'Removed from this chat on your devices',
            onTap: () => Navigator.of(context).pop(_DeleteChoice.me),
          ),
          _DeleteOption(
            label: 'Cancel',
            muted: true,
            onTap: () => Navigator.of(context).pop(),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _DeleteOption extends StatelessWidget {
  const _DeleteOption({
    required this.label,
    required this.onTap,
    this.note,
    this.danger = false,
    this.muted = false,
  });

  final String label;
  final String? note;
  final bool danger;
  final bool muted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tint = danger
        ? AppColors.alertRed
        : muted
            ? AppColors.textMuted
            : AppColors.textPrimary;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.fromLTRB(22, note == null ? 13 : 11, 22, 11),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
                color: tint,
              ),
            ),
            if (note != null) ...[
              const SizedBox(height: 2),
              Text(
                note!,
                style: TextStyle(
                  fontSize: 11.5,
                  color: AppColors.textMuted.withValues(alpha: 0.85),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Back to the newest message.
///
/// Only while you are away from it. A control that is always on screen is one
/// more thing sitting over the conversation, and for most of a session it
/// would do nothing.
class _JumpToLatest extends StatelessWidget {
  const _JumpToLatest({
    required this.visible,
    required this.unseen,
    required this.onTap,
  });

  final bool visible;

  /// Messages from the other person since you scrolled away. Zero draws a
  /// plain circle — a "0" badge is a badge that should not be there.
  final int unseen;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      // Hidden means untappable. An invisible button that still takes taps
      // steals them from the message underneath it.
      ignoring: !visible,
      child: AnimatedSlide(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        offset: visible ? Offset.zero : const Offset(0, 0.55),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 180),
          opacity: visible ? 1 : 0,
          child: GestureDetector(
            onTap: onTap,
            behavior: HitTestBehavior.opaque,
            child: Container(
              height: 40,
              padding: EdgeInsets.symmetric(horizontal: unseen > 0 ? 14 : 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                color: AppColors.canvasRaised,
                border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.45),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (unseen > 0) ...[
                    Container(
                      constraints: const BoxConstraints(minWidth: 20),
                      height: 20,
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        gradient: AppColors.safeGradient,
                      ),
                      child: Text(
                        // Past a certain point the exact number stops being
                        // information and starts being a wall of digits.
                        unseen > 99 ? '99+' : '$unseen',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF04121F),
                        ),
                      ),
                    ),
                    const SizedBox(width: 7),
                  ],
                  const Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 22,
                    color: AppColors.aqua,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The pinned message, held above the thread.
///
/// Shared by both people, unlike a star: either can set or clear it, and both
/// banners move together over the socket. That is the whole reason it exists
/// — it is for the address, the flight number, the date the two of you keep
/// scrolling back for, and a private bookmark would not serve that.
class _PinnedBanner extends StatelessWidget {
  const _PinnedBanner({
    required this.message,
    required this.onUnpin,
    required this.onTap,
  });

  final ChatMessage message;
  final VoidCallback onUnpin;
  final VoidCallback onTap;

  String get _preview {
    if (message.deleted) return 'Message deleted';

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
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
        decoration: BoxDecoration(
          color: AppColors.canvasRaised.withValues(alpha: 0.92),
          border: Border(
            bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
          ),
        ),
        child: Row(
          children: [
            const Icon(Icons.push_pin_rounded, size: 15, color: AppColors.aqua),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Pinned message',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
                      color: AppColors.aqua,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _preview,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
            // Unpinning from the banner rather than only from the message: the
            // pinned message may be a thousand rows back, and needing to find
            // it again to release it would make the pin feel permanent.
            IconButton(
              onPressed: onUnpin,
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.close_rounded,
                  size: 17, color: AppColors.textMuted),
              tooltip: 'Unpin',
            ),
          ],
        ),
      ),
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

/// The message being replied to, sitting above the composer.
///
/// Uses the same [QuotedStrip] the bubble does, so what you see while writing
/// is what lands in the conversation.
class _ReplyStrip extends StatelessWidget {
  const _ReplyStrip({required this.message, required this.onCancel});

  final ChatMessage message;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
      color: AppColors.canvas.withValues(alpha: 0.72),
      child: QuotedStrip(
        quote: QuotedMessage(
          id: message.remoteId ?? '',
          isMine: message.isMine,
          body: message.body,
          type: message.type,
          deleted: message.deleted,
        ),
        onClose: onCancel,
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
    required this.recorder,
    required this.slide,
    required this.lockProgress,
    required this.onMicDown,
    required this.onMicMove,
    required this.onMicUp,
    required this.onMicTap,
    required this.onCancel,
    required this.onStopLocked,
  });

  final TextEditingController controller;
  final FocusNode focus;
  final bool canSend;
  final VoidCallback onSend;
  final VoidCallback onAttach;

  final VoiceRecorder recorder;
  final double slide;
  final double lockProgress;
  final VoidCallback onMicDown;
  final void Function(Offset offset) onMicMove;
  final VoidCallback onMicUp;
  final VoidCallback onMicTap;
  final VoidCallback onCancel;
  final VoidCallback onStopLocked;

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
                child: recorder.isActive
                    ? VoiceRecorderStrip(
                        recorder: recorder,
                        slide: slide,
                        onCancel: onCancel,
                      )
                    : _field(),
              ),
              const SizedBox(width: 9),

              // One position, three jobs. The microphone must keep its place
              // in the tree while recording — it owns the long press.
              if (canSend)
                _SendButton(enabled: true, onTap: onSend)
              else
                _MicButton(
                  recorder: recorder,
                  lockProgress: lockProgress,
                  onDown: onMicDown,
                  onMove: onMicMove,
                  onUp: onMicUp,
                  onTap: onMicTap,
                  onStopLocked: onStopLocked,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field() {
    return Container(
      constraints: const BoxConstraints(minHeight: 46),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(23),
        color: Colors.white.withValues(alpha: 0.06),
        border: Border.all(color: Colors.white.withValues(alpha: 0.11)),
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
                // Grows to five lines then scrolls, so a long message never
                // swallows the conversation.
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
          // No second camera button in the field. Everything that attaches
          // lives behind +, so the text field is for typing and nothing else.
        ],
      ),
    );
  }
}

/// Hold to record.
///
/// Also the stop button once locked, which is why it is one widget rather
/// than two swapped in and out: the gesture must survive the transition into
/// hands-free mode without the detector being rebuilt underneath the finger.
class _MicButton extends StatelessWidget {
  const _MicButton({
    required this.recorder,
    required this.lockProgress,
    required this.onDown,
    required this.onMove,
    required this.onUp,
    required this.onTap,
    required this.onStopLocked,
  });

  final VoiceRecorder recorder;
  final double lockProgress;
  final VoidCallback onDown;
  final void Function(Offset offset) onMove;
  final VoidCallback onUp;
  final VoidCallback onTap;
  final VoidCallback onStopLocked;

  @override
  Widget build(BuildContext context) {
    final recording = recorder.isActive;
    final locked = recorder.isLocked;

    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        // The lock target, floating above the button while the finger is
        // still down. Positioned outside the button's own bounds, which is
        // why the Stack does not clip.
        if (recording && !locked)
          Positioned(
            bottom: 54,
            child: VoiceLockChip(progress: lockProgress),
          ),

        GestureDetector(
          // A locked recording is stopped by a tap, not a press.
          onTap: locked ? onStopLocked : onTap,
          onLongPressStart: locked ? null : (_) => onDown(),
          onLongPressMoveUpdate:
              locked ? null : (details) => onMove(details.offsetFromOrigin),
          onLongPressEnd: locked ? null : (_) => onUp(),

          // Covers the finger leaving the screen edge or the press being
          // interrupted — without it a recording can be left running with
          // nothing on screen to stop it.
          onLongPressCancel: locked ? null : onUp,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            width: recording ? 52 : 46,
            height: recording ? 52 : 46,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: recording ? AppColors.safeGradient : null,
              color: recording ? null : Colors.white.withValues(alpha: 0.06),
              boxShadow: recording
                  ? [
                      BoxShadow(
                        color: AppColors.mint.withValues(alpha: 0.35),
                        blurRadius: 20,
                        offset: const Offset(0, 5),
                      ),
                    ]
                  : const [],
            ),
            child: Icon(
              locked
                  ? Icons.stop_rounded
                  : recording
                      ? Icons.mic_rounded
                      : Icons.mic_none_rounded,
              size: recording ? 24 : 21,
              color: recording
                  ? const Color(0xFF04121F)
                  : AppColors.textMuted.withValues(alpha: 0.9),
            ),
          ),
        ),
      ],
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
