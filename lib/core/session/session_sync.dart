import '../api/api_client.dart';
import '../device/device_timezone.dart';
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
      await _syncTimezone(api);
    }
  } catch (_) {
    // Offline, timeout, or a server hiccup. The cached user stands.
  } finally {
    api.dispose();
  }
}

/// Keep the server's idea of the user's timezone matching the device.
///
/// This is what makes "daily" mean the right thing for a user anywhere in the
/// world. The server decides when a check-in day rolls over and when a
/// reminder fires, and it has to do both while the app is closed — so it needs
/// the zone stored, not inferred from whoever happens to be calling.
///
/// It also handles travel: land in another country, open the app, and the day
/// boundary follows you.
///
/// Only ever sent when it actually differs, so the common case costs nothing.
Future<void> _syncTimezone(ApiClient api) async {
  final device = await DeviceTimezone.name();

  if (device == null) return;
  if (Session.instance.user?.timezone == device) return;

  try {
    final res = await api.patch('profile', body: {'timezone': device});

    if (res.success && res.dataMap.isNotEmpty) {
      await Session.instance.updateUser(AuthUser.fromJson(res.dataMap));
    }
  } catch (_) {
    // Not worth a retry loop — the next sync will try again.
  }
}
