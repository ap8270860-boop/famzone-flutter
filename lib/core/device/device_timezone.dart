import 'package:flutter/foundation.dart';
import 'package:flutter_timezone/flutter_timezone.dart';

/// The device's IANA timezone name, e.g. "Asia/Kolkata", "Europe/Berlin".
///
/// The server needs a real zone name, not an offset. Offsets cannot express
/// daylight saving — "UTC+1" is Berlin in winter and London in summer — and
/// the server has to answer questions like "when does this user's day roll
/// over" and "when should tomorrow's reminder fire" hours in advance, with
/// the app closed.
///
/// Dart cannot supply one on its own: `DateTime.now().timeZoneName` returns
/// whatever the platform feels like ("IST", "GMT+05:30", "India Standard
/// Time"), none of which are IANA identifiers. Hence the plugin.
abstract final class DeviceTimezone {
  static String? _cached;

  /// Null when the platform will not say. Callers should treat that as "leave
  /// the stored zone alone" rather than guessing.
  static Future<String?> name() async {
    if (_cached != null) return _cached;

    try {
      // flutter_timezone 3.x returns a String here; 4.x returns a TimezoneInfo
      // with an `identifier`. Read it dynamically so either version compiles —
      // a static reference to `.identifier` fails to build on 3.x, and the
      // resolved version depends on the Dart SDK on whichever machine runs
      // `pub get`.
      final dynamic zone = await FlutterTimezone.getLocalTimezone();
      final name = (zone is String ? zone : zone.identifier as String).trim();

      // A bare offset is not usable server-side, so reject it rather than
      // storing something Carbon will refuse.
      if (name.isEmpty || !name.contains('/')) return null;

      return _cached = name;
    } catch (e) {
      debugPrint('[timezone] could not read device zone: $e');
      return null;
    }
  }

  /// Forget the cached value — used when the app resumes, since somebody who
  /// just landed in another country is exactly who this feature is for.
  static void invalidate() => _cached = null;
}
