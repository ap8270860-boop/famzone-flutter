import '../../../core/api/api_client.dart';
import '../../../core/api/api_response.dart';

/// The safety endpoints.
class SafetyApi {
  SafetyApi({ApiClient? client}) : _api = client ?? ApiClient();

  final ApiClient _api;

  Future<ApiResponse> status() => _api.get('safety/status');

  /// Everything here is optional context — a bare check-in is valid, and a
  /// denied location permission must never stop somebody marking themselves
  /// safe.
  Future<ApiResponse> checkIn({
    String? note,
    double? latitude,
    double? longitude,
    int? locationAccuracy,
    int? batteryLevel,
  }) =>
      _api.post('safety/check-in', body: {
        if (note != null && note.isNotEmpty) 'note': note,
        if (latitude != null) 'latitude': latitude,
        if (longitude != null) 'longitude': longitude,
        if (locationAccuracy != null) 'location_accuracy': locationAccuracy,
        if (batteryLevel != null) 'battery_level': batteryLevel,
      });

  Future<ApiResponse> history({int days = 30}) =>
      _api.get('safety/check-ins?days=$days');

  void dispose() => _api.dispose();
}
