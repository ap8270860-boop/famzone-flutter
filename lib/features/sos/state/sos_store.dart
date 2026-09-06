import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../../../core/session/session.dart';
import '../../location/state/location_tracker.dart';
import '../data/sos_api.dart';
import '../data/sos_models.dart';

/// Alarms, the service catalogue, and the search behind them.
///
/// One instance for the whole app. Two things depend on that: an alarm raised
/// from the nav bar and one raised from the Home tile are the same alarm, and
/// the incoming-alert handler needs somewhere to put a family member's SOS
/// that outlives whatever screen happens to be open.
class SosStore extends ChangeNotifier {
  SosStore._() {
    Session.instance.onSignOut(_reset);
  }

  static final SosStore instance = SosStore._();

  final SosApi _api = SosApi();

  List<EmergencyService> _services = const [];
  SosAlert? _active;
  String _disclaimer = '';
  bool _searchAvailable = false;
  int _familyCount = 0;

  bool _loading = false;
  bool _loaded = false;
  bool _raising = false;
  String? _error;

  /// A family member's alarm, when one is running.
  ///
  /// Held on the store rather than pushed straight onto the navigator so it
  /// survives whatever the person is doing — and so ending it clears the
  /// banner everywhere at once.
  SosAlert? _incoming;
  Map<String, dynamic>? _incomingPerson;

  List<EmergencyService> get services => _services;
  SosAlert? get active => _active;
  SosAlert? get incoming => _incoming;
  Map<String, dynamic>? get incomingPerson => _incomingPerson;
  String get disclaimer => _disclaimer;
  bool get searchAvailable => _searchAvailable;
  int get familyCount => _familyCount;

  bool get loading => _loading;
  bool get loaded => _loaded;
  bool get raising => _raising;
  bool get isActive => _active?.active == true;
  String? get error => _error;

  EmergencyService? service(String key) {
    for (final service in _services) {
      if (service.key == key) return service;
    }

    return null;
  }

  /*
  |----------------------------------------------------------------------------
  | Loading
  |----------------------------------------------------------------------------
  */

  /// Fetch the catalogue and any running alert.
  ///
  /// Called on first open and on every app resume. Cheap, and the one thing
  /// that keeps a person who force-quit the app mid-alarm from losing it.
  Future<void> load({bool quiet = false}) async {
    if (_loading) return;

    _loading = true;

    if (!quiet) {
      _error = null;
      _notify();
    }

    try {
      final response = await _api.overview();

      if (!response.success) {
        _error = response.message;

        return;
      }

      _apply(response.dataMap);
      _loaded = true;
    } catch (error) {
      /*
       | The catalogue is the only thing here that can be stale, and a stale
       | catalogue is still a working list of emergency numbers. So a failed
       | refresh keeps whatever we had rather than emptying the screen —
       | showing "could not load" where 112 used to be would be the worst
       | possible failure mode.
       */
      if (!_loaded) _error = error.toString();
    } finally {
      _loading = false;
      _notify();
    }
  }

  void _apply(Map<String, dynamic> data) {
    final services = data['services'];

    if (services is List) {
      _services = services
          .whereType<Map<String, dynamic>>()
          .map(EmergencyService.fromJson)
          .toList();
    }

    final active = data['active'] ?? data['alert'];

    _active = active is Map<String, dynamic> ? SosAlert.fromJson(active) : null;

    if (_active?.active == false) _active = null;

    _disclaimer = data['disclaimer'] as String? ?? _disclaimer;
    _searchAvailable = data['search_available'] as bool? ?? _searchAvailable;
    _familyCount = (data['family_count'] as num?)?.toInt() ?? _familyCount;
  }

  /*
  |----------------------------------------------------------------------------
  | Raising
  |----------------------------------------------------------------------------
  */

  /// Press the button.
  ///
  /// The position is attached if one is available *now* — from the tracker's
  /// last fix, or a quick one-shot — but never waited on beyond its own
  /// timeout. An alarm that will not send until the GPS agrees is an alarm
  /// that does not send.
  Future<bool> raise({String? category}) async {
    if (_raising) return false;

    _raising = true;
    _error = null;
    _notify();

    try {
      final known = LocationTracker.instance.myPosition;

      double? lat = known?.latitude;
      double? lng = known?.longitude;
      double? accuracy = known?.accuracy;

      if (lat == null || lng == null) {
        final fix = await LocationTracker.instance
            .currentFix(timeout: const Duration(seconds: 5));

        lat = fix?.latitude;
        lng = fix?.longitude;
        accuracy = fix?.accuracy;
      }

      final response = await _api.start(
        category: category,
        latitude: lat,
        longitude: lng,
        accuracy: accuracy,
      );

      if (!response.success) {
        _error = response.message;

        return false;
      }

      _apply(response.dataMap);

      return true;
    } catch (error) {
      _error = 'Could not raise the alert. Check your connection.';

      return false;
    } finally {
      _raising = false;
      _notify();
    }
  }

  /// Say which kind of help is wanted, once the person has chosen.
  Future<void> setCategory(String category) async {
    final alert = _active;

    if (alert == null) return;

    // Optimistic: the chosen service opens immediately and the round trip
    // catches up. Nothing on screen depends on the server agreeing.
    _active = SosAlert(
      id: alert.id,
      status: alert.status,
      active: alert.active,
      category: category,
      latitude: alert.latitude,
      longitude: alert.longitude,
      accuracy: alert.accuracy,
      address: alert.address,
      batteryLevel: alert.batteryLevel,
      note: alert.note,
      notifiedCount: alert.notifiedCount,
      startedAt: alert.startedAt,
      endedAt: alert.endedAt,
      durationSeconds: alert.durationSeconds,
    );

    _notify();

    try {
      await _api.update(alert.id, category: category);
    } catch (_) {
      // The category is a label on a record, not something anybody is waiting
      // on. A failure here costs nothing worth interrupting somebody for.
    }
  }

  /// End it. `resolved`, `cancelled` or `false_alarm`.
  Future<bool> end(String status) async {
    final alert = _active;

    if (alert == null) return true;

    try {
      final response = await _api.end(alert.id, status);

      if (!response.success) {
        _error = response.message;
        _notify();

        return false;
      }

      _active = null;
      _notify();

      return true;
    } catch (_) {
      _error = 'Could not end the alert. Check your connection.';
      _notify();

      return false;
    }
  }

  /*
  |----------------------------------------------------------------------------
  | Somebody else's alarm
  |----------------------------------------------------------------------------
  */

  /// A family member raised one. Routed here from the mailbox channel.
  void applyIncoming(Map<String, dynamic> data) {
    final alert = data['alert'];

    if (alert is! Map<String, dynamic>) return;

    _incoming = SosAlert.fromJson(alert);
    _incomingPerson = data['person'] as Map<String, dynamic>?;

    _notify();
  }

  /// Theirs ended.
  ///
  /// Cleared immediately and unconditionally. An alarm that keeps ringing
  /// after the person is safe is how people learn to ignore alarms.
  void clearIncoming(Map<String, dynamic>? data) {
    if (data != null) {
      final alert = data['alert'];

      // Only clear the one that ended — a second family member's alarm must
      // not be dismissed by the first one being resolved.
      if (alert is Map<String, dynamic> &&
          _incoming != null &&
          alert['id'] != _incoming!.id) {
        return;
      }
    }

    _incoming = null;
    _incomingPerson = null;

    _notify();
  }

  void dismissIncoming() => clearIncoming(null);

  /*
  |----------------------------------------------------------------------------
  | Sign-out
  |----------------------------------------------------------------------------
  */

  Future<void> _reset() async {
    _services = const [];
    _active = null;
    _incoming = null;
    _incomingPerson = null;
    _loaded = false;
    _error = null;

    _notify();
  }

  /*
  |----------------------------------------------------------------------------
  | Notifying safely
  |----------------------------------------------------------------------------
  */

  /// notifyListeners, but never in the middle of a build.
  ///
  /// [load] is called from initState, and initState runs *during* the build
  /// phase. A synchronous notifyListeners() there marks every listening widget
  /// dirty while the framework is already walking the tree — and Flutter
  /// throws for any listener it has already built, because it may not visit
  /// that widget again this frame.
  ///
  /// Which is exactly the case here: the SOS banner lives in AppShell, in a
  /// completely different branch, and is built long before any screen that
  /// loads this store.
  ///
  /// Deferring to the end of the frame is correct rather than merely quiet.
  /// Nothing needs to repaint mid-build, and one frame later is imperceptible.
  void _notify() {
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) => notifyListeners());

      return;
    }

    notifyListeners();
  }

}
