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

  /// How long to wait on any single request before giving up.
  static const Duration requestTimeout = Duration(seconds: 15);
}
