
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../../../core/session/session.dart';
import '../../chat/state/realtime_client.dart';
import '../data/family_models.dart';
import '../data/location_api.dart';
import '../data/location_models.dart';
import '../data/place_models.dart';
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

  /*
   | Two collections, and the difference matters.
   |
   | `_people` is who the map can draw — everybody with a live share pointed
   | at me. `_family` is who is in my family, sharing or not, which is the
   | larger set and the one the status card counts. Folding them into one
   | would mean either dropping non-sharers off the card or inventing
   | positions for them, and both are wrong.
   */
  List<FamilyMemberLive> _family = const [];
  FamilyStatus _status = const FamilyStatus.empty();

  /// My own places. Everybody's labels are computed against these on the
  /// server; here they are what the map draws as circles.
  List<FamilyPlace> _places = const [];

  /// Somebody just started sharing with me, for the banner.
  ///
  /// Held here rather than raised through a navigator: the announcement has
  /// to reach whoever is looking at whatever screen, and a route pushed from
  /// a socket handler would land on top of whatever they were doing.
  SharingNotice? _sharing;

  /// The last arrival or departure, for the banner. Cleared when dismissed
  /// or superseded — this is a notification, not a log, and Phase C's history
  /// screen is where a log belongs.
  PlaceCrossing? _crossing;

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

  /// Everybody in my family, sharing or not. Sharers first, then whoever was
  /// seen most recently — so the people you can actually act on are at the
  /// front of the strip rather than wherever the database happened to put
  /// them.
  List<FamilyMemberLive> get family {
    final list = [..._family];

    list.sort((a, b) {
      if (a.sharing != b.sharing) return a.sharing ? -1 : 1;

      return (a.presence.ageSeconds ?? 1 << 30)
          .compareTo(b.presence.ageSeconds ?? 1 << 30);
    });

    return list;
  }

  FamilyStatus get status => _status;

  List<FamilyPlace> get places => _places;

  PlaceCrossing? get crossing => _crossing;

  SharingNotice? get sharingNotice => _sharing;

  void dismissSharingNotice() {
    if (_sharing == null) return;

    _sharing = null;
    _notify();
  }

  FamilyPlace? place(String id) {
    for (final place in _places) {
      if (place.id == id) return place;
    }

    return null;
  }

  FamilyMemberLive? familyMember(String userId) {
    for (final member in _family) {
      if (member.user.id == userId) return member;
    }

    return null;
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

      _family = ((data['family'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(FamilyMemberLive.fromJson)
          .toList();

      _places = ((data['places'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(FamilyPlace.fromJson)
          .toList();

      final status = data['status'];

      _status = status is Map<String, dynamic>
          ? FamilyStatus.fromJson(status)
          : const FamilyStatus.empty();

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

    /*
     | The same fix, folded into the roster.
     |
     | Without this the map marker glides and the card under it keeps showing
     | the speed from the cold load, which is the kind of inconsistency people
     | notice immediately and cannot explain — two numbers for one person on
     | one screen. One frame, both collections.
     */
    _family = [
      for (final member in _family)
        if (member.user.id == position.userId)
          FamilyMemberLive(
            user: member.user,
            sharing: true,
            presence: member.presence,

            /*
             | A live frame carries a position, not a place.
             |
             | An earlier version recomputed `movement` here as
             | travelling/stationary unconditionally, which silently threw the
             | place away — somebody sitting at home flipped from "At Home" to
             | "Not moving" on their very next ping and stayed that way until
             | the next full load. The place survives until the server says
             | otherwise, which it does on the next `live` call.
             */
            movement: position.isStale
                ? 'stale'
                : member.place != null
                    ? member.movement
                    : (position.moving ? 'travelling' : 'stationary'),
            position: position,
            place: member.place,
          )
        else
          member,
    ];

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
     | The banner goes up now, on the frame, not after the round trip below.
     |
     | The event carries the sharer's name and avatar precisely so this can
     | happen — an announcement that waits on a network call before it can
     | say who it is about would be a banner reading "somebody started
     | sharing" for as long as the request takes.
     */
    final person = data['user'];

    if (person is Map<String, dynamic>) {
      final position = data['position'];

      _sharing = SharingNotice(
        userId: parsed.userId,
        name: person['name'] as String? ?? 'A family member',
        avatarUrl: person['avatar_url'] as String?,
        at: DateTime.now(),
        hasFix: position is Map<String, dynamic> &&
            (position['has_fix'] as bool? ?? position['latitude'] != null),
      );

      _notify();
    }

    /*
     | A person we have never seen still needs a round trip — the banner only
     | needs a name, but the map needs a full profile. That is one request per
     | new sharer, which is rare, and the alternative is a pin labelled with a
     | uuid.
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

    // They stay in the family, they just stop having a position. Leaving the
    // last one behind would put a pin on the map that nobody has permission
    // to see any more, quietly ageing.
    _family = [
      for (final member in _family)
        if (member.user.id == parsed.userId)
          FamilyMemberLive(
            user: member.user,
            sharing: false,
            presence: member.presence,
            movement: 'unknown',
          )
        else
          member,
    ];

    await _reconcileSubscriptions();

    _notify();
  }

  /*
  |----------------------------------------------------------------------------
  | Places
  |----------------------------------------------------------------------------
  */

  /// Create or update a place, and refresh everything it touches.
  ///
  /// A full [load] after the write rather than folding the response in
  /// locally. It looks wasteful and it is the right call: moving a circle
  /// changes who is inside it, which changes every member's label *and* the
  /// status card's buckets — all of which the server recomputes and none of
  /// which this client can derive. Patching the list locally would leave a
  /// map that is right about the circle and wrong about the people in it.
  Future<bool> savePlace(FamilyPlace place) async {
    final response = place.id.isEmpty
        ? await _api.createPlace(place.toJson())
        : await _api.updatePlace(place.id, place.toJson());

    if (!response.success) {
      _error = response.message;
      _notify();

      return false;
    }

    await load();

    return true;
  }

  Future<bool> deletePlace(String id) async {
    final response = await _api.deletePlace(id);

    if (!response.success) {
      _error = response.message;
      _notify();

      return false;
    }

    await load();

    return true;
  }

  /// Somebody arrived at or left one of my places.
  ///
  /// Routed from the mailbox channel. The payload carries a finished
  /// sentence, so nothing here assembles one — see [PlaceCrossing].
  void applyPlaceCrossing(Map<String, dynamic> data) {
    _crossing = PlaceCrossing.fromJson(data);

    /*
     | The label under their name changes too, and it changes now.
     |
     | Waiting for the next map refresh would leave a banner saying "Aarav
     | arrived at School" above a card that still says "Travelling", for up
     | to a minute. Two statements about one person, disagreeing, on one
     | screen — which reads as a bug even though both were true when written.
     |
     | A full reload would also fix it and would cost a round trip on every
     | arrival. This is the same information, applied locally.
     */
    final crossing = _crossing!;

    _family = [
      for (final member in _family)
        if (member.user.id == crossing.personId)
          FamilyMemberLive(
            user: member.user,
            sharing: member.sharing,
            presence: member.presence,
            movement: crossing.isArrival ? crossing.placeKind : 'stationary',
            position: member.position,
            place: crossing.isArrival
                ? PlaceRef(
                    id: '',
                    name: crossing.placeName,
                    kind: crossing.placeKind,
                  )
                : null,
          )
        else
          member,
    ];

    _notify();
  }

  void dismissCrossing() {
    if (_crossing == null) return;

    _crossing = null;
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
    _places = const [];
    _crossing = null;
    _sharing = null;
    _family = const [];
    _status = const FamilyStatus.empty();
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
