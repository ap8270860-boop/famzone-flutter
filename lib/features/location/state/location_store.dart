
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../../../core/session/session.dart';
import '../../chat/state/realtime_client.dart';
import '../data/location_api.dart';
import '../data/location_models.dart';
import 'location_tracker.dart';

/// Everybody's positions, and my own sharing state.
///
/// One instance for the whole app, not one per screen. That matters more than
/// it looks: this store owns the websocket subscriptions for every person
/// currently sharing with me, and two copies would mean two subscriptions,
/// two sets of handlers, and a map that updates twice per fix.
///
/// It is also what makes tracking survive an app restart. [bootstrap] asks
/// the server what I am sharing and hands the answer to the tracker, so a
/// share that was running when the process died picks straight back up —
/// without it, force-quitting the app would silently strand a family
/// share as a permanent "last seen 3 hours ago".
class LocationStore extends ChangeNotifier {
  LocationStore._() {
    Session.instance.onSignOut(_reset);
  }

  static final LocationStore instance = LocationStore._();

  final LocationApi _api = LocationApi();

  final Map<String, LivePerson> _people = {};
  final Set<String> _subscribed = {};

  List<LocationShare> _myShares = const [];

  bool _loading = false;
  bool _loaded = false;
  String? _error;

  /// Everybody sharing with me, newest fix first so the map's list reads as
  /// "who moved recently" rather than an arbitrary order.
  List<LivePerson> get people {
    final list = _people.values.toList();

    list.sort((a, b) =>
        (a.position.ageSeconds ?? 1 << 30)
            .compareTo(b.position.ageSeconds ?? 1 << 30));

    return list;
  }

  List<LocationShare> get myShares => _myShares;

  bool get isSharing => _myShares.any((share) => share.active);

  LocationShare? get familyShare {
    for (final share in _myShares) {
      if (share.isFamily && share.active) return share;
    }

    return null;
  }

  /// A share running in one particular thread, if there is one.
  LocationShare? shareIn(String conversationId) {
    for (final share in _myShares) {
      if (share.active && share.conversationId == conversationId) return share;
    }

    return null;
  }

  bool get loading => _loading;
  bool get loaded => _loaded;
  String? get error => _error;

  LivePerson? person(String userId) => _people[userId];

  /*
  |----------------------------------------------------------------------------
  | Loading
  |----------------------------------------------------------------------------
  */

  /// Called on sign-in and on every return to the foreground.
  ///
  /// Quiet on failure by design: this runs where nobody asked for it, and an
  /// error toast on app resume because the network was briefly down would be
  /// noise. The map screen calls [load] directly and does surface errors,
  /// because there somebody is looking at it.
  Future<void> bootstrap() async {
    if (!Session.instance.isAuthenticated) return;

    try {
      await load();
    } catch (_) {
      // Deliberately swallowed. See above.
    }
  }

  Future<void> load() async {
    if (_loading) return;

    _loading = true;
    _error = null;
    _notify();

    try {
      final response = await _api.live();

      if (!response.success) {
        _error = response.message;

        return;
      }

      final data = response.dataMap;

      _people
        ..clear()
        ..addEntries(
          ((data['people'] as List?) ?? const [])
              .whereType<Map<String, dynamic>>()
              .map(LivePerson.fromJson)
              .map((person) => MapEntry(person.user.id, person)),
        );

      final me = data['me'] as Map<String, dynamic>? ?? const {};

      _myShares = ((me['shares'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(LocationShare.fromJson)
          .toList();

      _loaded = true;

      await _reconcileSubscriptions();

      final tracking = data['tracking'];

      if (tracking is Map<String, dynamic>) {
        await LocationTracker.instance.apply(TrackingPlan.fromJson(tracking));
      }
    } finally {
      _loading = false;
      _notify();
    }
  }

  /*
  |----------------------------------------------------------------------------
  | Sharing
  |----------------------------------------------------------------------------
  */

  /// Start sharing, and start tracking.
  ///
  /// The opening fix is fetched first but never waited on beyond its own
  /// timeout — see [LocationTracker.currentFix]. A share that will not begin
  /// until the GPS agrees is a share people tap twice and then give up on.
  Future<bool> startShare({
    required String audience,
    String? conversationId,
    int? minutes,
  }) async {
    final fix = await LocationTracker.instance.currentFix();

    final response = await _api.share(
      audience: audience,
      conversationId: conversationId,
      minutes: minutes,
      fix: fix,
    );

    if (!response.success) {
      _error = response.message;
      _notify();

      return false;
    }

    final data = response.dataMap;
    final share = data['share'];

    if (share is Map<String, dynamic>) {
      _myShares = [
        ..._myShares.where((s) => s.id != share['id']),
        LocationShare.fromJson(share),
      ];
    }

    final tracking = data['tracking'];

    if (tracking is Map<String, dynamic>) {
      await LocationTracker.instance.apply(TrackingPlan.fromJson(tracking));
    }

    _notify();

    return true;
  }

  /// Stop one share, or — with no id — all of them.
  Future<bool> stopSharing({String? shareId}) async {
    final response = await _api.stop(shareId: shareId);

    if (!response.success) {
      _error = response.message;
      _notify();

      return false;
    }

    _myShares = shareId == null
        ? const []
        : _myShares.where((share) => share.id != shareId).toList();

    final tracking = response.dataMap['tracking'];

    await LocationTracker.instance.apply(
      tracking is Map<String, dynamic>
          ? TrackingPlan.fromJson(tracking)
          : const TrackingPlan.idle(),
    );

    _notify();

    return true;
  }

  /*
  |----------------------------------------------------------------------------
  | The socket
  |----------------------------------------------------------------------------
  */

  /// Subscribe to everybody visible, and drop everybody who is not.
  ///
  /// Channels are named after the person being watched, so this is one
  /// subscription per sharer regardless of how many of my screens are
  /// looking. Leaving is as important as joining: an un-left channel is a
  /// frame the app decodes and throws away, forever.
  Future<void> _reconcileSubscriptions() async {
    final wanted = _people.keys.toSet();

    for (final id in wanted.difference(_subscribed)) {
      await RealtimeClient.instance.joinLocation(id, _onLocationEvent);
      _subscribed.add(id);
    }

    for (final id in _subscribed.difference(wanted).toList()) {
      await RealtimeClient.instance.leaveLocation(id);
      _subscribed.remove(id);
    }
  }

  void _onLocationEvent(String event, Map<String, dynamic> data) {
    if (event != 'location.updated') return;

    final position = LivePosition.fromJson(data);
    final existing = _people[position.userId];

    /*
     | A frame for somebody not on the map is dropped, not used to invent
     | them. The payload carries a position and nothing about who the person
     | is, so folding it in would produce a nameless pin — and it can only
     | happen in the window between a share ending and the unsubscribe
     | landing, where the right answer is to ignore it.
     */
    if (existing == null) return;

    _people[position.userId] = existing.withPosition(position);

    _notify();
  }

  /// Somebody started sharing with me. Routed here from the mailbox channel,
  /// because it has to reach me before I am subscribed to their channel —
  /// being told to subscribe is the whole point of the event.
  Future<void> applyShareStarted(Map<String, dynamic> data) async {
    final share = data['share'];

    if (share is! Map<String, dynamic>) return;

    final parsed = LocationShare.fromJson(share);

    if (parsed.userId == Session.instance.user?.id) {
      _myShares = [
        ..._myShares.where((s) => s.id != parsed.id),
        parsed,
      ];

      _notify();

      return;
    }

    /*
     | The event carries a position but not a name, so a person we have never
     | seen needs a round trip. That is one request per new sharer, which is
     | rare — and the alternative, a pin labelled with a uuid, is not an
     | alternative.
     */
    final existing = _people[parsed.userId];

    if (existing == null) {
      await load();

      return;
    }

    final position = data['position'];

    _people[parsed.userId] = position is Map<String, dynamic>
        ? existing.withShare(parsed).withPosition(LivePosition.fromJson(position))
        : existing.withShare(parsed);

    await _reconcileSubscriptions();

    _notify();
  }

  /// A share ended. The pin comes off the map immediately.
  ///
  /// Not left behind as a "last known" — the server has already stopped
  /// publishing, so it would sit there looking live and getting older, and a
  /// stale dot on a safety app is worse than no dot.
  Future<void> applyShareEnded(Map<String, dynamic> data) async {
    final share = data['share'];

    if (share is! Map<String, dynamic>) return;

    final parsed = LocationShare.fromJson(share);

    if (parsed.userId == Session.instance.user?.id) {
      _myShares = _myShares.where((s) => s.id != parsed.id).toList();

      if (!isSharing) await LocationTracker.instance.stop();

      _notify();

      return;
    }

    _people.remove(parsed.userId);

    await _reconcileSubscriptions();

    _notify();
  }

  /*
  |----------------------------------------------------------------------------
  | Trails
  |----------------------------------------------------------------------------
  */

  Future<LocationTrail?> trail(String userId, {DateTime? since}) async {
    final response = await _api.trail(userId, since: since);

    if (!response.success) return null;

    return LocationTrail.fromJson(response.dataMap);
  }

  /*
  |----------------------------------------------------------------------------
  | Sign-out
  |----------------------------------------------------------------------------
  */

  Future<void> _reset() async {
    for (final id in _subscribed.toList()) {
      await RealtimeClient.instance.leaveLocation(id);
    }

    _subscribed.clear();
    _people.clear();
    _myShares = const [];
    _loaded = false;
    _error = null;

    await LocationTracker.instance.stop();

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
