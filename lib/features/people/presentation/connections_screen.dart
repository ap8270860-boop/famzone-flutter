import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/aurora_background.dart';
import '../data/people_api.dart';
import '../data/people_models.dart';
import 'user_profile_screen.dart';
import 'widgets/person_row.dart';

/// Which list opens first.
enum ConnectionsTab { followers, following, family }

/// Followers, following and family, as three swipeable lists.
///
/// Each tab loads on first view rather than all three up front — most visits
/// only ever look at the one that was tapped, and three requests to render one
/// list is wasted work on a phone connection.
class ConnectionsScreen extends StatefulWidget {
  const ConnectionsScreen({
    super.key,
    required this.userId,
    this.initialTab = ConnectionsTab.followers,
    this.title,
    this.counts,
  });

  /// Whose lists these are. The signed-in user's own id for "my profile".
  final String userId;

  final ConnectionsTab initialTab;

  /// Shown in the app bar — usually the person's name or username.
  final String? title;

  /// Seeds the tab labels so they carry numbers before the lists load.
  final Map<ConnectionsTab, int>? counts;

  @override
  State<ConnectionsScreen> createState() => _ConnectionsScreenState();
}

class _ConnectionsScreenState extends State<ConnectionsScreen>
    with SingleTickerProviderStateMixin {
  final _api = PeopleApi();

  late final TabController _tabs = TabController(
    length: ConnectionsTab.values.length,
    initialIndex: widget.initialTab.index,
    vsync: this,
  );

  final Map<ConnectionsTab, List<PersonSummary>> _lists = {};
  final Set<ConnectionsTab> _loading = {};
  final Map<ConnectionsTab, String> _errors = {};

  @override
  void initState() {
    super.initState();
    _tabs.addListener(_onTabChanged);
    _load(widget.initialTab);
  }

  @override
  void dispose() {
    _tabs.removeListener(_onTabChanged);
    _tabs.dispose();
    _api.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (_tabs.indexIsChanging) return;

    final tab = ConnectionsTab.values[_tabs.index];

    // Only the first visit fetches; coming back shows what is already there.
    if (!_lists.containsKey(tab)) _load(tab);
  }

  Future<void> _load(ConnectionsTab tab) async {
    if (_loading.contains(tab)) return;

    setState(() {
      _loading.add(tab);
      _errors.remove(tab);
    });

    try {
      final res = switch (tab) {
        ConnectionsTab.followers => await _api.followers(widget.userId),
        ConnectionsTab.following => await _api.following(widget.userId),
        ConnectionsTab.family => await _api.family(),
      };

      if (!mounted) return;

      if (res.success) {
        // Family comes back under "members", the follow lists under "results".
        // Both carry the same per-person shape, including the relationship
        // block the follow button needs.
        final raw = (res.dataMap['results'] ?? res.dataMap['members']) as List?;

        setState(() {
          _lists[tab] = raw
                  ?.whereType<Map<String, dynamic>>()
                  .map(PersonSummary.fromJson)
                  .toList() ??
              const [];
        });
      } else {
        setState(() => _errors[tab] = res.message);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _errors[tab] = 'Could not reach the server.');
      }
    } finally {
      if (mounted) setState(() => _loading.remove(tab));
    }
  }

  String _label(ConnectionsTab tab) {
    final name = switch (tab) {
      ConnectionsTab.followers => 'Followers',
      ConnectionsTab.following => 'Following',
      ConnectionsTab.family => 'Family',
    };

    // Prefer the loaded length; fall back to the count passed in, so the tabs
    // are not blank while the first request is in flight.
    final count = _lists[tab]?.length ?? widget.counts?[tab];

    return count == null ? name : '$name  $count';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: AuroraBackground(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 6, 20, 2),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_rounded,
                          color: AppColors.textPrimary),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    Expanded(
                      child: Text(
                        widget.title ?? 'Connections',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              TabBar(
                controller: _tabs,
                labelColor: AppColors.textPrimary,
                unselectedLabelColor: AppColors.textMuted,
                indicatorColor: AppColors.mint,
                indicatorWeight: 2.5,
                dividerColor: Colors.transparent,
                labelStyle: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
                unselectedLabelStyle: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
                tabs: [
                  for (final tab in ConnectionsTab.values)
                    Tab(text: _label(tab)),
                ],
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabs,
                  children: [
                    for (final tab in ConnectionsTab.values) _list(tab),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _list(ConnectionsTab tab) {
    final people = _lists[tab];
    final error = _errors[tab];

    if (error != null) {
      return _Empty(
        icon: Icons.cloud_off_rounded,
        title: 'Something went wrong',
        detail: error,
      );
    }

    if (people == null || (_loading.contains(tab) && people.isEmpty)) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.mint),
      );
    }

    if (people.isEmpty) {
      return _Empty(
        icon: switch (tab) {
          ConnectionsTab.followers => Icons.group_outlined,
          ConnectionsTab.following => Icons.person_add_alt_1_outlined,
          ConnectionsTab.family => Icons.favorite_outline_rounded,
        },
        title: switch (tab) {
          ConnectionsTab.followers => 'No followers yet',
          ConnectionsTab.following => 'Not following anyone',
          ConnectionsTab.family => 'No family yet',
        },
        detail: switch (tab) {
          ConnectionsTab.followers =>
            'When someone follows you, they will show up here.',
          ConnectionsTab.following =>
            'Search for people and follow them to see them here.',
          ConnectionsTab.family =>
            'Follow someone first, then invite them to your family.',
        },
      );
    }

    return RefreshIndicator(
      onRefresh: () => _load(tab),
      color: AppColors.mint,
      backgroundColor: AppColors.canvasRaised,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        itemCount: people.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, i) {
          final person = people[i];

          return PersonRow(
            person: person,
            action: tab == ConnectionsTab.family
                ? PersonRowAction.family
                : PersonRowAction.follow,
            onRemoved: () => _load(tab),
            onTap: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => UserProfileScreen(userId: person.id),
                ),
              );

              // The profile may have changed the relationship, which would
              // leave this row's button stale.
              if (mounted) _load(tab);
            },
            onChanged: (updated) =>
                setState(() => _lists[tab]![i] = updated),
          );
        },
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({
    required this.icon,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      children: [
        const SizedBox(height: 90),
        Icon(icon, size: 44, color: AppColors.textMuted.withValues(alpha: 0.5)),
        const SizedBox(height: 15),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 15.5,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 46),
          child: Text(
            detail,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12.5,
              height: 1.45,
              color: AppColors.textMuted,
            ),
          ),
        ),
      ],
    );
  }
}
