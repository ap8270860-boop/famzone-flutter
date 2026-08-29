#!/usr/bin/env python3
"""Put the family-circle icon back on the Chats tab.

Only the nav bar. The empty states inside chat keep the single bubble, where
"no messages yet" is what is being said — a group icon there would be about
the wrong thing.

Run from the famzone-flutter repo root. Idempotent.
"""

import io
import sys

P = 'lib/features/shell/presentation/app_shell.dart'
s = io.open(P, encoding='utf-8').read()

if 'Icons.groups_rounded' in s:
    sys.exit(f'{P}: already patched')

OLD = ("    _TabSpec(Icons.chat_bubble_rounded,\n"
       "        Icons.chat_bubble_outline_rounded, 'Chats'),")

NEW = "    _TabSpec(Icons.groups_rounded, Icons.groups_outlined, 'Chats'),"

if OLD not in s:
    sys.exit(f'{P}: Chats tab spec not found')

io.open(P, 'w', encoding='utf-8', newline='').write(s.replace(OLD, NEW, 1))
print(f'{P}: family-circle icon restored on Chats')
