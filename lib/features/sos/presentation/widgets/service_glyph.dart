import 'package:flutter/material.dart';

import '../../../../core/widgets/pulse_rings.dart';

/// The logo for one kind of emergency.
///
/// A coloured badge with rings breathing outwards behind it. The motion is
/// not decoration: on a screen somebody has reached in a hurry, a moving
/// element is the fastest way to say "this is the live thing, look here"
/// without making them read a word.
///
/// Stateless, because the animation itself lives in [PulseRings] — the same
/// widget behind the SOS button in the nav bar and the hold-to-activate
/// button. One implementation, so the app's three pulsing things cannot
/// drift apart into three slightly different rhythms.
class ServiceGlyph extends StatelessWidget {
  const ServiceGlyph({
    super.key,
    required this.icon,
    required this.tint,
    this.size = 96,
    this.animate = true,
  });

  /// The server's name for the icon: picks the artwork, and the Material
  /// icon to fall back to if there is none.
  final String icon;

  /// Still used even when the artwork loads — it tints the rings, so the
  /// pulse matches the badge it surrounds.
  final Color tint;

  final double size;

  /// Off in the list, where fourteen breathing rows would be a fairground.
  /// On in the detail screen, where there is exactly one.
  final bool animate;

  @override
  Widget build(BuildContext context) {
    /*
     | The badge is bigger when nothing is pulsing around it.
     |
     | The gap between the badge and the edge of [size] exists to give the
     | rings somewhere to travel. With `animate: false` there are no rings,
     | so that gap is just a smaller badge in a row that has no room to
     | spare — 40px of artwork instead of 24px, from the same call site.
     */
    final badge = size * (animate ? 0.52 : 0.86);

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (animate)
            Positioned.fill(
              child: PulseRings(
                color: tint,
                innerRadius: badge / 2,
                outerRadius: size / 2,
              ),
            ),
          _ServiceArt(icon: icon, tint: tint, size: badge),
        ],
      ),
    );
  }
}

/// The badge itself, with the pre-artwork design as its fallback.
///
/// The fallback is not defensive padding. These come from the server: a
/// service added to the catalogue before its artwork ships would otherwise
/// leave a hole in the list, and a hole is a worse failure than a plainer
/// icon. This degrades to exactly what the screen looked like before the
/// badges existed.
class _ServiceArt extends StatelessWidget {
  const _ServiceArt({
    required this.icon,
    required this.tint,
    required this.size,
  });

  final String icon;
  final Color tint;
  final double size;

  @override
  Widget build(BuildContext context) {
    // Decode at what is drawn, not at the source resolution.
    //
    // Flutter caches the *decoded* bitmap. Fourteen 192px badges left
    // uncapped hold 192x192x4 bytes each — about 2 MB of RGBA for a list
    // that never draws one above 40dp.
    final ratio = MediaQuery.maybeDevicePixelRatioOf(context) ?? 3.0;
    final decode = (size * ratio).round();

    return Image.asset(
      'assets/icons/services/$icon.png',
      width: size,
      height: size,
      cacheWidth: decode,
      cacheHeight: decode,
      filterQuality: FilterQuality.medium,
      errorBuilder: (_, __, ___) =>
          _FallbackDisc(icon: icon, tint: tint, size: size),
    );
  }
}

/// What every service looked like before the artwork arrived.
class _FallbackDisc extends StatelessWidget {
  const _FallbackDisc({
    required this.icon,
    required this.tint,
    required this.size,
  });

  final String icon;
  final Color tint;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            tint.withValues(alpha: 0.34),
            tint.withValues(alpha: 0.16),
          ],
        ),
        border: Border.all(color: tint.withValues(alpha: 0.65), width: 1.4),
      ),
      child: Icon(ServiceIcons.of(icon), size: size * 0.48, color: tint),
    );
  }
}

/// The server's icon names, mapped to Flutter's.
///
/// The wire carries a string like "police" and this decides what it looks
/// like. Doing it the other way — a server that names IconData constants —
/// would mean a Flutter rename breaking every deployed app, including the
/// ones on phones nobody can update.
///
/// An unknown name falls back rather than throwing. A service added on the
/// server before the app knows its icon should appear with a generic glyph,
/// not crash the screen somebody opened in an emergency.
class ServiceIcons {
  const ServiceIcons._();

  static const Map<String, IconData> _map = {
    'police': Icons.local_police_rounded,
    'ambulance': Icons.local_hospital_rounded,
    'fire': Icons.local_fire_department_rounded,
    'women': Icons.woman_rounded,
    'child': Icons.child_care_rounded,
    'cyber': Icons.security_rounded,
    'disaster': Icons.storm_rounded,
    'road': Icons.directions_car_filled_rounded,
    'railway': Icons.train_rounded,
    'mental_health': Icons.psychology_rounded,
    'senior': Icons.elderly_rounded,
    'gas': Icons.local_gas_station_rounded,
    'forest': Icons.forest_rounded,
    'narcotics': Icons.medication_rounded,
  };

  static IconData of(String name) => _map[name] ?? Icons.help_outline_rounded;
}
