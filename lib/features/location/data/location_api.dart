import '../../../core/api/api_client.dart';
import '../../../core/api/api_response.dart';
import 'location_models.dart';

/// Live location: sharing, pinging, reading the map.
class LocationApi {
  LocationApi({ApiClient? client}) : _api = client ?? ApiClient();

  final ApiClient _api;

  /// Everything the map needs to paint itself from cold.
  ///
  /// The socket carries deltas after this and nothing else, so a dropped
  /// connection leaves a stale map rather than an empty one.
  Future<ApiResponse> live() => _api.get('location/live');

  /// Push a buffer of readings.
  ///
  /// Always a list, even for one fix. The server accepts a bare object too,
  /// but sending one shape from one place means there is only ever one thing
  /// to debug.
  Future<ApiResponse> ping(List<LocationFix> fixes) => _api.post(
        'location/ping',
        body: {'fixes': fixes.map((fix) => fix.toJson()).toList()},
      );

  /// Start sharing.
  ///
  /// The opening fix is optional and sent when the phone happens to have one
  /// ready — the share should begin the moment it is asked for, not fifteen
  /// seconds later when the satellites agree.
  Future<ApiResponse> share({
    required String audience,
    String? conversationId,
    int? minutes,
    LocationFix? fix,
  }) =>
      _api.post('location/share', body: {
        'audience': audience,
        if (conversationId != null) 'conversation_id': conversationId,
        if (minutes != null) 'minutes': minutes,
        if (fix != null) ...fix.toJson(),
      });

  /// Stop one share, or — with no id — every one of them.
  Future<ApiResponse> stop({String? shareId}) => _api.post(
        'location/stop',
        body: {if (shareId != null) 'share_id': shareId},
      );

  /// Drop a static pin into a thread. No share, nothing to expire.
  Future<ApiResponse> pin({
    required String conversationId,
    required double latitude,
    required double longitude,
  }) =>
      _api.post('location/pin', body: {
        'conversation_id': conversationId,
        'latitude': latitude,
        'longitude': longitude,
      });

  /*
  |----------------------------------------------------------------------------
  | Family places
  |----------------------------------------------------------------------------
  */

  /// My own places.
  ///
  /// The map does not need this — `live()` already carries them, so the
  /// circles draw on the first paint rather than on a second round trip.
  /// This is for the manage screen, which can be opened without the map
  /// having loaded.
  Future<ApiResponse> places() => _api.get('location/places');

  Future<ApiResponse> createPlace(Map<String, dynamic> body) =>
      _api.post('location/places', body: body);

  Future<ApiResponse> updatePlace(String id, Map<String, dynamic> body) =>
      _api.patch('location/places/$id', body: body);

  Future<ApiResponse> deletePlace(String id) =>
      _api.delete('location/places/$id');

  /*
  |----------------------------------------------------------------------------
  | History
  |----------------------------------------------------------------------------
  */

  /// One person's day, as stays and journeys.
  ///
  /// The offset is minutes east of UTC, taken from this phone rather than
  /// from the account's stored timezone. The question being asked is "what
  /// did Tuesday look like", and Tuesday means the one wherever the reader is
  /// standing right now.
  Future<ApiResponse> history(String userId, DateTime day) {
    final offset = DateTime.now().timeZoneOffset.inMinutes;

    return _api.get(
      'location/$userId/history?date=${_dateKey(day)}&offset=$offset',
    );
  }

  /// Which days of a month have anything recorded, for the calendar.
  Future<ApiResponse> historyDays(String userId, DateTime month) {
    final offset = DateTime.now().timeZoneOffset.inMinutes;
    final key = '${month.year.toString().padLeft(4, '0')}-'
        '${month.month.toString().padLeft(2, '0')}';

    return _api.get(
      'location/$userId/history/days?month=$key&offset=$offset',
    );
  }

  static String _dateKey(DateTime day) =>
      '${day.year.toString().padLeft(4, '0')}-'
      '${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';

  /// The recent path behind somebody's marker.
  Future<ApiResponse> trail(String userId, {DateTime? since}) => _api.get(
        'location/$userId/trail'
        '${since == null ? '' : '?since=${Uri.encodeComponent(since.toUtc().toIso8601String())}'}',
      );
}
