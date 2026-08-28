import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../core/widgets/aurora_background.dart';
import '../../../core/widgets/glass_card.dart';
import '../../chat/presentation/chat_screen.dart';
import '../../posts/data/post_models.dart';
import '../../posts/data/posts_api.dart';
import '../../posts/presentation/widgets/post_grid.dart';
import '../data/people_api.dart';
import '../data/people_models.dart';
import '../state/family_store.dart';
import 'connections_screen.dart';
import 'widgets/block_sheet.dart';
import 'widgets/person_avatar.dart';

/// Somebody else's profile.
///
/// Every action here answers with the full profile, so the screen is always
/// repainted from the server's own view of the relationship rather than a
/// local guess about what the action did.
class UserProfileScreen extends StatefulWidget {
  const UserProfileScreen({super.key, required this.userId});

  final String userId;

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  final _api = PeopleApi();

  final _postsApi = PostsApi();

  List<Post> _posts = const [];
  bool _postsLoading = true;
  bool _postsVisible = true;

  Future<void> _loadPosts() async {
    try {
      final res = await _postsApi.forUser(widget.userId);

      if (!mounted) return;

      setState(() {
        if (res.success) {
          final page = PostPage.fromJson(res.dataMap);
          _posts = page.posts;
          _postsVisible = page.canView;
        }
        _postsLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _postsLoading = false);
    }
  }

  PersonProfile? _profile;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
    _loadPosts();
  }

  @override
  void dispose() {
    _api.dispose();
    _postsApi.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final res = await _api.profile(widget.userId);

      if (!mounted) return;

      setState(() {
        if (res.success) {
          _profile = PersonProfile.fromJson(res.dataMap);
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

  /// Run an action, then adopt the profile it returns.
  Future<void> _act(Future<dynamic> Function() action) async {
    if (_busy) return;

    setState(() => _busy = true);

    try {
      final res = await action();

      if (!mounted) return;

      if (res.success) {
        setState(() => _profile = PersonProfile.fromJson(res.dataMap));
        AppToast.success(context, res.message);
      } else {
        AppToast.error(context, res.message);
      }
    } catch (_) {
      if (mounted) AppToast.error(context, 'Could not reach the server.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleFollow() {
    final rel = _profile!.relationship;

    return _act(() => rel.isFollowing || rel.hasRequested
        ? _api.unfollow(widget.userId)
        : _api.follow(widget.userId));
  }

  Future<void> _respondToRequest(bool accept) {
    final id = _profile!.relationship.incomingRequestId!;

    return _act(() => _api.respondToFollowRequest(id, accept));
  }

  void _openChat() {
    final p = _profile;

    if (p == null) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          userId: p.id,
          name: p.name,
          username: p.username,
          avatarUrl: p.avatarUrl,
          initials: p.initials,
          presence: p.lastSeenLabel,
        ),
      ),
    );
  }

  void _openConnections(ConnectionsTab tab) {
    final p = _profile;

    if (p == null) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ConnectionsScreen(
          userId: p.id,
          initialTab: tab,
          title: p.username == null ? p.name : '@${p.username}',
          counts: {
            ConnectionsTab.followers: p.followers,
            ConnectionsTab.following: p.following,
            ConnectionsTab.family: p.familyCount,
          },
        ),
      ),
    );
  }


  Future<void> _openActions() async {
    final p = _profile;

    if (p == null) return;

    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => ProfileActionsSheet(
        isBlocked: p.relationship.blockedByMe,
      ),
    );

    if (choice == null || !mounted) return;

    if (choice == 'block') {
      p.relationship.blockedByMe ? await _unblock() : await _confirmBlock();
    } else if (choice == 'report') {
      AppToast.show(
        context,
        'Reporting is coming soon.',
        type: ToastType.info,
      );
    }
  }

  Future<void> _confirmBlock() async {
    final p = _profile!;

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => BlockSheet(
        name: p.name,
        username: p.username,
        avatarUrl: p.avatarUrl,
        initials: p.initials,
        isFamily: p.relationship.isFamily,
      ),
    );

    if (confirmed != true || !mounted) return;

    await _act(() => _api.block(widget.userId));

    // Blocking severs the family link, so the home strip is now wrong.
    await FamilyStore.instance.load();
  }

  Future<void> _unblock() => _act(() => _api.unblock(widget.userId));

  Future<void> _inviteToFamily() async {
    final relation = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const _RelationSheet(),
    );

    if (relation == null || !mounted) return;

    await _act(() => _api.inviteToFamily(
          widget.userId,
          relation: relation == 'skip' ? null : relation,
        ));

    await FamilyStore.instance.load();
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
                padding: const EdgeInsets.fromLTRB(6, 6, 16, 0),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_rounded,
                          color: AppColors.textPrimary),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    Expanded(
                      child: Text(
                        _profile?.username == null
                            ? (_profile?.name ?? 'Profile')
                            : '@${_profile!.username}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    if (_profile != null && !_profile!.relationship.isSelf)
                      IconButton(
                        icon: const Icon(Icons.more_vert_rounded,
                            color: AppColors.textPrimary),
                        onPressed: _openActions,
                      ),
                  ],
                ),
              ),
              Expanded(child: _body()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.mint),
      );
    }

    if (_error != null || _profile == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Text(
            _error ?? 'Profile unavailable.',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
          ),
        ),
      );
    }

    final p = _profile!;
    final rel = p.relationship;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 40),
      physics: const BouncingScrollPhysics(),
      children: [
        Center(
          child: PersonAvatar(
            size: 104,
            imageUrl: p.avatarUrl,
            initials: p.initials,
            ring: true,
          ),
        ),
        const SizedBox(height: 14),
        Center(
          child: Text(
            p.name,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        if (p.about != null && p.about!.isNotEmpty) ...[
          const SizedBox(height: 7),
          Center(
            child: Text(
              p.about!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12.5,
                height: 1.4,
                color: AppColors.textMuted,
              ),
            ),
          ),
        ],
        const SizedBox(height: 18),
        _Counts(
          profile: p,
          // Only reachable once you can see the profile — a private
          // account's follower list is part of what is private.
          onTap: p.isVisible ? _openConnections : null,
        ),
        const SizedBox(height: 18),

        // Their request comes first: answering somebody who is waiting on you
        // matters more than deciding whether to follow them back.
        if (rel.awaitingMyAnswer) ...[
          _RequestPanel(
            name: p.name,
            busy: _busy,
            onAccept: () => _respondToRequest(true),
            onDecline: () => _respondToRequest(false),
          ),
          const SizedBox(height: 12),
        ],

        if (!rel.isSelf)
          if (rel.blockedByMe)
            _Action(
              label: 'Unblock',
              filled: false,
              busy: _busy,
              onTap: _unblock,
            )
          else
            _actions(rel),

        if (rel.blockedByMe) ...[
          const SizedBox(height: 20),
          const _BlockedPanel(),
        ] else if (!p.isVisible) ...[
          const SizedBox(height: 20),
          const _PrivatePanel(),
        ],

        if (p.isVisible && p.phone != null) ...[
          const SizedBox(height: 14),
          _DetailRow(icon: Icons.phone_rounded, label: p.phone!),
        ],

        if (!rel.blockedByMe) ...[
          const SizedBox(height: 22),
          _postsSection(p),
        ],
      ],
    );
  }

  /// The photo grid.
  ///
  /// `can_view` from the API decides between a grid, a locked panel
  /// and an empty state. They are three different things, and showing
  /// an empty grid for a private account would read as "no posts".
  Widget _postsSection(PersonProfile p) {
    if (_postsLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 30),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: AppColors.mint),
          ),
        ),
      );
    }

    if (!_postsVisible) {
      return const PostGridEmpty(
        icon: Icons.lock_outline_rounded,
        title: 'Posts are private',
        detail: 'Follow this account, and once they accept you will '
            'see their photos.',
      );
    }

    if (_posts.isEmpty) {
      return const PostGridEmpty(
        icon: Icons.photo_camera_outlined,
        title: 'No posts yet',
        detail: 'When they share a photo it will show up here.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 10),
          child: Row(
            children: [
              const Icon(Icons.grid_on_rounded,
                  size: 15, color: AppColors.textMuted),
              const SizedBox(width: 7),
              Text(
                _posts.length == 1 ? '1 post' : '${_posts.length} posts',
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),
        PostGrid(
          posts: _posts,
          title: p.username == null ? p.name : '@${p.username}',
          onChanged: _loadPosts,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
        ),
      ],
    );
  }

  /// Follow and Message on the top row — the two things anybody opens a
  /// profile to do. Family gets its own line below, because it is conditional
  /// and squeezing three buttons across a phone leaves none of them legible.
  Widget _actions(Relationship rel) {
    final hasFamilyRow = rel.canInviteToFamily ||
        rel.family == 'pending_out' ||
        rel.isFamily;

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _Action(
                label: rel.followLabel,
                filled: !rel.isFollowing && !rel.hasRequested,
                busy: _busy,
                onTap: _toggleFollow,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _Action(
                label: 'Message',
                icon: Icons.chat_bubble_outline_rounded,
                filled: false,
                accent: AppColors.aqua,
                busy: false,
                onTap: _openChat,
              ),
            ),
          ],
        ),
        if (hasFamilyRow) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              if (rel.canInviteToFamily)
                Expanded(
                  child: _Action(
                    label: 'Add to family',
                    icon: Icons.group_add_rounded,
                    filled: false,
                    accent: AppColors.mint,
                    busy: _busy,
                    onTap: _inviteToFamily,
                  ),
                )
              else if (rel.family == 'pending_out')
                const Expanded(child: _Static(label: 'Family invite sent'))
              else
                Expanded(
                  child: _Static(
                    label: rel.familyRelation == null
                        ? 'Family'
                        : _titled(rel.familyRelation!),
                    icon: Icons.favorite_rounded,
                    accent: AppColors.mint,
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }

  static String _titled(String value) =>
      value.isEmpty ? value : value[0].toUpperCase() + value.substring(1);
}

class _Counts extends StatelessWidget {
  const _Counts({required this.profile, this.onTap});

  final PersonProfile profile;
  final void Function(ConnectionsTab tab)? onTap;

  @override
  Widget build(BuildContext context) {
    Widget cell(String value, String label, ConnectionsTab tab) =>
        Expanded(
          child: GestureDetector(
            onTap: onTap == null ? null : () => onTap!(tab),
            behavior: HitTestBehavior.opaque,
            child: Column(
            children: [
              Text(
                value,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11.5,
                  color: AppColors.textMuted,
                ),
              ),
            ],
            ),
          ),
        );

    return GlassCard(
      padding: const EdgeInsets.symmetric(vertical: 14),
      radius: 18,
      child: Row(
        children: [
          cell('${profile.followers}', 'Followers',
              ConnectionsTab.followers),
          cell('${profile.following}', 'Following',
              ConnectionsTab.following),
          cell('${profile.familyCount}', 'Family',
              ConnectionsTab.family),
        ],
      ),
    );
  }
}

class _RequestPanel extends StatelessWidget {
  const _RequestPanel({
    required this.name,
    required this.busy,
    required this.onAccept,
    required this.onDecline,
  });

  final String name;
  final bool busy;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      radius: 18,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$name wants to follow you',
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _Action(
                  label: 'Accept',
                  filled: true,
                  busy: busy,
                  onTap: onAccept,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _Action(
                  label: 'Decline',
                  filled: false,
                  busy: busy,
                  onTap: onDecline,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BlockedPanel extends StatelessWidget {
  const _BlockedPanel();

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(18, 22, 18, 22),
      radius: 18,
      child: Column(
        children: [
          Icon(Icons.block_flipped,
              size: 30, color: AppColors.alertRed.withValues(alpha: 0.8)),
          const SizedBox(height: 11),
          const Text(
            'You blocked this account',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 5),
          const Text(
            'They cannot find you, see your profile, or contact you. They '
            'were not told. Unblocking does not restore following or family.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              height: 1.45,
              color: AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _PrivatePanel extends StatelessWidget {
  const _PrivatePanel();

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(18, 22, 18, 22),
      radius: 18,
      child: Column(
        children: [
          Icon(Icons.lock_outline_rounded,
              size: 30, color: AppColors.textMuted.withValues(alpha: 0.7)),
          const SizedBox(height: 11),
          const Text(
            'This account is private',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 5),
          const Text(
            'Send a follow request. Once they accept, you will see their '
            'profile.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              height: 1.45,
              color: AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      radius: 14,
      child: Row(
        children: [
          Icon(icon, size: 17, color: AppColors.aqua),
          const SizedBox(width: 11),
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({
    required this.label,
    required this.filled,
    required this.busy,
    required this.onTap,
    this.icon,
    this.accent,
  });

  final String label;
  final bool filled;
  final bool busy;
  final VoidCallback onTap;
  final IconData? icon;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final fg = filled ? const Color(0xFF04121F) : (accent ?? AppColors.textPrimary);

    return GestureDetector(
      onTap: busy ? null : onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 46,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: filled ? AppColors.safeGradient : null,
          color: filled ? null : Colors.white.withValues(alpha: 0.07),
          border: filled
              ? null
              : Border.all(
                  color: (accent ?? Colors.white).withValues(alpha: 0.2),
                ),
        ),
        child: busy
            ? SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(fg),
                ),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 16, color: fg),
                    const SizedBox(width: 7),
                  ],
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: fg,
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _Static extends StatelessWidget {
  const _Static({required this.label, this.icon, this.accent});

  final String label;
  final IconData? icon;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final fg = accent ?? AppColors.textMuted;

    return Container(
      height: 46,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: fg.withValues(alpha: 0.10),
        border: Border.all(color: fg.withValues(alpha: 0.24)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 15, color: fg),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: fg,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Optional label for a family invite.
class _RelationSheet extends StatelessWidget {
  const _RelationSheet();

  static const _relations = [
    'mother', 'father', 'sister', 'brother', 'son', 'daughter',
    'spouse', 'partner', 'grandparent', 'grandchild', 'friend', 'other',
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        20, 18, 20, 18 + MediaQuery.viewPaddingOf(context).bottom,
      ),
      decoration: const BoxDecoration(
        color: AppColors.canvasRaised,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(2),
                color: Colors.white.withValues(alpha: 0.18),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'How are they related?',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Optional — you can set this later.',
            style: TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final relation in _relations)
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(relation),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 9),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      color: Colors.white.withValues(alpha: 0.06),
                      border: Border.all(color: AppColors.glassBorder),
                    ),
                    child: Text(
                      relation[0].toUpperCase() + relation.substring(1),
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: () => Navigator.of(context).pop('skip'),
            child: Container(
              height: 46,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: AppColors.safeGradient,
              ),
              child: const Text(
                'Send invite without a label',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF04121F),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
