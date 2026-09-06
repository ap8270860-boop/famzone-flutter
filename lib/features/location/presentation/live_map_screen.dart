import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/session/session.dart';
import '../../../core/theme/app_colors.dart';
import '../data/location_models.dart';
import '../state/location_permissions.dart';
import '../state/location_store.dart';
import '../state/location_tracker.dart';
import 'widgets/avatar_marker.dart';
import 'widgets/map_style.dart';
import 'widgets/share_location_sheet.dart';

/// The family map.
///
/// The whole screen is built around one idea: a position arrives every few
/// seconds, and a marker that jumps to each one as it lands looks broken no
/// matter how accurate it is. So the data and the drawing are separated —
/// [LocationStore] holds the truth, and every marker on screen holds a
/// [_Glide] that walks towards it at sixty frames a second.
///
/// That is the difference between this and a map that merely works.
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
  final Map<String, BitmapDescriptor> _icons = {};

  Set<Marker> _markers = const {};

  /// Whose marker the camera is chasing. Null means the camera is the user's
  /// to move — which it becomes the moment they drag it.
  String? _following;

  bool _ready = false;
  int _lastCameraMs = 0;

  static const CameraPosition _india = CameraPosition(
    target: LatLng(20.5937, 78.9629),
    zoom: 4,
  );

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);

    _following = widget.focusUserId;

    _store.addListener(_onData);
    _tracker.addListener(_onData);

    _ticker = createTicker(_onTick)..start();

    _boot();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);

    _store.removeListener(_onData);
    _tracker.removeListener(_onData);

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

  /// A position landed. Retarget, do not teleport.
  void _onData() {
    if (!mounted) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    final seen = <String>{};

    for (final person in _store.people) {
      final position = person.position;

      if (!position.hasFix) continue;

      seen.add(person.user.id);

      _retarget(
        person.user.id,
        LatLng(position.latitude!, position.longitude!),
        now,
      );

      _ensureIcon(
        id: person.user.id,
        initials: person.user.initials,
        avatarUrl: person.user.avatarUrl,
        stale: position.isStale,
      );
    }

    final mine = _tracker.myPosition;

    if (mine != null && mine.hasFix) {
      const meKey = '__me__';

      seen.add(meKey);

      _retarget(meKey, LatLng(mine.latitude!, mine.longitude!), now);

      _ensureIcon(
        id: meKey,
        initials: Session.instance.user?.initials ?? 'Me',
        avatarUrl: Session.instance.user?.avatarUrl,
        stale: false,
        isMe: true,
      );
    }

    // Somebody stopped sharing. Their glide goes with them, or it would keep
    // being drawn at wherever it happened to have got to.
    _glides.removeWhere((id, _) => !seen.contains(id));

    // setState, not a bare call: a first placement is not a movement, so
    // the ticker will not fire and nothing else would schedule a frame.
    setState(_rebuildMarkers);
  }

  void _retarget(String id, LatLng target, int nowMs) {
    final existing = _glides[id];

    if (existing == null) {
      // First sight of somebody is a placement, not a journey. Animating in
      // from a previous position they never had would be a lie.
      _glides[id] = _Glide(target);

      return;
    }

    existing.retarget(target, nowMs);
  }

  Future<void> _ensureIcon({
    required String id,
    required String initials,
    String? avatarUrl,
    bool stale = false,
    bool isMe = false,
  }) async {
    final key = '$id|$stale';

    if (_icons.containsKey(key)) return;

    final ratio = MediaQuery.maybeDevicePixelRatioOf(context) ?? 3.0;

    final icon = await AvatarMarker.forPerson(
      userId: id,
      initials: initials,
      avatarUrl: avatarUrl,
      stale: stale,
      isMe: isMe,
      pixelRatio: ratio,
    );

    if (!mounted) return;

    // Keyed on staleness too, so a pin that goes stale repaints itself once
    // rather than being stuck bright for as long as the screen is open.
    _icons
      ..remove('$id|${!stale}')
      ..[key] = icon;

    setState(_rebuildMarkers);
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

    final glide = _glides[_following == Session.instance.user?.id
        ? '__me__'
        : _following];

    if (glide == null) return;

    _map?.moveCamera(CameraUpdate.newLatLng(glide.valueAt(nowMs)));
  }

  void _rebuildMarkers() {
    final now = DateTime.now().millisecondsSinceEpoch;

    _markers = {
      for (final entry in _glides.entries)
        if (_iconFor(entry.key) != null)
          Marker(
            markerId: MarkerId(entry.key),
            position: entry.value.valueAt(now),
            icon: _iconFor(entry.key)!,

            // The pin's point is its position; without this the marker is
            // centred on the coordinate and everybody sits half a building
            // north of where they are.
            anchor: const Offset(0.5, 1.0),

            zIndex: entry.key == '__me__' ? 2.0 : 1.0,
            onTap: () => _follow(entry.key),
          ),
    };
  }

  BitmapDescriptor? _iconFor(String id) =>
      _icons['$id|false'] ?? _icons['$id|true'];

  /*
  |----------------------------------------------------------------------------
  | Camera
  |----------------------------------------------------------------------------
  */

  void _follow(String key) {
    setState(() => _following = key);

    final glide = _glides[key];

    if (glide == null) return;

    _map?.animateCamera(
      CameraUpdate.newLatLngZoom(
        glide.valueAt(DateTime.now().millisecondsSinceEpoch),
        16.5,
      ),
    );
  }

  void _moveTo(LatLng target, {double zoom = 15}) {
    _map?.animateCamera(CameraUpdate.newLatLngZoom(target, zoom));
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

    await _map?.animateCamera(CameraUpdate.newLatLngBounds(bounds, 72));
  }

  /*
  |----------------------------------------------------------------------------
  | Build
  |----------------------------------------------------------------------------
  */

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: _india,
            style: MapStyle.dark,
            markers: _markers,

            // Our own marker is drawn for us, with a face on it. Google's
            // blue dot alongside it would be the same person twice.
            myLocationEnabled: false,
            myLocationButtonEnabled: false,

            compassEnabled: false,
            mapToolbarEnabled: false,
            zoomControlsEnabled: false,
            padding: EdgeInsets.only(bottom: 210 + bottom, top: 96),

            onMapCreated: (controller) {
              _map = controller;

              if (mounted) setState(() => _ready = true);
            },

            // Any deliberate camera move is the user taking over. Snapping
            // back to a followed marker after somebody has panned away is
            // the single most irritating thing a map can do.
            onCameraMoveStarted: () {
              if (_following != null) setState(() => _following = null);
            },
          ),

          if (!_ready)
            const Center(
              child: CircularProgressIndicator(color: AppColors.neonCyan),
            ),

          _Header(
            onBack: () => Navigator.of(context).maybePop(),
            onFit: _fitAll,
          ),

          Positioned(
            right: 16,
            bottom: 214 + bottom,
            child: _RoundButton(
              icon: Icons.my_location_rounded,
              onTap: () async {
                final mine = _tracker.myPosition;

                if (mine != null && mine.hasFix) {
                  setState(() => _following = '__me__');
                  _moveTo(LatLng(mine.latitude!, mine.longitude!), zoom: 16.5);

                  return;
                }

                final fix = await _tracker.currentFix();

                if (fix != null && mounted) {
                  _moveTo(LatLng(fix.latitude, fix.longitude), zoom: 16.5);
                }
              },
            ),
          ),

          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _BottomPanel(
              store: _store,
              onSelect: _follow,
              onShare: _openShareSheet,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openShareSheet() async {
    final access = await LocationPermissions.ensure(context);

    if (!mounted) return;

    if (!access.canTrack) return;

    await showShareLocationSheet(context);
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

  void retarget(LatLng next, int nowMs) {
    if (_near(_to, next)) {
      _lastFixMs = nowMs;

      return;
    }

    // The gap since the previous fix, which is the best available guess at
    // the gap until the next one. Clamped: a first fix after an hour offline
    // must not produce an hour-long crawl.
    final gap = (nowMs - _lastFixMs).clamp(400, 8000);

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

class _Header extends StatelessWidget {
  const _Header({required this.onBack, required this.onFit});

  final VoidCallback onBack;
  final VoidCallback onFit;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: MediaQuery.paddingOf(context).top + 8,
      left: 12,
      right: 12,
      child: Row(
        children: [
          _RoundButton(icon: Icons.arrow_back_rounded, onTap: onBack),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.canvasRaised.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: AppColors.glassBorder),
            ),
            child: const Text(
              'Family map',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const Spacer(),
          _RoundButton(icon: Icons.zoom_out_map_rounded, onTap: onFit),
        ],
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.canvasRaised.withValues(alpha: 0.92),
      shape: const CircleBorder(
        side: BorderSide(color: AppColors.glassBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(icon, color: AppColors.textPrimary, size: 21),
        ),
      ),
    );
  }
}

/// Who is on the map, and what I am doing about it.
class _BottomPanel extends StatelessWidget {
  const _BottomPanel({
    required this.store,
    required this.onSelect,
    required this.onShare,
  });

  final LocationStore store;
  final void Function(String key) onSelect;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final people = store.people;

        return Container(
          padding: EdgeInsets.fromLTRB(
            0,
            18,
            0,
            16 + MediaQuery.paddingOf(context).bottom,
          ),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x00001528), Color(0xE6001528), Color(0xFF001528)],
              stops: [0, 0.35, 1],
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 96,
                child: people.isEmpty
                    ? const _NobodySharing()
                    : ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: people.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 10),
                        itemBuilder: (context, index) => _PersonCard(
                          person: people[index],
                          onTap: () => onSelect(people[index].user.id),
                        ),
                      ),
              ),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _ShareButton(store: store, onShare: onShare),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _NobodySharing extends StatelessWidget {
  const _NobodySharing();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Text(
              'Nobody is sharing right now',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: 6),
            Text(
              'When family or friends share their location, they appear here.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textMuted,
                fontSize: 12.5,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PersonCard extends StatelessWidget {
  const _PersonCard({required this.person, required this.onTap});

  final LivePerson person;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final position = person.position;
    final speed = position.speedKmh;

    return Material(
      color: AppColors.canvasRaised.withValues(alpha: 0.95),
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: 200,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: position.isStale
                  ? AppColors.glassBorder
                  : AppColors.mint.withValues(alpha: 0.4),
            ),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 21,
                backgroundColor: AppColors.royalNavy,
                backgroundImage: person.user.avatarUrl == null
                    ? null
                    : NetworkImage(person.user.avatarUrl!),
                child: person.user.avatarUrl != null
                    ? null
                    : Text(
                        person.user.initials,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      person.user.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: position.isStale
                                ? AppColors.lavenderGray
                                : AppColors.mint,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            speed == null
                                ? position.ageLabel
                                : '${speed.round()} km/h',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 12,
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

class _ShareButton extends StatelessWidget {
  const _ShareButton({required this.store, required this.onShare});

  final LocationStore store;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    final sharing = store.isSharing;

    return SizedBox(
      height: 54,
      width: double.infinity,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: sharing
              ? const LinearGradient(
                  colors: [Color(0xFF3A1730), Color(0xFF4A1C2A)],
                )
              : AppColors.brandGradient,
          borderRadius: BorderRadius.circular(17),
          border: sharing
              ? Border.all(color: AppColors.alertRed.withValues(alpha: 0.5))
              : null,
        ),
        child: TextButton.icon(
          onPressed: sharing ? () => store.stopSharing() : onShare,
          style: TextButton.styleFrom(
            foregroundColor: sharing ? AppColors.alertRed : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(17),
            ),
          ),
          icon: Icon(
            sharing ? Icons.stop_circle_outlined : Icons.near_me_rounded,
            size: 20,
          ),
          label: Text(
            sharing ? 'Stop sharing my location' : 'Share my location',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
        ),
      ),
    );
  }
}
