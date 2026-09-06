import 'dart:async';
import 'dart:io';

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
    final previous = _plan;
    _plan = next;

    if (!next.active) {
      await stop();

      return;
    }

    if (running && previous.sameShapeAs(next)) return;

    await _restart();
  }

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

    final settings = _settings();

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

  /// Stop everything and tell nobody. Ending a share is what tells people.
  Future<void> stop() async {
    await _cancel();

    _flusher?.cancel();
    _flusher = null;

    _plan = const TrackingPlan.idle();

    // Anything already measured is still worth sending — the last fix before
    // somebody taps "stop sharing" is the most interesting one in the buffer.
    await flush();

    notifyListeners();
  }

  /*
  |----------------------------------------------------------------------------
  | Platform settings
  |----------------------------------------------------------------------------
  */

  /// The two platforms are configured differently enough that a shared
  /// LocationSettings would be a lowest common denominator on both.
  LocationSettings _settings() {
    final distance = _plan.distance;
    final interval = _plan.interval;

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

        foregroundNotificationConfig: _plan.background
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

        allowBackgroundLocationUpdates: _plan.background,

        /*
         | The blue "using your location" bar, when running in the background.
         |
         | Required by App Review for background location, and right anyway:
         | a person should never have to open an app to find out it is
         | tracking them.
         */
        showBackgroundLocationIndicator: _plan.background,
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

  void _onFix(Position position) {
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
       | "Moving" is decided here, from speed, rather than taken from an
       | activity recogniser. One dependency fewer, and the only thing the
       | server does with it is choose a sampling rate — so being wrong for a
       | few seconds at the start of a journey costs one extra fix.
       */
      moving: position.speed > 1.0,
    );

    _buffer.add(fix);

    if (_buffer.length > _bufferCap) {
      _buffer.removeRange(0, _buffer.length - _bufferCap);
    }

    // The local dot moves now, not when the network agrees.
    _mine = LivePosition(
      userId: Session.instance.user?.id ?? '',
      hasFix: true,
      latitude: fix.latitude,
      longitude: fix.longitude,
      accuracy: fix.accuracy,
      speed: fix.speed,
      heading: fix.heading,
      moving: fix.moving,
      recordedAt: fix.recordedAt,
      ageSeconds: 0,
    );

    notifyListeners();

    if (_buffer.length >= _flushAt) flush();
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

    return LocationFix(
      latitude: position.latitude,
      longitude: position.longitude,
      recordedAt: position.timestamp,
      accuracy: position.accuracy,
      speed: position.speed < 0 ? null : position.speed,
      heading: position.heading >= 0 ? position.heading : null,
      moving: position.speed > 1.0,
    );
  }
}
