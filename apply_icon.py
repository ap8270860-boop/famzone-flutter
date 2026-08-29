#!/usr/bin/env python3
"""One icon for chat, everywhere.

`forum` is two overlapping bubbles: noisy at nav-bar size, and it collides
with the unread badge on its top-right corner. Every other tab in the bar is
a single solid silhouette — home, shield, person — so a single bubble is the
shape that belongs there.

Run from the famzone-flutter repo root. Idempotent.
"""

import io
import sys

changed = []

EDITS = [
    (
        'lib/features/shell/presentation/app_shell.dart',
        [(
            "    _TabSpec(Icons.forum_rounded, Icons.forum_outlined, 'Chats'),",
            "    _TabSpec(Icons.chat_bubble_rounded,\n"
            "        Icons.chat_bubble_outline_rounded, 'Chats'),",
        )],
    ),
    (
        'lib/features/chat/presentation/inbox_screen.dart',
        [(
            "                      ? Icons.mark_email_unread_outlined\n"
            "                      : Icons.forum_outlined,",
            "                      ? Icons.mark_email_unread_outlined\n"
            "                      : Icons.chat_bubble_outline_rounded,",
        )],
    ),
    (
        'lib/features/chat/presentation/chat_screen.dart',
        [(
            "            Icon(Icons.forum_outlined,",
            "            Icon(Icons.chat_bubble_outline_rounded,",
        )],
    ),
]

for path, pairs in EDITS:
    s = io.open(path, encoding='utf-8').read()

    if 'Icons.forum' not in s:
        print(f'{path}: already patched')
        continue

    for old, new in pairs:
        if old not in s:
            sys.exit(f'{path}: anchor missing ->\n{old}')

        s = s.replace(old, new, 1)

    io.open(path, 'w', encoding='utf-8', newline='').write(s)
    changed.append(path)
    print(f'{path}: chat_bubble')

print('\ndone: ' + (', '.join(changed) if changed else 'nothing to do'))
