import 'package:flutter/foundation.dart';

import '../../../core/api/api_response.dart';
import '../../../core/session/session.dart';
import '../data/safety_api.dart';
import '../data/safety_models.dart';

/// Holds the safety status both home-screen cards render from.
///
/// A [ChangeNotifier] singleton, matching [Session] — the Riverpod-vs-Bloc
/// decision is still open, and keeping the two stores shaped alike means
/// moving them later is one mechanical pass rather than two arguments.
///
/// The point of a shared store here is that the status card and the check-in
/// card are two views of one fact. Holding that fact in one place is what
/// makes "tap check in, watch the status card change" work without either
/// card knowing the other exists.
class SafetyStore extends ChangeNotifier {
  SafetyStore._();

  static final SafetyStore instance = SafetyStore._();

  final SafetyApi _api = SafetyApi();

  SafetyStatus? _status;
  bool _loading = false;
  bool _submitting = false;
  String? _error;

  SafetyStatus? get status => _status;

  /// True only for the very first load, when there is nothing to show yet.
  /// A refresh over existing data must not blank the cards out.
  bool get loading => _loading && _status == null;

  bool get submitting => _submitting;
  String? get error => _error;
  bool get hasData => _status != null;

  /// Fetch the current status.
  ///
  /// Failures are kept rather than thrown: the home screen is not the place
  /// to interrupt somebody because a refresh timed out. The cards fall back
  /// to whatever they last knew.
  Future<void> load() async {
    if (!Session.instance.isAuthenticated || _loading) return;

    // Deliberately no notifyListeners() here. load() is called from
    // initState, which runs during a build, and notifying synchronously would
    // mark listeners dirty mid-frame. Nothing needs the signal anyway: with no
    // status yet the cards already render their skeletons.
    _loading = true;

    try {
      final res = await _api.status();

      if (res.success && res.dataMap.isNotEmpty) {
        _status = SafetyStatus.fromJson(res.dataMap);
        _error = null;
      } else {
        _error = res.message;
      }
    } on ApiException catch (e) {
      _error = e.message;
    } catch (_) {
      _error = 'Could not reach the server.';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Mark the user safe for today.
  ///
  /// Repaints both cards immediately from a predicted status, then reconciles
  /// with what the server actually says. On failure the previous status is put
  /// back, so the UI never keeps a success that did not happen.
  ///
  /// Returns the message to surface, or null when there is nothing to say.
  Future<CheckInOutcome> checkIn({String? note}) async {
    if (_submitting) return const CheckInOutcome(ok: false);

    final previous = _status;

    _submitting = true;
    _status = previous?.optimisticallyCheckedIn(DateTime.now());
    notifyListeners();

    try {
      final res = await _api.checkIn(note: note);

      if (res.success) {
        if (res.dataMap.isNotEmpty) {
          _status = SafetyStatus.fromJson(res.dataMap);
        }
        _error = null;
        return CheckInOutcome(ok: true, message: res.message);
      }

      _status = previous;
      return CheckInOutcome(ok: false, message: res.message);
    } on ApiException catch (e) {
      _status = previous;
      return CheckInOutcome(ok: false, message: e.message);
    } catch (_) {
      _status = previous;
      return const CheckInOutcome(
        ok: false,
        message: 'Could not reach the server. Try again.',
      );
    } finally {
      _submitting = false;
      notifyListeners();
    }
  }

  /// Drop everything on sign-out, so the next account never sees the last
  /// one's status flash past.
  void clear() {
    _status = null;
    _error = null;
    _loading = false;
    _submitting = false;
    notifyListeners();
  }

}

/// What came of a check-in attempt.
@immutable
class CheckInOutcome {
  const CheckInOutcome({required this.ok, this.message});

  final bool ok;
  final String? message;
}
