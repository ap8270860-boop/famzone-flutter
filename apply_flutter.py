#!/usr/bin/env python3
"""Phase 2 (Flutter) — put the websocket underneath the chat.

Run from the famzone-flutter repo root, after:
    flutter pub add web_socket_channel

Idempotent.
"""

import io
import sys

changed = []


def read(p):
    return io.open(p, encoding='utf-8').read()


def write(p, s):
    io.open(p, 'w', encoding='utf-8', newline='').write(s)


def patch(path, pairs, marker):
    """Apply (old, new) pairs to a file unless `marker` is already in it."""
    s = read(path)

    if marker in s:
        print(f'{path}: already patched')

        return False

    for old, new in pairs:
        if old not in s:
            sys.exit(f'{path}: anchor missing ->\n{old[:160]}')

        s = s.replace(old, new, 1)

    write(path, s)
    changed.append(path)

    return True


# ============================================================ app_config

P = 'lib/core/config/app_config.dart'

CONFIG = """
  /// The Reverb application key, from the API's .env.
  ///
  ///   flutter run --dart-define=REVERB_KEY=xxxxxxxx
  ///
  /// Empty by default, and that is a feature: with no key the realtime layer
  /// stays dormant and the app behaves exactly as it did before websockets
  /// existed — messages still send over HTTP, screens still refresh. A build
  /// can ship before the socket server is ready.
  static const String reverbKey = String.fromEnvironment('REVERB_KEY');

  /// Where the websocket lives. Behind nginx on 443 in production; point it
  /// at the machine running `php artisan reverb:start` in development:
  ///
  ///   --dart-define=REVERB_HOST=10.0.2.2
  ///   --dart-define=REVERB_PORT=8080
  ///   --dart-define=REVERB_TLS=false
  static const String reverbHost = String.fromEnvironment(
    'REVERB_HOST',
    defaultValue: 'ws.sfamily.co',
  );

  static const int reverbPort = int.fromEnvironment(
    'REVERB_PORT',
    defaultValue: 443,
  );

  static const bool reverbTls = bool.fromEnvironment(
    'REVERB_TLS',
    defaultValue: true,
  );

  /// Whether to open a socket at all.
  static bool get realtimeEnabled => reverbKey.isNotEmpty;

  /// How long to wait on any single request before giving up.
  static const Duration requestTimeout = Duration(seconds: 15);
}
"""

patch(P, [(
    """
  /// How long to wait on any single request before giving up.
  static const Duration requestTimeout = Duration(seconds: 15);
}
""",
    CONFIG,
)], marker='reverbKey')


# ============================================================= ChatStore

P = 'lib/features/chat/state/chat_store.dart'

STORE_EVENT = """
  /// Fold a live `inbox.updated` frame into the list.
  ///
  /// The payload is the same conversation summary the inbox endpoint
  /// returns, so this is the socket doing what a refresh would have done —
  /// without the refresh.
  void applyInboxEvent(Map<String, dynamic> json) {
    final conversation = Conversation.fromJson(json, _meId);

    if (conversation.id.isEmpty) return;

    if (conversation.isRequest) {
      // A request belongs in the other tab, and must not be counted as
      // unread — it is a decision waiting, not a conversation waiting.
      _requests = [
        conversation,
        ..._requests.where((t) => t.id != conversation.id),
      ];

      _threads = _threads.where((t) => t.id != conversation.id).toList();
      _requestCount = _requests.length;

      notifyListeners();

      return;
    }

    absorb(conversation);

    // Report the arrival straight away, so the sender's second tick appears
    // without the recipient touching their phone.
    unawaited(_acknowledge(conversation));
  }

  Future<void> _acknowledge(Conversation thread) async {
    final last = thread.lastMessage;

    if (last == null || last.isMine || last.remoteId == null) return;
    if (thread.myDeliveredSeq >= last.seq) return;

    try {
      await _api.markDelivered(thread.id, last.remoteId!);
    } catch (_) {
      // Best effort. The next refresh tries again.
    }
  }

  /// Drop everything on sign-out."""

patch(P, [
    (
        "import 'package:flutter/foundation.dart';",
        "import 'dart:async';\n\nimport 'package:flutter/foundation.dart';",
    ),
    ("\n  /// Drop everything on sign-out.", STORE_EVENT),
], marker='applyInboxEvent')


# ===================================================== ConversationStore

P = 'lib/features/chat/state/conversation_store.dart'

REALTIME = """
  /*
  |----------------------------------------------------------------------------
  | Realtime
  |----------------------------------------------------------------------------
  */

  /// Handle a frame on this conversation's channel.
  ///
  /// Subscribed for exactly as long as the screen is open, which is what
  /// keeps one thread's traffic out of every other screen: a conversation
  /// nobody is looking at has no subscription to deliver anything to.
  void _onRealtime(String event, Map<String, dynamic> data) {
    if (event != 'message.sent') return;

    final message = ChatMessage.fromJson(data, _meId)
        .copyWith(state: DeliveryState.sent);

    // Ignore anything without a sequence number — it cannot be placed.
    if (message.seq <= 0) return;

    // Our own echo comes back too. It is keyed on the same client id as the
    // optimistic bubble already on screen, so this resolves to that bubble
    // rather than adding a second one. Broadcasting to everyone and letting
    // the client key on client_uuid is what makes multi-device support a
    // change of mind rather than a rewrite.
    _pending.removeWhere((p) => p.id == message.id);
    _upsert(message);

    // The screen is open, so anything arriving on it has been seen.
    if (!message.isMine) unawaited(_markRead());

    _rebuild();
  }

  /// Insert or replace by sequence number, keeping the list ordered."""

patch(P, [
    (
        "import 'package:flutter/foundation.dart';",
        "import 'dart:async';\n\nimport 'package:flutter/foundation.dart';",
    ),
    (
        "import 'chat_store.dart';",
        "import 'chat_store.dart';\nimport 'realtime_client.dart';",
    ),
    (
        """      _conversation = Conversation.fromJson(res.dataMap, _meId);
      conversationId = _conversation!.id;

      await _fetch();""",
        """      _conversation = Conversation.fromJson(res.dataMap, _meId);
      conversationId = _conversation!.id;

      // Subscribe before the first fetch, not after. Anything that lands in
      // the gap between them arrives on the socket and is merged by sequence
      // number; the other order drops it silently.
      unawaited(
        RealtimeClient.instance.joinConversation(conversationId!, _onRealtime),
      );

      await _fetch();""",
    ),
    ("\n  /// Insert or replace by sequence number, keeping the list ordered.",
     REALTIME),
    (
        """  @override
  void dispose() {
    _disposed = true;
    _api.dispose();""",
        """  @override
  void dispose() {
    _disposed = true;

    final id = conversationId;

    if (id != null) unawaited(RealtimeClient.instance.leaveConversation(id));

    _api.dispose();""",
    ),
], marker='_onRealtime')


# ============================================================= app_shell

P = 'lib/features/shell/presentation/app_shell.dart'

patch(P, [
    (
        "import '../../home/presentation/home_screen.dart';",
        "import '../../chat/state/realtime_client.dart';\n"
        "import '../../home/presentation/home_screen.dart';",
    ),
    (
        """  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(""",
        """  @override
  void initState() {
    super.initState();

    // Opens the websocket and joins this user's mailbox channel, so the
    // unread badge stays right whether or not a chat screen is open. A no-op
    // when no Reverb key is configured.
    RealtimeClient.instance.start();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(""",
    ),
], marker='RealtimeClient')


# =========================================================== chat_screen

P = 'lib/features/chat/presentation/chat_screen.dart'

STRIP = '''
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

class _Header extends StatelessWidget {'''

patch(P, [
    (
        "import '../state/conversation_store.dart';",
        "import '../state/conversation_store.dart';\n"
        "import '../state/realtime_client.dart';",
    ),
    (
        """                  if (_store.isRequest)""",
        """                  const _ConnectionStrip(),
                  if (_store.isRequest)""",
    ),
    ("\nclass _Header extends StatelessWidget {", STRIP),
], marker='_ConnectionStrip')


print('\ndone: ' + (', '.join(changed) if changed else 'nothing to do'))
