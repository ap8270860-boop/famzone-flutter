import '../../chat/data/chat_models.dart';

/// A single reading, on its way up.
///
/// The client's half of the contract with `POST /location/ping`. Deliberately
/// dumb: no filtering happens here, because a phone that decides for itself
/// which of its readings are worth sending is a phone whose bugs you cannot
/// fix without a store release.
class LocationFix {
  const LocationFix({
    required this.latitude,
    required this.longitude,
    required this.recordedAt,
    this.accuracy,
    this.speed,
    this.heading,
    this.moving = false,
    this.batteryLevel,
  });

  final double latitude;
  final double longitude;
  final DateTime recordedAt;

  /// Metres, as a 68% confidence radius.
  final double? accuracy;

  /// Metres per second, in the unit both platforms report.
  final double? speed;

  /// Degrees clockwise from true north.
  final double? heading;

  final bool moving;
  final int? batteryLevel;

  Map<String, dynamic> toJson() => {
        'latitude': latitude,
        'longitude': longitude,
        'recorded_at': recordedAt.toUtc().toIso8601String(),
        if (accuracy != null) 'accuracy': accuracy,
        if (speed != null) 'speed': speed,
        if (heading != null) 'heading': heading,
        'moving': moving,
        if (batteryLevel != null) 'battery_level': batteryLevel,
      };
}

/// Where somebody is, as the map draws them.
class LivePosition {
  const LivePosition({
    required this.userId,
    required this.hasFix,
    this.latitude,
    this.longitude,
    this.accuracy,
    this.speed,
    this.heading,
    this.moving = false,
    this.batteryLevel,
    this.recordedAt,
    this.ageSeconds,
  });

  final String userId;

  /// False before the first fix lands. A pin is not drawn for these — an
  /// avatar sitting at 0°N 0°E in the Gulf of Guinea is the classic tell of
  /// a null coordinate that nobody guarded.
  final bool hasFix;

  final double? latitude;
  final double? longitude;
  final double? accuracy;
  final double? speed;
  final double? heading;
  final bool moving;
  final int? batteryLevel;
  final DateTime? recordedAt;

  /// How old the server thought this was when it sent it.
  ///
  /// Used in preference to comparing timestamps, because that would mean
  /// trusting the phone's clock against the server's — and a device an hour
  /// fast would grey out every pin on the map.
  final int? ageSeconds;

  factory LivePosition.fromJson(Map<String, dynamic> json) {
    double? number(Object? value) =>
        value == null ? null : (value as num).toDouble();

    return LivePosition(
      userId: json['user_id'] as String? ?? '',
      hasFix: json['has_fix'] as bool? ?? json['latitude'] != null,
      latitude: number(json['latitude']),
      longitude: number(json['longitude']),
      accuracy: number(json['accuracy']),
      speed: number(json['speed']),
      heading: number(json['heading']),
      moving: json['moving'] as bool? ?? false,
      batteryLevel: (json['battery_level'] as num?)?.toInt(),
      recordedAt: json['recorded_at'] == null
          ? null
          : DateTime.tryParse(json['recorded_at'] as String)?.toLocal(),
      ageSeconds: (json['age_seconds'] as num?)?.toInt(),
    );
  }

  /// Old enough that the map should stop presenting it as the truth.
  ///
  /// A stale dot on a safety app is worse than no dot, because people act on
  /// it. The pin stays — knowing where somebody was twenty minutes ago is
  /// still useful — but it is drawn dimmed and labelled with its age.
  bool get isStale => (ageSeconds ?? 0) > 180;

  /// "Now", "2 min ago", "1 hr ago".
  String get ageLabel {
    final seconds = ageSeconds ?? 0;

    if (seconds < 45) return 'Now';
    if (seconds < 3600) return '${(seconds / 60).round()} min ago';
    if (seconds < 86400) return '${(seconds / 3600).round()} hr ago';

    return '${(seconds / 86400).round()} d ago';
  }

  /// Kilometres per hour, for a label. Null below walking pace, where the
  /// reported figure is mostly noise and showing "2 km/h" for somebody
  /// standing still looks like a bug.
  double? get speedKmh {
    final value = speed;

    if (value == null || value < 1.0) return null;

    return value * 3.6;
  }
}

/// Permission to be seen, with an expiry on it.
class LocationShare {
  const LocationShare({
    required this.id,
    required this.userId,
    required this.audience,
    required this.active,
    this.conversationId,
    this.startedAt,
    this.expiresAt,
    this.endedAt,
  });

  static const String audienceConversation = 'conversation';
  static const String audienceFamily = 'family';

  final String id;
  final String userId;
  final String audience;
  final bool active;
  final String? conversationId;
  final DateTime? startedAt;

  /// Null on a family share, which runs until it is stopped.
  final DateTime? expiresAt;
  final DateTime? endedAt;

  factory LocationShare.fromJson(Map<String, dynamic> json) => LocationShare(
        id: json['id'] as String? ?? '',
        userId: json['user_id'] as String? ?? '',
        audience: json['audience'] as String? ?? audienceConversation,
        active: json['active'] as bool? ?? false,
        conversationId: json['conversation_id'] as String?,
        startedAt: json['started_at'] == null
            ? null
            : DateTime.tryParse(json['started_at'] as String)?.toLocal(),
        expiresAt: json['expires_at'] == null
            ? null
            : DateTime.tryParse(json['expires_at'] as String)?.toLocal(),
        endedAt: json['ended_at'] == null
            ? null
            : DateTime.tryParse(json['ended_at'] as String)?.toLocal(),
      );

  bool get isFamily => audience == audienceFamily;

  Duration? get remaining {
    final end = expiresAt;

    if (end == null) return null;

    final left = end.difference(DateTime.now());

    return left.isNegative ? Duration.zero : left;
  }

  /// "4 hr 12 min left", "8 min left", "Until you stop".
  String get remainingLabel {
    final left = remaining;

    if (left == null) return 'Until you stop';
    if (left == Duration.zero) return 'Ended';

    final hours = left.inHours;
    final minutes = left.inMinutes % 60;

    if (hours > 0) return '$hours hr $minutes min left';

    return '${left.inMinutes + 1} min left';
  }
}

/// What the server says the phone should do next.
///
/// The client holds no opinion of its own about sampling rates. Everything
/// here arrives on every ping response, which is what lets the cadence be
/// tuned — or a runaway tracker shut down — without a store release.
class TrackingPlan {
  const TrackingPlan({
    required this.active,
    this.intervalSeconds,
    this.distanceFilter,
    this.until,
    this.background = false,
  });

  const TrackingPlan.idle()
      : active = false,
        intervalSeconds = null,
        distanceFilter = null,
        until = null,
        background = false;

  final bool active;
  final int? intervalSeconds;
  final int? distanceFilter;
  final DateTime? until;

  /// Whether this warrants running with the app in the background — which is
  /// to say, a permanent notification on Android and the "Always" permission
  /// on iOS. Only a family share earns it.
  final bool background;

  factory TrackingPlan.fromJson(Map<String, dynamic> json) => TrackingPlan(
        active: json['active'] as bool? ?? false,
        intervalSeconds: (json['interval_seconds'] as num?)?.toInt(),
        distanceFilter: (json['distance_filter'] as num?)?.toInt(),
        until: json['until'] == null
            ? null
            : DateTime.tryParse(json['until'] as String)?.toLocal(),
        background: json['background'] as bool? ?? false,
      );

  Duration get interval => Duration(seconds: intervalSeconds ?? 30);

  int get distance => distanceFilter ?? 25;

  /// Whether two plans would configure the stream identically. Used to avoid
  /// tearing down and rebuilding a healthy location stream on every ping
  /// response, which on Android costs a fresh satellite acquisition.
  bool sameShapeAs(TrackingPlan other) =>
      active == other.active &&
      intervalSeconds == other.intervalSeconds &&
      distanceFilter == other.distanceFilter &&
      background == other.background;
}

/// One person on the map.
class LivePerson {
  const LivePerson({
    required this.user,
    required this.position,
    required this.share,
  });

  final ChatPerson user;
  final LivePosition position;
  final LocationShare share;

  factory LivePerson.fromJson(Map<String, dynamic> json) => LivePerson(
        user: ChatPerson.fromJson(json['user'] as Map<String, dynamic>),
        position: LivePosition.fromJson(
          json['position'] as Map<String, dynamic>? ?? const {},
        ),
        share: LocationShare.fromJson(
          json['share'] as Map<String, dynamic>? ?? const {},
        ),
      );

  LivePerson withPosition(LivePosition next) =>
      LivePerson(user: user, position: next, share: share);

  LivePerson withShare(LocationShare next) =>
      LivePerson(user: user, position: position, share: next);
}

/// The location half of a chat message.
class MessageLocation {
  const MessageLocation({
    this.latitude,
    this.longitude,
    this.live = false,
    this.active = false,
    this.shareId,
    this.expiresAt,
    this.endedAt,
  });

  final double? latitude;
  final double? longitude;

  /// Whether this bubble announced a live share rather than a static pin.
  final bool live;

  /// Whether that share is still running. A live bubble whose share has
  /// ended stays in the thread as a record — it just stops claiming to be
  /// current.
  final bool active;

  final String? shareId;
  final DateTime? expiresAt;
  final DateTime? endedAt;

  factory MessageLocation.fromJson(Map<String, dynamic> json) {
    double? number(Object? value) =>
        value == null ? null : (value as num).toDouble();

    return MessageLocation(
      latitude: number(json['latitude']),
      longitude: number(json['longitude']),
      live: json['live'] as bool? ?? false,
      active: json['active'] as bool? ?? false,
      shareId: json['share_id'] as String?,
      expiresAt: json['expires_at'] == null
          ? null
          : DateTime.tryParse(json['expires_at'] as String)?.toLocal(),
      endedAt: json['ended_at'] == null
          ? null
          : DateTime.tryParse(json['ended_at'] as String)?.toLocal(),
    );
  }

  bool get hasPoint => latitude != null && longitude != null;
}

/// A path behind a marker.
class LocationTrail {
  const LocationTrail({required this.userId, required this.points});

  final String userId;
  final List<TrailPoint> points;

  factory LocationTrail.fromJson(Map<String, dynamic> json) => LocationTrail(
        userId: json['user_id'] as String? ?? '',
        points: ((json['points'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(TrailPoint.fromJson)
            .toList(),
      );
}

class TrailPoint {
  const TrailPoint({
    required this.latitude,
    required this.longitude,
    this.recordedAt,
  });

  final double latitude;
  final double longitude;
  final DateTime? recordedAt;

  factory TrailPoint.fromJson(Map<String, dynamic> json) => TrailPoint(
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
        recordedAt: json['recorded_at'] == null
            ? null
            : DateTime.tryParse(json['recorded_at'] as String)?.toLocal(),
      );
}
