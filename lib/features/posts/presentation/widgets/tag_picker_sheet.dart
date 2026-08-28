import 'package:flutter/material.dart';

import '../../../../core/session/session.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../people/data/people_api.dart';
import '../../../people/data/people_models.dart';
import '../../../people/presentation/widgets/person_avatar.dart';

/// Pick people to tag.
///
/// Only followers and following — the server enforces the same rule, and it
/// exists because otherwise a post is a way to attach your name to a
/// stranger's photo, which is how tagging turns into spam everywhere it is
/// left open.
class TagPickerSheet extends StatefulWidget {
  const TagPickerSheet({super.key, this.selected = const []});

  final List<PersonSummary> selected;

  @override
  State<TagPickerSheet> createState() => _TagPickerSheetState();
}

class _TagPickerSheetState extends State<TagPickerSheet> {
  final _api = PeopleApi();
  final _search = TextEditingController();

  List<PersonSummary> _people = const [];
  late List<PersonSummary> _chosen = List.of(widget.selected);
  bool _loading = true;
  String _filter = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    _api.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final me = Session.instance.user;

    if (me == null) {
      setState(() => _loading = false);
      return;
    }

    try {
      // Both lists, merged and de-duplicated: somebody who follows you is as
      // taggable as somebody you follow, and mutuals appear in both.
      final results = await Future.wait([
        _api.followers(me.id),
        _api.following(me.id),
      ]);

      if (!mounted) return;

      final byId = <String, PersonSummary>{};

      for (final res in results) {
        if (!res.success) continue;

        for (final raw in (res.dataMap['results'] as List?) ?? const []) {
          if (raw is Map<String, dynamic>) {
            final person = PersonSummary.fromJson(raw);
            byId[person.id] = person;
          }
        }
      }

      setState(() {
        _people = byId.values.toList()
          ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _toggle(PersonSummary person) {
    setState(() {
      _chosen.any((p) => p.id == person.id)
          ? _chosen.removeWhere((p) => p.id == person.id)
          : _chosen.add(person);
    });
  }

  @override
  Widget build(BuildContext context) {
    final visible = _filter.isEmpty
        ? _people
        : _people
            .where((p) =>
                p.name.toLowerCase().contains(_filter) ||
                (p.username ?? '').toLowerCase().contains(_filter))
            .toList();

    return Container(
      height: MediaQuery.sizeOf(context).height * 0.78,
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      decoration: const BoxDecoration(
        color: AppColors.canvasRaised,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 38,
            height: 4,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(2),
              color: Colors.white.withValues(alpha: 0.18),
            ),
          ),
          const SizedBox(height: 14),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Tag people',
                    style: TextStyle(
                      fontSize: 16.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(_chosen),
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 4),
                    child: Text(
                      _chosen.isEmpty ? 'Done' : 'Done (${_chosen.length})',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.mint,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Container(
              height: 42,
              padding: const EdgeInsets.symmetric(horizontal: 13),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(21),
                color: Colors.white.withValues(alpha: 0.06),
                border: Border.all(color: AppColors.glassBorder),
              ),
              child: Row(
                children: [
                  const Icon(Icons.search_rounded,
                      size: 18, color: AppColors.textMuted),
                  const SizedBox(width: 9),
                  Expanded(
                    child: TextField(
                      controller: _search,
                      onChanged: (v) =>
                          setState(() => _filter = v.trim().toLowerCase()),
                      style: const TextStyle(
                          fontSize: 14, color: AppColors.textPrimary),
                      decoration: const InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        hintText: 'Search your people',
                        hintStyle: TextStyle(
                            fontSize: 13.5, color: AppColors.textMuted),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),

          Expanded(child: _list(visible)),
        ],
      ),
    );
  }

  Widget _list(List<PersonSummary> visible) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.mint),
      );
    }

    if (_people.isEmpty) {
      return const _Note(
        'Nobody to tag yet',
        'You can tag people who follow you, or who you follow.',
      );
    }

    if (visible.isEmpty) {
      return const _Note('No match', 'Nobody here by that name.');
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 20),
      physics: const BouncingScrollPhysics(),
      itemCount: visible.length,
      itemBuilder: (context, i) {
        final person = visible[i];
        final selected = _chosen.any((p) => p.id == person.id);

        return GestureDetector(
          onTap: () => _toggle(person),
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
            child: Row(
              children: [
                PersonAvatar(
                  size: 42,
                  imageUrl: person.avatarUrl,
                  initials: person.initials,
                ),
                const SizedBox(width: 12),
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
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        person.handle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textMuted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected ? AppColors.mint : Colors.transparent,
                    border: Border.all(
                      color: selected
                          ? AppColors.mint
                          : Colors.white.withValues(alpha: 0.28),
                      width: 1.6,
                    ),
                  ),
                  child: selected
                      ? const Icon(Icons.check_rounded,
                          size: 14, color: Color(0xFF04121F))
                      : null,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.title, this.detail);

  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(44, 0, 44, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 12.5, height: 1.45, color: AppColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}
