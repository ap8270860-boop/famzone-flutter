import 'package:flutter/material.dart';

/// One number you can dial.
class EmergencyNumber {
  const EmergencyNumber({
    required this.number,
    required this.label,
    this.primary = false,
  });

  final String number;
  final String label;

  /// Whether this is the big button. Exactly one per service.
  final bool primary;

  factory EmergencyNumber.fromJson(Map<String, dynamic> json) =>
      EmergencyNumber(
        number: json['number'] as String? ?? '',
        label: json['label'] as String? ?? '',
        primary: json['primary'] as bool? ?? false,
      );

  /// What goes into the `tel:` URI.
  ///
  /// Spaces and dashes are for reading; the dialler wants neither. A `+` is
  /// kept because it is meaningful, everything else that is not a digit goes.
  String get dialable =>
      number.replaceAll(RegExp(r'[^0-9+]'), '');
}

/// A kind of help — police, ambulance, fire.
///
/// Everything about it comes from the server, including the numbers. The app
/// holds no emergency number of its own, which is the point: a wrong number
/// that cannot be corrected until users update is not a bug, it is a hazard.
class EmergencyService {
  const EmergencyService({
    required this.key,
    required this.label,
    required this.tagline,
    required this.icon,
    required this.tint,
    required this.numbers,
    this.searchTypes = const [],
    this.searchLabel,
    this.linkLabel,
    this.linkUrl,
    this.guidance = const [],
    this.warning,
    this.disclaimer,
  });

  final String key;
  final String label;
  final String tagline;

  /// A name, not an icon — the wire carries a string and the app maps it.
  /// A server that could name a Flutter IconData would be a server that
  /// breaks the app every time Flutter renames one.
  final String icon;

  final Color tint;
  final List<EmergencyNumber> numbers;

  /// Empty when this service is phone-only. Several of them are, and that is
  /// a design decision rather than missing data — there is no useful map of
  /// "nearest cyber crime".
  final List<String> searchTypes;
  final String? searchLabel;

  final String? linkLabel;
  final String? linkUrl;

  /// What to do while help is on its way. Short, and every line an action.
  final List<String> guidance;

  /// The red one. Only where getting it wrong is dangerous.
  final String? warning;

  final String? disclaimer;

  bool get canSearch => searchTypes.isNotEmpty;

  EmergencyNumber? get primaryNumber {
    for (final number in numbers) {
      if (number.primary) return number;
    }

    return numbers.isEmpty ? null : numbers.first;
  }

  List<EmergencyNumber> get alternates =>
      numbers.where((n) => !n.primary).toList();

  factory EmergencyService.fromJson(Map<String, dynamic> json) {
    final search = json['search'];
    final link = json['link'];

    return EmergencyService(
      key: json['key'] as String? ?? '',
      label: json['label'] as String? ?? '',
      tagline: json['tagline'] as String? ?? '',
      icon: json['icon'] as String? ?? 'help',
      tint: _colour(json['tint'] as String?),
      numbers: ((json['call'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(EmergencyNumber.fromJson)
          .toList(),
      searchTypes: search is Map<String, dynamic>
          ? ((search['types'] as List?) ?? const []).whereType<String>().toList()
          : const [],
      searchLabel: search is Map<String, dynamic>
          ? search['label'] as String?
          : null,
      linkLabel: link is Map<String, dynamic> ? link['label'] as String? : null,
      linkUrl: link is Map<String, dynamic> ? link['url'] as String? : null,
      guidance: ((json['guidance'] as List?) ?? const [])
          .whereType<String>()
          .toList(),
      warning: json['warning'] as String?,
      disclaimer: json['disclaimer'] as String?,
    );
  }

  /// "#4C8DFF" to a Color, tolerantly.
  ///
  /// A malformed tint must never take a screen down — somebody looking at
  /// this screen has a worse problem than a wrong colour.
  static Color _colour(String? hex) {
    if (hex == null) return const Color(0xFF4C8DFF);

    final cleaned = hex.replaceAll('#', '').trim();
    final value = int.tryParse(cleaned, radix: 16);

    if (value == null) return const Color(0xFF4C8DFF);

    return Color(cleaned.length <= 6 ? 0xFF000000 | value : value);
  }
}

/// One alarm, raised.
class SosAlert {
  const SosAlert({
    required this.id,
    required this.status,
    required this.active,
    this.category,
    this.latitude,
    this.longitude,
    this.accuracy,
    this.address,
    this.batteryLevel,
    this.note,
    this.notifiedCount = 0,
    this.startedAt,
    this.endedAt,
    this.durationSeconds,
  });

  static const String statusActive = 'active';
  static const String statusResolved = 'resolved';
  static const String statusCancelled = 'cancelled';
  static const String statusFalseAlarm = 'false_alarm';

  final String id;
  final String status;
  final bool active;
  final String? category;

  final double? latitude;
  final double? longitude;
  final int? accuracy;
  final String? address;
  final int? batteryLevel;
  final String? note;

  /// How many family members the server tried to reach.
  final int notifiedCount;

  final DateTime? startedAt;
  final DateTime? endedAt;
  final int? durationSeconds;

  bool get hasLocation => latitude != null && longitude != null;

  factory SosAlert.fromJson(Map<String, dynamic> json) => SosAlert(
        id: json['id'] as String? ?? '',
        status: json['status'] as String? ?? statusActive,
        active: json['active'] as bool? ?? false,
        category: json['category'] as String?,
        latitude: (json['latitude'] as num?)?.toDouble(),
        longitude: (json['longitude'] as num?)?.toDouble(),
        accuracy: (json['accuracy'] as num?)?.toInt(),
        address: json['address'] as String?,
        batteryLevel: (json['battery_level'] as num?)?.toInt(),
        note: json['note'] as String?,
        notifiedCount: (json['notified_count'] as num?)?.toInt() ?? 0,
        startedAt: json['started_at'] == null
            ? null
            : DateTime.tryParse(json['started_at'] as String)?.toLocal(),
        endedAt: json['ended_at'] == null
            ? null
            : DateTime.tryParse(json['ended_at'] as String)?.toLocal(),
        durationSeconds: (json['duration_seconds'] as num?)?.toInt(),
      );

  /// How it reads in a history list.
  String get statusLabel => switch (status) {
        statusActive => 'Active',
        statusResolved => 'Resolved',
        statusCancelled => 'Cancelled',
        statusFalseAlarm => 'False alarm',
        _ => status,
      };

  /// "4:12", counted from when it started.
  ///
  /// Computed here rather than taken from the server's duration_seconds for a
  /// live alert, because a live one has to tick — a number baked server-side
  /// is wrong one second after it arrives.
  String get elapsedLabel {
    final start = startedAt;

    if (start == null) return '--:--';

    final end = endedAt ?? DateTime.now();
    final seconds = end.difference(start).inSeconds.clamp(0, 86399);

    final minutes = seconds ~/ 60;
    final rest = seconds % 60;

    if (minutes >= 60) {
      return '${minutes ~/ 60}:${(minutes % 60).toString().padLeft(2, '0')}'
          ':${rest.toString().padLeft(2, '0')}';
    }

    return '$minutes:${rest.toString().padLeft(2, '0')}';
  }
}

/// A hospital, police station or fire station from Google.
class NearbyPlace {
  const NearbyPlace({
    required this.placeId,
    required this.name,
    this.address,
    this.kind,
    this.latitude,
    this.longitude,
    this.distanceMetres,
    this.distanceLabel,
    this.operational = true,
  });

  final String placeId;
  final String name;
  final String? address;

  /// Google's own words for what it is — "Hospital", "Police Station".
  final String? kind;

  final double? latitude;
  final double? longitude;
  final int? distanceMetres;
  final String? distanceLabel;

  /// False when Google believes it has closed down. Shown, not hidden — a
  /// closed hospital that is still the nearest building matters, and a silent
  /// gap in the list is worse than a labelled one.
  final bool operational;

  bool get hasPoint => latitude != null && longitude != null;

  factory NearbyPlace.fromJson(Map<String, dynamic> json) => NearbyPlace(
        placeId: json['place_id'] as String? ?? '',
        name: json['name'] as String? ?? 'Unnamed',
        address: json['address'] as String?,
        kind: json['kind'] as String?,
        latitude: (json['latitude'] as num?)?.toDouble(),
        longitude: (json['longitude'] as num?)?.toDouble(),
        distanceMetres: (json['distance_m'] as num?)?.toInt(),
        distanceLabel: json['distance_label'] as String?,
        operational: json['operational'] as bool? ?? true,
      );
}

/// One place's phone number — fetched only when somebody taps Call.
class PlaceContact {
  const PlaceContact({
    required this.placeId,
    this.name,
    this.address,
    this.phone,
    this.phoneInternational,
    this.mapsUrl,
    this.latitude,
    this.longitude,
  });

  final String placeId;
  final String? name;
  final String? address;
  final String? phone;
  final String? phoneInternational;
  final String? mapsUrl;
  final double? latitude;
  final double? longitude;

  bool get hasPhone => (phone ?? phoneInternational ?? '').isNotEmpty;

  String get dialable =>
      (phone ?? phoneInternational ?? '').replaceAll(RegExp(r'[^0-9+]'), '');

  factory PlaceContact.fromJson(Map<String, dynamic> json) => PlaceContact(
        placeId: json['place_id'] as String? ?? '',
        name: json['name'] as String?,
        address: json['address'] as String?,
        phone: json['phone'] as String?,
        phoneInternational: json['phone_international'] as String?,
        mapsUrl: json['maps_url'] as String?,
        latitude: (json['latitude'] as num?)?.toDouble(),
        longitude: (json['longitude'] as num?)?.toDouble(),
      );
}
