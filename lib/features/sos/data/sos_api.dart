import '../../../core/api/api_client.dart';
import '../../../core/api/api_response.dart';

/// Raising alarms, and finding somewhere to go.
class SosApi {
  SosApi({ApiClient? client}) : _api = client ?? ApiClient();

  final ApiClient _api;

  /// The screen, cold: every service with its numbers, plus any running alert.
  Future<ApiResponse> overview() => _api.get('sos');

  /// Press the button.
  ///
  /// Position is optional on purpose — a phone with no fix must still be able
  /// to raise an alarm. Sending what we have beats waiting for something
  /// better.
  Future<ApiResponse> start({
    String? category,
    double? latitude,
    double? longitude,
    double? accuracy,
    String? note,
  }) =>
      _api.post('sos', body: {
        if (category != null) 'category': category,
        if (latitude != null) 'latitude': latitude,
        if (longitude != null) 'longitude': longitude,
        if (accuracy != null) 'accuracy': accuracy,
        if (note != null) 'note': note,
      });

  /// Attach a category once the person knows who they need, or push a better
  /// fix once the GPS settles.
  Future<ApiResponse> update(
    String alertId, {
    String? category,
    double? latitude,
    double? longitude,
    double? accuracy,
    String? note,
  }) =>
      _api.post('sos/$alertId', body: {
        if (category != null) 'category': category,
        if (latitude != null) 'latitude': latitude,
        if (longitude != null) 'longitude': longitude,
        if (accuracy != null) 'accuracy': accuracy,
        if (note != null) 'note': note,
      });

  /// `resolved` | `cancelled` | `false_alarm`.
  Future<ApiResponse> end(String alertId, String status) =>
      _api.post('sos/$alertId/end', body: {'status': status});

  Future<ApiResponse> history({int page = 1}) =>
      _api.get('sos/history?page=$page');

  /// Nearest places of a kind, or a typed search.
  ///
  /// Never carries phone numbers — those bill at a scarcer tier and come one
  /// at a time from [contact], on tap.
  Future<ApiResponse> nearby({
    required double latitude,
    required double longitude,
    String? category,
    String? query,
    int? radius,
  }) {
    final params = <String, String>{
      'latitude': latitude.toString(),
      'longitude': longitude.toString(),
      if (category != null) 'category': category,
      if (query != null && query.isNotEmpty) 'query': query,
      if (radius != null) 'radius': radius.toString(),
    };

    final search = params.entries
        .map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');

    return _api.get('sos/nearby?$search');
  }

  /// One place's phone number. The expensive call — only ever on a tap.
  Future<ApiResponse> contact(String placeId) =>
      _api.get('sos/places/${Uri.encodeComponent(placeId)}');
}
