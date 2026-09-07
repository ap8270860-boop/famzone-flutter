import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/gradient_border_card.dart';

/// The four shortcuts under the status card.
class QuickActions extends StatelessWidget {
  const QuickActions({super.key, this.onTap});

  final void Function(String key)? onTap;

  /// key, artwork, label, and the icon to fall back to.
  ///
  /// The fallback is not defensive padding — an asset that fails to load
  /// throws a grey box with a stack trace in debug and an empty gap in
  /// release, and a gap where "Smart SOS" should be is a worse failure than
  /// a slightly plainer icon. A renamed or missing file degrades to what
  /// this screen looked like before the artwork existed.
  static const _items = <(String, String, String, IconData)>[
    ('sos', 'assets/icons/sos.png', 'Smart SOS', Icons.sos_rounded),
    (
      'location',
      'assets/icons/live-location.png',
      'Live Location',
      Icons.location_on_rounded,
    ),
    (
      'audio',
      'assets/icons/audio-detect.png',
      'Audio Detect',
      Icons.hearing_rounded,
    ),
    (
      'circle',
      'assets/icons/family-circle.png',
      'Family Circle',
      Icons.groups_rounded,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final (key, asset, label, fallback) in _items) ...[
          Expanded(
            child: _ActionTile(
              asset: asset,
              label: label,
              fallback: fallback,
              onTap: () => onTap?.call(key),
            ),
          ),
          if (key != _items.last.$1) const SizedBox(width: 10),
        ],
      ],
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.asset,
    required this.label,
    required this.fallback,
    required this.onTap,
  });

  final String asset;
  final String label;
  final IconData fallback;
  final VoidCallback onTap;

  /// Drawn size of the artwork's *frame*, not of the artwork.
  ///
  /// Each PNG centres its art in a square canvas with the art occupying
  /// roughly 70–79% of it — deliberately not the same fraction for each one,
  /// because they are normalised by ink mass rather than by bounding box.
  /// So 42 here draws about 32dp of visible glyph, which is why this number
  /// looks larger than an icon size usually would.
  static const double _size = 42;

  @override
  Widget build(BuildContext context) {
    // Decode at roughly what is drawn, not at the source resolution.
    //
    // Flutter caches the *decoded* bitmap, so a 256px PNG shown at 32dp
    // otherwise holds 256×256×4 bytes of RGBA per icon for the life of the
    // screen. Capping the decode at 3x the drawn size covers the densest
    // phone and costs a sixteenth of the memory.
    final ratio = MediaQuery.maybeDevicePixelRatioOf(context) ?? 3.0;
    final decode = (_size * ratio).round();

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 15),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: Colors.white.withValues(alpha: 0.055),
          border: Border.all(color: AppColors.glassBorder),
        ),
        child: Column(
          children: [
            SizedBox(
              height: _size,
              width: _size,
              child: Image.asset(
                asset,
                cacheWidth: decode,
                cacheHeight: decode,
                filterQuality: FilterQuality.medium,
                // The artwork keeps its own colour. It is already in the
                // app's green family, and tinting line art of this weight
                // flattens the internal detail that makes each one
                // recognisable at this size.
                errorBuilder: (_, __, ___) => GradientIcon(fallback, size: 26),
              ),
            ),
            const SizedBox(height: 10),
            // Labels vary in length; scale rather than wrap or clip.
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
