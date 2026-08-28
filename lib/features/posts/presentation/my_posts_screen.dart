import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../core/api/api_response.dart';
import '../../../core/session/session.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/aurora_background.dart';
import '../../people/presentation/connections_screen.dart';
import '../../people/presentation/widgets/person_avatar.dart';
import '../../profile/presentation/edit_profile_screen.dart';
import '../data/post_models.dart';
import '../data/posts_api.dart';
import 'create_post_screen.dart';
import 'widgets/post_grid.dart';

/// The signed-in user's own profile: identity, counts, then the photo grid.
///
/// Laid out as slivers rather than a Column so the tab strip can pin itself
/// under the app bar while the grid scrolls past — the behaviour that makes a
/// long grid usable, since you can switch tabs without scrolling back up.
class MyPostsScreen extends StatefulWidget {
  const MyPostsScreen({super.key});

  @override
  State<MyPostsScreen> createState() => _MyPostsScreenState();
}

class _MyPostsScreenState extends State<MyPostsScreen> {
  final _api = PostsApi();

  /// 0 = my posts, 1 = posts I am tagged in.
  int _tab = 0;

  final Map<int, List<Post>> _lists = {};
  final Map<int, int> _totals = {};
  final Set<int> _loading = {};
  final Set<int> _loaded = {};
  String? _error;

  @override
  void initState() {
    super.initState();
    _load(0);
  }

  @override
  void dispose() {
    _api.dispose();
    super.dispose();
  }

  Future<void> _load(int tab) async {
    final me = Session.instance.user;

    if (me == null || _loading.contains(tab)) return;

    setState(() {
      _loading.add(tab);
      _error = null;
    });

    try {
      final res = tab == 0
          ? await _api.forUser(me.id)
          : await _api.taggedIn(me.id);

      if (!mounted) return;

      setState(() {
        if (res.success) {
          final page = PostPage.fromJson(res.dataMap);
          _lists[tab] = page.posts;
          _totals[tab] = page.total;
          _loaded.add(tab);
        } else {
          _error = res.message;
        }
      });
    } on ApiException catch (e) {
      // The client already turned this into something readable — repeating
      // it as "could not reach the server" would throw that away, and the
      // two failures need different words.
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Something went wrong.');
    } finally {
      if (mounted) setState(() => _loading.remove(tab));
    }
  }

  void _select(int tab) {
    if (tab == _tab) return;

    setState(() => _tab = tab);

    // Only the first visit fetches; coming back shows what is already there.
    if (!_loaded.contains(tab)) _load(tab);
  }

  Future<void> _create() async {
    final posted = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const CreatePostScreen()),
    );

    if (posted == true && mounted) _load(0);
  }

  Future<void> _editProfile() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const EditProfileScreen()),
    );
    // The header reads name, avatar and counts from Session, which the edit
    // screen refreshes — so nothing to reload here beyond a repaint.
    if (mounted) setState(() {});
  }

  void _openConnections(ConnectionsTab tab) {
    final me = Session.instance.user;

    if (me == null) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ConnectionsScreen(
          userId: me.id,
          initialTab: tab,
          title: me.username == null ? me.name : '@${me.username}',
          counts: {
            ConnectionsTab.followers: me.followersCount,
            ConnectionsTab.following: me.followingCount,
            ConnectionsTab.family: me.familyCount,
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: AuroraBackground(
        child: AnimatedBuilder(
          animation: Session.instance,
          builder: (context, _) => _build(context),
        ),
      ),
    );
  }

  Widget _build(BuildContext context) {
    final me = Session.instance.user;
    final posts = _lists[_tab] ?? const <Post>[];

    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        onRefresh: () => _load(_tab),
        color: AppColors.mint,
        backgroundColor: AppColors.canvasRaised,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          slivers: [
            SliverToBoxAdapter(
              child: _TopBar(
                username: me?.username == null
                    ? (me?.name ?? 'My profile')
                    : '@${me!.username}',
                onCreate: _create,
              ),
            ),

            SliverToBoxAdapter(
              child: _ProfileBlock(
                name: me?.name ?? '',
                about: me?.about,
                avatarUrl: me?.avatarUrl,
                initials: me?.initials ?? '?',
                posts: _totals[0] ?? _lists[0]?.length ?? 0,
                followers: me?.followersCount ?? 0,
                following: me?.followingCount ?? 0,
                onCreate: _create,
                onEdit: _editProfile,
                onCounts: _openConnections,
              ),
            ),

            SliverPersistentHeader(
              pinned: true,
              delegate: _TabStrip(
                selected: _tab,
                onSelect: _select,
              ),
            ),

            if (_loading.contains(_tab) && posts.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Padding(
                  padding: EdgeInsets.only(top: 60),
                  child: Center(
                    child: CircularProgressIndicator(color: AppColors.mint),
                  ),
                ),
              )
            else if (_error != null)
              SliverToBoxAdapter(
                child: PostGridEmpty(
                  icon: Icons.cloud_off_rounded,
                  title: 'Cannot load your posts',
                  detail: _error!,
                  onRetry: () => _load(_tab),
                ),
              )
            else if (posts.isEmpty)
              SliverToBoxAdapter(
                child: PostGridEmpty(
                  icon: _tab == 0
                      ? Icons.photo_camera_outlined
                      : Icons.account_box_outlined,
                  title: _tab == 0 ? 'No posts yet' : 'No tagged posts',
                  detail: _tab == 0
                      ? 'Share a photo and it will appear here, and on your '
                          'profile for the people who follow you.'
                      : 'When somebody tags you in a photo, it shows up here.',
                ),
              )
            else
              SliverPadding(
                // The strip needs air under it, or the first row of
                // photos reads as part of the tab bar.
                padding: const EdgeInsets.fromLTRB(2, 14, 2, 40),
                sliver: PostGridSliver(
                  posts: posts,
                  title: _tab == 0 ? 'My posts' : 'Tagged',
                  onChanged: () => _load(_tab),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.username, required this.onCreate});

  final String username;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 4, 8, 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_rounded,
                color: AppColors.textPrimary),
            onPressed: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: Text(
              username,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          IconButton(
            // A bare plus. The boxed variant reads as a second grid icon
            // sitting next to the real one, which is exactly the confusion an
            // app bar cannot afford.
            icon: const Icon(Icons.add_rounded,
                size: 28, color: AppColors.textPrimary),
            tooltip: 'New post',
            onPressed: onCreate,
          ),
        ],
      ),
    );
  }
}

/// Avatar, counts, name, bio, actions.
class _ProfileBlock extends StatelessWidget {
  const _ProfileBlock({
    required this.name,
    required this.about,
    required this.avatarUrl,
    required this.initials,
    required this.posts,
    required this.followers,
    required this.following,
    required this.onCreate,
    required this.onEdit,
    required this.onCounts,
  });

  final String name;
  final String? about;
  final String? avatarUrl;
  final String initials;
  final int posts;
  final int followers;
  final int following;
  final VoidCallback onCreate;
  final VoidCallback onEdit;
  final void Function(ConnectionsTab tab) onCounts;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 6, 18, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // The avatar carries the new-post affordance, so the action is
              // where the eye already is rather than only in the app bar.
              GestureDetector(
                onTap: onCreate,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    PersonAvatar(
                      size: 86,
                      imageUrl: avatarUrl,
                      initials: initials,
                      ring: true,
                    ),
                    Positioned(
                      right: -2,
                      bottom: -2,
                      child: Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: AppColors.safeGradient,
                          border: Border.all(
                              color: AppColors.canvas, width: 2.5),
                        ),
                        child: const Icon(Icons.add_rounded,
                            size: 15, color: Color(0xFF04121F)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Row(
                  children: [
                    _Count(
                      value: posts,
                      label: 'posts',
                      onTap: null,
                    ),
                    _Count(
                      value: followers,
                      label: 'followers',
                      onTap: () => onCounts(ConnectionsTab.followers),
                    ),
                    _Count(
                      value: following,
                      label: 'following',
                      onTap: () => onCounts(ConnectionsTab.following),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          Text(
            name,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          if (about != null && about!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              about!,
              style: const TextStyle(
                fontSize: 13,
                height: 1.4,
                color: AppColors.textMuted,
              ),
            ),
          ],
          const SizedBox(height: 16),

          Row(
            children: [
              Expanded(
                child: _Action(
                  label: 'Edit profile',
                  onTap: onEdit,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: _Action(
                  label: 'New post',
                  filled: true,
                  icon: Icons.add_a_photo_rounded,
                  onTap: onCreate,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _Count extends StatelessWidget {
  const _Count({required this.value, required this.label, this.onTap});

  final int value;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          children: [
            Text(
              '$value',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                height: 1.15,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({
    required this.label,
    required this.onTap,
    this.filled = false,
    this.icon,
  });

  final String label;
  final VoidCallback onTap;
  final bool filled;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final fg = filled ? const Color(0xFF04121F) : AppColors.textPrimary;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(11),
          gradient: filled ? AppColors.safeGradient : null,
          color: filled ? null : Colors.white.withValues(alpha: 0.07),
          border: filled
              ? null
              : Border.all(color: Colors.white.withValues(alpha: 0.14)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 15, color: fg),
              const SizedBox(width: 7),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: fg,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Grid / Tagged, pinned under the app bar as the grid scrolls.
/// Posts / Tagged, pinned under the header as the grid scrolls.
///
/// Frosted rather than filled with a flat colour. A pinned header has to be
/// opaque enough to hide the grid sliding under it, and a solid navy band
/// across a screen built from glass and gradient looks like a patch. A blur
/// does the same job and belongs to the same material as everything else.
class _TabStrip extends SliverPersistentHeaderDelegate {
  _TabStrip({required this.selected, required this.onSelect});

  final int selected;
  final ValueChanged<int> onSelect;

  static const double _height = 54;

  @override
  double get minExtent => _height;

  @override
  double get maxExtent => _height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          height: _height,
          decoration: BoxDecoration(
            color: AppColors.canvas.withValues(alpha: 0.72),
            border: Border(
              top: BorderSide(color: Colors.white.withValues(alpha: 0.07)),
              bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
            ),
          ),
          child: Row(
            children: [
              _Tab(
                icon: Icons.grid_on_rounded,
                active: selected == 0,
                onTap: () => onSelect(0),
              ),
              _Tab(
                // A frame with a person in it: the shape people already read
                // as "photos of me". A luggage-style tag says "label", which
                // is a different idea entirely.
                icon: Icons.account_box_outlined,
                active: selected == 1,
                onTap: () => onSelect(1),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(_TabStrip old) => old.selected != selected;
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.icon,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(height: 4),
            AnimatedScale(
              scale: active ? 1.0 : 0.94,
              duration: const Duration(milliseconds: 180),
              child: Icon(
                icon,
                size: 23,
                color: active ? AppColors.textPrimary : AppColors.navInactive,
              ),
            ),
            const SizedBox(height: 9),
            // A short pill under the icon rather than a full-width rule —
            // it points at the icon instead of dividing the screen.
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              height: 3,
              width: active ? 26 : 0,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(2),
                gradient: AppColors.safeGradient,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
