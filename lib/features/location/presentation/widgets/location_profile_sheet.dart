// FontFeature, for tabular figures on the coordinates — without them a
// latitude re-flows sideways every time a digit changes.
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/widgets/app_toast.dart';
import '../../../chat/state/chat_store.dart';
import '../../data/family_models.dart';
import '../../data/location_models.dart';
import 'map_style.dart';
import 'unread_pip.dart';

/// Everything known about one person's position, in one sheet.
///
/// Opened by tapping a marker or a card in the strip. The ordering is not
/// arbitrary — it runs from the answers people came for to the ones they only
/// want when something looks wrong:
///
///   1. Who, and are they reachable. Usually the whole question.
///   2. How far, and how long to get there. The next question, always.
///   3. Speed, heading, movement. What they are doing right now.
///   4. Coordinates, accuracy, battery. The forensic layer — irrelevant
///      ninety-nine times out of a hundred, and the only thing that matters
///      the other time.
///
/// Accuracy is shown as ±8 m rather than hidden because this is a safety app,
/// and a position without its error bar invites people to believe it to the
/// metre. On a phone indoors that is how you end up searching the wrong
/// building.
Future<void> showLocationProfileSheet(
  BuildContext context, {
  required FamilyMemberLive member,
  required MapPalette palette,
  LivePosition? viewerPosition,
  VoidCallback? onChat,
  VoidCallback? onFocus,
  VoidCallback? onHistory,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => LocationProfileSheet(
      member: member,
      palette: palette,
      viewerPosition: viewerPosition,
      onChat: onChat,
      onFocus: onFocus,
      onHistory: onHistory,
    ),
  );
}

class LocationProfileSheet extends StatelessWidget {
  const LocationProfileSheet({
    super.key,
    required this.member,
    required this.palette,
    this.viewerPosition,
    this.onChat,
    this.onFocus,
    this.onHistory,
  });

  final FamilyMemberLive member;
  final MapPalette palette;

  /// Where I am, for the distance and reach-out figures. Null when my own fix
  /// has not landed — in which case both are simply not shown, rather than
  /// shown as zero.
  final LivePosition? viewerPosition;

  final VoidCallback? onChat;
  final VoidCallback? onFocus;
  final VoidCallback? onHistory;

  double? get _metresAway {
    final mine = viewerPosition;
    final theirs = member.position;

    if (mine == null || !mine.hasFix) return null;
    if (theirs == null || !theirs.hasFix) return null;

    return Geo.metresBetween(
      mine.latitude!,
      mine.longitude!,
      theirs.latitude!,
      theirs.longitude!,
    );
  }

  @override
  Widget build(BuildContext context) {
    final position = member.position;
    final away = _metresAway;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.82,
      ),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: palette.textMuted.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              _Identity(member: member, palette: palette),
              const SizedBox(height: 18),

              if (away != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: _Headline(
                    palette: palette,
                    distance: Geo.distanceLabel(away),
                    reach: Geo.reachLabel(away),
                  ),
                ),

              Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 4),
                child: AnimatedBuilder(
                  animation: ChatStore.instance,
                  builder: (context, _) => _Actions(
                  palette: palette,
                  unread: ChatStore.instance.unreadWith(member.user.id),
                  onChat: onChat,
                  onDirections: position != null && position.hasFix
                      ? () => _openDirections(
                            context,
                            position.latitude!,
                            position.longitude!,
                            member.user.name,
                          )
                      : null,
                  ),
                ),
              ),

              if (position == null || !position.hasFix)
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 22, 18, 26),
                  child: _NoPosition(member: member, palette: palette),
                )
              else ...[
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: _Telemetry(
                    position: position,
                    member: member,
                    palette: palette,
                  ),
                ),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: _Coordinates(position: position, palette: palette),
                ),
                if (onFocus != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 6, 18, 0),
                    child: TextButton.icon(
                      onPressed: () {
                        Navigator.of(context).pop();
                        onFocus!();
                      },
                      icon: const Icon(Icons.center_focus_strong_rounded,
                          size: 18),
                      label: const Text('Centre the map on them'),
                      style: TextButton.styleFrom(
                        foregroundColor: palette.accent,
                        minimumSize: const Size(double.infinity, 44),
                      ),
                    ),
                  ),
                const SizedBox(height: 6),
              ],

              /*
               | Outside the has-position branch on purpose.
               |
               | Somebody with no fix right now — phone off, or not sharing
               | this minute — may still have a full day behind them, and
               | hiding the way to it exactly when the live view is empty
               | would remove the feature at the moment it is most wanted.
               */
              if (onHistory != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 4),
                  child: Material(
                    color: palette.textMuted.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(14),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () {
                        Navigator.of(context).pop();
                        onHistory!();
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 13,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.history_rounded,
                              size: 19,
                              color: palette.accent,
                            ),
                            const SizedBox(width: 11),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'Location history',
                                    style: TextStyle(
                                      color: palette.textPrimary,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 1),
                                  Text(
                                    'Where they went, day by day',
                                    style: TextStyle(
                                      color: palette.textMuted,
                                      fontSize: 11.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              Icons.chevron_right_rounded,
                              size: 19,
                              color: palette.textMuted,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

              const SizedBox(height: 18),
            ],
          ),
        ),
      ),
    );
  }

  /// Hand the coordinates to whatever maps app the phone actually uses.
  ///
  /// A `geo:` URI rather than a Google Maps URL, with a label attached so the
  /// destination arrives named rather than as a pair of numbers. Falls back to
  /// a maps.google.com link, which every platform resolves — including an
  /// Android without Google Maps installed, where the `geo:` scheme has no
  /// handler at all.
  static Future<void> _openDirections(
    BuildContext context,
    double lat,
    double lng,
    String label,
  ) async {
    final encoded = Uri.encodeComponent(label);

    final candidates = [
      Uri.parse('geo:$lat,$lng?q=$lat,$lng($encoded)'),
      Uri.parse('https://maps.google.com/?q=$lat,$lng'),
    ];

    for (final uri in candidates) {
      try {
        if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
      } catch (_) {
        // Try the next one. A platform without a handler throws rather than
        // returning false, so both outcomes have to be caught.
      }
    }

    if (context.mounted) {
      AppToast.error(context, 'No maps app could open that location.');
    }
  }
}

/*
|------------------------------------------------------------------------------
| Header
|------------------------------------------------------------------------------
*/

class _Identity extends StatelessWidget {
  const _Identity({required this.member, required this.palette});

  final FamilyMemberLive member;
  final MapPalette palette;

  @override
  Widget build(BuildContext context) {
    final user = member.user;
    final online = member.presence.isOnline;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Row(
        children: [
          Stack(
            children: [
              CircleAvatar(
                radius: 29,
                backgroundColor: palette.accent.withValues(alpha: 0.18),
                backgroundImage: user.avatarUrl == null
                    ? null
                    : NetworkImage(user.avatarUrl!),
                child: user.avatarUrl != null
                    ? null
                    : Text(
                        user.initials,
                        style: TextStyle(
                          color: palette.accent,
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),

              // The dot sits on the avatar rather than beside the name
              // because that is where every messaging app has trained people
              // to look for it.
              if (!member.presence.isHidden)
                Positioned(
                  right: 1,
                  bottom: 1,
                  child: Container(
                    width: 15,
                    height: 15,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: online
                          ? const Color(0xFF16A34A)
                          : const Color(0xFF94A3B8),
                      border: Border.all(color: palette.surface, width: 2.5),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  user.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (user.username != null && user.username!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    '@${user.username}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: palette.textMuted,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                const SizedBox(height: 5),
                Row(
                  children: [
                    _Chip(
                      label: member.presence.label,
                      tint: online
                          ? const Color(0xFF16A34A)
                          : palette.textMuted,
                      palette: palette,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: _Chip(
                        label: member.statusLabel,
                        tint: palette.accent,
                        palette: palette,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.tint,
    required this.palette,
  });

  final String label;
  final Color tint;
  final MapPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: tint,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Distance and reach-out time, given the space they deserve.
class _Headline extends StatelessWidget {
  const _Headline({
    required this.palette,
    required this.distance,
    required this.reach,
  });

  final MapPalette palette;
  final String distance;
  final String reach;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 13),
      decoration: BoxDecoration(
        color: palette.accent.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        children: [
          Expanded(
            child: _Half(
              palette: palette,
              icon: Icons.straighten_rounded,
              value: distance,
              label: 'Away from you',
            ),
          ),
          Container(
            width: 1,
            height: 34,
            color: palette.textMuted.withValues(alpha: 0.22),
          ),
          Expanded(
            child: _Half(
              palette: palette,
              icon: Icons.schedule_rounded,
              value: reach,
              label: 'To reach them',
            ),
          ),
        ],
      ),
    );
  }
}

class _Half extends StatelessWidget {
  const _Half({
    required this.palette,
    required this.icon,
    required this.value,
    required this.label,
  });

  final MapPalette palette;
  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 15, color: palette.accent),
            const SizedBox(width: 6),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  value,
                  maxLines: 1,
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            color: palette.textMuted,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/*
|------------------------------------------------------------------------------
| Actions
|------------------------------------------------------------------------------
*/

class _Actions extends StatelessWidget {
  const _Actions({
    required this.palette,
    this.unread = 0,
    this.onChat,
    this.onDirections,
  });

  final MapPalette palette;
  final int unread;
  final VoidCallback? onChat;
  final VoidCallback? onDirections;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _Action(
            palette: palette,
            icon: Icons.chat_bubble_rounded,
            label: 'Chat',
            badge: unread,
            onTap: onChat,
          ),
        ),
        const SizedBox(width: 10),

        /*
         | Voice and video are drawn, and they do not work.
         |
         | That is a deliberate choice over leaving them out. Calling is a
         | real planned feature, and the row it lands in should not
         | re-shuffle itself the week it arrives — people build muscle memory
         | for button positions faster than anyone expects. Disabled and
         | honest beats absent and then rearranged.
         |
         | What is not acceptable is a button that looks live and does
         | nothing, so these are visibly greyed and say so when tapped.
         */
        Expanded(
          child: _Action(
            palette: palette,
            icon: Icons.call_rounded,
            label: 'Voice',
            onTap: () => _soon(context, 'Voice calling'),
            disabled: true,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _Action(
            palette: palette,
            icon: Icons.videocam_rounded,
            label: 'Video',
            onTap: () => _soon(context, 'Video calling'),
            disabled: true,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _Action(
            palette: palette,
            icon: Icons.directions_rounded,
            label: 'Directions',
            onTap: onDirections,
          ),
        ),
      ],
    );
  }

  static void _soon(BuildContext context, String what) {
    AppToast.show(context, '$what is coming soon.');
  }
}

class _Action extends StatelessWidget {
  const _Action({
    required this.palette,
    required this.icon,
    required this.label,
    this.onTap,
    this.disabled = false,
    this.badge = 0,
  });

  final MapPalette palette;
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool disabled;
  final int badge;

  @override
  Widget build(BuildContext context) {
    final dim = disabled || onTap == null;

    final tint = dim
        ? palette.textMuted.withValues(alpha: 0.55)
        : palette.accent;

    return Material(
      color: dim
          ? palette.textMuted.withValues(alpha: 0.07)
          : palette.accent.withValues(alpha: 0.11),
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 11),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // The badge rides on the icon, unclipped, so it reads as
              // belonging to Chat rather than as a fourth element in a row
              // of four.
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(icon, size: 19, color: tint),
                  if (badge > 0)
                    Positioned(
                      right: -8,
                      top: -7,
                      child: UnreadPip(count: badge, size: 15, onTap: onTap),
                    ),
                ],
              ),
              const SizedBox(height: 5),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  style: TextStyle(
                    color: tint,
                    fontSize: 11,
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

/*
|------------------------------------------------------------------------------
| The numbers
|------------------------------------------------------------------------------
*/

class _Telemetry extends StatelessWidget {
  const _Telemetry({
    required this.position,
    required this.member,
    required this.palette,
  });

  final LivePosition position;
  final FamilyMemberLive member;
  final MapPalette palette;

  @override
  Widget build(BuildContext context) {
    final speed = position.speedKmh;
    final heading = position.heading;
    final battery = position.batteryLevel;

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _Cell(
                palette: palette,
                icon: Icons.speed_rounded,
                label: 'Speed',
                value: speed == null ? '—' : '${speed.round()} km/h',
              ),
            ),
            Expanded(
              child: _Cell(
                palette: palette,
                icon: Icons.explore_rounded,
                label: 'Heading',
                // Degrees *and* the compass point. The number is what was
                // asked for; the letters are what anybody can actually read
                // at a glance without picturing a protractor.
                value: heading == null
                    ? '—'
                    : '${heading.round()}° ${Geo.compass(heading)}',
              ),
            ),
          ],
        ),
        Row(
          children: [
            Expanded(
              child: _Cell(
                palette: palette,
                icon: Icons.my_location_rounded,
                label: 'Accuracy',
                value: position.accuracy == null
                    ? '—'
                    : '± ${position.accuracy!.round()} m',
              ),
            ),
            Expanded(
              child: _Cell(
                palette: palette,
                icon: _batteryIcon(battery),
                label: 'Battery',
                value: battery == null ? '—' : '$battery%',
                tint: _batteryTint(battery),
              ),
            ),
          ],
        ),
        Row(
          children: [
            Expanded(
              child: _Cell(
                palette: palette,
                icon: position.moving
                    ? Icons.directions_walk_rounded
                    : Icons.pause_circle_outline_rounded,
                label: 'Movement',
                value: member.statusLabel,
              ),
            ),
            Expanded(
              child: _Cell(
                palette: palette,
                icon: Icons.update_rounded,
                label: 'Updated',
                value: position.ageLabel,
                tint: position.isStale ? const Color(0xFFD08700) : null,
              ),
            ),
          ],
        ),
      ],
    );
  }

  static IconData _batteryIcon(int? level) {
    if (level == null) return Icons.battery_unknown_rounded;
    if (level <= 15) return Icons.battery_alert_rounded;
    if (level <= 50) return Icons.battery_4_bar_rounded;

    return Icons.battery_full_rounded;
  }

  /// Only a low battery gets a colour.
  ///
  /// Colouring every level turns the sheet into a traffic light and teaches
  /// people to ignore it. A phone about to die is the one battery fact that
  /// changes what somebody does next, so it is the only one that shouts.
  static Color? _batteryTint(int? level) {
    if (level == null) return null;
    if (level <= 15) return const Color(0xFFE5484D);
    if (level <= 30) return const Color(0xFFD08700);

    return null;
  }
}

class _Cell extends StatelessWidget {
  const _Cell({
    required this.palette,
    required this.icon,
    required this.label,
    required this.value,
    this.tint,
  });

  final MapPalette palette;
  final IconData icon;
  final String label;
  final String value;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          Icon(icon, size: 17, color: tint ?? palette.textMuted),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: palette.textMuted,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 1),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    maxLines: 1,
                    style: TextStyle(
                      color: tint ?? palette.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Latitude and longitude, copyable.
///
/// Six decimal places, which is about 11 cm — past the point where more
/// digits mean anything given the accuracy figure sitting above them. The
/// copy button is the reason this row exists at all: the moment somebody
/// needs these numbers, they need them in another app.
class _Coordinates extends StatelessWidget {
  const _Coordinates({required this.position, required this.palette});

  final LivePosition position;
  final MapPalette palette;

  @override
  Widget build(BuildContext context) {
    final text =
        '${position.latitude!.toStringAsFixed(6)}, ${position.longitude!.toStringAsFixed(6)}';

    return Container(
      padding: const EdgeInsets.fromLTRB(13, 11, 6, 11),
      decoration: BoxDecoration(
        color: palette.textMuted.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        children: [
          Icon(Icons.pin_drop_rounded, size: 17, color: palette.textMuted),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Latitude, longitude',
                  style: TextStyle(
                    color: palette.textMuted,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 1),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    text,
                    maxLines: 1,
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: text));

              if (context.mounted) {
                AppToast.success(context, 'Coordinates copied.');
              }
            },
            icon: Icon(Icons.copy_rounded, size: 17, color: palette.accent),
            tooltip: 'Copy',
          ),
        ],
      ),
    );
  }
}

/// What the sheet says when there is nothing to say.
class _NoPosition extends StatelessWidget {
  const _NoPosition({required this.member, required this.palette});

  final FamilyMemberLive member;
  final MapPalette palette;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(
          Icons.location_off_rounded,
          size: 30,
          color: palette.textMuted.withValues(alpha: 0.6),
        ),
        const SizedBox(height: 10),
        Text(
          member.sharing
              ? 'Waiting for their first fix'
              : '${member.user.name.split(' ').first} is not sharing location',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: palette.textPrimary,
            fontSize: 14.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          member.sharing
              ? 'Their phone has not reported a position yet. It usually takes a few seconds outdoors, longer inside.'
              : 'You will see them on the map as soon as they share it with the family.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: palette.textMuted,
            fontSize: 12.5,
            height: 1.45,
          ),
        ),
      ],
    );
  }
}
