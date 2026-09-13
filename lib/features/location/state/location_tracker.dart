import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../../../core/session/session.dart';
import '../data/location_api.dart';
import '../data/location_models.dart';

/// The thing that watches the phone.
///
/// Deliberately dumb about *why* it is running: it is handed a [TrackingPlan]
/// and it obeys it. Every plan comes from the server, on the response to
/// every ping, which means the sampling rate, the distance filter and the
/// decision to stop altogether are all things that can be changed for
/// everybody without shipping a build. A client that decides for itself when
/// to stop tracking is a client you cannot fix.
///
/// Two rates, not one. The stream runs at whatever the plan says and updates
/// the local dot immediately, because your own position on your own map
/// should never lag. Uploads are batched on top of that, because a POST every
/// five seconds is a battery and data cost with no user-visible benefit — the
/// people watching cannot tell the difference between a fix that is one
/// second old and one that is eight.
class LocationTracker extends ChangeNotifier {
  LocationTracker._() {
    Session.instance.onSignOut(stop);
  }

  static final LocationTracker instance = LocationTracker._();

  final LocationApi _api = LocationApi();

  StreamSubscription<Position>? _stream;
  Timer? _flusher;

  TrackingPlan _plan = const TrackingPlan.idle();
  TrackingPlan get plan => _plan;

  bool get running => _stream != null;

  /// Where this phone is, updated at stream rate.
  ///
  /// Separate from anything the server knows: the blue dot on your own map
  /// should move the moment the GPS says so, not when a round trip completes.
  LivePosition? _mine;
  LivePosition? get myPosition => _mine;

  final List<LocationFix> _buffer = [];
  bool _sending = false;

  /// How many unsent fixes to keep before dropping the oldest.
  ///
  /// A phone with no signal for an hour at five-second intervals would
  /// otherwise accumulate 720 of them and then try to send the lot. Two
  /// hundred is about twenty minutes of dense tracking, which is as much
  /// backfill as anybody actually looks at.
  static const int _bufferCap = 200;

  /// Send at least this often while tracking, even if the buffer is short.
  static const Duration _flushEvery = Duration(seconds: 12);

  /// Or as soon as this many have piled up, whichever comes first.
  static const int _flushAt = 6;

  /*
  |----------------------------------------------------------------------------
  | The plan
  |----------------------------------------------------------------------------
  */

  /// Obey a plan from the server.
  ///
  /// Cheap to call on every ping response, which is the point: the common
  /// case is that nothing changed, and a plan of the same shape leaves the
  /// running stream completely alone. Tearing down and rebuilding a location
  /// stream costs a fresh satellite acquisition on Android — a few seconds of
  /// nothing, every time — so doing it needlessly would show up as exactly
  /// the stutter this whole class exists to avoid.
  Future<void> apply(TrackingPlan next) async {
    _plan = next;

    // Not `stop()` any more. A share ending does not necessarily mean the
    // stream should close — somebody may still be looking at the map, and
    // their own dot should keep working.
    await _reconcile();
  }

  /*
  |----------------------------------------------------------------------------
  | Watching without sharing
  |----------------------------------------------------------------------------
  |
  | The bug this exists for: "my own marker sometimes appears and sometimes
  | does not, and when I stop sharing it shows up."
  |
  | [myPosition] was only ever written by the tracking stream, and the
  | tracking stream only ran while a share was live. So the map had no idea
  | where its own user was until a share had been running long enough for the
  | first satellite lock — five seconds on a good day, thirty inside a
  | building — and had no idea at all when nothing was being shared. Whether
  | the marker appeared came down to how long you had been staring at the
  | screen, which is exactly the inconsistency that was reported.
  |
  | Opening the map is itself a reason to know where you are. So the screen
  | takes a *hold*: while it is on screen the stream runs regardless of
  | sharing, at a gentler rate, and nothing is uploaded unless a share is
  | actually live. Permission to see yourself on your own phone is not the
  | same as permission to broadcast, and the two are kept apart here rather
  | than in the caller.
  */

  int _holds = 0;

  /// The plan used when nobody is sharing but somebody is looking at a map.
  ///
  /// Coarser than the sharing plans: this only has to keep a dot honest on a
  /// screen the user is already looking at, so it costs far less than the
  /// five-second plan and is still far better than nothing.
  static const TrackingPlan _watchPlan = TrackingPlan(
    active: true,
    intervalSeconds: 10,
    distanceFilter: 15,
  );

  /// Called by a screen that needs the user's own position on it.
  ///
  /// Reference counted, because two map screens can be stacked — the history
  /// screen over the live one — and the second one closing must not switch
  /// the first one's dot off.
  Future<void> hold() async {
    _holds++;

    if (_holds == 1) await _reconcile();
  }

  Future<void> release() async {
    if (_holds > 0) _holds--;

    if (_holds == 0) await _reconcile();
  }

  /// The plan actually in force: the server's if a share is live, the watch
  /// plan if only a screen is asking, nothing otherwise.
  TrackingPlan get _effective {
    if (_plan.active) return _plan;
    if (_holds > 0) return _watchPlan;

    return const TrackingPlan.idle();
  }

  /// Whether fixes may leave the device.
  ///
  /// Only a live share earns that. A hold is somebody looking at their own
  /// map, and looking at your own map is not consent to be recorded.
  bool get _uploading => _plan.active;

  Future<void> _reconcile() async {
    final wanted = _effective;

    if (!wanted.active) {
      await _teardown();

      return;
    }

    if (running && _running != null && _running!.sameShapeAs(wanted)) return;

    await _restart();
  }

  /// The plan the open stream was configured with, so a reconcile can tell
  /// whether anything actually needs reopening.
  TrackingPlan? _running;

  /// Why the stream is not running, when it is not running.
  ///
  /// Held rather than only logged, because the failure mode this exists for
  /// is silent: a stream that will not open produces no fixes, and every
  /// other part of the system carries on looking perfectly healthy while the
  /// coordinates are simply never there.
  String? _fault;
  String? get fault => _fault;

  /// Begin, or reconfigure.
  Future<void> _restart() async {
    await _cancel();

    final plan = _effective;
    _running = plan;

    final settings = _settings(plan);

    try {
      _stream = Geolocator.getPositionStream(locationSettings: settings).listen(
        _onFix,
        onError: (Object error) {
          /*
           | Errors *during* a stream are almost always the user revoking
           | permission or switching location off underneath us. Neither is
           | worth an alert: the map shows the last known position going
           | stale, which says the same thing without interrupting anybody.
           */
          _fault = error.toString();

          debugPrint('location stream error: $error');
        },
        cancelOnError: false,
      );

      _fault = null;
    } catch (error) {
      /*
       | Failing to open at all is a different thing, and it is the one that
       | cost an afternoon: a missing WAKE_LOCK declaration threw here, the
       | stream never started, and nothing downstream had any way to say so.
       | Swallowed rather than rethrown — a phone that cannot track must not
       | crash the screen — but recorded, so the next person gets a reason.
       */
      _stream = null;
      _fault = error.toString();

      debugPrint('location stream failed to open: $error');
    }

    _flusher?.cancel();
    _flusher = Timer.periodic(_flushEvery, (_) => flush());

    notifyListeners();
  }

  /// Cancelling a stream that never opened throws. Guarded so a failed start
  /// cannot take the stop path down with it.
  Future<void> _cancel() async {
    final stream = _stream;

    _stream = null;

    if (stream == null) return;

    try {
      await stream.cancel();
    } catch (error) {
      debugPrint('location stream cancel: $error');
    }
  }

  /// Stop sharing. Tell nobody — ending a share is what tells people.
  ///
  /// The stream may well keep running afterwards: if a map screen is open,
  /// its hold keeps the user's own dot alive. What stops is the *uploading*.
  Future<void> stop() async {
    _plan = const TrackingPlan.idle();

    // Anything already measured is still worth sending — the last fix before
    // somebody taps "stop sharing" is the most interesting one in the buffer.
    await flush();

    await _reconcile();

    notifyListeners();
  }

  /// Close the stream outright. Only when nothing wants it at all.
  Future<void> _teardown() async {
    await _cancel();

    _flusher?.cancel();
    _flusher = null;

    _running = null;

    // Forget the movement anchor. A stream restarted an hour later would
    // otherwise measure its first displacement against wherever the phone
    // was when it closed.
    //
    // [_mine] deliberately survives: the last known position is still the
    // best answer to "where am I" until a better one arrives, and throwing
    // it away is what made the marker vanish when a share ended.
    _anchor = null;
    _moving = false;

    notifyListeners();
  }

  /*
  |----------------------------------------------------------------------------
  | Platform settings
  |----------------------------------------------------------------------------
  */

  /// The two platforms are configured differently enough that a shared
  /// LocationSettings would be a lowest common denominator on both.
  LocationSettings _settings(TrackingPlan plan) {
    final distance = plan.distance;
    final interval = plan.interval;

    if (Platform.isAndroid) {
      return AndroidSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: distance,

        /*
         | The minimum gap between fixes, not a promise of one every N.
         |
         | Android will happily deliver faster if another app has already
         | asked for it, which is free — the radio is on either way. What
         | this stops is *us* being the reason it is on.
         */
        intervalDuration: interval,

        foregroundNotificationConfig: plan.background
            ? const ForegroundNotificationConfig(
                notificationTitle: 'SFamily is sharing your location',
                notificationText:
                    'Your family can see where you are. Tap to stop.',
                enableWakeLock: true,
                setOngoing: false,
              )
            : null,
      );
    }

    if (Platform.isIOS || Platform.isMacOS) {
      return AppleSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: distance,

        /*
         | Tells iOS this is a person moving around a city, which is what it
         | uses to decide when it may switch the GPS off to save power.
         */
        activityType: ActivityType.otherNavigation,

        /*
         | Off, deliberately.
         |
         | iOS will otherwise pause updates when it decides you have stopped
         | moving — and it does not reliably resume them. That behaviour is
         | correct for a fitness tracker and catastrophic for a safety app,
         | where "her location stopped updating" must mean something happened,
         | not that the OS made a judgement call.
         */
        pauseLocationUpdatesAutomatically: false,

        allowBackgroundLocationUpdates: plan.background,

        /*
         | The blue "using your location" bar, when running in the background.
         |
         | Required by App Review for background location, and right anyway:
         | a person should never have to open an app to find out it is
         | tracking them.
         */
        showBackgroundLocationIndicator: plan.background,
      );
    }

    return LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: distance,
    );
  }

  /*
  |----------------------------------------------------------------------------
  | Fixes
  |----------------------------------------------------------------------------
  */

  /*
  |----------------------------------------------------------------------------
  | Battery
  |----------------------------------------------------------------------------
  |
  | A family member's battery percentage is one of the more useful things on
  | this map and one of the cheapest to send: the column, the wire format and
  | the presenter have all existed since the first version. Nothing was ever
  | reading the battery, so it arrived null every time — the whole feature was
  | a missing four-line sampler.
  |
  | Cached rather than read per fix. A reading is a platform channel call, a
  | phone at 5 s intervals would make twelve a minute, and the answer changes
  | perhaps once every few minutes. Ninety seconds is far finer than the
  | quantity it measures.
  */

  static const Duration _batteryEvery = Duration(seconds: 90);

  final Battery _battery = Battery();

  int? _batteryLevel;
  DateTime? _batteryAt;

  /// Kick off a refresh if the cached reading is old. Never awaited — a fix
  /// must not wait on a battery reading, and the value it misses will be on
  /// the next one a few seconds later.
  void _refreshBattery() {
    final at = _batteryAt;

    if (at != null && DateTime.now().difference(at) < _batteryEvery) return;

    // Stamped before the await, not after, so a platform that never answers
    // cannot make this retry on every single fix.
    _batteryAt = DateTime.now();

    _readBattery();
  }

  /// Read it, and survive a platform that has no answer.
  ///
  /// This was a `.then().catchError(() => 0)` and the analyser was right to
  /// object: `then` with a void body produces a `Future<Null>`, so the error
  /// handler has to return null, not an int. It would have thrown a TypeError
  /// into the zone on exactly the devices the catch existed for — an
  /// emulator, or anything without a battery API — which is the worst
  /// possible place for a crash to appear, because it only happens where
  /// nobody is testing.
  ///
  /// A plain try/catch cannot get this wrong.
  Future<void> _readBattery() async {
    try {
      final level = await _battery.batteryLevel;

      if (level >= 0 && level <= 100) _batteryLevel = level;
    } catch (_) {
      // No battery API. Null is a perfectly good answer and the UI already
      // draws a dash for it.
    }
  }

  /*
  |----------------------------------------------------------------------------
  | Am I moving?
  |----------------------------------------------------------------------------
  |
  | Not `position.speed > 1.0`, which is what this used to be and what made
  | walking family members show as stationary on everybody else's map.
  |
  | The speed field is the least trustworthy thing in a fix. Android's fused
  | provider derives it from Doppler shift and reports a flat 0.0 whenever the
  | lock is not good enough — which, for somebody walking between buildings,
  | is most of the time. iOS reports -1 for "unknown", which this class
  | already turns into null. On both, a pedestrian frequently looks stopped.
  |
  | That mattered far more than it sounds, because the server sets the
  | sampling cadence from this flag: reported stationary meant a 60 m distance
  | filter, which on Android suppresses updates until the phone has moved 60 m
  | — about forty-three seconds of walking. So the flag starved the very
  | stream of fixes that could have corrected it.
  |
  | Displacement needs no cooperation from the sensor. The server does the
  | same arithmetic authoritatively on every accepted fix; this is the local
  | copy, so the phone's own dot and its first ping are right too.
  */

  /// The fix the current verdict is measured against, and when it was taken.
  ///
  /// An *anchor*, not the previous fix. Consecutive fixes arrive five seconds
  /// apart, and over five seconds nothing can be told apart from noise. Over
  /// twenty, a walk at a constant pace separates cleanly: GPS error is
  /// mean-reverting rather than diffusive, so noise-implied speed decays as
  /// 1/t while real speed does not.
  Position? _anchor;

  bool _moving = false;

  static const double _movingSpeedMs = 0.7; // 2.5 km/h
  static const double _movingMinMetres = 10.0;
  static const double _movingAccuracyFactor = 2.0;
  static const double _movingMaxAccuracy = 40.0;
  static const double _movingBaselineS = 20.0;

  bool _isMoving(Position position) {
    final anchor = _anchor;

    if (anchor == null) {
      _anchor = position;

      // Nothing to measure against yet, so the sensor is all there is — and
      // it is only the first fix of a session.
      _moving = position.speed > _movingSpeedMs;

      return _moving;
    }

    // A fix worse than this votes on nothing. Guessing from a reading you do
    // not trust is how a stationary phone talks itself into the five-second
    // plan and flattens a battery.
    if (position.accuracy > _movingMaxAccuracy) return _moving;

    final seconds =
        position.timestamp.difference(anchor.timestamp).inMilliseconds / 1000.0;

    if (seconds < _movingBaselineS) return _moving;

    final metres = Geolocator.distanceBetween(
      anchor.latitude,
      anchor.longitude,
      position.latitude,
      position.longitude,
    );

    final needed = math.max(
      _movingMinMetres,
      _movingAccuracyFactor * position.accuracy,
    );

    _moving = metres >= needed && metres / seconds >= _movingSpeedMs;
    _anchor = position;

    return _moving;
  }

  /// Set the local dot from a raw position, without going near the buffer.
  ///
  /// Used by the one-shot and last-known paths, which have no business
  /// queueing anything for upload — they exist purely so the map has
  /// something to draw immediately.
  void _adopt(Position position) {
    _mine = LivePosition(
      userId: Session.instance.user?.id ?? '',
      hasFix: true,
      latitude: position.latitude,
      longitude: position.longitude,
      accuracy: position.accuracy,
      speed: position.speed < 0 ? null : position.speed,
      heading: position.heading >= 0 ? position.heading : null,
      moving: _moving,
      batteryLevel: _batteryLevel,
      recordedAt: position.timestamp,
      ageSeconds: 0,
    );

    notifyListeners();
  }

  /// The fastest possible answer to "where am I", for a screen that has just
  /// opened.
  ///
  /// `getLastKnownPosition` is usually instant and often minutes old, which
  /// is the right trade for a first paint: a marker in roughly the right
  /// place now beats an empty map for the fifteen seconds a cold lock takes.
  /// The stream overwrites it as soon as it has something better.
  Future<void> primeFromLastKnown() async {
    if (_mine != null) return;

    try {
      final position = await Geolocator.getLastKnownPosition();

      if (position != null && _mine == null) _adopt(position);
    } catch (_) {
      // No permission, or no cached fix. Both are ordinary.
    }
  }

  void _onFix(Position position) {
    _refreshBattery();

    final moving = _isMoving(position);

    final fix = LocationFix(
      latitude: position.latitude,
      longitude: position.longitude,
      recordedAt: position.timestamp,
      accuracy: position.accuracy,
      speed: position.speed < 0 ? null : position.speed,

      /*
       | Below walking pace the reported heading is noise — a stationary phone
       | reports whatever direction its last movement happened to be, and
       | feeding that to a rotating marker makes it spin on the spot.
       */
      heading: position.speed > 1.0 && position.heading >= 0
          ? position.heading
          : null,

      /*
       | From displacement, not from the speed sensor. See [_isMoving].
       |
       | The server recomputes this from the same two positions and its answer
       | is the one that counts — this copy exists so the local dot and the
       | very first ping of a session are right before any round trip.
       */
      moving: moving,
      batteryLevel: _batteryLevel,
    );

    /*
     | Buffered only while a share is live.
     |
     | A hold — somebody looking at their own map — moves the local dot and
     | nothing else. Uploading fixes taken under a hold would mean recording a
     | position nobody agreed to share, which is the one line this feature
     | must not cross.
     */
    if (_uploading) _buffer.add(fix);

    if (_buffer.length > _bufferCap) {
      _buffer.removeRange(0, _buffer.length - _bufferCap);
    }

    // The local dot moves now, not when the network agrees — and it moves
    // whether or not anything is being shared. This is the line that makes
    // "You" appear on the map the moment it opens.
    _mine = LivePosition(
      userId: Session.instance.user?.id ?? '',
      hasFix: true,
      latitude: fix.latitude,
      longitude: fix.longitude,
      accuracy: fix.accuracy,
      speed: fix.speed,
      heading: fix.heading,
      moving: fix.moving,
      batteryLevel: fix.batteryLevel,
      recordedAt: fix.recordedAt,
      ageSeconds: 0,
    );

    notifyListeners();

    if (_uploading && _buffer.length >= _flushAt) flush();
  }

  /// Send whatever has piled up.
  ///
  /// Safe to call at any time and from anywhere — on a timer, when the buffer
  /// fills, when the app goes to the background, when a share is stopped.
  Future<void> flush() async {
    if (_sending || _buffer.isEmpty) return;
    if (!Session.instance.isAuthenticated) return;

    _sending = true;

    // Taken, not copied-and-cleared afterwards: a failure puts them back at
    // the front, and meanwhile new fixes land in an empty buffer rather than
    // being sent twice.
    final batch = List<LocationFix>.from(_buffer);
    _buffer.clear();

    try {
      final response = await _api.ping(batch);

      if (response.success) {
        final next = response.dataMap['tracking'];

        if (next is Map<String, dynamic>) {
          await apply(TrackingPlan.fromJson(next));
        }
      }
    } catch (_) {
      /*
       | Back to the front of the queue, oldest first.
       |
       | A tunnel, a lift, a dead spot — all of these end, and the trail
       | should close up behind the person rather than showing a gap where
       | the network was. The cap in _onFix is what stops this growing
       | without bound.
       */
      _buffer.insertAll(0, batch);

      if (_buffer.length > _bufferCap) {
        _buffer.removeRange(0, _buffer.length - _bufferCap);
      }
    } finally {
      _sending = false;
    }
  }

  /*
  |----------------------------------------------------------------------------
  | One-shot
  |----------------------------------------------------------------------------
  */

  /// A single reading, for starting a share or dropping a pin.
  ///
  /// Falls back to the last known position when a fresh one does not arrive
  /// in time. That fallback is the difference between "share" working
  /// instantly indoors and appearing to hang: a cold GPS lock under a roof
  /// can take far longer than anybody will wait, and a position from ninety
  /// seconds ago is a perfectly good answer to "roughly where are you".
  Future<LocationFix?> currentFix({
    Duration timeout = const Duration(seconds: 8),
  }) async {
    _refreshBattery();

    Position? position;

    try {
      position = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: timeout,
        ),
      );
    } catch (_) {
      position = null;
    }

    position ??= await Geolocator.getLastKnownPosition();

    if (position == null) return null;

    /*
     | Prime the local dot from this one-shot.
     |
     | It used to be thrown away after moving the camera, which meant opening
     | the map put the camera in the right place and drew no marker there —
     | the single most confusing thing this screen did. A one-shot or even a
     | last-known fix is a perfectly good answer to "where am I" until the
     | stream produces a better one.
     */
    _adopt(position);

    return LocationFix(
      latitude: position.latitude,
      longitude: position.longitude,
      recordedAt: position.timestamp,
      accuracy: position.accuracy,
      speed: position.speed < 0 ? null : position.speed,
      heading: position.heading >= 0 ? position.heading : null,

      // A one-off fix has nothing to compare against, so the sensor is all
      // there is. It is only the opening fix of a share; the stream corrects
      // it within seconds.
      moving: position.speed > _movingSpeedMs,
      batteryLevel: _batteryLevel,
    );
  }
}
