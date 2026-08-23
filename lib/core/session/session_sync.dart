import '../api/api_client.dart';
import 'session.dart';

/// Re-read the signed-in user from the API and refresh [Session].
///
/// Worth doing on every launch and on pull-to-refresh, because avatar links
/// are signed and expire (`User::MEDIA_LINK_HOURS` on the server). A user
/// object restored from secure storage can easily be older than that, and a
/// stale link renders as the initials fallback rather than the photo — which
/// looks exactly like "my avatar didn't save".
///
/// Deliberately silent. This runs in the background behind a screen that is
/// already showing the cached user, so a failure means "keep what we have",
/// never an error in the user's face.
Future<void> syncSession() async {
  if (!Session.instance.isAuthenticated) return;

  final api = ApiClient();

  try {
    final res = await api.get('me');

    if (res.success && res.dataMap.isNotEmpty) {
      await Session.instance.updateUser(AuthUser.fromJson(res.dataMap));
    }
  } catch (_) {
    // Offline, timeout, or a server hiccup. The cached user stands.
  } finally {
    api.dispose();
  }
}
