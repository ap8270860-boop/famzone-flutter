import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../location/presentation/live_map_screen.dart';
import '../../../location/presentation/widgets/map_style.dart';
import '../../data/sos_models.dart';
import '../../state/sos_store.dart';

/// Somebody in your family has raised an alarm.
///
/// Mounted once, above everything, in AppShell — so it reaches you on
/// whatever tab you happen to be looking at rather than only on a screen you
/// might never open. It is not a route push for the same reason: an alarm
/// that can be dismissed with the back gesture, or buried under whatever
/// screen you navigate to next, is not an alarm.
///
/// A banner rather than a full-screen takeover, deliberately. Hijacking the
/// whole screen is the obvious design and the wrong one — the first thing
/// most people do on seeing this is try to phone the person, and an interface
/// that has seized control makes that harder. The banner is impossible to
/// miss, sits above everything, and leaves the app usable underneath.
class IncomingSosBanner extends StatelessWidget {
  const IncomingSosBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final store = SosStore.instance;

    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final alert = store.incoming;

        if (alert == null) return const SizedBox.shrink();

        final person = store.incomingPerson ?? const {};

        return SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
            child: _Card(
              alert: alert,
              name: person['name'] as String? ?? 'A family member',
              avatarUrl: person['avatar_url'] as String?,
              userId: person['id'] as String?,
              onDismiss: store.dismissIncoming,
            ),
          ),
        );
      },
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({
    required this.alert,
    required this.name,
    required this.avatarUrl,
    required this.userId,
    required this.onDismiss,
  });

  final SosAlert alert;
  final String name;
  final String? avatarUrl;
  final String? userId;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => _openDetail(context),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 13, 10, 13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: const LinearGradient(
              colors: [Color(0xFF5A1224), Color(0xFF3B1030)],
            ),
            border: Border.all(color: AppColors.alertRed, width: 1.4),
            boxShadow: [
              BoxShadow(
                color: AppColors.alertRed.withValues(alpha: 0.35),
                blurRadius: 22,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: AppColors.alertRed.withValues(alpha: 0.28),
                backgroundImage:
                    avatarUrl == null ? null : NetworkImage(avatarUrl!),
                child: avatarUrl != null
                    ? null
                    : const Icon(
                        Icons.sos_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$name needs help',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      alert.hasLocation
                          ? 'Tap to see where they are'
                          : 'SOS raised — no location yet',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.78),
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onDismiss,
                icon: const Icon(Icons.close_rounded),
                color: Colors.white.withValues(alpha: 0.7),
                iconSize: 20,
                tooltip: 'Hide',
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openDetail(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _IncomingSheet(
        alert: alert,
        name: name,
        avatarUrl: avatarUrl,
        userId: userId,
      ),
    );
  }
}

/// Where they are, and how to reach them.
class _IncomingSheet extends StatelessWidget {
  const _IncomingSheet({
    required this.alert,
    required this.name,
    required this.avatarUrl,
    required this.userId,
  });

  final SosAlert alert;
  final String name;
  final String? avatarUrl;
  final String? userId;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.fromLTRB(
        12, 0, 12, 12 + MediaQuery.viewPaddingOf(context).bottom,
      ),
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: AppColors.canvasRaised,
        border: Border.all(color: AppColors.alertRed.withValues(alpha: 0.55)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 38,
              height: 4,
              margin: const EdgeInsets.only(bottom: 18),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                color: Colors.white.withValues(alpha: 0.16),
              ),
            ),
          ),
          Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: AppColors.royalNavy,
                backgroundImage:
                    avatarUrl == null ? null : NetworkImage(avatarUrl!),
                child: avatarUrl != null
                    ? null
                    : const Icon(Icons.person_rounded, color: Colors.white),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'SOS active · ${alert.elapsedLabel}',
                      style: const TextStyle(
                        color: AppColors.alertRed,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          if (alert.hasLocation) ...[
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: SizedBox(
                height: 170,
                child: GoogleMap(
                  initialCameraPosition: CameraPosition(
                    target: LatLng(alert.latitude!, alert.longitude!),
                    zoom: 15.5,
                  ),
                  style: MapStyle.emergency,

                  // A still picture of where they were when they pressed it.
                  // The live view is one tap away and is a different question.
                  zoomControlsEnabled: false,
                  scrollGesturesEnabled: false,
                  zoomGesturesEnabled: false,
                  rotateGesturesEnabled: false,
                  tiltGesturesEnabled: false,
                  mapToolbarEnabled: false,
                  compassEnabled: false,
                  liteModeEnabled: false,

                  markers: {
                    Marker(
                      markerId: const MarkerId('sos'),
                      position: LatLng(alert.latitude!, alert.longitude!),
                      icon: BitmapDescriptor.defaultMarkerWithHue(
                        BitmapDescriptor.hueRed,
                      ),
                    ),
                  },
                ),
              ),
            ),
          ],

          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 50,
                  child: FilledButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();

                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => LiveMapScreen(focusUserId: userId),
                        ),
                      );
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor:
                          AppColors.alertRed.withValues(alpha: 0.24),
                      foregroundColor: AppColors.alertRed,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                    ),
                    icon: const Icon(Icons.my_location_rounded, size: 19),
                    label: const Text(
                      'Live location',
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SizedBox(
                  height: 50,
                  child: OutlinedButton.icon(
                    onPressed: alert.hasLocation
                        ? () => _directions(alert)
                        : null,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textPrimary,
                      side: const BorderSide(color: AppColors.glassBorder),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                    ),
                    icon: const Icon(Icons.directions_rounded, size: 19),
                    label: const Text(
                      'Directions',
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            alert.notifiedCount > 1
                ? '${alert.notifiedCount} family members were alerted.'
                : 'You were alerted.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _directions(SosAlert alert) async {
    final uri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1'
      '&destination=${alert.latitude},${alert.longitude}',
    );

    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // The live map is still there, and it is the better answer anyway.
    }
  }
}
