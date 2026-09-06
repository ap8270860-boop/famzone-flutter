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

  /// The recent path behind somebody's marker.
  Future<ApiResponse> trail(String userId, {DateTime? since}) => _api.get(
        'location/$userId/trail'
        '${since == null ? '' : '?since=${Uri.encodeComponent(since.toUtc().toIso8601String())}'}',
      );
}
