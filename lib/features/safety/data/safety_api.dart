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
  ///
  /// [contacts] is the ordered list of family to notify, and is sent only when
  /// the user just arranged it — on their first check-in, or after editing the
  /// order in the same gesture. Omitted on an ordinary day, which leaves the
  /// saved list untouched. Sending an empty list is a real instruction: it
  /// clears the list and makes the check-in private.
  Future<ApiResponse> checkIn({
    String? note,
    double? latitude,
    double? longitude,
    int? locationAccuracy,
    int? batteryLevel,
    List<String>? contacts,
  }) =>
      _api.post('safety/check-in', body: {
        if (note != null && note.isNotEmpty) 'note': note,
        if (latitude != null) 'latitude': latitude,
        if (longitude != null) 'longitude': longitude,
        if (locationAccuracy != null) 'location_accuracy': locationAccuracy,
        if (batteryLevel != null) 'battery_level': batteryLevel,
        if (contacts != null) 'contacts': contacts,
      });

  Future<ApiResponse> history({int days = 30}) =>
      _api.get('safety/check-ins?days=$days');

  /*
  |----------------------------------------------------------------------------
  | The notification chain
  |----------------------------------------------------------------------------
  */

  /// The picker's payload: the saved order, everybody who could join it, and
  /// the limits — one request rather than three.
  Future<ApiResponse> contacts() => _api.get('safety/check-in/contacts');

  /// Replace the order. PUT, because the array sent *is* the list afterwards.
  Future<ApiResponse> saveContacts(List<String> contactIds) =>
      _api.put('safety/check-in/contacts', body: {'contacts': contactIds});

  /// Check-ins waiting on this user's answer.
  ///
  /// Deliberately not the notification feed. The feed is history that happens
  /// to contain some actionable rows; this is the short list of things
  /// somebody is actively waiting on, and it is what the resume banner is
  /// built from.
  Future<ApiResponse> incomingRequests() =>
      _api.get('safety/check-in/requests');

  /// Accept — "I know you are safe" — ends the chain and nobody further down
  /// the list is told. Decline hands it to the next person immediately rather
  /// than making them wait out the timer.
  Future<ApiResponse> respondToRequest(String stepId, bool accept) =>
      _api.post('safety/check-in/requests/$stepId/respond', body: {
        'accept': accept,
      });

  void dispose() => _api.dispose();
}
