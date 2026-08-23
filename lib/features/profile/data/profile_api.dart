import '../../../core/api/api_client.dart';
import '../../../core/api/api_response.dart';

/// What the server said about a username the user is typing.
class UsernameStatus {
  const UsernameStatus({
    required this.username,
    required this.available,
    required this.reason,
    required this.message,
    this.suggestions = const [],
  });

  final String username;
  final bool available;

  /// available | taken | current | reserved | too_short | too_long |
  /// invalid_characters
  final String reason;

  final String message;
  final List<String> suggestions;

  bool get isCurrent => reason == 'current';

  factory UsernameStatus.fromJson(Map<String, dynamic> json) {
    return UsernameStatus(
      username: json['username'] as String? ?? '',
      available: json['available'] as bool? ?? false,
      reason: json['reason'] as String? ?? 'taken',
      message: json['message'] as String? ?? '',
      suggestions: (json['suggestions'] as List?)?.cast<String>() ?? const [],
    );
  }
}

/// Everything the profile screens ask of the API.
class ProfileApi {
  ProfileApi({ApiClient? client}) : _api = client ?? ApiClient();

  final ApiClient _api;

  Future<ApiResponse> fetch() => _api.get('profile');

  /// Send only what changed — the endpoint patches, it does not replace.
  Future<ApiResponse> update(Map<String, dynamic> changes) =>
      _api.patch('profile', body: changes);

  Future<UsernameStatus> checkUsername(String username) async {
    final res = await _api.get(
      'profile/username/check?username=${Uri.encodeQueryComponent(username)}',
    );
    return UsernameStatus.fromJson(res.dataMap);
  }

  Future<ApiResponse> changePassword({
    String? currentPassword,
    required String password,
    required String confirmation,
  }) =>
      _api.post('profile/password', body: {
        if (currentPassword != null) 'current_password': currentPassword,
        'password': password,
        'password_confirmation': confirmation,
      });

  /// [slot] is 'primary' or 'alternate'.
  Future<ApiResponse> uploadAvatar(String filePath, {String slot = 'primary'}) =>
      _api.upload(
        'profile/avatar',
        field: 'avatar',
        filePath: filePath,
        fields: {'slot': slot},
      );

  Future<ApiResponse> removeAvatar({String slot = 'primary'}) =>
      _api.delete('profile/avatar?slot=$slot');

  void dispose() => _api.dispose();
}
