import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_toast.dart';
import '../../people/presentation/user_profile_screen.dart';
import '../data/post_models.dart';
import '../data/posts_api.dart';
import 'widgets/post_card.dart';

/// The scrolling post view you land on after tapping a grid tile.
///
/// Opens on the tapped post with everything newer above it and everything
/// older below, both reachable by scrolling — the behaviour people expect from
/// a photo grid.
///
/// Built with `CustomScrollView`'s `center` sliver rather than by scrolling to
/// an offset. Post heights vary with caption length, so any offset would be an
/// estimate that drifts further down the list; `center` needs no arithmetic at
/// all and is exact whatever the content does.
class PostDetailScreen extends StatefulWidget {
  const PostDetailScreen({
    super.key,
    required this.posts,
    required this.initialIndex,
    this.title,
  });

  final List<Post> posts;
  final int initialIndex;
  final String? title;

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  final _api = PostsApi();
  final _centerKey = const ValueKey('post-detail-center');

  late List<Post> _posts = List.of(widget.posts);

  /// Posts currently in flight, so a like cannot be sent twice.
  final Set<String> _busy = {};

  @override
  void dispose() {
    _api.dispose();
    super.dispose();
  }

  /// Optimistic like.
  ///
  /// The heart and the count move immediately and roll back if the request
  /// fails — a like that waits on a round trip feels broken, and this is the
  /// one interaction people do without looking.
  Future<void> _setLike(Post post, bool liked) async {
    if (_busy.contains(post.id)) return;

    final index = _posts.indexWhere((p) => p.id == post.id);
    if (index == -1) return;

    final previous = _posts[index];

    setState(() {
      _busy.add(post.id);
      _posts[index] = previous.copyWith(
        likedByMe: liked,
        likesCount: (previous.likesCount + (liked ? 1 : -1)).clamp(0, 1 << 31),
      );
    });

    try {
      final res = liked ? await _api.like(post.id) : await _api.unlike(post.id);

      if (!mounted) return;

      if (res.success) {
        // Adopt the server's count — someone else may have liked it since.
        final at = _posts.indexWhere((p) => p.id == post.id);
        if (at != -1) {
          setState(() => _posts[at] = _posts[at].copyWith(
                likesCount: res.dataMap['likes_count'] as int? ??
                    _posts[at].likesCount,
                likedByMe: res.dataMap['liked'] as bool? ?? liked,
              ));
        }
      } else {
        setState(() => _posts[index] = previous);
        AppToast.error(context, res.message);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _posts[index] = previous);
      AppToast.error(context, 'Could not reach the server.');
    } finally {
      if (mounted) setState(() => _busy.remove(post.id));
    }
  }

  Future<void> _delete(Post post) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.canvasRaised,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        title: const Text('Delete this post?',
            style: TextStyle(
                fontSize: 16.5,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary)),
        content: const Text(
          'The photo and its likes are removed. This cannot be undone.',
          style: TextStyle(
              fontSize: 13, height: 1.45, color: AppColors.textMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel',
                style: TextStyle(color: AppColors.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete',
                style: TextStyle(
                    color: AppColors.alertRed, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      final res = await _api.delete(post.id);

      if (!mounted) return;

      if (res.success) {
        AppToast.success(context, res.message);
        // Hand the removal back so the grid behind refreshes.
        Navigator.of(context).pop(true);
      } else {
        AppToast.error(context, res.message);
      }
    } catch (_) {
      if (mounted) AppToast.error(context, 'Could not reach the server.');
    }
  }

  void _openAuthor(Post post) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => UserProfileScreen(userId: post.author.id),
      ),
    );
  }

  Widget _card(Post post) => PostCard(
        post: post,
        onToggleLike: (liked) => _setLike(post, liked),
        onOpenAuthor: () => _openAuthor(post),
        onDelete: post.isMine ? () => _delete(post) : null,
      );

  @override
  Widget build(BuildContext context) {
    final index = widget.initialIndex.clamp(0, _posts.length - 1);

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        backgroundColor: AppColors.canvas,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded,
              color: AppColors.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          widget.title ?? 'Posts',
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
      ),
      body: CustomScrollView(
        center: _centerKey,
        physics: const BouncingScrollPhysics(),
        slivers: [
          // Newer posts, laid out upward from the centre.
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, i) => _card(_posts[index - 1 - i]),
              childCount: index,
            ),
          ),

          SliverToBoxAdapter(
            key: _centerKey,
            child: _card(_posts[index]),
          ),

          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, i) => _card(_posts[index + 1 + i]),
              childCount: _posts.length - index - 1,
            ),
          ),
        ],
      ),
    );
  }
}
