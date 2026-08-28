import '../../../core/api/api_client.dart';
import '../../../core/api/api_response.dart';

/// People, following, family and notifications.
class PeopleApi {
  PeopleApi({ApiClient? client}) : _api = client ?? ApiClient();

  final ApiClient _api;

  // --- Discovery ---------------------------------------------------------

  Future<ApiResponse> search(String term) =>
      _api.get('users/search?q=${Uri.encodeQueryComponent(term)}');

  Future<ApiResponse> profile(String userId) => _api.get('users/$userId');

  // --- Following ---------------------------------------------------------

  Future<ApiResponse> follow(String userId) =>
      _api.post('users/$userId/follow');

  /// Unfollow, or withdraw a request that has not been answered yet.
  Future<ApiResponse> unfollow(String userId) =>
      _api.delete('users/$userId/follow');

  Future<ApiResponse> removeFollower(String userId) =>
      _api.delete('users/$userId/follower');

  Future<ApiResponse> respondToFollowRequest(String requestId, bool accept) =>
      _api.post('follow-requests/$requestId/respond', body: {'accept': accept});

  Future<ApiResponse> followRequests() => _api.get('follow-requests');

  Future<ApiResponse> followers(String userId) =>
      _api.get('users/$userId/followers');

  Future<ApiResponse> following(String userId) =>
      _api.get('users/$userId/following');

  // --- Family ------------------------------------------------------------

  Future<ApiResponse> family() => _api.get('family');

  Future<ApiResponse> inviteToFamily(String userId, {String? relation}) =>
      _api.post('users/$userId/family', body: {
        if (relation != null) 'relation': relation,
      });

  Future<ApiResponse> respondToFamilyInvite(
    String inviteId,
    bool accept, {
    String? relation,
  }) =>
      _api.post('family-invites/$inviteId/respond', body: {
        'accept': accept,
        if (relation != null) 'relation': relation,
      });

  Future<ApiResponse> removeFamilyMember(String familyId) =>
      _api.delete('family/$familyId');

  // --- Blocking ----------------------------------------------------------

  Future<ApiResponse> block(String userId, {String? reason}) =>
      _api.post('users/$userId/block', body: {
        if (reason != null) 'reason': reason,
      });

  Future<ApiResponse> unblock(String userId) =>
      _api.delete('users/$userId/block');

  Future<ApiResponse> blockedAccounts() => _api.get('blocks');

  // --- Notifications -----------------------------------------------------

  Future<ApiResponse> notifications({int page = 1}) =>
      _api.get('notifications?page=$page');

  Future<ApiResponse> unreadCount() => _api.get('notifications/unread-count');

  Future<ApiResponse> markRead(String id) =>
      _api.post('notifications/$id/read');

  Future<ApiResponse> markAllRead() => _api.post('notifications/read-all');

  void dispose() => _api.dispose();
}
