import 'package:flutter/foundation.dart';

/// Somebody named on a post — its author, or a tagged person.
@immutable
class PostPerson {
  const PostPerson({
    required this.id,
    required this.name,
    this.username,
    this.avatarUrl,
  });

  final String id;
  final String name;
  final String? username;
  final String? avatarUrl;

  String get handle => username == null ? name : '@$username';

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  factory PostPerson.fromJson(Map<String, dynamic> json) => PostPerson(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        username: json['username'] as String?,
        avatarUrl: json['avatar_url'] as String?,
      );
}

/// A photo post.
@immutable
class Post {
  const Post({
    required this.id,
    required this.imageUrl,
    required this.author,
    this.caption,
    this.likesCount = 0,
    this.likedByMe = false,
    this.isMine = false,
    this.width = 1,
    this.height = 1,
    this.createdAt,
    this.tagged = const [],
    this.likesPreview = const [],
  });

  final String id;
  final String imageUrl;
  final PostPerson author;
  final String? caption;
  final int likesCount;
  final bool likedByMe;
  final bool isMine;
  final int width;
  final int height;
  final DateTime? createdAt;
  final List<PostPerson> tagged;

  /// A few recent likers, for the "Liked by …" line. Capped by the
  /// API — never the full list.
  final List<PostPerson> likesPreview;

  double get aspectRatio => height == 0 ? 1 : width / height;

  /// "2h", "3d", "5w" — computed on the device so it matches the phone clock.
  String get age {
    if (createdAt == null) return '';

    final d = DateTime.now().difference(createdAt!.toLocal());

    if (d.inSeconds < 60) return 'now';
    if (d.inMinutes < 60) return '${d.inMinutes}m';
    if (d.inHours < 24) return '${d.inHours}h';
    if (d.inDays < 7) return '${d.inDays}d';
    if (d.inDays < 365) return '${(d.inDays / 7).floor()}w';

    return '${(d.inDays / 365).floor()}y';
  }

  Post copyWith({int? likesCount, bool? likedByMe}) => Post(
        id: id,
        imageUrl: imageUrl,
        author: author,
        caption: caption,
        likesCount: likesCount ?? this.likesCount,
        likedByMe: likedByMe ?? this.likedByMe,
        isMine: isMine,
        width: width,
        height: height,
        createdAt: createdAt,
        tagged: tagged,
        likesPreview: likesPreview,
      );

  factory Post.fromJson(Map<String, dynamic> json) => Post(
        id: json['id'] as String? ?? '',
        imageUrl: json['image_url'] as String? ?? '',
        caption: json['caption'] as String?,
        likesCount: json['likes_count'] as int? ?? 0,
        likedByMe: json['liked_by_me'] as bool? ?? false,
        isMine: json['is_mine'] as bool? ?? false,
        width: json['width'] as int? ?? 1,
        height: json['height'] as int? ?? 1,
        createdAt: DateTime.tryParse(json['created_at'] as String? ?? ''),
        author: PostPerson.fromJson(
          json['author'] as Map<String, dynamic>? ?? const {},
        ),
        tagged: (json['tagged'] as List?)
                ?.whereType<Map<String, dynamic>>()
                .map(PostPerson.fromJson)
                .toList() ??
            const [],
        likesPreview: (json['likes_preview'] as List?)
                ?.whereType<Map<String, dynamic>>()
                .map(PostPerson.fromJson)
                .toList() ??
            const [],
      );
}

/// One page of somebody's grid.
@immutable
class PostPage {
  const PostPage({
    required this.posts,
    required this.canView,
    required this.total,
    required this.page,
    required this.hasMore,
  });

  final List<Post> posts;

  /// False when the account is private and the viewer is not an accepted
  /// follower. The grid draws a locked panel rather than an empty state — an
  /// empty grid would read as "no posts", which is a different thing.
  final bool canView;

  final int total;
  final int page;
  final bool hasMore;

  factory PostPage.fromJson(Map<String, dynamic> json) => PostPage(
        posts: (json['posts'] as List?)
                ?.whereType<Map<String, dynamic>>()
                .map(Post.fromJson)
                .toList() ??
            const [],
        canView: json['can_view'] as bool? ?? true,
        total: json['total'] as int? ?? 0,
        page: json['page'] as int? ?? 1,
        hasMore: json['has_more'] as bool? ?? false,
      );
}
