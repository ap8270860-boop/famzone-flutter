import 'package:flutter/material.dart';

import '../../../../core/widgets/pulse_rings.dart';

/// The animated logo for one kind of emergency.
///
/// Rings breathing outwards behind a tinted disc. The motion is not
/// decoration: on a screen somebody has reached in a hurry, a moving element
/// is the fastest way to say "this is the live thing, look here" without
/// making them read a word.
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

  /// The server's name for the icon, mapped by [ServiceIcons].
  final String icon;

  final Color tint;
  final double size;

  /// Off in the grid, where fourteen breathing tiles would be a fairground.
  /// On in the detail screen, where there is exactly one.
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final disc = size * 0.52;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: PulseRings(
              color: tint,
              innerRadius: disc / 2,
              outerRadius: size / 2,
              running: animate,
            ),
          ),
          Container(
            width: disc,
            height: disc,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  tint.withValues(alpha: 0.34),
                  tint.withValues(alpha: 0.16),
                ],
              ),
              border: Border.all(
                color: tint.withValues(alpha: 0.65),
                width: 1.4,
              ),
            ),
            child: Icon(
              ServiceIcons.of(icon),
              size: disc * 0.48,
              color: tint,
            ),
          ),
        ],
      ),
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
