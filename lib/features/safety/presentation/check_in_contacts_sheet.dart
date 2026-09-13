import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../people/presentation/widgets/person_avatar.dart';
import '../data/check_in_chain.dart';

/// Choose who hears about your check-in, and in what order.
///
/// The order is the feature. Every other "pick some people" sheet in the app
/// is a set — this one is a queue, and the difference has to be visible at a
/// glance or nobody will believe their arrangement was kept. So the chosen
/// list is numbered, always vertical, and drag-reorderable, while the people
/// not yet chosen sit below in a plainly unordered grid.
///
/// Returns the ordered list of user ids, or null if the sheet was dismissed.
/// An empty list is a real answer and not a cancel: it means "notify nobody",
/// which is how somebody goes back to a private check-in.
class CheckInContactsSheet extends StatefulWidget {
  const CheckInContactsSheet({
    super.key,
    required this.book,
    this.saveLabel = 'Save order',
    this.intro,
  });

  final ContactBook book;

  /// "Save order" when editing, "Save & check in" when this sheet is the first
  /// half of a check-in — which is the only time the button does two things,
  /// and it should say so.
  final String saveLabel;

  /// One line above the list, when there is something worth explaining.
  final String? intro;

  /// Opens the sheet and returns the chosen ids in order, or null on dismiss.
  static Future<List<String>?> show(
    BuildContext context, {
    required ContactBook book,
    String saveLabel = 'Save order',
    String? intro,
  }) {
    return showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CheckInContactsSheet(
        book: book,
        saveLabel: saveLabel,
        intro: intro,
      ),
    );
  }

  @override
  State<CheckInContactsSheet> createState() => _CheckInContactsSheetState();
}

class _CheckInContactsSheetState extends State<CheckInContactsSheet> {
  /// The working copy. Held as a list of people rather than ids so the rows
  /// can be drawn during a drag without a lookup on every frame.
  late List<ChainPerson> _chosen;

  @override
  void initState() {
    super.initState();

    /*
     | Start from the saved order, but keep only people who are still family.
     |
     | The server drops severed links when it saves, so a stale name here
     | would vanish on the round trip and look like the sheet lost somebody's
     | choice. Filtering up front means what you see is what gets saved.
     */
    final family = {for (final person in widget.book.available) person.id};

    _chosen = [
      for (final person in widget.book.chosen)
        if (family.contains(person.id)) person,
    ];
  }

  List<ChainPerson> get _remaining {
    final taken = {for (final person in _chosen) person.id};

    return [
      for (final person in widget.book.available)
        if (!taken.contains(person.id)) person,
    ];
  }

  bool get _atLimit => _chosen.length >= widget.book.max;

  void _add(ChainPerson person) {
    if (_atLimit) return;

    // Appended, not inserted. Tapping people in the order you want them told
    // is the fastest way to build the queue, and it is what everybody tries
    // first.
    setState(() => _chosen = [..._chosen, person]);
  }

  void _remove(ChainPerson person) {
    setState(() => _chosen = [
          for (final other in _chosen)
            if (other.id != person.id) other,
        ]);
  }

  void _reorder(int from, int to) {
    setState(() {
      final next = [..._chosen];

      // ReorderableListView reports the destination index as it would be
      // *before* the dragged row is lifted out, so anything moving down lands
      // one place too far without this.
      final target = to > from ? to - 1 : to;

      next.insert(target, next.removeAt(from));

      _chosen = next;
    });
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);

    return Padding(
      // Lift clear of the keyboard even though there is no field here today —
      // a search box in this sheet is an obvious next step once somebody has
      // thirty family members.
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: Container(
        constraints: BoxConstraints(maxHeight: media.size.height * 0.86),
        decoration: const BoxDecoration(
          color: AppColors.canvasRaised,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.textMuted.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            _header(),
            Flexible(child: _body()),
            _footer(media.viewPadding.bottom),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Who should know',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              if (_chosen.isNotEmpty)
                Text(
                  '${_chosen.length}/${widget.book.max}',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textMuted,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            widget.intro ??
                'We tell them one at a time, in this order. As soon as '
                    'somebody confirms, the rest are never disturbed — and if '
                    'nobody answers within ${widget.book.timeoutMinutes} '
                    'minutes, it moves to the next person.',
            style: const TextStyle(
              fontSize: 12.5,
              height: 1.5,
              color: AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _body() {
    if (widget.book.available.isEmpty) return const _NoFamily();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_chosen.isEmpty)
            const _EmptyOrder()
          else
            ReorderableListView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              onReorder: _reorder,
              children: [
                for (var i = 0; i < _chosen.length; i++)
                  _ChosenRow(
                    // Keyed by person, not by index — an index key would make
                    // Flutter reuse the wrong row's state mid-drag and the
                    // list would appear to shuffle at random.
                    key: ValueKey(_chosen[i].id),
                    index: i,
                    person: _chosen[i],
                    onRemove: () => _remove(_chosen[i]),
                  ),
              ],
            ),
          if (_remaining.isNotEmpty) ...[
            const SizedBox(height: 18),
            Row(
              children: [
                const Text(
                  'Add from your family',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(width: 8),
                if (_atLimit)
                  const Text(
                    'list is full',
                    style: TextStyle(fontSize: 11.5, color: AppColors.warmGold),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final person in _remaining)
                  _AddChip(
                    person: person,
                    disabled: _atLimit,
                    onTap: () => _add(person),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _footer(double inset) {
    return Container(
      padding: EdgeInsets.fromLTRB(20, 12, 20, 14 + inset),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.glassBorder)),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              behavior: HitTestBehavior.opaque,
              child: Container(
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.glassBorder),
                ),
                child: const Text(
                  'Cancel',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(
                [for (final person in _chosen) person.id],
              ),
              behavior: HitTestBehavior.opaque,
              child: Container(
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  gradient: AppColors.safeGradient,
                ),
                child: Text(
                  widget.saveLabel,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF04121F),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One person in the queue: their place, their face, and a handle.
class _ChosenRow extends StatelessWidget {
  const _ChosenRow({
    super.key,
    required this.index,
    required this.person,
    required this.onRemove,
  });

  final int index;
  final ChainPerson person;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 9, 4, 9),
        decoration: BoxDecoration(
          color: AppColors.glassFill,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.glassBorder),
        ),
        child: Row(
          children: [
            /*
             | The number, not a bullet.
             |
             | "Second" is the fact this row carries and the only reason the
             | list is vertical instead of a wrap. Spelling it out is what
             | makes a drag feel like it did something.
             */
            Container(
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.mint.withValues(alpha: 0.16),
              ),
              child: Text(
                '${index + 1}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: AppColors.mint,
                ),
              ),
            ),
            const SizedBox(width: 10),
            PersonAvatar(
              size: 38,
              imageUrl: person.avatarUrl,
              initials: person.initials,
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Text(
                person.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            IconButton(
              onPressed: onRemove,
              visualDensity: VisualDensity.compact,
              tooltip: 'Remove ${person.shortName}',
              icon: Icon(
                Icons.close_rounded,
                size: 18,
                color: AppColors.textMuted.withValues(alpha: 0.8),
              ),
            ),
            /*
             | An explicit handle rather than long-press-anywhere.
             |
             | buildDefaultDragHandles is off because the row also carries a
             | remove button, and a list where holding a finger anywhere picks
             | the row up makes that button feel like a trap.
             */
            ReorderableDragStartListener(
              index: index,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Icon(
                  Icons.drag_handle_rounded,
                  size: 20,
                  color: AppColors.textMuted.withValues(alpha: 0.7),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Somebody not in the queue yet.
class _AddChip extends StatelessWidget {
  const _AddChip({
    required this.person,
    required this.disabled,
    required this.onTap,
  });

  final ChainPerson person;
  final bool disabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: disabled ? 0.4 : 1,
      child: GestureDetector(
        onTap: disabled ? null : onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.fromLTRB(6, 6, 12, 6),
          decoration: BoxDecoration(
            color: AppColors.glassFill,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: AppColors.glassBorder),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              PersonAvatar(
                size: 28,
                imageUrl: person.avatarUrl,
                initials: person.initials,
              ),
              const SizedBox(width: 8),
              // Capped, because a wrap of chips with one very long name in it
              // stops wrapping and starts overflowing.
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 120),
                child: Text(
                  person.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.add_rounded, size: 16, color: AppColors.mint),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyOrder extends StatelessWidget {
  const _EmptyOrder();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.glassBorder,
          style: BorderStyle.solid,
        ),
      ),
      child: const Column(
        children: [
          Icon(Icons.format_list_numbered_rounded,
              size: 26, color: AppColors.textMuted),
          SizedBox(height: 10),
          Text(
            'Nobody chosen yet',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          SizedBox(height: 5),
          Text(
            'Tap a name below. The first person you pick is the first '
            'person we ask.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.45,
              color: AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _NoFamily extends StatelessWidget {
  const _NoFamily();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(34, 30, 34, 30),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.group_add_rounded, size: 38, color: AppColors.textMuted),
          SizedBox(height: 14),
          Text(
            'No family yet',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          SizedBox(height: 7),
          Text(
            'Add someone to your family circle first, then choose who to '
            'notify when you check in.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.5,
              color: AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}
