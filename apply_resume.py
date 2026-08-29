#!/usr/bin/env python3
"""Phase 2 follow-up — wake the socket on resume, and show the unread badge.

Run from the famzone-flutter repo root. Idempotent.
"""

import io
import sys

changed = []


def read(p):
    return io.open(p, encoding='utf-8').read()


def write(p, s):
    io.open(p, 'w', encoding='utf-8', newline='').write(s)


def patch(path, pairs, marker):
    s = read(path)

    if marker in s:
        print(f'{path}: already patched')

        return

    for old, new in pairs:
        if old not in s:
            sys.exit(f'{path}: anchor missing ->\n{old[:200]}')

        s = s.replace(old, new, 1)

    write(path, s)
    changed.append(path)
    print(f'{path}: patched')


# ============================================================== app_shell

P = 'lib/features/shell/presentation/app_shell.dart'

patch(P, [
    (
        "import '../../chat/state/realtime_client.dart';",
        "import '../../chat/state/chat_store.dart';\n"
        "import '../../chat/state/realtime_client.dart';",
    ),
    (
        "class _AppShellState extends State<AppShell> {",
        "class _AppShellState extends State<AppShell> with WidgetsBindingObserver {",
    ),
    (
        """  @override
  void initState() {
    super.initState();

    // Opens the websocket and joins this user's mailbox channel, so the
    // unread badge stays right whether or not a chat screen is open. A no-op
    // when no Reverb key is configured.
    RealtimeClient.instance.start();
  }""",
        """  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);

    // Opens the websocket and joins this user's mailbox channel, so the
    // unread badge stays right whether or not a chat screen is open. A no-op
    // when no Reverb key is configured.
    RealtimeClient.instance.start();

    // The badge has to be right before anybody opens Messages. Without this
    // the only way to find out you have unread messages is to go looking for
    // them, which rather defeats the point of a badge.
    ChatStore.instance.refreshBadge();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;

    // Dart timers are frozen while the process is suspended, so a socket that
    // died overnight sits in a pending retry that fires whenever it gets
    // around to it. Poking it here is the difference between a chat that is
    // live the moment the phone is unlocked and one that takes half a minute
    // to notice it is alone.
    RealtimeClient.instance.resume();
    ChatStore.instance.refreshBadge();
  }""",
    ),
], marker='didChangeAppLifecycleState')


# ============================================================= app_drawer

P = 'lib/features/shell/presentation/app_drawer.dart'

patch(P, [
    (
        "import '../../chat/presentation/inbox_screen.dart';",
        "import '../../chat/presentation/inbox_screen.dart';\n"
        "import '../../chat/state/chat_store.dart';",
    ),
    (
        """                    _item(
                      context,
                      Icons.forum_outlined,
                      'Messages',
                      () => _push(context, const InboxScreen()),
                    ),""",
        """                    // Rebuilt from the store rather than passed in, so a
                    // message arriving over the socket updates the count even
                    // while the drawer is open.
                    AnimatedBuilder(
                      animation: ChatStore.instance,
                      builder: (context, _) => _item(
                        context,
                        Icons.forum_outlined,
                        'Messages',
                        () => _push(context, const InboxScreen()),
                        badge: ChatStore.instance.unread > 0
                            ? '${ChatStore.instance.unread}'
                            : null,
                      ),
                    ),""",
    ),
], marker='ChatStore.instance.unread')


print('\ndone: ' + (', '.join(changed) if changed else 'nothing to do'))
