import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/session/session.dart';
import '../../../core/theme/app_colors.dart';
import '../../chat/presentation/chat_screen.dart';
import '../../chat/state/chat_store.dart';
import '../data/family_models.dart';
import '../data/location_models.dart';
import '../data/place_models.dart';
import '../state/location_permissions.dart';
import '../state/location_store.dart';
import '../state/location_tracker.dart';
import 'location_history_screen.dart';
import 'places_screen.dart';
import 'widgets/avatar_marker.dart';
import 'widgets/crossing_banner.dart';
import 'widgets/family_status_card.dart';
import 'widgets/location_profile_sheet.dart';
import 'widgets/map_style.dart';
import 'widgets/place_editor_sheet.dart';
import 'widgets/place_marker.dart';
import 'widgets/unread_pip.dart';
import 'widgets/share_location_sheet.dart';

/// The family map.
///
/// Two ideas hold this screen up.
///
/// The first is that a position arrives every few seconds, and a marker that
/// jumps to each one as it lands looks broken no matter how accurate it is.
/// So the data and the drawing are separated — [LocationStore] holds the
/// truth, and every marker on screen holds a [_Glide] that walks towards it at
/// sixty frames a second. That is the difference between this and a map that
/// merely works.
///
/// The second is that most people open this screen to find out that nothing is
/// wrong. The status card above the map answers that in one line, so the
/// common visit ends without anybody reading a single pin — and the map is
/// there for the visit where the answer is not reassuring.
class LiveMapScreen extends StatefulWidget {
  const LiveMapScreen({super.key, this.focusUserId});

  /// Open centred on one person — used when a location bubble in a chat is
  /// tapped, so the map arrives already answering the question that was asked.
  final String? focusUserId;

  @override
  State<LiveMapScreen> createState() => _LiveMapScreenState();
}

class _LiveMapScreenState extends State<LiveMapScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final LocationStore _store = LocationStore.instance;
  final LocationTracker _tracker = LocationTracker.instance;

  GoogleMapController? _map;
  Ticker? _ticker;

  /// One per person on screen, plus one for me.
  final Map<String, _Glide> _glides = {};

  /// The appearance each marker should currently have, and the one it is
  /// actually wearing. They differ for the moment it takes to paint a new
  /// bitmap, and during that moment the old one keeps being drawn — a marker
  /// that blinks out while its label is repainted is worse than a label that
  /// is a second behind.
  final Map<String, String> _wanted = {};
  final Map<String, String> _drawn = {};

  Set<Marker> _markers = const {};
  Set<Circle> _circles = const {};

  /*
   | The place being drawn right now, if any.
   |
   | Held on the screen rather than inside the editor sheet, because the
   | preview *is* the real circle on the real map — the sheet reports a
   | radius and this redraws. A diagram of a circle inside a sheet would be
   | much easier to build and would not answer the only question that
   | matters, which is whether the circle swallows the neighbours' houses.
   */
  FamilyPlace? _draft;

  /// Zoom, kept so place names can be hidden when their circles are too
  /// small on screen for a name to mean anything.
  double _zoom = 4;

  /// Whose marker the camera is chasing. Null means the camera is the user's
  /// to move — which it becomes the moment they drag it.
  String? _following;

  bool _ready = false;
  bool _night = false;

  /*
   | Until when a camera move is ours rather than the user's.
   |
   | `onCameraMoveStarted` fires for programmatic moves as well as gestures,
   | and the handler below treats a move as "the user has taken over" and
   | stops following. Left alone that is self-defeating: the first frame of
   | chasing a marker cancels the chase, so following silently never worked.
   |
   | A timestamp rather than a bool because moveCamera is called every 33 ms
   | while a marker is gliding, and a flag cleared on idle would be cleared
   | between two of our own moves.
   */
  int _selfMoveUntilMs = 0;
  bool _traffic = false;
  bool _panning = false;

  /// Folded away by hand, and it stays folded.
  ///
  /// Separate from [_panning], which folds it only for the duration of a
  /// gesture. Keeping the two apart is what lets a deliberate collapse
  /// survive a pan, and a pan restore a card the user had open.
  bool _cardFolded = false;
  MapType _type = MapType.normal;

  int _lastCameraMs = 0;

  static const String _meKey = '__me__';

  static const CameraPosition _india = CameraPosition(
    target: LatLng(20.5937, 78.9629),
    zoom: 4,
  );

  MapPalette get _palette => MapPalette.of(_night);

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);

    _following = widget.focusUserId;

    _store.addListener(_onData);
    _tracker.addListener(_onData);

    // A message arriving changes a badge on a face, which is a marker
    // repaint — so the inbox is a source of map truth like any other.
    ChatStore.instance.addListener(_onData);

    // And it has to be *loaded*, not merely listened to. Without this the
    // badges are blank for anyone who opened the app straight onto the map,
    // because nothing else in the app fills the thread list until the Chats
    // tab is tapped.
    ChatStore.instance.ensureLoaded();

    _ticker = createTicker(_onTick)..start();

    /*
     | Two things, in this order, and both matter.
     |
     | The hold keeps a location stream running for as long as this screen is
     | open, share or no share — so "You" is on the map because you are
     | looking at a map, not because you happen to be broadcasting.
     |
     | The prime paints a marker *now* from the phone's last known position,
     | which is usually instant. Without it the screen is markerless for the
     | five to thirty seconds a cold satellite lock takes, which is the whole
     | of most visits.
     */
    _tracker.hold();
    _tracker.primeFromLastKnown();

    _boot();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);

    _store.removeListener(_onData);
    _tracker.removeListener(_onData);
    ChatStore.instance.removeListener(_onData);

    // Hand the stream back. If a share is still running it carries on at the
    // server's rate; if not, it closes.
    _tracker.release();

    _ticker?.dispose();
    _map?.dispose();

    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    /*
     | Send what we have before the process is suspended.
     |
     | Without this, the last few fixes before somebody pockets their phone
     | sit in a buffer until the app is next opened — which is exactly the
     | stretch of time a family member is most likely to be looking.
     */
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _tracker.flush();
    }

    if (state == AppLifecycleState.resumed) {
      _store.bootstrap();
    }
  }

  Future<void> _boot() async {
    await _store.load();

    if (!mounted) return;

    /*
     | Permission is asked for on arrival, not on the first tap of "share".
     |
     | The map is useless without at least knowing where the viewer is — it
     | opens on the whole of India otherwise — and arriving at a screen whose
     | entire purpose is location is the moment the request makes the most
     | sense to the person being asked.
     */
    final access = await LocationPermissions.ensure(context);

    if (!mounted) return;

    if (access.canTrack) {
      final fix = await _tracker.currentFix();

      if (fix != null && mounted && _following == null) {
        _moveTo(LatLng(fix.latitude, fix.longitude), zoom: 15);
      }
    }

    _onData();
  }

  /*
  |----------------------------------------------------------------------------
  | Truth in, glides out
  |----------------------------------------------------------------------------
  */

  /// Where I am, for distance labels. The tracker's own fix in preference to
  /// the server's copy of it, because it is fresher by exactly one round trip.
  LivePosition? get _myPosition {
    final mine = _tracker.myPosition;

    if (mine != null && mine.hasFix) return mine;

    return null;
  }

  /// Whether the camera has been taken to [widget.focusUserId] yet.
  ///
  /// Setting `_following` in initState is not enough on its own, and the bug
  /// was invisible until the sharing banner made this the common path: the
  /// chase loop only runs while a marker is *moving*, so arriving focused on
  /// somebody standing still left the camera over the whole of India with
  /// their pin somewhere in it. The first time their glide exists, take the
  /// camera there once.
  bool _framedFocus = false;

  /// A position landed. Retarget, do not teleport.
  void _onData() {
    if (!mounted) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    final seen = <String>{};
    final me = _myPosition;

    for (final person in _store.people) {
      final position = person.position;

      if (!position.hasFix) continue;

      final id = person.user.id;

      seen.add(id);

      _retarget(id, LatLng(position.latitude!, position.longitude!), now);

      _want(
        id: id,
        name: person.user.name,
        initials: person.user.initials,
        avatarUrl: person.user.avatarUrl,
        caption: _captionFor(person, me),
        stale: position.isStale,
        unread: ChatStore.instance.unreadWith(id),
      );
    }

    final mine = _tracker.myPosition;

    if (mine != null && mine.hasFix) {
      seen.add(_meKey);

      _retarget(
        _meKey,
        LatLng(mine.latitude!, mine.longitude!),
        now,
        // Only ever true for our own marker: the tracker is the only source
        // that knows the accuracy of the reading it just replaced. Family
        // positions arrive from the server already settled.
        snap: _tracker.myPositionCorrected,
      );

      _want(
        id: _meKey,
        name: 'You',
        initials: Session.instance.user?.initials ?? 'Me',
        avatarUrl: Session.instance.user?.avatarUrl,
        caption: _store.isSharing ? 'Sharing' : 'Only you',
        stale: false,
        isMe: true,
      );
    }

    // Somebody stopped sharing. Their glide goes with them, or it would keep
    // being drawn at wherever it happened to have got to.
    _glides.removeWhere((id, _) => !seen.contains(id));
    _wanted.removeWhere((id, _) => !seen.contains(id));
    _drawn.removeWhere((id, _) => !seen.contains(id));

    _wantPlaceLabels();

    // setState, not a bare call: a first placement is not a movement, so
    // the ticker will not fire and nothing else would schedule a frame.
    setState(_rebuildMarkers);

    final focus = widget.focusUserId;

    if (!_framedFocus && focus != null && _glides.containsKey(focus)) {
      _framedFocus = true;

      _follow(focus);
    }
  }

  /// The second line on somebody's marker label.
  ///
  /// Distance when we know where we are, because "1.2 km" is the single most
  /// useful thing a glance at the map can tell you. Their movement status
  /// otherwise — never blank, because a label card with one line of text in a
  /// two-line box looks like a rendering fault.
  String _captionFor(LivePerson person, LivePosition? me) {
    final theirs = person.position;

    if (me != null && theirs.hasFix) {
      final metres = Geo.metresBetween(
        me.latitude!,
        me.longitude!,
        theirs.latitude!,
        theirs.longitude!,
      );

      final label = AvatarMarker.distanceLabel(metres);

      if (label != null) return label;
    }

    return _store.familyMember(person.user.id)?.statusLabel ??
        theirs.ageLabel;
  }

  /// [snap] means the position was corrected rather than followed — put the
  /// marker there, do not walk it there. See [LocationTracker.myPositionCorrected].
  void _retarget(String id, LatLng target, int nowMs, {bool snap = false}) {
    final existing = _glides[id];

    if (existing == null) {
      // First sight of somebody is a placement, not a journey. Animating in
      // from a previous position they never had would be a lie.
      _glides[id] = _Glide(target);

      return;
    }

    existing.retarget(target, nowMs, snap: snap);
  }

  /// Note the appearance a marker should have, and paint it if it is new.
  void _want({
    required String id,
    required String name,
    required String initials,
    String? avatarUrl,
    String? caption,
    bool stale = false,
    bool isMe = false,
    int unread = 0,
  }) {
    final ratio = MediaQuery.maybeDevicePixelRatioOf(context) ?? 3.0;
    final ring = _palette.ringFor(isMe: isMe, stale: stale);

    final key = AvatarMarker.cacheKey(
      userId: id,
      avatarUrl: avatarUrl,
      name: name,
      caption: caption,
      ring: ring,
      stale: stale,
      isMe: isMe,
      unread: unread,
      pixelRatio: ratio,
    );

    _wanted[id] = key;

    if (AvatarMarker.cached(key) != null) {
      _drawn[id] = key;

      return;
    }

    AvatarMarker.forPerson(
      userId: id,
      initials: initials,
      avatarUrl: avatarUrl,
      name: name,
      caption: caption,
      ring: ring,
      stale: stale,
      isMe: isMe,
      unread: unread,
      pixelRatio: ratio,
    ).then((_) {
      if (!mounted) return;

      // Only adopt it if it is still what we want. A burst of fixes can
      // queue three paints, and the last one to finish is not necessarily
      // the one that should win.
      if (_wanted[id] != key) return;

      setState(() => _drawn[id] = key);
    });
  }

  /*
  |----------------------------------------------------------------------------
  | The frame loop
  |----------------------------------------------------------------------------
  */

  void _onTick(Duration _) {
    if (!mounted) return;

    final now = DateTime.now().millisecondsSinceEpoch;

    // Nothing is moving, so nothing needs redrawing. On a map of stationary
    // people this loop costs one comparison per frame and no rebuilds at all.
    if (!_glides.values.any((glide) => glide.isMoving(now))) return;

    setState(_rebuildMarkers);

    if (_following != null) _chase(now);
  }

  /// Keep the followed marker under the camera.
  ///
  /// moveCamera rather than animateCamera: the glide is already the
  /// animation, and layering the platform's own easing on top of it produces
  /// a camera that lags the marker and then overshoots it. Throttled to 30 Hz
  /// because a camera update is a platform channel call, and sixty of those a
  /// second is where the frame budget goes on older Android hardware.
  void _chase(int nowMs) {
    if (nowMs - _lastCameraMs < 33) return;

    _lastCameraMs = nowMs;

    final glide = _glides[_following];

    if (glide == null) return;

    _selfMoveUntilMs = nowMs + 400;

    _map?.moveCamera(CameraUpdate.newLatLng(glide.valueAt(nowMs)));
  }

  /*
  |----------------------------------------------------------------------------
  | Places
  |----------------------------------------------------------------------------
  */

  /// Every place as a tinted circle, plus the one being drafted.
  ///
  /// The draft is layered last so it sits over any place it overlaps — while
  /// somebody is dragging a radius, theirs is the circle that matters.
  void _rebuildCircles() {
    final places = [..._store.places];

    final draft = _draft;

    _circles = {
      for (final place in places)
        if (draft == null || draft.id != place.id)
          _circleFor(place, draft: false),
      if (draft != null) _circleFor(draft, draft: true),
    };
  }

  Circle _circleFor(FamilyPlace place, {required bool draft}) {
    final tint = place.tint;

    return Circle(
      circleId: CircleId(draft ? '__draft__' : place.id),
      center: LatLng(place.latitude, place.longitude),
      radius: place.radiusMetres,

      /*
       | Faint. A geofence is context, not content.
       |
       | The first version filled at 0.18 and the map turned into a set of
       | coloured lagoons with people lost in them. The stroke is what makes
       | the boundary legible; the fill only has to hint that the inside is
       | different from the outside.
       */
      fillColor: tint.withValues(alpha: draft ? 0.16 : 0.09),
      strokeColor: tint.withValues(alpha: draft ? 0.95 : 0.55),
      strokeWidth: draft ? 3 : 2,

      /*
       | Tappable, so the circle itself is a way in.
       |
       | The name pill hides when the circle is small on screen, which left
       | places unreachable at a wide zoom — and therefore undeletable. The
       | circle is always there.
       |
       | Not while drafting: during an edit the circle is a preview, and a tap
       | on it would reopen the sheet that is already open.
       */
      consumeTapEvents: !draft,
      onTap: draft ? null : () => _editPlace(place),
    );
  }

  /// Ask for a name pill for every place worth labelling at this zoom.
  void _wantPlaceLabels() {
    final ratio = MediaQuery.maybeDevicePixelRatioOf(context) ?? 3.0;

    for (final place in _store.places) {
      if (!PlaceMarker.labelVisibleAt(_zoom, place.radiusMetres)) continue;

      final key = PlaceMarker.cacheKey(place, ratio);

      if (PlaceMarker.cached(key) != null) continue;

      PlaceMarker.forPlace(place, pixelRatio: ratio).then((_) {
        if (mounted) setState(_rebuildMarkers);
      });
    }
  }

  void _rebuildMarkers() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final ratio = MediaQuery.maybeDevicePixelRatioOf(context) ?? 3.0;

    _rebuildCircles();

    final placeMarkers = <Marker>{};

    for (final place in _store.places) {
      // Hidden rather than shrunk when the circle is a dot on screen. A pill
      // the size of the thing it is naming is not a label, it is clutter.
      if (!PlaceMarker.labelVisibleAt(_zoom, place.radiusMetres)) continue;

      final icon = PlaceMarker.cached(PlaceMarker.cacheKey(place, ratio));

      if (icon == null) continue;

      placeMarkers.add(
        Marker(
          markerId: MarkerId('place.${place.id}'),
          position: LatLng(place.latitude, place.longitude),
          icon: icon,
          anchor: PlaceMarker.anchor,

          // Under the people. A place is where somebody is, and if the two
          // overlap it is the person you came to look at.
          //
          // zIndexInt, not zIndex: the double version is deprecated because
          // some platforms truncate it to an int, which would collapse 0.5
          // to 0 on one platform and keep it on another. Layering that
          // differs between Android and iOS is the kind of bug nobody
          // reproduces.
          zIndexInt: 0,
          onTap: () => _editPlace(place),
        ),
      );
    }

    _markers = {
      ...placeMarkers,
      for (final entry in _glides.entries)
        if (_iconFor(entry.key) != null)
          Marker(
            markerId: MarkerId(entry.key),
            position: entry.value.valueAt(now),
            icon: _iconFor(entry.key)!,

            // The marker's point is the tip of its pointer, which sits in
            // the middle of the bitmap because a label card hangs below it.
            // Anchoring at the bottom instead would hang everybody a label's
            // height north of where they are.
            anchor: AvatarMarker.anchorFor(),

            // Me on top of everybody else, everybody else on top of places.
            zIndexInt: entry.key == _meKey ? 2 : 1,
            onTap: () => _onMarkerTap(entry.key),
          ),
    };
  }

  BitmapDescriptor? _iconFor(String id) {
    final drawn = _drawn[id];

    return drawn == null ? null : AvatarMarker.cached(drawn);
  }

  /*
  |----------------------------------------------------------------------------
  | Interaction
  |----------------------------------------------------------------------------
  */

  void _onMarkerTap(String key) {
    if (key == _meKey) {
      _follow(key);

      return;
    }

    final member = _store.familyMember(key) ?? _asMember(key);

    if (member == null) {
      _follow(key);

      return;
    }

    _openProfile(member);
  }

  /// A profile for somebody sharing with me who is not family.
  ///
  /// A fifteen-minute share in a chat thread puts a pin on this map from
  /// somebody who will never appear in the roster. Tapping that pin has to do
  /// the same thing as tapping any other, so the sheet's input is synthesised
  /// from what the share itself carries.
  FamilyMemberLive? _asMember(String userId) {
    final person = _store.person(userId);

    if (person == null) return null;

    return FamilyMemberLive(
      user: person.user,
      sharing: true,
      presence: const Presence.unknown(),
      movement: person.position.isStale
          ? 'stale'
          : (person.position.moving ? 'travelling' : 'stationary'),
      position: person.position,
    );
  }

  /// Open the thread with somebody, from wherever on this screen.
  void _openChat(FamilyMemberLive member) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          userId: member.user.id,
          name: member.user.name,
          username: member.user.username,
          avatarUrl: member.user.avatarUrl,
          initials: member.user.initials,
          presence: member.presence.label,
        ),
      ),
    );
  }

  void _openProfile(FamilyMemberLive member) {
    showLocationProfileSheet(
      context,
      member: member,
      palette: _palette,
      viewerPosition: _myPosition,
      onChat: () {
        Navigator.of(context).pop();
        _openChat(member);
      },
      onFocus: member.hasFix ? () => _follow(member.user.id) : null,
      onHistory: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => LocationHistoryScreen(person: member.user),
        ),
      ),
    );
  }

  /// Long-pressed the map, or tapped Add place.
  ///
  /// Inside an existing circle this opens *that* place rather than stacking a
  /// new one on top of it. Two reasons, and the second is the important one.
  ///
  /// Overlapping circles are almost never wanted — somebody pressing inside
  /// their own Home is far more likely to be reaching for it than to be
  /// defining a second place in the same garden.
  ///
  /// And it is how a place gets deleted. The pill carrying a place's name
  /// only appears once the circle is big enough on screen to be worth
  /// labelling, so at a wide zoom there was nothing to tap and no way to
  /// remove a place from the map at all. The gesture that creates them now
  /// also reaches them.
  Future<void> _newPlace(LatLng at) async {
    final existing = _placeAt(at);

    if (existing != null) {
      await _editPlace(existing);

      return;
    }

    await _openEditor(
      FamilyPlace(
        id: '',
        name: '',
        kind: 'home',
        latitude: at.latitude,
        longitude: at.longitude,
        radiusMetres: FamilyPlace.defaultRadius,
      ),
      isNew: true,
    );
  }

  Future<void> _editPlace(FamilyPlace place) => _openEditor(place, isNew: false);

  /// The smallest of my places containing this point, if any.
  ///
  /// Smallest rather than first: a school inside a wider neighbourhood circle
  /// should be what a press on the school reaches, which is the same rule the
  /// server uses when it decides what to call somebody's position.
  FamilyPlace? _placeAt(LatLng at) {
    FamilyPlace? best;

    for (final place in _store.places) {
      final metres = Geo.metresBetween(
        at.latitude,
        at.longitude,
        place.latitude,
        place.longitude,
      );

      if (metres > place.radiusMetres) continue;

      if (best == null || place.radiusMetres < best.radiusMetres) best = place;
    }

    return best;
  }

  Future<void> _openEditor(FamilyPlace place, {required bool isNew}) async {
    setState(() {
      _draft = place;
      _rebuildMarkers();
    });

    /*
     | Frame the circle before the sheet covers half the screen.
     |
     | Without this, adding a place while zoomed out leaves somebody adjusting
     | a radius they cannot see. The zoom is derived from the radius so the
     | circle lands at a usable size whatever they picked.
     */
    _claimMove();

    await _map?.animateCamera(
      CameraUpdate.newLatLngZoom(
        LatLng(place.latitude, place.longitude),
        _zoomForRadius(place.radiusMetres),
      ),
    );

    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PlaceEditorSheet(
        place: place,
        palette: _palette,
        onSave: (edited) async {
          final ok = await _store.savePlace(edited);

          if (ok && mounted) {
            setState(() {
              _draft = null;
              _rebuildMarkers();
            });

            _wantPlaceLabels();
          }

          return ok;
        },
        onDelete: isNew ? null : () => _deletePlace(place),
        onRadiusChanged: (metres) {
          if (!mounted) return;

          setState(() {
            _draft = _draft?.copyWith(radiusMetres: metres);
            _rebuildCircles();
          });
        },
      ),
    );

    // Dismissed without saving, or saved — either way the draft is done.
    if (mounted && _draft != null) {
      setState(() {
        _draft = null;
        _rebuildMarkers();
      });
    }
  }

  /// Remove a place, having asked first.
  ///
  /// The list screen already confirmed and the map did not, which is exactly
  /// backwards: on the map the delete button sits next to a circle somebody
  /// is mid-way through adjusting, so a misplaced tap is *more* likely here,
  /// not less.
  ///
  /// The question names the place and says what stops. "Are you sure?" is a
  /// question nobody reads.
  Future<void> _deletePlace(FamilyPlace place) async {
    final palette = _palette;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: palette.surface,
        title: Text(
          'Remove ${place.name}?',
          style: TextStyle(color: palette.textPrimary, fontSize: 17),
        ),
        content: Text(
          'Arrival and departure alerts for this place stop, and it comes off '
          'the map. Nobody else in your family is affected.',
          style: TextStyle(color: palette.textMuted, height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep it'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFE5484D),
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final removed = await _store.deletePlace(place.id);

    if (!mounted) return;

    setState(() {
      _draft = null;
      _rebuildMarkers();
    });

    // Close the editor the delete was launched from — but only on success, so
    // a server refusal leaves the sheet open with the place still in it.
    if (removed) Navigator.of(context).pop();
  }

  /// A zoom at which a circle of this radius fills a comfortable part of the
  /// screen — about a third of its width.
  double _zoomForRadius(double metres) {
    final width = MediaQuery.sizeOf(context).width;
    final wanted = (metres * 2) / (width / 3);

    // Inverse of metres-per-pixel. Clamped either side so a 2 km circle does
    // not fling the camera into orbit and an 80 m one does not bury it in the
    // pavement.
    final zoom = (math.log(156543.03392 / wanted) / math.ln2);

    return zoom.clamp(13.0, 18.0);
  }

  void _follow(String key) {
    setState(() => _following = key);

    final glide = _glides[key];

    if (glide == null) return;

    _claimMove();

    _map?.animateCamera(
      CameraUpdate.newLatLngZoom(
        glide.valueAt(DateTime.now().millisecondsSinceEpoch),
        16.5,
      ),
    );
  }

  void _moveTo(LatLng target, {double zoom = 15}) {
    _claimMove();

    _map?.animateCamera(CameraUpdate.newLatLngZoom(target, zoom));
  }

  /// Mark the next moment's camera movement as the app's own.
  ///
  /// An animated move takes about 300 ms and reports its start once, so a
  /// second of grace is generous without being long enough to swallow a real
  /// gesture that follows it.
  void _claimMove() {
    _selfMoveUntilMs = DateTime.now().millisecondsSinceEpoch + 1000;
  }

  /// Fit everybody, including me, into the frame.
  Future<void> _fitAll() async {
    setState(() => _following = null);

    final points = _glides.values
        .map((g) => g.valueAt(DateTime.now().millisecondsSinceEpoch))
        .toList();

    if (points.isEmpty) return;

    if (points.length == 1) {
      _moveTo(points.first, zoom: 16);

      return;
    }

    final bounds = LatLngBounds(
      southwest: LatLng(
        points.map((p) => p.latitude).reduce(math.min),
        points.map((p) => p.longitude).reduce(math.min),
      ),
      northeast: LatLng(
        points.map((p) => p.latitude).reduce(math.max),
        points.map((p) => p.longitude).reduce(math.max),
      ),
    );

    _claimMove();

    await _map?.animateCamera(CameraUpdate.newLatLngBounds(bounds, 72));
  }

  Future<void> _locateMe() async {
    final mine = _tracker.myPosition;

    if (mine != null && mine.hasFix) {
      setState(() => _following = _meKey);
      _moveTo(LatLng(mine.latitude!, mine.longitude!), zoom: 16.5);

      return;
    }

    final fix = await _tracker.currentFix();

    if (fix != null && mounted) {
      _moveTo(LatLng(fix.latitude, fix.longitude), zoom: 16.5);
    }
  }

  /// Switching ground repaints every marker.
  ///
  /// The ring colours differ between the two palettes — mint reads on navy and
  /// washes out on a pale road — so the markers have to be rebuilt, not just
  /// recoloured. [_want] handles that for free: the palette is part of the
  /// cache key, so asking for the same people again produces new bitmaps and
  /// the old ones stay cached for switching back.
  void _setNight(bool night) {
    if (_night == night) return;

    setState(() => _night = night);

    _onData();
  }

  /*
  |----------------------------------------------------------------------------
  | Build
  |----------------------------------------------------------------------------
  */

  @override
  Widget build(BuildContext context) {
    final palette = _palette;
    final bottom = MediaQuery.paddingOf(context).bottom;
    final top = MediaQuery.paddingOf(context).top;

    // Room for the chrome, so Google's own logo and the compass are not
    // hidden under the panels — hiding the logo is a terms-of-service
    // violation, not just untidy.
    final panelHeight = 168 + bottom;

    return Scaffold(
      backgroundColor: _night ? AppColors.canvas : const Color(0xFFF4F6F8),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: _india,
            style: _night ? MapStyle.dark : MapStyle.light,
            mapType: _type,
            trafficEnabled: _traffic,
            markers: _markers,
            circles: _circles,

            // Our own marker is drawn for us, with a face on it. Google's
            // blue dot alongside it would be the same person twice.
            myLocationEnabled: false,
            myLocationButtonEnabled: false,

            compassEnabled: false,
            mapToolbarEnabled: false,
            zoomControlsEnabled: false,

            // Both on by default, and both worth naming: rotate is how a
            // passenger orients a map to the road in front of them, and tilt
            // is what makes a dense junction legible. Turning them off is a
            // common reflex and it is what makes a map feel like a picture.
            rotateGesturesEnabled: true,
            tiltGesturesEnabled: true,

            padding: EdgeInsets.only(bottom: panelHeight - 40, top: 96),

            onMapCreated: (controller) {
              _map = controller;

              if (mounted) setState(() => _ready = true);
            },

            // Any deliberate camera move is the user taking over. Snapping
            // back to a followed marker after somebody has panned away is
            // the single most irritating thing a map can do.
            onCameraMoveStarted: () {
              // Ours, not theirs — see _selfMoveUntilMs.
              if (DateTime.now().millisecondsSinceEpoch < _selfMoveUntilMs) {
                return;
              }

              setState(() {
                _following = null;
                _panning = true;
              });
            },

            onCameraIdle: () async {
              if (!mounted) return;

              /*
               | Zoom, read on idle rather than on every camera frame.
               |
               | Place names appear and disappear with zoom, and recomputing
               | that sixty times a second during a pinch would mean painting
               | pills nobody ever sees. Once the gesture settles is soon
               | enough — the labels arrive as the map comes to rest, which
               | is also when somebody starts reading them.
               */
              final zoom = await _map?.getZoomLevel();

              if (!mounted) return;

              setState(() {
                _panning = false;

                if (zoom != null) _zoom = zoom;
              });

              _wantPlaceLabels();
              setState(_rebuildMarkers);
            },

            /*
             | Press and hold to drop a place.
             |
             | The gesture the whole feature hangs off, and the only one on
             | this screen that is not visible. That is why the rail also has
             | an Add place button and the empty places screen spells the
             | gesture out — a hidden primary action is a feature nobody
             | finds.
             */
            onLongPress: _newPlace,
          ),

          if (!_ready)
            Center(
              child: CircularProgressIndicator(color: palette.accent),
            ),

          /*
           | The card, and the back button beside it.
           |
           | IgnorePointer is deliberately absent: the card is tappable, and
           | the map underneath it is not. On a screen this dense, a control
           | that sometimes passes taps through would be worse than one that
           | never does.
           */
          Positioned(
            top: top + 8,
            left: 12,
            right: 12,
            child: Column(
              children: [
                Row(
                  children: [
                    _RoundButton(
                      icon: Icons.arrow_back_rounded,
                      palette: palette,
                      onTap: () => Navigator.of(context).maybePop(),
                    ),
                    const Spacer(),
                    _RoundButton(
                      icon: Icons.zoom_out_map_rounded,
                      palette: palette,
                      onTap: _fitAll,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                AnimatedBuilder(
                  animation: _store,
                  builder: (context, _) => Column(
                    children: [
                      FamilyStatusCard(
                        status: _store.status,
                        palette: palette,
                        collapsed: _cardFolded || _panning,
                        onToggle: () =>
                            setState(() => _cardFolded = !_cardFolded),
                      ),
                      CrossingBanner(
                        crossing: _store.crossing,
                        palette: palette,
                        onDismiss: _store.dismissCrossing,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // The rail.
          Positioned(
            right: 12,
            bottom: panelHeight + 12,
            child: Column(
              children: [
                _RoundButton(
                  icon: Icons.add_location_alt_rounded,
                  palette: palette,
                  onTap: _addPlaceHere,
                ),
                const SizedBox(height: 10),
                _RoundButton(
                  icon: Icons.traffic_rounded,
                  palette: palette,
                  active: _traffic,
                  onTap: () => setState(() => _traffic = !_traffic),
                ),
                const SizedBox(height: 10),
                _RoundButton(
                  icon: Icons.my_location_rounded,
                  palette: palette,
                  active: _following == _meKey,
                  onTap: _locateMe,
                ),
              ],
            ),
          ),

          Positioned(
            left: 12,
            bottom: panelHeight + 12,
            child: _MapViewChip(
              palette: palette,
              night: _night,
              type: _type,
              onPick: _openMapViewSheet,
            ),
          ),

          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _BottomPanel(
              store: _store,
              palette: palette,
              myPosition: _myPosition,
              onSelect: _openProfile,
              onChat: _openChat,
              onShare: _openShareSheet,
            ),
          ),
        ],
      ),
    );
  }

  /// Add a place at the middle of what is on screen.
  ///
  /// The button's honest equivalent of the long-press: whatever you have
  /// framed is what you meant. Falls back to your own position if the camera
  /// will not answer, and does nothing at all if neither is available —
  /// rather than dropping a circle at 0°N 0°E in the Gulf of Guinea, which is
  /// the classic tell of an unguarded null coordinate.
  Future<void> _addPlaceHere() async {
    final region = await _map?.getVisibleRegion();

    if (!mounted) return;

    if (region != null) {
      final centre = LatLng(
        (region.southwest.latitude + region.northeast.latitude) / 2,
        (region.southwest.longitude + region.northeast.longitude) / 2,
      );

      // A map that has never moved reports a region around the whole of
      // India, whose centre is a field in Madhya Pradesh.
      if (centre.latitude.abs() > 0.001 || centre.longitude.abs() > 0.001) {
        await _newPlace(centre);

        return;
      }
    }

    final mine = _myPosition;

    if (mine != null) {
      await _newPlace(LatLng(mine.latitude!, mine.longitude!));
    }
  }

  Future<void> _openShareSheet() async {
    final access = await LocationPermissions.ensure(context);

    if (!mounted) return;

    if (!access.canTrack) return;

    await showShareLocationSheet(context);
  }

  Future<void> _openMapViewSheet() async {
    final palette = _palette;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: palette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheet) => SafeArea(
        top: false,
        child: StatefulBuilder(
          builder: (_, refresh) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 14),
              Text(
                'Map view',
                style: TextStyle(
                  color: palette.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    for (final option in const [
                      (MapType.normal, false, 'Day', Icons.light_mode_rounded),
                      (MapType.normal, true, 'Night', Icons.dark_mode_rounded),
                      (
                        MapType.hybrid,
                        false,
                        'Satellite',
                        Icons.satellite_alt_rounded
                      ),
                      (
                        MapType.terrain,
                        false,
                        'Terrain',
                        Icons.terrain_rounded
                      ),
                    ])
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: _ViewOption(
                            palette: palette,
                            icon: option.$4,
                            label: option.$3,
                            selected: _type == option.$1 &&
                                (option.$1 != MapType.normal ||
                                    _night == option.$2),
                            onTap: () {
                              setState(() => _type = option.$1);
                              _setNight(option.$2);
                              refresh(() {});
                            },
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Divider(height: 1, color: palette.border),
              ListTile(
                onTap: () {
                  Navigator.of(sheet).pop();

                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const PlacesScreen()),
                  );
                },
                leading: Icon(Icons.place_rounded, color: palette.accent),
                title: Text(
                  'Family places',
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                subtitle: Text(
                  'Home, School and anywhere else that matters',
                  style: TextStyle(color: palette.textMuted, fontSize: 12),
                ),
                trailing: Icon(
                  Icons.chevron_right_rounded,
                  color: palette.textMuted,
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

/*
|------------------------------------------------------------------------------
| Interpolation
|------------------------------------------------------------------------------
*/

/// One marker walking towards where it has been told it is.
///
/// The rules that make this look right rather than merely animated:
///
///  - Retargeting starts from where the marker *is*, not from the last target
///    it was given. A fix that lands mid-glide would otherwise snap the
///    marker back to the previous point and re-run the journey.
///  - The duration is the measured gap since the previous fix, so the marker
///    arrives at roughly the moment the next one does. Guessing a fixed 500 ms
///    means a marker that sprints and then waits, which reads as stuttering.
///  - Linear, not eased. Eased interpolation is right for a thing that starts
///    and stops; a person walking down a street is doing neither, and easing
///    every segment makes them appear to brake at every fix.
class _Glide {
  _Glide(LatLng start)
      : _from = start,
        _to = start,
        _startMs = DateTime.now().millisecondsSinceEpoch,
        _durationMs = 1;

  LatLng _from;
  LatLng _to;
  int _startMs;
  int _durationMs;

  /// When the last target arrived, for measuring the gap to the next.
  int _lastFixMs = DateTime.now().millisecondsSinceEpoch;

  /// Below this, a "move" is GPS noise rather than travel, and animating it
  /// makes a stationary marker shiver.
  static const double _minMoveDegrees = 0.000012; // ~1.3 metres

  void retarget(LatLng next, int nowMs, {bool snap = false}) {
    if (_near(_to, next)) {
      _lastFixMs = nowMs;

      return;
    }

    /*
     | A correction is not a journey.
     |
     | Every other retarget here portrays travel, and animating it is the whole
     | point. This one portrays the phone changing its mind — the satellites
     | answered and the earlier guess was wrong — and walking the marker across
     | that distance says "they moved" about somebody standing still.
     |
     | So it lands. _from and _to are set to the same point and the clock is
     | already spent, which leaves valueAt returning the new position from the
     | very next frame.
     */
    if (snap) {
      _from = next;
      _to = next;
      _startMs = nowMs;
      _durationMs = 1;
      _lastFixMs = nowMs;

      return;
    }

    /*
     | The gap since the previous fix, which is the best available guess at
     | the gap until the next one.
     |
     | The ceiling used to be 8 seconds and that was the single biggest reason
     | walking family members looked stationary. A phone on the still plan
     | delivered a fix every forty seconds or so; the marker covered the whole
     | distance in eight seconds and then sat motionless for thirty-two. Four
     | glances out of five caught it parked.
     |
     | 45 seconds instead. The marker now walks the whole way across the gap,
     | so somebody on a sparse cadence still reads as *moving slowly* rather
     | than as *stopped* — which is both truer and what anybody watching the
     | map actually wants to know.
     |
     | The ceiling still exists for the case it was written for: a first fix
     | after an hour offline must not produce an hour-long crawl across the
     | city. Past 45 seconds the marker simply arrives.
     */
    final gap = (nowMs - _lastFixMs).clamp(400, 45000);

    _from = valueAt(nowMs);
    _to = next;
    _startMs = nowMs;
    _durationMs = gap;
    _lastFixMs = nowMs;
  }

  LatLng valueAt(int nowMs) {
    final t = ((nowMs - _startMs) / _durationMs).clamp(0.0, 1.0);

    if (t >= 1.0) return _to;

    return LatLng(
      _from.latitude + (_to.latitude - _from.latitude) * t,
      _from.longitude + (_to.longitude - _from.longitude) * t,
    );
  }

  bool isMoving(int nowMs) => nowMs - _startMs < _durationMs;

  static bool _near(LatLng a, LatLng b) =>
      (a.latitude - b.latitude).abs() < _minMoveDegrees &&
      (a.longitude - b.longitude).abs() < _minMoveDegrees;
}

/*
|------------------------------------------------------------------------------
| Chrome
|------------------------------------------------------------------------------
*/

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.palette,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final MapPalette palette;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: palette.shadow,
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: active ? palette.accent : palette.surface,
        shape: CircleBorder(side: BorderSide(color: palette.border)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(
              icon,
              size: 20,
              color: active ? Colors.white : palette.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

class _MapViewChip extends StatelessWidget {
  const _MapViewChip({
    required this.palette,
    required this.night,
    required this.type,
    required this.onPick,
  });

  final MapPalette palette;
  final bool night;
  final MapType type;
  final VoidCallback onPick;

  String get _label => switch (type) {
        MapType.hybrid || MapType.satellite => 'Satellite',
        MapType.terrain => 'Terrain',
        _ => night ? 'Night' : 'Day',
      };

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: palette.shadow,
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: palette.surface,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPick,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.layers_rounded, size: 17, color: palette.accent),
                const SizedBox(width: 7),
                Text(
                  _label,
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 3),
                Icon(
                  Icons.expand_less_rounded,
                  size: 17,
                  color: palette.textMuted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ViewOption extends StatelessWidget {
  const _ViewOption({
    required this.palette,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final MapPalette palette;
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? palette.accent.withValues(alpha: 0.14)
          : palette.textMuted.withValues(alpha: 0.07),
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? palette.accent : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 20,
                color: selected ? palette.accent : palette.textMuted,
              ),
              const SizedBox(height: 6),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  style: TextStyle(
                    color: selected ? palette.accent : palette.textMuted,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Who is in the family, and what I am doing about my own location.
class _BottomPanel extends StatelessWidget {
  const _BottomPanel({
    required this.store,
    required this.palette,
    required this.myPosition,
    required this.onSelect,
    required this.onChat,
    required this.onShare,
  });

  final LocationStore store;
  final MapPalette palette;
  final LivePosition? myPosition;
  final void Function(FamilyMemberLive member) onSelect;
  final void Function(FamilyMemberLive member) onChat;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    // Both stores: the roster decides who is listed, the inbox decides who is
    // wearing a badge, and a message arriving has to move the badge without
    // waiting for a position.
    return AnimatedBuilder(
      animation: Listenable.merge([store, ChatStore.instance]),
      builder: (context, _) {
        final family = store.family;

        return Container(
          padding: EdgeInsets.fromLTRB(
            0,
            14,
            0,
            12 + MediaQuery.paddingOf(context).bottom,
          ),
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
            boxShadow: [
              BoxShadow(
                color: palette.shadow,
                blurRadius: 22,
                offset: const Offset(0, -6),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 10, 10),
                child: Row(
                  children: [
                    Text(
                      'Family Members',
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Spacer(),
                    _SharePill(
                      store: store,
                      palette: palette,
                      onShare: onShare,
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: 86,
                child: family.isEmpty
                    ? _Empty(palette: palette)
                    : ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        itemCount: family.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 10),
                        itemBuilder: (context, index) => _MemberCard(
                          member: family[index],
                          palette: palette,
                          myPosition: myPosition,
                          onTap: () => onSelect(family[index]),
                          onChat: () => onChat(family[index]),
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Start or stop sharing, in the width of a chip.
///
/// It used to be a full-width button under the strip. The strip is what people
/// came for, and giving a control they touch twice a week more vertical space
/// than the family itself had it backwards.
class _SharePill extends StatelessWidget {
  const _SharePill({
    required this.store,
    required this.palette,
    required this.onShare,
  });

  final LocationStore store;
  final MapPalette palette;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    final sharing = store.isSharing;

    final tint = sharing ? const Color(0xFFE5484D) : palette.accent;

    return Material(
      color: tint.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: sharing ? () => store.stopSharing() : onShare,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                sharing ? Icons.stop_circle_rounded : Icons.near_me_rounded,
                size: 16,
                color: tint,
              ),
              const SizedBox(width: 6),
              Text(
                sharing ? 'Stop sharing' : 'Share mine',
                style: TextStyle(
                  color: tint,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.palette});

  final MapPalette palette;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Text(
          'Add family members and they will appear here, with their location '
          'whenever they choose to share it.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: palette.textMuted,
            fontSize: 12.5,
            height: 1.4,
          ),
        ),
      ),
    );
  }
}

class _MemberCard extends StatelessWidget {
  const _MemberCard({
    required this.member,
    required this.palette,
    required this.myPosition,
    required this.onTap,
    required this.onChat,
  });

  final FamilyMemberLive member;
  final MapPalette palette;
  final LivePosition? myPosition;
  final VoidCallback onTap;
  final VoidCallback onChat;

  String? get _distance {
    final mine = myPosition;
    final theirs = member.position;

    if (mine == null || !mine.hasFix) return null;
    if (theirs == null || !theirs.hasFix) return null;

    return Geo.distanceLabel(
      Geo.metresBetween(
        mine.latitude!,
        mine.longitude!,
        theirs.latitude!,
        theirs.longitude!,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final online = member.presence.isOnline;
    final battery = member.position?.batteryLevel;
    final distance = _distance;
    final unread = ChatStore.instance.unreadWith(member.user.id);

    return Material(
      color: palette.textMuted.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          // 162, not 152. At 152 the bottom line — "70%  ·  1.2 km" — wanted
          // 83dp of an available 81 and ellipsised the distance away, which
          // is the one number on the card somebody is reading it for.
          width: 162,
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: member.sharing
                  ? palette.accent.withValues(alpha: 0.35)
                  : palette.border,
            ),
          ),
          child: Row(
            children: [
              /*
               | Unclipped, because the badge hangs outside the avatar.
               |
               | A Stack clips to its own bounds by default, and a pip placed
               | at right:-4 on a 40dp circle would simply be cut in half —
               | silently, with no error, which is the worst way for a layout
               | to be wrong.
               */
              Stack(
                clipBehavior: Clip.none,
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: palette.accent.withValues(alpha: 0.16),
                    backgroundImage: member.user.avatarUrl == null
                        ? null
                        : NetworkImage(member.user.avatarUrl!),
                    child: member.user.avatarUrl != null
                        ? null
                        : Text(
                            member.user.initials,
                            style: TextStyle(
                              color: palette.accent,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                  ),
                  if (!member.presence.isHidden)
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: online
                              ? const Color(0xFF16A34A)
                              : const Color(0xFF94A3B8),
                          border:
                              Border.all(color: palette.surface, width: 2),
                        ),
                      ),
                    ),

                  /*
                   | Unread messages, opposite the presence dot.
                   |
                   | Top-right rather than bottom-right because that corner
                   | is already taken, and because every messaging app on the
                   | phone puts a count up there. Overflowing the avatar's
                   | box is intentional — the Stack is unclipped and a badge
                   | tucked inside the circle would sit on the face.
                   */
                  Positioned(
                    right: -4,
                    top: -4,
                    child: UnreadPip(count: unread, onTap: onChat),
                  ),
                ],
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      member.user.name.split(' ').first,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      member.statusLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.textMuted,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (battery != null) ...[
                          Icon(
                            battery <= 15
                                ? Icons.battery_alert_rounded
                                : Icons.battery_full_rounded,
                            size: 12,
                            color: battery <= 15
                                ? const Color(0xFFE5484D)
                                : palette.textMuted,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            '$battery%',
                            style: TextStyle(
                              color: battery <= 15
                                  ? const Color(0xFFE5484D)
                                  : palette.textMuted,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                        if (battery != null && distance != null)
                          Text(
                            '  ·  ',
                            style: TextStyle(
                              color: palette.textMuted.withValues(alpha: 0.5),
                              fontSize: 10.5,
                            ),
                          ),
                        if (distance != null)
                          Flexible(
                            child: Text(
                              distance,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: palette.textMuted,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
