import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../../core/theme/app_colors.dart';

/// How much access we actually have.
enum LocationAccess {
  /// The phone's location services are switched off system-wide. Nothing the
  /// app can ask for helps until this is fixed, so it is checked first.
  serviceDisabled,

  /// Asked and refused, but askable again.
  denied,

  /// Refused permanently, or blocked by policy. The only route left is
  /// Settings — and on Android a second `requestPermission()` in this state
  /// returns instantly without showing anything, which looks to the user
  /// like a dead button.
  deniedForever,

  /// Enough for the map, a chat share, and everything in phase one.
  whileInUse,

  /// Enough to keep reporting with the app closed.
  always,
}

extension LocationAccessX on LocationAccess {
  bool get canTrack =>
      this == LocationAccess.whileInUse || this == LocationAccess.always;

  bool get canTrackInBackground => this == LocationAccess.always;
}

/// The permission ladder.
///
/// Location is the one permission where the order of the asking matters as
/// much as the asking. Both platforms give you exactly one clean shot at the
/// system prompt; a refusal is close to permanent, and on Android the second
/// attempt does not even appear. So the rules here are:
///
///  1. Never ask cold. A prompt with no explanation in front of it is a
///     prompt people decline, and a declined location permission on a safety
///     app is the whole app.
///  2. Never ask for "Always" first. Both stores treat it as a red flag, iOS
///     will not offer it as a first choice anyway, and it is not needed until
///     background tracking is switched on.
///  3. Check that location services are on before asking for permission —
///     otherwise the app holds a granted permission and still cannot get a
///     fix, which is impossible to diagnose from the user's side.
class LocationPermissions {
  const LocationPermissions._();

  /// What we have right now, asking nobody.
  static Future<LocationAccess> check() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return LocationAccess.serviceDisabled;
    }

    return _map(await Geolocator.checkPermission());
  }

  static LocationAccess _map(LocationPermission permission) {
    switch (permission) {
      case LocationPermission.always:
        return LocationAccess.always;
      case LocationPermission.whileInUse:
        return LocationAccess.whileInUse;
      case LocationPermission.deniedForever:
        return LocationAccess.deniedForever;
      case LocationPermission.denied:
      case LocationPermission.unableToDetermine:
        return LocationAccess.denied;
    }
  }

  /// Get to "while in use", explaining first and helping afterwards.
  ///
  /// Returns what we ended up with. Callers should treat anything that is not
  /// [LocationAccessX.canTrack] as a refusal and carry on without location
  /// rather than nagging — a second prompt in the same session is how an app
  /// earns a permanent no.
  static Future<LocationAccess> ensure(BuildContext context) async {
    var access = await check();

    if (access.canTrack) return access;

    if (access == LocationAccess.serviceDisabled) {
      if (!context.mounted) return access;

      final go = await _ask(
        context,
        icon: Icons.location_disabled_rounded,
        title: 'Location is switched off',
        body: 'Your phone’s location services are off, so SFamily can’t see '
            'where you are. Turn them on and come back.',
        confirm: 'Open settings',
      );

      if (go == true) await Geolocator.openLocationSettings();

      /*
       | Re-checked rather than assumed.
       |
       | The user may have flipped the switch, or may have looked at the
       | screen and come straight back. There is no callback for either, so
       | the honest thing is to ask the system again.
       */
      access = await check();

      if (access.canTrack) return access;
      if (access == LocationAccess.serviceDisabled) return access;
    }

    if (access == LocationAccess.deniedForever) {
      if (!context.mounted) return access;

      final go = await _ask(
        context,
        icon: Icons.lock_outline_rounded,
        title: 'Location is blocked',
        body: 'SFamily was denied access to your location. You can turn it '
            'back on in your phone’s settings for this app.',
        confirm: 'Open settings',
      );

      if (go == true) await Geolocator.openAppSettings();

      return check();
    }

    // The rationale, before the system prompt rather than after it.
    if (!context.mounted) return access;

    final proceed = await _ask(
      context,
      icon: Icons.my_location_rounded,
      title: 'Share where you are',
      body: 'SFamily uses your location so the people you choose can see '
          'you on the map, and so you can send your position in a chat. '
          'You decide who sees it and for how long — and you can stop at '
          'any moment.',
      confirm: 'Continue',
    );

    if (proceed != true) return access;

    return _map(await Geolocator.requestPermission());
  }

  /// Ask to be upgraded from "while in use" to "always".
  ///
  /// Only ever called when the server has said a share needs background
  /// tracking, and only after [ensure] has already succeeded. Asking for this
  /// before the foreground permission exists gets a straight refusal on
  /// Android and is not even offered on iOS.
  ///
  /// A no here is not a failure. The share still works whenever the app is
  /// open, which the caller should say plainly rather than treating it as a
  /// broken feature.
  static Future<LocationAccess> ensureAlways(BuildContext context) async {
    final access = await check();

    if (access == LocationAccess.always) return access;

    if (!access.canTrack) return ensure(context);

    if (!context.mounted) return access;

    final proceed = await _ask(
      context,
      icon: Icons.shield_moon_outlined,
      title: 'Keep sharing in the background',
      body: 'To keep your family updated when SFamily isn’t open, your phone '
          'needs to allow location “all the time”. Without it, your family '
          'only sees you while the app is on screen.\n\n'
          'Your position is only ever sent while a share you started is '
          'running.',
      confirm: 'Allow always',
    );

    if (proceed != true) return access;

    /*
     | On Android this shows a second system prompt, and on 11 and up that
     | prompt is a trip to Settings rather than a dialog. On iOS it shows the
     | "Change to Always Allow?" sheet. Either way the platform decides what
     | appears; all we control is that we have earned the right to ask.
     */
    final upgraded = _map(await Geolocator.requestPermission());

    if (upgraded == LocationAccess.always) return upgraded;

    if (!context.mounted) return upgraded;

    // Android 11+ sends "Always" to Settings rather than granting it inline,
    // so a whileInUse result here is the expected outcome, not a refusal.
    final go = await _ask(
      context,
      icon: Icons.settings_outlined,
      title: 'One more step',
      body: 'Your phone wants you to choose “Allow all the time” in settings. '
          'Open Location for SFamily and pick it there.',
      confirm: 'Open settings',
    );

    if (go == true) await Geolocator.openAppSettings();

    return check();
  }

  /*
  |----------------------------------------------------------------------------
  | The sheet
  |----------------------------------------------------------------------------
  */

  static Future<bool?> _ask(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String body,
    required String confirm,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) => Container(
        decoration: const BoxDecoration(
          color: AppColors.canvasRaised,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          border: Border(
            top: BorderSide(color: AppColors.glassBorder),
          ),
        ),
        padding: EdgeInsets.fromLTRB(
          24,
          16,
          24,
          24 + MediaQuery.of(sheetContext).padding.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.lavenderGray.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                gradient: AppColors.brandGradient,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(icon, color: Colors.white, size: 28),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w700,
                height: 1.25,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              body,
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 14,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 52,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: AppColors.brandGradient,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: TextButton(
                  onPressed: () => Navigator.of(sheetContext).pop(true),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: Text(
                    confirm,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.of(sheetContext).pop(false),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.textMuted,
              ),
              child: const Text('Not now'),
            ),
          ],
        ),
      ),
    );
  }
}
