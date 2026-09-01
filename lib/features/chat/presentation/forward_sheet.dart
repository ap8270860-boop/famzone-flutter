import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../people/presentation/widgets/person_avatar.dart';
import '../data/chat_models.dart';
import '../state/chat_store.dart';

/// Choose which chats to forward into.
///
/// Multi-select with an explicit Send, rather than tap-to-send. Forwarding is
/// the one action here that puts a message in front of somebody who was not
/// part of the conversation, and a single mistaken tap doing that irreversibly
/// is the wrong trade.
Future<List<String>?> showForwardSheet(BuildContext context) {
  return showModalBottomSheet<List<String>>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => const _ForwardSheet(),
  );
}

class _ForwardSheet extends StatefulWidget {
  const _ForwardSheet();

  @override
  State<_ForwardSheet> createState() => _ForwardSheetState();
}

class _ForwardSheetState extends State<_ForwardSheet> {
  final ChatStore _store = ChatStore.instance;
  final Set<String> _selected = {};

  /// Matches ForwardRequest::MAX_TARGETS. Capped because forwarding is the
  /// mechanic every chain message rides on.
  static const int _max = 10;

  @override
  void initState() {
    super.initState();

    // The list may never have been loaded if the user came straight from a
    // profile into a chat without opening Chats.
    if (!_store.loaded) _store.refresh();
  }

  void _toggle(String id) {
    setState(() {
      if (_selected.contains(id)) {
        _selected.remove(id);
      } else if (_selected.length < _max) {
        _selected.add(id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height * 0.7;

    return Container(
      height: height,
      margin: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        color: AppColors.canvasRaised,
        border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
      ),
      child: AnimatedBuilder(
        animation: _store,
        builder: (context, _) {
          // Forwarding into a blocked or pending thread would fail on the
          // server, so those never appear as options.
          final threads = _store.threads
              .where((t) => !t.blocked && t.other != null)
              .toList();

          return Column(
            children: [
              Container(
                width: 38,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  color: Colors.white.withValues(alpha: 0.16),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 2, 20, 10),
                child: Row(
                  children: [
                    const Text(
                      'Forward to',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const Spacer(),
                    if (_selected.isNotEmpty)
                      Text(
                        '${_selected.length} of $_max',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textMuted,
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: _store.loading
                    ? const Center(
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : threads.isEmpty
                        ? const Center(
                            child: Padding(
                              padding: EdgeInsets.symmetric(horizontal: 40),
                              child: Text(
                                'No other chats to forward to yet.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: AppColors.textMuted,
                                ),
                              ),
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.only(bottom: 8),
                            itemCount: threads.length,
                            itemBuilder: (context, i) => _Row(
                              thread: threads[i],
                              selected: _selected.contains(threads[i].id),
                              onTap: () => _toggle(threads[i].id),
                            ),
                          ),
              ),
              _SendBar(
                count: _selected.length,
                onSend: _selected.isEmpty
                    ? null
                    : () => Navigator.of(context).pop(_selected.toList()),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.thread,
    required this.selected,
    required this.onTap,
  });

  final Conversation thread;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final person = thread.other;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 9, 18, 9),
        child: Row(
          children: [
            PersonAvatar(
              size: 42,
              imageUrl: person?.avatarUrl,
              initials: person?.initials ?? '?',
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                person?.name ?? 'Someone',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            // A tick rather than a checkbox: it reads at a glance down a list
            // and does not draw an empty square beside every unselected row.
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? AppColors.mint : Colors.transparent,
                border: Border.all(
                  color: selected
                      ? AppColors.mint
                      : Colors.white.withValues(alpha: 0.22),
                  width: 1.6,
                ),
              ),
              child: selected
                  ? const Icon(Icons.check_rounded,
                      size: 15, color: Color(0xFF04121F))
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _SendBar extends StatelessWidget {
  const _SendBar({required this.count, required this.onSend});

  final int count;
  final VoidCallback? onSend;

  @override
  Widget build(BuildContext context) {
    final enabled = onSend != null;

    return Container(
      padding: EdgeInsets.fromLTRB(
        18, 12, 18, 14 + MediaQuery.viewPaddingOf(context).bottom,
      ),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.07)),
        ),
      ),
      child: GestureDetector(
        onTap: onSend,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: enabled ? AppColors.safeGradient : null,
            color: enabled ? null : Colors.white.withValues(alpha: 0.06),
          ),
          child: Text(
            // Dead until something is chosen, and it says why rather than
            // just looking broken.
            enabled
                ? (count == 1 ? 'Forward' : 'Forward to $count chats')
                : 'Choose a chat',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: enabled
                  ? const Color(0xFF04121F)
                  : AppColors.textMuted.withValues(alpha: 0.8),
            ),
          ),
        ),
      ),
    );
  }
}
