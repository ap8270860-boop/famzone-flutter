import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../data/post_models.dart';
import '../post_detail_screen.dart';

/// Grid tiles are 4:5 portrait rather than square.
///
/// Photos of people are overwhelmingly portrait, and a square tile crops
/// the top and bottom off every one of them — heads and feet, usually.
/// A taller tile shows more of each photo and fits more of a feed on
/// screen, which is why photo apps moved away from squares.
const gridDelegate = SliverGridDelegateWithFixedCrossAxisCount(
  crossAxisCount: 3,
  crossAxisSpacing: 2,
  mainAxisSpacing: 2,
  childAspectRatio: 4 / 5,
);

/// The three-across photo grid.
///
/// Square tiles with hairline gaps, which is the layout that lets someone read
/// a whole feed at a glance — the reason every photo app converged on it.
class PostGrid extends StatelessWidget {
  const PostGrid({
    super.key,
    required this.posts,
    required this.onChanged,
    this.title,
    this.shrinkWrap = false,
    this.physics,
    this.padding = EdgeInsets.zero,
  });

  final List<Post> posts;

  /// Called when the detail view reports a deletion, so the grid reloads.
  final VoidCallback onChanged;

  final String? title;
  final bool shrinkWrap;
  final ScrollPhysics? physics;
  final EdgeInsets padding;

  Future<void> _open(BuildContext context, int index) => openPostDetail(
        context,
        posts: posts,
        index: index,
        title: title,
        onChanged: onChanged,
      );


  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: padding,
      shrinkWrap: shrinkWrap,
      physics: physics,
      gridDelegate: gridDelegate,
      itemCount: posts.length,
      itemBuilder: (context, i) => PostTile(
        post: posts[i],
        onTap: () => _open(context, i),
      ),
    );
  }
}

/// Shown in place of a grid when there is nothing to draw.
class PostGridEmpty extends StatelessWidget {
  const PostGridEmpty({
    super.key,
    required this.icon,
    required this.title,
    required this.detail,
    this.onRetry,
  });

  final IconData icon;
  final String title;
  final String detail;

  /// Shown only when the failure is something the user can act on — being
  /// offline, mostly. A Retry button under "no posts yet" would be nonsense.
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 44, 40, 44),
      child: Column(
        children: [
          Icon(icon, size: 42, color: AppColors.textMuted.withValues(alpha: 0.5)),
          const SizedBox(height: 14),
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
          Text(
            detail,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12.5,
              height: 1.45,
              color: AppColors.textMuted,
            ),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 18),
            GestureDetector(
              onTap: onRetry,
              behavior: HitTestBehavior.opaque,
              child: Container(
                height: 38,
                padding: const EdgeInsets.symmetric(horizontal: 22),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(11),
                  color: Colors.white.withValues(alpha: 0.07),
                  border:
                      Border.all(color: Colors.white.withValues(alpha: 0.16)),
                ),
                child: const Text(
                  'Try again',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One tile. Shared by [PostGrid] and [PostGridSliver] so the two cannot
/// drift apart as the design changes.
class PostTile extends StatelessWidget {
  const PostTile({super.key, required this.post, required this.onTap});

  final Post post;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        color: AppColors.canvasRaised,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.network(
              post.imageUrl,
              fit: BoxFit.cover,
              loadingBuilder: (context, child, progress) => progress == null
                  ? child
                  : const ColoredBox(color: AppColors.canvasRaised),
              errorBuilder: (_, __, ___) => const Icon(
                Icons.broken_image_outlined,
                size: 20,
                color: AppColors.textMuted,
              ),
            ),
            if (post.likesCount > 0)
              Positioned(
                right: 5,
                bottom: 5,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    color: Colors.black.withValues(alpha: 0.42),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        post.likedByMe
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        size: 10,
                        color:
                            post.likedByMe ? AppColors.alertRed : Colors.white,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        '${post.likesCount}',
                        style: const TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The same grid as a sliver, for screens that scroll it under a pinned
/// header.
class PostGridSliver extends StatelessWidget {
  const PostGridSliver({
    super.key,
    required this.posts,
    required this.onChanged,
    this.title,
  });

  final List<Post> posts;
  final VoidCallback onChanged;
  final String? title;

  @override
  Widget build(BuildContext context) {
    return SliverGrid(
      gridDelegate: gridDelegate,
      delegate: SliverChildBuilderDelegate(
        (context, i) => PostTile(
          post: posts[i],
          onTap: () => openPostDetail(
            context,
            posts: posts,
            index: i,
            title: title,
            onChanged: onChanged,
          ),
        ),
        childCount: posts.length,
      ),
    );
  }
}

/// Open the scrolling detail view, and report back if something was deleted.
Future<void> openPostDetail(
  BuildContext context, {
  required List<Post> posts,
  required int index,
  required VoidCallback onChanged,
  String? title,
}) async {
  final changed = await Navigator.of(context).push<bool>(
    MaterialPageRoute(
      builder: (_) => PostDetailScreen(
        posts: posts,
        initialIndex: index,
        title: title,
      ),
    ),
  );

  if (changed == true) onChanged();
}
