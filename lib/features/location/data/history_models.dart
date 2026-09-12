import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'place_models.dart';

/// One entry in a day: somewhere they stopped, or a trip between stops.
///
/// One class with a kind rather than two, because every consumer wants them
/// interleaved in time order and a sealed pair would mean a switch at every
/// use site to ask a question the list has already answered by ordering.
class TimelineEntry {
  const TimelineEntry({
    required this.kind,
    required this.from,
    required this.to,
    required this.seconds,
    this.latitude,
    this.longitude,
    this.place,
    this.metres,
    this.topSpeed,
    this.route = const [],
  });

  static const String stay = 'stay';
  static const String journey = 'journey';

  final String kind;
  final DateTime from;
  final DateTime to;
  final int seconds;

  /// Where a stay was. Null on a journey, which has a route instead.
  final double? latitude;
  final double? longitude;

  /// Which of *my* places the stay fell inside, if any.
  ///
  /// Recomputed by the server from the position rather than read from the
  /// visit record, so a place that has since been moved or renamed describes
  /// the world as it is now — which is the world the reader is in.
  final PlaceRef? place;

  final int? metres;

  /// Metres per second, as reported by the phone at its fastest.
  final double? topSpeed;

  final List<LatLng> route;

  factory TimelineEntry.fromJson(Map<String, dynamic> json) => TimelineEntry(
        kind: json['kind'] as String? ?? stay,
        from: DateTime.parse(json['from'] as String).toLocal(),
        to: DateTime.parse(json['to'] as String).toLocal(),
        seconds: (json['seconds'] as num?)?.toInt() ?? 0,
        latitude: (json['latitude'] as num?)?.toDouble(),
        longitude: (json['longitude'] as num?)?.toDouble(),
        place: json['place'] == null
            ? null
            : PlaceRef.fromJson(json['place'] as Map<String, dynamic>),
        metres: (json['metres'] as num?)?.toInt(),
        topSpeed: (json['top_speed'] as num?)?.toDouble(),
        route: ((json['route'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map((p) => LatLng(
                  (p['latitude'] as num).toDouble(),
                  (p['longitude'] as num).toDouble(),
                ))
            .toList(),
      );

  bool get isStay => kind == stay;

  /// "Home", "Stopped" — what to call the place they were.
  String get title {
    if (!isStay) return 'Journey';

    return place?.name ?? 'Stopped';
  }

  /// "2 hr 15 min", "8 min".
  String get durationLabel => formatDuration(seconds);

  /// "4.2 km".
  String? get distanceLabel {
    final m = metres;

    if (m == null) return null;
    if (m < 1000) return '$m m';

    return '${(m / 1000).toStringAsFixed(1)} km';
  }

  /// Average over the whole segment, which is a more honest headline than
  /// the peak — a single 90 km/h reading on a motorway slip road says very
  /// little about a journey that took forty minutes.
  String? get paceLabel {
    final m = metres;

    if (m == null || seconds < 30) return null;

    final kmh = (m / seconds) * 3.6;

    if (kmh < 1) return null;

    return '${kmh.round()} km/h avg';
  }

  /// The same duration, short enough for a stat tile.
  ///
  /// "12 hr 45 min" wants 116dp and the summary gives each figure 101dp, so
  /// the verbose form arrives pre-shrunk by a FittedBox and reads small next
  /// to the two figures beside it. "12h 45m" fits at full size, and in a
  /// three-across row of numbers the context makes the units obvious.
  static String compactDuration(int seconds) {
    if (seconds < 60) return '${seconds}s';

    final minutes = seconds ~/ 60;

    if (minutes < 60) return '${minutes}m';

    final hours = minutes ~/ 60;
    final rest = minutes % 60;

    if (rest == 0) return '${hours}h';

    return '${hours}h ${rest}m';
  }

  static String formatDuration(int seconds) {
    if (seconds < 60) return '${seconds}s';

    final minutes = seconds ~/ 60;

    if (minutes < 60) return '$minutes min';

    final hours = minutes ~/ 60;
    final rest = minutes % 60;

    if (rest == 0) return '$hours hr';

    return '$hours hr $rest min';
  }
}

/// A day's headline figures.
class DaySummary {
  const DaySummary({
    this.metres = 0,
    this.movingSeconds = 0,
    this.topSpeed = 0,
    this.stays = 0,
    this.points = 0,
    this.truncated = false,
  });

  final int metres;
  final int movingSeconds;
  final double topSpeed;
  final int stays;
  final int points;

  /// The day hit the server's row ceiling and is incomplete.
  ///
  /// Surfaced rather than swallowed: a truncated day looks exactly like
  /// somebody who stopped moving at lunchtime, and that is the wrong thing
  /// for a safety app to imply by accident.
  final bool truncated;

  factory DaySummary.fromJson(Map<String, dynamic> json) => DaySummary(
        metres: (json['metres'] as num?)?.toInt() ?? 0,
        movingSeconds: (json['moving_seconds'] as num?)?.toInt() ?? 0,
        topSpeed: (json['top_speed'] as num?)?.toDouble() ?? 0,
        stays: (json['stays'] as num?)?.toInt() ?? 0,
        points: (json['points'] as num?)?.toInt() ?? 0,
        truncated: json['truncated'] as bool? ?? false,
      );

  String get distanceLabel => metres < 1000
      ? '$metres m'
      : '${(metres / 1000).toStringAsFixed(1)} km';

  String get movingLabel => TimelineEntry.compactDuration(movingSeconds);

  String get topSpeedLabel =>
      topSpeed < 1 ? '—' : '${(topSpeed * 3.6).round()} km/h';
}

/// One person, one day.
class DayTimeline {
  const DayTimeline({
    required this.date,
    required this.entries,
    required this.summary,
  });

  const DayTimeline.empty(this.date)
      : entries = const [],
        summary = const DaySummary();

  final String date;
  final List<TimelineEntry> entries;
  final DaySummary summary;

  factory DayTimeline.fromJson(Map<String, dynamic> json) => DayTimeline(
        date: json['date'] as String? ?? '',
        entries: ((json['entries'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(TimelineEntry.fromJson)
            .toList(),
        summary: DaySummary.fromJson(
          json['summary'] as Map<String, dynamic>? ?? const {},
        ),
      );

  bool get isEmpty => entries.isEmpty;

  /// Every route point of the day, in order — for framing the camera.
  List<LatLng> get allPoints => [
        for (final entry in entries) ...entry.route,
        for (final entry in entries)
          if (entry.isStay && entry.latitude != null)
            LatLng(entry.latitude!, entry.longitude!),
      ];
}

/// Which days in a month have anything in them, for the calendar's dots.
class HistoryMonth {
  const HistoryMonth({
    required this.month,
    required this.days,
    this.oldest,
  });

  const HistoryMonth.empty(this.month)
      : days = const {},
        oldest = null;

  final String month;

  /// `2026-09-11` to the number of fixes recorded that day.
  final Map<String, int> days;

  /// The earliest date the server will answer for. Days before it are drawn
  /// disabled rather than empty — "we do not keep this" and "nothing
  /// happened" are different answers and should not look the same.
  final DateTime? oldest;

  factory HistoryMonth.fromJson(Map<String, dynamic> json) => HistoryMonth(
        month: json['month'] as String? ?? '',
        days: ((json['days'] as Map?) ?? const {}).map(
          (key, value) => MapEntry('$key', (value as num?)?.toInt() ?? 0),
        ),
        oldest: json['oldest'] == null
            ? null
            : DateTime.tryParse(json['oldest'] as String),
      );

  bool has(DateTime day) => (days[_key(day)] ?? 0) > 0;

  bool isTooOld(DateTime day) {
    final floor = oldest;

    if (floor == null) return false;

    return DateTime(day.year, day.month, day.day)
        .isBefore(DateTime(floor.year, floor.month, floor.day));
  }

  static String _key(DateTime day) =>
      '${day.year.toString().padLeft(4, '0')}-'
      '${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';

  static String keyFor(DateTime day) => _key(day);
}
