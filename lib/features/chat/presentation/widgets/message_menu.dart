import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../data/chat_models.dart';

/// What a long press on a message can do.
enum MessageAction { reply, copy, forward, pin, unpin, star, unstar, delete }

/// The long-press menu.
///
/// Anchored near the message rather than presented as a bottom sheet, unlike
/// the other menus in this app. That difference is deliberate: these actions
/// act on one particular message, and a sheet at the bottom of the screen
/// severs the connection to which one — by the time your eye reaches it you
/// have lost the bubble you pressed.
///
/// The emoji reaction row belongs above this list. It is not here yet because
/// reactions need a table and a broadcast event of their own; the layout
/// leaves room for it.
/// What a long press produced: an action, or an emoji.
@immutable
class MessageMenuResult {
  const MessageMenuResult.action(this.action) : emoji = null;
  const MessageMenuResult.emoji(this.emoji) : action = null;

  final MessageAction? action;
  final String? emoji;
}

Future<MessageMenuResult?> showMessageMenu(
  BuildContext context, {
  required Offset at,
  required bool canCopy,
  required bool pinned,
  required bool starred,
  bool deleted = false,
  String? myReaction,
}) {
  const delete = _Item(
    MessageAction.delete,
    Icons.delete_outline_rounded,
    'Delete',
    danger: true,
  );

  /*
   | Delete is offered on every message, including theirs.
   |
   | It no longer means one thing: the dialog behind it decides whether
   | deleting for everyone is on the table. Taking something off your own
   | screen needs no permission from whoever wrote it.
   */
  final actions = deleted
      // A tombstone has nothing to reply to, copy, forward, pin or keep. All
      // that is left is clearing it from your own side.
      ? const [delete]
      : <_Item>[
          const _Item(MessageAction.reply, Icons.reply_rounded, 'Reply'),
          if (canCopy)
            const _Item(MessageAction.copy, Icons.copy_rounded, 'Copy'),
          const _Item(MessageAction.forward, Icons.shortcut_rounded, 'Forward'),

          // Pin and star both read as toggles, so the label says which way it
          // will go rather than naming the feature. "Pin" on something
          // already pinned would leave you guessing what tapping it does.
          pinned
              ? const _Item(MessageAction.unpin, Icons.push_pin_rounded, 'Unpin')
              : const _Item(MessageAction.pin, Icons.push_pin_outlined, 'Pin'),

          starred
              ? const _Item(MessageAction.unstar, Icons.star_rounded, 'Unstar')
              : const _Item(
                  MessageAction.star, Icons.star_outline_rounded, 'Star'),

          delete,
        ];

  return showGeneralDialog<MessageMenuResult>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Message actions',
    // Dark enough to lift the menu off the conversation, light enough that
    // the surrounding messages stay readable — the context is half the point
    // of anchoring it here.
    barrierColor: Colors.black.withValues(alpha: 0.45),
    transitionDuration: const Duration(milliseconds: 140),
    pageBuilder: (context, animation, _) => _MessageMenu(
      at: at,
      actions: actions,
      animation: animation,
      myReaction: myReaction,
      // Nothing to react to on a message that is gone.
      reactions: !deleted,
    ),
  );
}

class _Item {
  const _Item(this.action, this.icon, this.label, {this.danger = false});

  final MessageAction action;
  final IconData icon;
  final String label;
  final bool danger;
}

class _MessageMenu extends StatelessWidget {
  const _MessageMenu({
    required this.at,
    required this.actions,
    required this.animation,
    required this.reactions,
    this.myReaction,
  });

  final Offset at;
  final List<_Item> actions;
  final Animation<double> animation;

  /// Whether the quick-reaction strip is drawn along the top.
  final bool reactions;

  /// The emoji this person already has on the message, if any — shown
  /// selected, and tapping it takes the reaction off.
  final String? myReaction;

  static const double _width = 232;
  static const double _reactionRowHeight = 56;
  static const double _rowHeight = 48;
  static const double _padding = 8;
  static const double _margin = 12;

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final insets = MediaQuery.viewPaddingOf(context);

    final height = actions.length * _rowHeight +
        _padding * 2 +
        (reactions ? _reactionRowHeight : 0);

    // Horizontally centred on the press, then pulled back inside the screen.
    final left = (at.dx - _width / 2).clamp(
      _margin,
      screen.width - _width - _margin,
    );

    // Above the finger when the message sits low, below when it sits high —
    // so the menu never opens under the hand that summoned it.
    final below = at.dy < screen.height / 2;

    final top = below
        ? (at.dy + 12).clamp(insets.top + _margin,
            screen.height - height - insets.bottom - _margin)
        : (at.dy - height - 12).clamp(insets.top + _margin,
            screen.height - height - insets.bottom - _margin);

    return Stack(
      children: [
        Positioned(
          left: left.toDouble(),
          top: top.toDouble(),
          width: _width,
          child: FadeTransition(
            opacity: animation,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.92, end: 1).animate(
                CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
              ),
              // Grows from the edge nearest the message, so it reads as
              // coming out of the bubble rather than appearing over it.
              alignment: below ? Alignment.topCenter : Alignment.bottomCenter,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: _padding),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    color: AppColors.canvasRaised,
                    border:
                        Border.all(color: Colors.white.withValues(alpha: 0.1)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.5),
                        blurRadius: 28,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (reactions) ...[
                        _ReactionRow(mine: myReaction),
                        Divider(
                          height: 1,
                          thickness: 1,
                          color: Colors.white.withValues(alpha: 0.07),
                        ),
                        const SizedBox(height: 4),
                      ],
                      for (final item in actions)
                        _Row(
                          item: item,
                          onTap: () => Navigator.of(context).pop(
                            MessageMenuResult.action(item.action),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The quick-reaction strip along the top of the menu.
class _ReactionRow extends StatelessWidget {
  const _ReactionRow({this.mine});

  final String? mine;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _MessageMenu._reactionRowHeight - 5,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          for (final emoji in kQuickReactions)
            GestureDetector(
              // Tapping the one you already have removes it — the server
              // treats a repeat as a toggle, so the gesture matches.
              onTap: () => Navigator.of(context).pop(
                MessageMenuResult.emoji(emoji),
              ),
              behavior: HitTestBehavior.opaque,
              child: Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: emoji == mine
                      ? AppColors.aqua.withValues(alpha: 0.22)
                      : Colors.transparent,
                ),
                child: Text(emoji, style: const TextStyle(fontSize: 21)),
              ),
            ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.item, required this.onTap});

  final _Item item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tint = item.danger ? AppColors.alertRed : AppColors.textPrimary;

    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: _MessageMenu._rowHeight,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Row(
            children: [
              Icon(
                item.icon,
                size: 19,
                color: item.danger ? tint : AppColors.aqua,
              ),
              const SizedBox(width: 14),
              Text(
                item.label,
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                  color: tint,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
