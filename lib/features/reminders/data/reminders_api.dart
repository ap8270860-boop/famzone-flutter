import '../../../core/api/api_client.dart';
import '../../../core/api/api_response.dart';

/// The reminder endpoints.
class RemindersApi {
  RemindersApi({ApiClient? client}) : _api = client ?? ApiClient();

  final ApiClient _api;

  /// The twelve categories and their presets.
  ///
  /// Seeded data, identical for every account and cached server-side for an
  /// hour — which is why it is a separate call rather than riding along with
  /// the reminders on every open.
  Future<ApiResponse> catalogue() => _api.get('reminders/catalogue');

  /// Mine to do, what I set for others, today, and the alarms to register.
  Future<ApiResponse> overview() => _api.get('reminders');

  /// Just the alarms — cheaper than the overview, and safe on every resume.
  Future<ApiResponse> schedule() => _api.get('reminders/schedule');

  Future<ApiResponse> day(String date) => _api.get('reminders/day?date=$date');

  /// A month of squares for the calendar: counts and a state per day, not the
  /// occurrences themselves. Tapping a square calls [day] for the detail.
  Future<ApiResponse> month(String month) =>
      _api.get('reminders/month?month=$month');

  Future<ApiResponse> score({int days = 30}) =>
      _api.get('reminders/score?days=$days');

  Future<ApiResponse> create(Map<String, dynamic> body) =>
      _api.post('reminders', body: body);

  Future<ApiResponse> update(String id, Map<String, dynamic> body) =>
      _api.put('reminders/$id', body: body);

  Future<ApiResponse> remove(String id) => _api.delete('reminders/$id');

  /// Accept or decline a reminder somebody set for you.
  Future<ApiResponse> respond(String id, bool accept) =>
      _api.post('reminders/$id/respond', body: {'accept': accept});

  /// Mark one occurrence done, snoozed or skipped.
  ///
  /// The occurrence is named by its due instant rather than by an id, because
  /// it usually has no id yet — the future is computed, and the row is written
  /// by this call at the moment somebody has an opinion about it.
  Future<ApiResponse> settle({
    required String reminderId,
    required DateTime dueAt,
    required String status,
  }) =>
      _api.post('reminders/$reminderId/occurrences', body: {
        'due_at': dueAt.toUtc().toIso8601String(),
        'status': status,
      });

  void dispose() => _api.dispose();
}
