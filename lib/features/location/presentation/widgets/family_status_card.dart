import 'package:flutter/material.dart';

import '../../data/family_models.dart';
import 'map_style.dart';

/// The card across the top of the map.
///
/// It answers the question people actually open this screen for, which is not
/// "where is everybody" — it is "is everybody alright". Those look similar and
/// are not: the first needs a map, the second needs one sentence, and putting
/// the sentence above the map means most visits end without anybody having to
/// read a single pin.
///
/// Every number here is counted on the server. That is deliberate and it is
/// the reason the card can grow: when family places land, "Stationary"
/// becomes "At Home" and "At School" without this file changing at all.
class FamilyStatusCard extends StatelessWidget {
  const FamilyStatusCard({
    super.key,
    required this.status,
    required this.palette,
    this.onViewAll,
    this.collapsed = false,
  });

  final FamilyStatus status;
  final MapPalette palette;
  final VoidCallback? onViewAll;

  /// Shown as a single line while somebody is looking at the map.
  ///
  /// The full card is 150-odd pixels of a phone screen, and the moment a
  /// person starts panning, the map is what they want that space for. It
  /// expands again when they let go.
  final bool collapsed;

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: Container(
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: palette.border),
          boxShadow: [
            BoxShadow(
              color: palette.shadow,
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: collapsed ? _summaryLine() : _full(),
      ),
    );
  }

  Widget _full() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 13, 12, 0),
          child: Row(
            children: [
              Icon(Icons.shield_rounded, size: 17, color: palette.accent),
              const SizedBox(width: 7),
              Text(
                'Family Status',
                style: TextStyle(
                  color: palette.textPrimary,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              if (onViewAll != null)
                TextButton(
                  onPressed: onViewAll,
                  style: TextButton.styleFrom(
                    foregroundColor: palette.accent,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'View All',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Icon(Icons.chevron_right_rounded, size: 17),
                    ],
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 12),
          child: Row(
            children: [
              for (final bucket in status.buckets)
                Expanded(child: _Stat(bucket: bucket, palette: palette)),
            ],
          ),
        ),
        Divider(height: 1, thickness: 1, color: palette.border),
        _summaryLine(),
      ],
    );
  }

  Widget _summaryLine() {
    final tone = _toneColour(status.tone);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 11),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(_toneIcon(status.tone), size: 15, color: tone),
          const SizedBox(width: 7),
          Flexible(
            child: RichText(
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              text: TextSpan(
                children: [
                  TextSpan(
                    text: status.headline,
                    style: TextStyle(
                      color: tone,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const TextSpan(text: '  '),
                  TextSpan(
                    text: status.detail,
                    style: TextStyle(
                      color: palette.textMuted,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _toneColour(String tone) => switch (tone) {
        'alert' => const Color(0xFFE5484D),
        'caution' => const Color(0xFFD08700),
        'empty' => palette.textMuted,
        _ => palette.accent,
      };

  IconData _toneIcon(String tone) => switch (tone) {
        'alert' => Icons.error_rounded,
        'caution' => Icons.schedule_rounded,
        'empty' => Icons.group_add_rounded,
        _ => Icons.check_circle_rounded,
      };
}

/// One count, with its glyph.
///
/// Stacked, not side by side. The first version put the icon to the left of
/// the number the way the reference mockup does, and on a 360dp phone that
/// leaves each of four buckets 37dp for text that wants 65 — so "Not
/// reachable" arrived scaled to about six points. The mockup was drawn wide;
/// phones are not.
///
/// Vertical gives every bucket the full 82dp of its slot, which fits
/// "Travelling" at a readable weight with room to spare, and it reads as a
/// row of four equal things rather than four cramped ones.
class _Stat extends StatelessWidget {
  const _Stat({required this.bucket, required this.palette});

  final StatusBucket bucket;
  final MapPalette palette;

  @override
  Widget build(BuildContext context) {
    final tint = _tint(bucket.key);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: tint.withValues(alpha: 0.13),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(_glyph(bucket.icon), size: 16, color: tint),
        ),
        const SizedBox(height: 5),
        Text(
          '${bucket.count}',
          maxLines: 1,
          style: TextStyle(
            color: palette.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w800,
            height: 1.05,
          ),
        ),
        const SizedBox(height: 1),
        // Still worth a FittedBox: the server owns this string, and a place
        // name added in a later phase ("Badminton") is longer than anything
        // in the current vocabulary.
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            bucket.label,
            maxLines: 1,
            style: TextStyle(
              color: palette.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              height: 1.2,
            ),
          ),
        ),
      ],
    );
  }

  /// Bucket keys to colours.
  ///
  /// Keyed on the server's string rather than on position, so a bucket that
  /// moves in the row keeps its colour — people remember "the orange one is
  /// travelling" long before they remember which slot it was in.
  static Color _tint(String key) => switch (key) {
        'members' => const Color(0xFF12A66B),
        'travelling' => const Color(0xFFF08C2E),
        'offline' => const Color(0xFF8A97B1),
        'home' => const Color(0xFF2F7BF0),
        'school' => const Color(0xFF8B5CF6),
        'office' => const Color(0xFF0EA5A5),
        'alert' => const Color(0xFFE5484D),
        _ => const Color(0xFF2F7BF0),
      };

  /// Icon names to glyphs.
  ///
  /// An unknown name gets a neutral pin rather than nothing. The server is
  /// allowed to invent bucket types after this build has shipped, and a
  /// missing glyph must not be a hole in the card.
  static IconData _glyph(String? icon) => switch (icon) {
        'group' => Icons.groups_rounded,
        'home' => Icons.home_rounded,
        'car' => Icons.directions_car_filled_rounded,
        'school' => Icons.school_rounded,
        'office' => Icons.business_rounded,
        'offline' => Icons.cloud_off_rounded,
        'hospital' => Icons.local_hospital_rounded,
        'alert' => Icons.error_rounded,
        _ => Icons.place_rounded,
      };
}
