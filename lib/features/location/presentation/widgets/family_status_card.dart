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
    this.onToggle,
    this.collapsed = false,
  });

  final FamilyStatus status;
  final MapPalette palette;

  /// Fold the card away, or bring it back.
  ///
  /// This replaced a "View All" link, which was the wrong control in the
  /// wrong place. The card is a third of a phone screen and the screen it
  /// sits on is a map — so the thing a person wants from that corner is not
  /// another destination, it is *their map back*.
  final VoidCallback? onToggle;

  /// Shown as a single line.
  ///
  /// Two things collapse it: a deliberate tap on the chevron, which sticks,
  /// and panning the map, which does not. Both funnel through this one flag
  /// so the card never has to reason about why it is small.
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
        child: collapsed ? _collapsedBar() : _full(),
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
              _Chevron(palette: palette, collapsed: false, onTap: onToggle),
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

  /// The one-line form: the verdict, and the way back.
  ///
  /// The whole bar is tappable, not just the chevron. A 44dp target in the
  /// corner is the minimum anybody should have to hit; a person reaching for
  /// a card they just folded away will aim at the card.
  Widget _collapsedBar() {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onToggle,
        child: Row(
          children: [
            Expanded(child: _summaryLine()),
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: _Chevron(
                palette: palette,
                collapsed: true,
                onTap: onToggle,
              ),
            ),
          ],
        ),
      ),
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

/// The open/close control.
///
/// Rotates rather than swapping glyph, so the two states read as one control
/// turning over instead of two different buttons appearing in the same spot.
class _Chevron extends StatelessWidget {
  const _Chevron({
    required this.palette,
    required this.collapsed,
    required this.onTap,
  });

  final MapPalette palette;
  final bool collapsed;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    if (onTap == null) return const SizedBox.shrink();

    return Semantics(
      button: true,
      label: collapsed ? 'Show family status' : 'Hide family status',
      child: Material(
        color: palette.textMuted.withValues(alpha: 0.08),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: 32,
            height: 32,
            child: AnimatedRotation(
              // Half a turn, matched to the card's own resize so the arrow
              // and the panel move as one thing.
              turns: collapsed ? 0.5 : 0,
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              child: Icon(
                Icons.keyboard_arrow_up_rounded,
                size: 20,
                color: palette.textMuted,
              ),
            ),
          ),
        ),
      ),
    );
  }
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
