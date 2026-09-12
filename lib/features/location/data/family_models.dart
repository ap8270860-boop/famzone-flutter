import 'dart:math' as math;
import 'dart:ui' show Color;

import '../../chat/data/chat_models.dart';
import 'location_models.dart';
import 'place_models.dart';

/// Whether somebody is reachable, and when they last were.
///
/// Separate from position staleness on purpose. They are different questions:
/// staleness asks "is this pin still worth believing", presence asks "is this
/// person contactable". A phone in a pocket with the screen off stops
/// producing fixes long before its owner stops being reachable, and conflating
/// the two makes a family of five look like a family that has gone missing.
class Presence {
  const Presence({required this.state, this.lastSeenAt, this.ageSeconds});

  static const String online = 'online';
  static const String offline = 'offline';

  /// The other person has last-seen switched off. Not "offline" — we do not
  /// know, and saying otherwise would be inventing information about somebody
  /// who explicitly asked us not to share it.
  static const String hidden = 'hidden';

  final String state;
  final DateTime? lastSeenAt;
  final int? ageSeconds;

  const Presence.unknown()
      : state = hidden,
        lastSeenAt = null,
        ageSeconds = null;

  factory Presence.fromJson(Map<String, dynamic> json) => Presence(
        state: json['state'] as String? ?? hidden,
        lastSeenAt: json['last_seen_at'] == null
            ? null
            : DateTime.tryParse(json['last_seen_at'] as String)?.toLocal(),
        ageSeconds: (json['age_seconds'] as num?)?.toInt(),
      );

  bool get isOnline => state == online;
  bool get isHidden => state == hidden;

  /// "Online", "Last seen 12 min ago", "Last seen unknown".
  String get label {
    if (isOnline) return 'Online';
    if (isHidden) return 'Last seen hidden';

    final seconds = ageSeconds;

    if (seconds == null) return 'Offline';
    if (seconds < 3600) return 'Last seen ${(seconds / 60).round()} min ago';
    if (seconds < 86400) return 'Last seen ${(seconds / 3600).round()} hr ago';

    return 'Last seen ${(seconds / 86400).round()} d ago';
  }
}

/// One family member, sharing or not.
///
/// The distinction from [LivePerson] is the whole reason this exists.
/// `LivePerson` is somebody the map can draw; this is somebody in the family.
/// The second set is larger, and the status card is about the second set — a
/// card that says "4 members safe" has to count the member whose phone is in
/// a drawer, or it is not a family status card.
class FamilyMemberLive {
  const FamilyMemberLive({
    required this.user,
    required this.sharing,
    required this.presence,
    required this.movement,
    this.position,
    this.place,
  });

  final ChatPerson user;

  /// Whether they are currently sharing *with me*. False means [position] is
  /// null — not that it is old. Permission to be seen does not outlive the
  /// share, so there is deliberately nothing to fall back to.
  final bool sharing;

  final Presence presence;

  /// `travelling`, `stationary`, `stale`, `unknown` — and, once family places
  /// exist, a place key such as `home` or `school`. The server decides the
  /// vocabulary so it can grow without a store release; anything this client
  /// does not recognise falls through to a humanised version of the string.
  final String movement;

  final LivePosition? position;

  /// The place they are inside, if any — name, kind and id only.
  ///
  /// Separate from [movement], which carries the *kind* as a key this file
  /// can switch on. The name travels here because people name their own
  /// places, so "At Nani's house" has to render on a build that has never
  /// heard of a place called that — which is every build.
  final PlaceRef? place;

  factory FamilyMemberLive.fromJson(Map<String, dynamic> json) =>
      FamilyMemberLive(
        user: ChatPerson.fromJson(json['user'] as Map<String, dynamic>),
        sharing: json['sharing'] as bool? ?? false,
        presence: Presence.fromJson(
          json['presence'] as Map<String, dynamic>? ?? const {},
        ),
        movement: json['movement'] as String? ?? 'unknown',
        position: json['position'] == null
            ? null
            : LivePosition.fromJson(json['position'] as Map<String, dynamic>),
        place: json['place'] == null
            ? null
            : PlaceRef.fromJson(json['place'] as Map<String, dynamic>),
      );

  bool get hasFix => position?.hasFix ?? false;

  /// What to write under their name.
  ///
  /// The place's own name wins over everything, because "At School" is what
  /// the reader asked for and "Travelling" is what the accelerometer
  /// happened to notice. Somebody walking around inside school grounds is
  /// moving *and* at school; only one of those answers the question.
  String get statusLabel {
    final at = place;

    if (at != null) return 'At ${at.name}';

    return switch (movement) {
      'travelling' => 'Travelling',
      'stationary' => 'Not moving',
      'stale' => 'Position is old',
      'unknown' => sharing ? 'Waiting for a fix' : 'Not sharing',
      // A movement key this build has never seen. Title-cased rather than
      // dropped: "At Badminton_club" is odd, but a blank line where a status
      // should be looks like a bug.
      _ => 'At ${_humanise(movement)}',
    };
  }

  /// The colour and glyph for that status, if it is a place.
  Color? get placeTint => place == null ? null : PlaceKinds.tint(place!.kind);

  static String _humanise(String key) {
    final words = key.replaceAll('_', ' ').trim();

    if (words.isEmpty) return 'a place';

    return words[0].toUpperCase() + words.substring(1);
  }
}

/// Somebody just started sharing their location with me.
///
/// Deliberately tiny. The websocket frame that raises this carries a share, a
/// position and now three fields about the person — enough for a banner to
/// render on the frame it arrives, with no round trip. Anything more belongs
/// on the map screen the banner opens.
class SharingNotice {
  const SharingNotice({
    required this.userId,
    required this.name,
    required this.at,
    this.avatarUrl,
    this.hasFix = false,
  });

  final String userId;
  final String name;
  final DateTime at;
  final String? avatarUrl;

  /// Whether their opening fix came with the event.
  ///
  /// It usually does — the server ships the first position alongside the
  /// announcement precisely so the pin is not empty for a minute. When it
  /// does not, the banner still opens the map; the pin simply fills in on
  /// their next ping.
  final bool hasFix;

  /// Up to two initials, for the avatar fallback.
  String get initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);

    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();

    return (parts.first[0] + parts.last[0]).toUpperCase();
  }
}

/// One count on the family status card.
class StatusBucket {
  const StatusBucket({
    required this.key,
    required this.label,
    required this.count,
    this.icon,
  });

  final String key;
  final String label;
  final int count;

  /// A name, not an icon. The server picks it so Phase 2 can add "school"
  /// without a store release; an unknown name draws a neutral glyph.
  final String? icon;

  factory StatusBucket.fromJson(Map<String, dynamic> json) => StatusBucket(
        key: json['key'] as String? ?? '',
        label: json['label'] as String? ?? '',
        count: (json['count'] as num?)?.toInt() ?? 0,
        icon: json['icon'] as String?,
      );
}

/// The card across the top of the map.
class FamilyStatus {
  const FamilyStatus({
    required this.tone,
    required this.headline,
    required this.detail,
    required this.buckets,
  });

  const FamilyStatus.empty()
      : tone = 'empty',
        headline = 'No family yet',
        detail = 'Add family members to see them here.',
        buckets = const [];

  /// `safe`, `caution`, `alert`, `empty`. Drives the colour, nothing else.
  final String tone;

  final String headline;
  final String detail;
  final List<StatusBucket> buckets;

  factory FamilyStatus.fromJson(Map<String, dynamic> json) => FamilyStatus(
        tone: json['tone'] as String? ?? 'safe',
        headline: json['headline'] as String? ?? '',
        detail: json['detail'] as String? ?? '',
        buckets: ((json['buckets'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(StatusBucket.fromJson)
            .toList(),
      );
}

/*
|------------------------------------------------------------------------------
| Geometry, client side
|------------------------------------------------------------------------------
*/

/// Distance and travel-time maths, done on the phone.
///
/// Deliberately not a Routes API call. A road distance and a traffic-aware ETA
/// are better numbers, and they are billed per request — with a family of five
/// on a map that refreshes, it is the line item that grows fastest. These are
/// honest approximations and the UI labels them as approximate, which is worth
/// more than a precise number nobody checked.
class Geo {
  const Geo._();

  static const double _earthMetres = 6371000.0;

  /// Great-circle distance in metres.
  ///
  /// Haversine rather than a flat-earth approximation, for the same reason
  /// the server uses it: the flat version's error grows with latitude, and a
  /// distance that drifts with where you are is one nobody can reason about.
  static double metresBetween(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    final dLat = _radians(lat2 - lat1);
    final dLng = _radians(lng2 - lng1);

    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_radians(lat1)) *
            math.cos(_radians(lat2)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);

    return _earthMetres * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  static double _radians(double degrees) => degrees * math.pi / 180.0;

  /// "450 m", "1.2 km", "34 km".
  static String distanceLabel(double metres) {
    if (metres < 1000) return '${(metres / 10).round() * 10} m';

    final km = metres / 1000;

    if (km < 100) return '${km.toStringAsFixed(1)} km';

    return '${km.round()} km';
  }

  /// Roughly how long until you could reach them.
  ///
  /// Straight-line distance over an assumed pace, and every part of that is a
  /// simplification: roads are longer than the line, traffic exists, and the
  /// pace below is a guess. It is returned as "~18 min" and never as "18 min",
  /// because the tilde is doing real work — it is the difference between an
  /// estimate and a promise.
  ///
  /// The pace scales with distance rather than being fixed. Two kilometres
  /// across a city is slow going; forty kilometres is mostly highway, and
  /// using the city figure for it would predict a four-hour drive to the next
  /// town.
  static String reachLabel(double metres) {
    if (metres < 120) return 'Right here';

    final kmh = switch (metres) {
      < 1200 => 5.0, // walking
      < 8000 => 20.0, // city traffic
      < 40000 => 35.0, // arterial
      _ => 55.0, // highway
    };

    // Roads are not straight. 1.3 is the usual detour factor for a dense
    // street grid and it is close enough for a number with a tilde on it.
    final minutes = (metres * 1.3 / 1000) / kmh * 60;

    if (minutes < 1) return '~1 min';
    if (minutes < 60) return '~${minutes.round()} min';

    final hours = minutes / 60;

    if (hours < 10) return '~${hours.toStringAsFixed(1)} hr';

    return '~${hours.round()} hr';
  }

  /// "NE", "SSW" — a bearing anybody can read without thinking.
  static String compass(double degrees) {
    const points = [
      'N', 'NNE', 'NE', 'ENE',
      'E', 'ESE', 'SE', 'SSE',
      'S', 'SSW', 'SW', 'WSW',
      'W', 'WNW', 'NW', 'NNW',
    ];

    final normalised = ((degrees % 360) + 360) % 360;

    return points[((normalised / 22.5).round()) % 16];
  }
}
