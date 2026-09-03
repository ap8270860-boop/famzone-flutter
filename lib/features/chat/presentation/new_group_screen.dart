import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/aurora_background.dart';
import '../../people/presentation/widgets/person_avatar.dart';
import '../data/chat_api.dart';
import '../data/chat_models.dart';
import 'group_details_screen.dart';

/// Who goes in the group.
///
/// Two scopes behind one screen: everybody you are connected with, or family
/// only. The list is fetched rather than assembled here — the server decides
/// who may be added, and a picker that offered anybody else would just be
/// collecting names for a 422.
class NewGroupScreen extends StatefulWidget {
  const NewGroupScreen({super.key, this.familyOnly = false});

  /// True for "Family group": the same flow, a shorter list, and a name the
  /// screen says out loud so nobody wonders where everyone went.
  final bool familyOnly;

  @override
  State<NewGroupScreen> createState() => _NewGroupScreenState();
}

class _NewGroupScreenState extends State<NewGroupScreen> {
  final ChatApi _api = ChatApi();
  final TextEditingController _search = TextEditingController();

  List<ChatPerson> _people = const [];

  /// Insertion-ordered, so the chips read in the order they were tapped
  /// rather than jumping about as the list is filtered.
  final List<ChatPerson> _selected = [];

  bool _loading = true;
  String? _error;
  String _query = '';

  String get _scope => widget.familyOnly ? 'family' : 'connections';

  @override
  void initState() {
    super.initState();

    _search.addListener(() {
      setState(() => _query = _search.text.trim().toLowerCase());
    });

    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    _api.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final res = await _api.groupCandidates(scope: _scope);

      if (!mounted) return;

      setState(() {
        if (res.success) {
          _people = (res.dataMap['people'] as List<dynamic>? ?? const [])
              .whereType<Map<String, dynamic>>()
              .map(ChatPerson.fromJson)
              .toList();

          _error = null;
        } else {
          _error = res.message;
        }

        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _error = 'Could not reach the server.';
        _loading = false;
      });
    }
  }

  List<ChatPerson> get _visible {
    if (_query.isEmpty) return _people;

    return _people
        .where((p) =>
            p.name.toLowerCase().contains(_query) ||
            (p.username ?? '').toLowerCase().contains(_query))
        .toList();
  }

  void _toggle(ChatPerson person) {
    setState(() {
      final index = _selected.indexWhere((p) => p.id == person.id);

      if (index >= 0) {
        _selected.removeAt(index);
      } else {
        _selected.add(person);
      }
    });
  }

  Future<void> _next() async {
    if (_selected.isEmpty) return;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GroupDetailsScreen(
          members: List.of(_selected),
          scope: _scope,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: AuroraBackground(
        child: SafeArea(
          child: Column(
            children: [
              _bar(),

              /*
               | Grown into, not snapped in.
               |
               | The chips row only exists once somebody is selected, so
               | without this the whole list jumps 84px the moment the first
               | tap lands — and jumps back on the last untap. Animating the
               | height makes it read as the row arriving rather than as the
               | screen flinching.
               */
              AnimatedSize(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: _selected.isEmpty
                    ? const SizedBox(width: double.infinity, height: 0)
                    : _chips(),
              ),

              _field(),
              Expanded(child: _body()),

              // Always present, so the bottom of the screen never moves. It
              // says what it wants instead of appearing out of nowhere.
              _nextBar(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 6, 20, 2),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_rounded,
                color: AppColors.textPrimary),
            onPressed: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.familyOnly ? 'Family group' : 'New group',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  _selected.isEmpty
                      ? 'Add people'
                      : '${_selected.length} selected',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The people chosen so far, scrolling sideways.
  Widget _chips() {
    return SizedBox(
      height: 84,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
        itemCount: _selected.length,
        itemBuilder: (context, i) {
          final person = _selected[i];

          return Padding(
            padding: const EdgeInsets.only(right: 14),
            child: GestureDetector(
              onTap: () => _toggle(person),
              behavior: HitTestBehavior.opaque,
              child: SizedBox(
                width: 56,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Stack(
                      children: [
                        PersonAvatar(
                          size: 46,
                          imageUrl: person.avatarUrl,
                          initials: person.initials,
                        ),
                        // Tapping a chip takes that person out again, which
                        // is quicker than hunting for their row in the list.
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Container(
                            width: 17,
                            height: 17,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppColors.canvasRaised,
                              border: Border.all(
                                  color: AppColors.canvas, width: 1.5),
                            ),
                            child: const Icon(Icons.close_rounded,
                                size: 11, color: AppColors.textPrimary),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      person.name.split(' ').first,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _field() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          color: Colors.white.withValues(alpha: 0.06),
          border: Border.all(color: Colors.white.withValues(alpha: 0.11)),
        ),
        child: Row(
          children: [
            Icon(Icons.search_rounded,
                size: 19, color: AppColors.textMuted.withValues(alpha: 0.9)),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _search,
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.textPrimary,
                ),
                decoration: const InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText: 'Search',
                  hintStyle:
                      TextStyle(fontSize: 14, color: AppColors.textMuted),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    final people = _visible;

    if (people.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(height: MediaQuery.sizeOf(context).height * 0.14),
          Icon(
            _error == null ? Icons.people_outline_rounded : Icons.cloud_off_rounded,
            size: 42,
            color: AppColors.textMuted.withValues(alpha: 0.45),
          ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 44),
            child: Text(
              _error ??
                  (_query.isNotEmpty
                      ? 'Nobody by that name.'
                      : widget.familyOnly
                          // Said specifically, because an empty list here has
                          // a specific cause and a specific fix.
                          ? 'Add family members from their profile first, and '
                              'they will appear here.'
                          : 'You can add people you follow, people who follow '
                              'you, and your family.'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                height: 1.45,
                color: AppColors.textMuted,
              ),
            ),
          ),
        ],
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 20),
      itemCount: people.length,
      itemBuilder: (context, i) {
        final person = people[i];
        final chosen = _selected.any((p) => p.id == person.id);

        return _PersonRow(
          person: person,
          selected: chosen,
          onTap: () => _toggle(person),
        );
      },
    );
  }

  Widget _nextBar() {
    final ready = _selected.isNotEmpty;

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
        onTap: ready ? _next : null,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: ready ? AppColors.safeGradient : null,
            color: ready ? null : Colors.white.withValues(alpha: 0.06),
          ),
          child: Text(
            ready
                ? (_selected.length == 1
                    ? 'Next · 1 person'
                    : 'Next · ${_selected.length} people')
                : 'Choose people',
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
              color: ready
                  ? const Color(0xFF04121F)
                  : AppColors.textMuted.withValues(alpha: 0.8),
            ),
          ),
        ),
      ),
    );
  }
}

class _PersonRow extends StatelessWidget {
  const _PersonRow({
    required this.person,
    required this.selected,
    required this.onTap,
  });

  final ChatPerson person;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 9, 18, 9),
        child: Row(
          children: [
            PersonAvatar(
              size: 44,
              imageUrl: person.avatarUrl,
              initials: person.initials,
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    person.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  if (person.username != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      '@${person.username}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
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
