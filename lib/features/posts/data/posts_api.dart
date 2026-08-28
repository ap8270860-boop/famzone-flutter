import '../../../core/api/api_client.dart';
import '../../../core/api/api_response.dart';

/// Post endpoints.
class PostsApi {
  PostsApi({ApiClient? client}) : _api = client ?? ApiClient();

  final ApiClient _api;

  Future<ApiResponse> forUser(String userId, {int page = 1}) =>
      _api.get('users/$userId/posts?page=$page');

  Future<ApiResponse> taggedIn(String userId, {int page = 1}) =>
      _api.get('users/$userId/tagged-posts?page=$page');

  Future<ApiResponse> show(String postId) => _api.get('posts/$postId');

  Future<ApiResponse> create({
    required String imagePath,
    String? caption,
    List<String> tagged = const [],
  }) =>
      _api.upload(
        'posts',
        field: 'image',
        filePath: imagePath,
        fields: {
          if (caption != null && caption.isNotEmpty) 'caption': caption,
          // Laravel reads repeated `tagged[]` keys as an array. Sent as
          // indexed keys because multipart has no native list type.
          for (var i = 0; i < tagged.length; i++) 'tagged[$i]': tagged[i],
        },
      );

  Future<ApiResponse> delete(String postId) => _api.delete('posts/$postId');

  Future<ApiResponse> like(String postId) => _api.post('posts/$postId/like');

  Future<ApiResponse> unlike(String postId) =>
      _api.delete('posts/$postId/like');

  Future<ApiResponse> likes(String postId) => _api.get('posts/$postId/likes');

  void dispose() => _api.dispose();
}
