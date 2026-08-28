import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../people/presentation/widgets/person_avatar.dart';
import '../../data/post_models.dart';

/// One post in the scrolling detail view.
class PostCard extends StatefulWidget {
  const PostCard({
    super.key,
    required this.post,
    required this.onToggleLike,
    this.onOpenAuthor,
    this.onDelete,
  });

  final Post post;

  /// Called with the state the user asked for, not a toggle — so a double tap
  /// that lands twice cannot flip it back off.
  final ValueChanged<bool> onToggleLike;

  final VoidCallback? onOpenAuthor;
  final VoidCallback? onDelete;

  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _burst = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );

  @override
  void dispose() {
    _burst.dispose();
    super.dispose();
  }

  /// Double tap always likes, never unlikes.
  ///
  /// Unliking is a deliberate act and belongs on the heart button. A gesture
  /// that toggles would let an over-eager second tap silently undo the first.
  void _doubleTap() {
    if (!widget.post.likedByMe) widget.onToggleLike(true);

    _burst
      ..reset()
      ..forward();
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.post;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Header(
          post: post,
          onOpenAuthor: widget.onOpenAuthor,
          onDelete: widget.onDelete,
        ),

        GestureDetector(
          onDoubleTap: _doubleTap,
          child: Stack(
            alignment: Alignment.center,
            children: [
              AspectRatio(
                aspectRatio: post.aspectRatio,
                child: Container(
                  color: AppColors.canvasRaised,
                  child: Image.network(
                    post.imageUrl,
                    fit: BoxFit.cover,
                    loadingBuilder: (context, child, progress) =>
                        progress == null
                            ? child
                            : const Center(
                                child: SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.mint,
                                  ),
                                ),
                              ),
                    errorBuilder: (_, __, ___) => const Center(
                      child: Icon(Icons.broken_image_outlined,
                          size: 34, color: AppColors.textMuted),
                    ),
                  ),
                ),
              ),
              _HeartBurst(controller: _burst),
            ],
          ),
        ),

        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
          child: Row(
            children: [
              _LikeButton(
                liked: post.likedByMe,
                onTap: () => widget.onToggleLike(!post.likedByMe),
              ),
              const Spacer(),
              Text(
                post.age,
                style: const TextStyle(
                  fontSize: 11.5,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),

        if (post.likesCount > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 9, 14, 0),
            child: _LikedBy(post: post),
          ),

        if (post.caption != null && post.caption!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
            child: Text.rich(
              TextSpan(children: [
                TextSpan(
                  text: post.author.username ?? post.author.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const TextSpan(text: '  '),
                TextSpan(text: post.caption),
              ]),
              style: const TextStyle(
                fontSize: 13,
                height: 1.4,
                color: AppColors.textMuted,
              ),
            ),
          ),

        if (post.tagged.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 9, 14, 0),
            child: Row(
              children: [
                const Icon(Icons.person_outline_rounded,
                    size: 14, color: AppColors.aqua),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    post.tagged.map((p) => p.handle).join(', '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.aqua,
                    ),
                  ),
                ),
              ],
            ),
          ),

        const SizedBox(height: 22),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.post, this.onOpenAuthor, this.onDelete});

  final Post post;
  final VoidCallback? onOpenAuthor;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
      child: Row(
        children: [
          GestureDetector(
            onTap: onOpenAuthor,
            behavior: HitTestBehavior.opaque,
            child: Row(
              children: [
                PersonAvatar(
                  size: 36,
                  imageUrl: post.author.avatarUrl,
                  initials: post.author.initials,
                ),
                const SizedBox(width: 10),
                Text(
                  post.author.username ?? post.author.name,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          if (post.isMine && onDelete != null)
            IconButton(
              icon: const Icon(Icons.more_vert_rounded,
                  size: 20, color: AppColors.textPrimary),
              onPressed: onDelete,
            ),
        ],
      ),
    );
  }
}

class _LikeButton extends StatelessWidget {
  const _LikeButton({required this.liked, required this.onTap});

  final bool liked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedScale(
        scale: liked ? 1.1 : 1.0,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutBack,
        child: Icon(
          liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
          size: 25,
          color: liked ? AppColors.alertRed : AppColors.textPrimary,
        ),
      ),
    );
  }
}

/// The heart that blooms over the photo on a double tap.
class _HeartBurst extends StatelessWidget {
  const _HeartBurst({required this.controller});

  final AnimationController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        if (controller.isDismissed) return const SizedBox.shrink();

        final t = controller.value;

        // Grow fast, hold, then fade — roughly how a physical stamp lands.
        final scale = t < 0.3
            ? Curves.easeOutBack.transform(t / 0.3) * 1.15
            : 1.15 - (t - 0.3) / 0.7 * 0.15;

        final opacity = t < 0.5 ? 1.0 : 1.0 - (t - 0.5) / 0.5;

        return Opacity(
          opacity: opacity.clamp(0.0, 1.0),
          child: Transform.scale(
            scale: scale.clamp(0.0, 1.3),
            child: const Icon(Icons.favorite_rounded,
                size: 96, color: Colors.white),
          ),
        );
      },
    );
  }
}

/// "Liked by faisal and 6 others", with a small stack of faces.
///
/// Named people first, count second. A bare number says how popular a post is;
/// a name says whether it is popular with anyone you know, which is the part
/// people actually read.
class _LikedBy extends StatelessWidget {
  const _LikedBy({required this.post});

  final Post post;

  @override
  Widget build(BuildContext context) {
    final preview = post.likesPreview;

    return Row(
      children: [
        if (preview.isNotEmpty) ...[
          SizedBox(
            // Three 20px faces overlapping by 7 each.
            width: 20.0 + (preview.length - 1) * 13,
            height: 22,
            child: Stack(
              children: [
                for (var i = preview.length - 1; i >= 0; i--)
                  Positioned(
                    left: i * 13,
                    child: Container(
                      padding: const EdgeInsets.all(1.5),
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.canvas,
                      ),
                      child: PersonAvatar(
                        size: 19,
                        imageUrl: preview[i].avatarUrl,
                        initials: preview[i].initials,
                        fontSize: 8,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 9),
        ],
        Expanded(
          child: Text.rich(
            _label(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12.5,
              height: 1.3,
              color: AppColors.textMuted,
            ),
          ),
        ),
      ],
    );
  }

  TextSpan _label() {
    const bold = TextStyle(
      fontWeight: FontWeight.w700,
      color: AppColors.textPrimary,
    );

    final preview = post.likesPreview;

    // No names came back — fall back to the plain count rather than
    // inventing anybody.
    if (preview.isEmpty) {
      return TextSpan(
        text: post.likesCount == 1 ? '1 like' : '${post.likesCount} likes',
        style: bold,
      );
    }

    final first = preview.first;
    final remaining = post.likesCount - 1;

    if (remaining <= 0) {
      return TextSpan(children: [
        const TextSpan(text: 'Liked by '),
        TextSpan(text: first.username ?? first.name, style: bold),
      ]);
    }

    return TextSpan(children: [
      const TextSpan(text: 'Liked by '),
      TextSpan(text: first.username ?? first.name, style: bold),
      const TextSpan(text: ' and '),
      TextSpan(
        text: remaining == 1 ? '1 other' : '$remaining others',
        style: bold,
      ),
    ]);
  }
}
