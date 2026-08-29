/// Environment-specific configuration.
///
/// Override the base URL at build time without editing this file:
///
///   flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000/api/v1
///
/// (10.0.2.2 is how an Android emulator reaches the host machine's localhost.)
class AppConfig {
  const AppConfig._();

  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://admin-cp.sfamily.co/api/v1',
  );

  /// The Reverb application key.
  ///
  /// Safe to keep in the repo. Unlike REVERB_APP_SECRET, the key is public by
  /// design: it travels in the WebSocket URL of every client that connects,
  /// so it is already visible to anyone who looks at network traffic. What
  /// actually protects a conversation is channel authorisation — every
  /// private subscription is signed server-side with the secret, which never
  /// leaves EC2. Holding the key alone lets somebody open a socket and
  /// subscribe to nothing.
  ///
  /// Override for a local Reverb, or set it empty to turn the realtime layer
  /// off entirely — with no key the app falls back to exactly how it behaved
  /// before websockets existed, which is a useful thing to be able to do
  /// while diagnosing something:
  ///
  ///   flutter run --dart-define=REVERB_KEY=
  static const String reverbKey = String.fromEnvironment(
    'REVERB_KEY',
    defaultValue: 'lrqwccbcdgoprday7bub',
  );

  /// Where the websocket lives. Behind nginx on 443 in production; point it
  /// at the machine running `php artisan reverb:start` in development:
  ///
  ///   --dart-define=REVERB_HOST=10.0.2.2
  ///   --dart-define=REVERB_PORT=8080
  ///   --dart-define=REVERB_TLS=false
  static const String reverbHost = String.fromEnvironment(
    'REVERB_HOST',
    defaultValue: 'ws.sfamily.co',
  );

  static const int reverbPort = int.fromEnvironment(
    'REVERB_PORT',
    defaultValue: 443,
  );

  static const bool reverbTls = bool.fromEnvironment(
    'REVERB_TLS',
    defaultValue: true,
  );

  /// Whether to open a socket at all.
  static bool get realtimeEnabled => reverbKey.isNotEmpty;

  /// How long to wait on any single request before giving up.
  static const Duration requestTimeout = Duration(seconds: 15);

  /// Uploads get their own, much longer.
  ///
  /// 15 seconds is generous for a JSON round trip and hopeless for a photo on
  /// mobile data — a 4 MB file at 500 kbps is over a minute. Sharing the
  /// short timeout would mean uploads failing constantly on exactly the
  /// connections where they matter most.
  static const Duration uploadTimeout = Duration(minutes: 3);
}
