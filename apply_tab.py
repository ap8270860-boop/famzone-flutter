#!/usr/bin/env python3
"""Chats becomes a primary tab, with a live badge on the nav bar.

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
            sys.exit(f'{path}: anchor missing ->\n{old[:220]}')

        s = s.replace(old, new, 1)

    write(path, s)
    changed.append(path)
    print(f'{path}: patched')


# ============================================================== app_shell

P = 'lib/features/shell/presentation/app_shell.dart'

patch(P, [
    (
        "import '../../chat/state/chat_store.dart';",
        "import '../../chat/presentation/inbox_screen.dart';\n"
        "import '../../chat/state/chat_store.dart';",
    ),

    # --- tab spec ------------------------------------------------------
    (
        "    _TabSpec(Icons.groups_rounded, Icons.groups_outlined, 'Circle'),",
        "    _TabSpec(Icons.forum_rounded, Icons.forum_outlined, 'Chats'),",
    ),

    # --- the tab itself ------------------------------------------------
    (
        """            const PlaceholderTab(
              icon: Icons.groups_rounded,
              title: 'Your circle',
              message: 'Family and friend groups land here next.',
            ),""",
        """            // Kept alive by the IndexedStack, so returning to it does
            // not refetch — and it does not need to, because the socket has
            // been updating it the whole time it was off screen.
            const InboxScreen(embedded: true),""",
    ),

    # --- nav bar, rebuilt from the store -------------------------------
    (
        """        bottomNavigationBar: _GlassNavBar(
          tabs: _tabs,
          index: _index,
          onChanged: (i) => setState(() => _index = i),
          onSos: () => _confirmSos(context),
        ),""",
        """        // Rebuilt from the store so the badge changes the moment a
        // message arrives, on whatever tab the user happens to be looking at.
        bottomNavigationBar: AnimatedBuilder(
          animation: ChatStore.instance,
          builder: (context, _) => _GlassNavBar(
            tabs: _tabs,
            index: _index,
            badges: [0, ChatStore.instance.unread, 0, 0],
            onChanged: _select,
            onSos: () => _confirmSos(context),
          ),
        ),""",
    ),

    # --- tab change ----------------------------------------------------
    (
        """  /// SOS is destructive and irreversible once sent, so it always confirms.""",
        """  void _select(int index) {
    setState(() => _index = index);

    // Opening Chats reconciles with the server. The socket keeps the list
    // live while the app runs, but anything that happened during a dropped
    // connection is only caught by asking.
    if (index == 1) ChatStore.instance.refresh();
  }

  /// SOS is destructive and irreversible once sent, so it always confirms.""",
    ),

    # --- nav bar widget ------------------------------------------------
    (
        """  const _GlassNavBar({
    required this.tabs,
    required this.index,
    required this.onChanged,
    required this.onSos,
  });

  final List<_TabSpec> tabs;
  final int index;
  final ValueChanged<int> onChanged;
  final VoidCallback onSos;""",
        """  const _GlassNavBar({
    required this.tabs,
    required this.index,
    required this.badges,
    required this.onChanged,
    required this.onSos,
  });

  final List<_TabSpec> tabs;
  final int index;

  /// One count per tab; zero draws nothing.
  final List<int> badges;

  final ValueChanged<int> onChanged;
  final VoidCallback onSos;""",
    ),

    # --- the item, with its badge --------------------------------------
    (
        """  Widget _item(int i) {
    final selected = index == i;
    final tab = tabs[i];

    return Expanded(
      child: GestureDetector(
        onTap: () => onChanged(i),
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              selected ? tab.active : tab.inactive,
              size: 29,
              color: selected ? AppColors.mint : AppColors.navInactive,
            ),
            const SizedBox(height: 4),""",
        """  Widget _item(int i) {
    final selected = index == i;
    final tab = tabs[i];
    final badge = i < badges.length ? badges[i] : 0;

    return Expanded(
      child: GestureDetector(
        onTap: () => onChanged(i),
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // The badge overhangs the icon rather than sitting beside it, so
            // a count appearing never shifts the row's layout.
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(
                  selected ? tab.active : tab.inactive,
                  size: 29,
                  color: selected ? AppColors.mint : AppColors.navInactive,
                ),
                if (badge > 0)
                  Positioned(
                    top: -3,
                    right: -8,
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 18),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        color: AppColors.alertRed,
                        // A ring in the bar's own colour, so the badge reads
                        // as sitting on top of the icon rather than merging
                        // into it.
                        border: Border.all(
                          color: AppColors.barSurface,
                          width: 2,
                        ),
                      ),
                      child: Text(
                        badge > 99 ? '99+' : '$badge',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 9.5,
                          height: 1.25,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),""",
    ),
], marker='InboxScreen(embedded: true)')


# ============================================================= app_drawer

# Chats is a primary destination now. Leaving a duplicate in the drawer means
# two ways to the same place, one of which pushes a second copy over the tab.
P = 'lib/features/shell/presentation/app_drawer.dart'
s = read(P)

if 'InboxScreen' not in s:
    print(f'{P}: already patched')
else:
    OLD_ITEM = """                    // Rebuilt from the store rather than passed in, so a
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
                    ),
"""

    if OLD_ITEM not in s:
        sys.exit(f'{P}: Messages drawer item not found')

    s = s.replace(OLD_ITEM, '', 1)
    s = s.replace("import '../../chat/presentation/inbox_screen.dart';\n", '', 1)
    s = s.replace("import '../../chat/state/chat_store.dart';\n", '', 1)

    write(P, s)
    changed.append(P)
    print(f'{P}: Messages removed — it is a primary tab now')


print('\ndone: ' + (', '.join(changed) if changed else 'nothing to do'))
