import 'package:flutter/material.dart';

/// A named circle on the family map.
///
/// Home, School, the grandparents'. The whole reason this exists is to turn
/// "28.6139, 77.2090" into "At School", which is the difference between data
/// and an answer.
///
/// A place belongs to whoever created it, and the labels you see are computed
/// against *your* places. So "At Home" on your map means the home you told the
/// app about — which is what you meant by the question. The alternative,
/// pooling every family member's places, produces two circles called "Home"
/// the moment two people in one household both set one up.
class FamilyPlace {
  const FamilyPlace({
    required this.id,
    required this.name,
    required this.kind,
    required this.latitude,
    required this.longitude,
    required this.radiusMetres,
    this.notifyOnArrive = true,
    this.notifyOnLeave = true,
  });

  /// What the app has an icon and a colour for. A kind outside this list is
  /// stored and drawn with a neutral pin rather than rejected — the server is
  /// allowed to add one after this build has shipped.
  static const List<String> kinds = [
    'home',
    'school',
    'office',
    'hospital',
    'gym',
    'park',
    'shop',
    'custom',
  ];

  /// Below this, GPS cannot tell inside from outside, and a geofence becomes
  /// a stream of arrivals from somebody sitting still. Mirrors the server,
  /// which is the one that actually enforces it.
  static const double minRadius = 80;
  static const double maxRadius = 2000;

  static const double defaultRadius = 150;

  final String id;
  final String name;
  final String kind;
  final double latitude;
  final double longitude;
  final double radiusMetres;
  final bool notifyOnArrive;
  final bool notifyOnLeave;

  factory FamilyPlace.fromJson(Map<String, dynamic> json) => FamilyPlace(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? 'Place',
        kind: json['kind'] as String? ?? 'custom',
        latitude: (json['latitude'] as num?)?.toDouble() ?? 0,
        longitude: (json['longitude'] as num?)?.toDouble() ?? 0,
        radiusMetres:
            (json['radius_m'] as num?)?.toDouble() ?? defaultRadius,
        notifyOnArrive: json['notify_on_arrive'] as bool? ?? true,
        notifyOnLeave: json['notify_on_leave'] as bool? ?? true,
      );

  FamilyPlace copyWith({
    String? name,
    String? kind,
    double? latitude,
    double? longitude,
    double? radiusMetres,
    bool? notifyOnArrive,
    bool? notifyOnLeave,
  }) =>
      FamilyPlace(
        id: id,
        name: name ?? this.name,
        kind: kind ?? this.kind,
        latitude: latitude ?? this.latitude,
        longitude: longitude ?? this.longitude,
        radiusMetres: radiusMetres ?? this.radiusMetres,
        notifyOnArrive: notifyOnArrive ?? this.notifyOnArrive,
        notifyOnLeave: notifyOnLeave ?? this.notifyOnLeave,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'kind': kind,
        'latitude': latitude,
        'longitude': longitude,
        'radius_m': radiusMetres.round(),
        'notify_on_arrive': notifyOnArrive,
        'notify_on_leave': notifyOnLeave,
      };

  /// "150 m", "1.2 km" — the radius as somebody would say it.
  String get radiusLabel => radiusMetres < 1000
      ? '${radiusMetres.round()} m'
      : '${(radiusMetres / 1000).toStringAsFixed(1)} km';

  IconData get icon => PlaceKinds.icon(kind);
  Color get tint => PlaceKinds.tint(kind);
}

/// Icons and colours for the kinds the app knows.
///
/// Both fall back rather than throwing. A place kind is a string on the wire
/// precisely so the server can add one without a store release, and the cost
/// of that is that this file must never assume it has seen them all.
class PlaceKinds {
  const PlaceKinds._();

  static const Map<String, IconData> _icons = {
    'home': Icons.home_rounded,
    'school': Icons.school_rounded,
    'office': Icons.business_rounded,
    'hospital': Icons.local_hospital_rounded,
    'gym': Icons.fitness_center_rounded,
    'park': Icons.park_rounded,
    'shop': Icons.storefront_rounded,
    'custom': Icons.place_rounded,
  };

  static const Map<String, Color> _tints = {
    'home': Color(0xFF2F7BF0),
    'school': Color(0xFF8B5CF6),
    'office': Color(0xFF0EA5A5),
    'hospital': Color(0xFFE5484D),
    'gym': Color(0xFFF08C2E),
    'park': Color(0xFF12A66B),
    'shop': Color(0xFFD08700),
    'custom': Color(0xFF64748B),
  };

  static IconData icon(String kind) => _icons[kind] ?? Icons.place_rounded;

  static Color tint(String kind) => _tints[kind] ?? const Color(0xFF64748B);

  /// "Home", "Custom place".
  static String label(String kind) => switch (kind) {
        'custom' => 'Custom place',
        _ => kind.isEmpty
            ? 'Place'
            : kind[0].toUpperCase() + kind.substring(1),
      };
}

/// The place somebody is standing in, as the roster reports it.
///
/// Not a [FamilyPlace]: the roster does not repeat the centre, radius and
/// notification switches for every member on every refresh. Three fields is
/// all a label needs, and the full record is already on the map.
class PlaceRef {
  const PlaceRef({
    required this.id,
    required this.name,
    required this.kind,
  });

  final String id;
  final String name;
  final String kind;

  factory PlaceRef.fromJson(Map<String, dynamic> json) => PlaceRef(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        kind: json['kind'] as String? ?? 'custom',
      );
}

/// Somebody crossed into or out of one of my places.
///
/// Carries a ready-made sentence from the server rather than three fields to
/// assemble. Two reasons: the web app would otherwise assemble its own and
/// the two would drift, and the same string is what a push notification will
/// carry once push exists — and a push payload is built where there is no
/// client to ask.
class PlaceCrossing {
  const PlaceCrossing({
    required this.direction,
    required this.message,
    required this.placeName,
    required this.placeKind,
    required this.personId,
    required this.personName,
    this.personAvatarUrl,
    this.at,
  });

  static const String arrived = 'arrived';
  static const String left = 'left';

  final String direction;
  final String message;
  final String placeName;
  final String placeKind;

  /// The uuid, not the name. Matching a crossing to a roster row by name
  /// works right up until a family has two people called the same thing,
  /// and then it silently relabels the wrong one.
  final String personId;

  final String personName;
  final String? personAvatarUrl;
  final DateTime? at;

  factory PlaceCrossing.fromJson(Map<String, dynamic> json) {
    final place = json['place'] as Map<String, dynamic>? ?? const {};
    final user = json['user'] as Map<String, dynamic>? ?? const {};

    return PlaceCrossing(
      direction: json['direction'] as String? ?? arrived,
      message: json['message'] as String? ?? '',
      placeName: place['name'] as String? ?? '',
      placeKind: place['kind'] as String? ?? 'custom',
      personId: user['id'] as String? ?? '',
      personName: user['name'] as String? ?? '',
      personAvatarUrl: user['avatar_url'] as String?,
      at: json['at'] == null
          ? null
          : DateTime.tryParse(json['at'] as String)?.toLocal(),
    );
  }

  bool get isArrival => direction == arrived;

  IconData get icon => PlaceKinds.icon(placeKind);

  /// Arrivals are reassuring and leaves are neutral. Neither is an alarm —
  /// colouring a departure red would teach people that a child leaving
  /// school at half past three is an emergency.
  Color get tint => isArrival ? const Color(0xFF12A66B) : const Color(0xFF64748B);
}
