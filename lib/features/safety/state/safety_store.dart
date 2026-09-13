import 'package:flutter/foundation.dart';

import '../../../core/api/api_response.dart';
import '../../../core/session/session.dart';
import '../data/check_in_chain.dart';
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
///
/// Since the chain landed this store holds two sides of the same feature that
/// never appear on screen together: [status], which is *my* check-in going out
/// to my family, and [incoming], which is *their* check-ins waiting on me.
/// They live together because one websocket connection feeds both and because
/// answering a request on my side has to clear the badge on this side in the
/// same breath.
class SafetyStore extends ChangeNotifier {
  SafetyStore._();

  static final SafetyStore instance = SafetyStore._();

  final SafetyApi _api = SafetyApi();

  SafetyStatus? _status;
  bool _loading = false;
  bool _submitting = false;
  String? _error;

  List<CheckInRequestInfo> _incoming = const [];
  final Set<String> _answering = {};

  SafetyStatus? get status => _status;

  /// True only for the very first load, when there is nothing to show yet.
  /// A refresh over existing data must not blank the cards out.
  bool get loading => _loading && _status == null;

  bool get submitting => _submitting;
  String? get error => _error;
  bool get hasData => _status != null;

  /// Today's chain, if there is one.
  CheckInChain? get chain => _status?.checkIn.chain;

  /// Whether an order has been chosen. False means the next tap on "I'm Safe"
  /// should open the picker rather than check in.
  bool get hasContacts => _status?.checkIn.notify.configured ?? false;

  /// Check-ins from family waiting on my answer, newest first.
  List<CheckInRequestInfo> get incoming => _incoming;

  bool isAnswering(String id) => _answering.contains(id);

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
  /// [contacts] carries the order when the user has just arranged it — the
  /// first check-in, where the picker and the tap are one gesture. Passing
  /// null leaves the saved list alone, which is every ordinary day.
  Future<CheckInOutcome> checkIn({String? note, List<String>? contacts}) async {
    if (_submitting) return const CheckInOutcome(ok: false);

    final previous = _status;

    _submitting = true;
    _status = previous?.optimisticallyCheckedIn(DateTime.now());
    notifyListeners();

    try {
      final res = await _api.checkIn(note: note, contacts: contacts);

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

  /*
  |----------------------------------------------------------------------------
  | The contact list
  |----------------------------------------------------------------------------
  */

  /// Load the picker's payload.
  ///
  /// Always fetched fresh rather than cached. The list of who *could* be
  /// notified is the family list, which changes on another screen entirely —
  /// opening the picker is exactly the moment to find out whether somebody was
  /// added since it was last seen.
  Future<ContactBook?> contactBook() async {
    try {
      final res = await _api.contacts();

      if (res.success && res.dataMap.isNotEmpty) {
        return ContactBook.fromJson(res.dataMap);
      }
    } catch (_) {
      // Null means the sheet cannot be opened; the caller says so.
    }

    return null;
  }

  /// Save a new order without checking in.
  ///
  /// Reloads the status afterwards rather than patching the notify list
  /// locally, because the server drops people whose family link has since gone
  /// and the row of faces has to show what was actually kept.
  Future<CheckInOutcome> saveContacts(List<String> contactIds) async {
    try {
      final res = await _api.saveContacts(contactIds);

      if (res.success) {
        await load();

        return CheckInOutcome(ok: true, message: res.message);
      }

      return CheckInOutcome(ok: false, message: res.message);
    } on ApiException catch (e) {
      return CheckInOutcome(ok: false, message: e.message);
    } catch (_) {
      return const CheckInOutcome(
        ok: false,
        message: 'Could not reach the server. Try again.',
      );
    }
  }

  /*
  |----------------------------------------------------------------------------
  | Requests waiting on me
  |----------------------------------------------------------------------------
  */

  Future<void> loadIncoming() async {
    if (!Session.instance.isAuthenticated) return;

    try {
      final res = await _api.incomingRequests();

      if (res.success) {
        _incoming = (res.dataMap['requests'] as List?)
                ?.whereType<Map<String, dynamic>>()
                .map(CheckInRequestInfo.fromJson)
                .toList() ??
            const [];

        notifyListeners();
      }
    } catch (_) {
      // Keep whatever is on screen.
    }
  }

  /// A websocket frame said it is my turn.
  ///
  /// Deduplicated by id and prepended, so a frame that arrives while the list
  /// is already loaded does not push a second copy of the same request. The
  /// socket reconnecting and replaying is a normal event, not an exception.
  void applyIncomingRequest(Map<String, dynamic> data) {
    final raw = data['request'];

    if (raw is! Map<String, dynamic>) return;

    final request = CheckInRequestInfo.fromJson(raw);

    if (request.id.isEmpty) return;

    _incoming = [
      request,
      for (final other in _incoming)
        if (other.id != request.id) other,
    ];

    notifyListeners();
  }

  /// A websocket frame said somebody answered my check-in.
  ///
  /// Folds the chain in without touching the streak or the week strip, which
  /// this frame knows nothing about. If there is no status held yet — the app
  /// was launched straight onto another tab — the frame is dropped rather than
  /// half-applied, and the next load picks the truth up anyway.
  void applyChain(Map<String, dynamic> data) {
    final raw = data['chain'];
    final current = _status;

    if (current == null) return;

    _status = current.withChain(
      raw is Map<String, dynamic> ? CheckInChain.fromJson(raw) : null,
    );

    notifyListeners();
  }

  /// Accept or decline a request that is waiting on me.
  ///
  /// The row leaves the list optimistically, because whatever the server
  /// replies the answer is given and this request is no longer mine to
  /// answer — including in the case where it had already moved on, which comes
  /// back as a success with a sentence explaining what happened.
  Future<CheckInOutcome> respond({
    required String requestId,
    required bool accept,
  }) async {
    if (_answering.contains(requestId)) {
      return const CheckInOutcome(ok: false);
    }

    _answering.add(requestId);
    notifyListeners();

    try {
      final res = await _api.respondToRequest(requestId, accept);

      if (res.success) {
        _incoming = [
          for (final other in _incoming)
            if (other.id != requestId) other,
        ];

        return CheckInOutcome(ok: true, message: res.message);
      }

      return CheckInOutcome(ok: false, message: res.message);
    } on ApiException catch (e) {
      return CheckInOutcome(ok: false, message: e.message);
    } catch (_) {
      return const CheckInOutcome(
        ok: false,
        message: 'Could not reach the server. Try again.',
      );
    } finally {
      _answering.remove(requestId);
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
    _incoming = const [];
    _answering.clear();
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
