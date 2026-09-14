import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// Why a reminder might not go off, and what to do about it.
///
/// This screen exists because of something no amount of code fixes. Android
/// gives every manufacturer licence to build its own battery saver on top, and
/// vivo, Xiaomi, Oppo, realme and Samsung all ship one that **revokes
/// scheduled alarms from apps the user has not opened recently**. The alarm is
/// registered correctly, the permission is granted, and the OS quietly drops
/// it anyway.
///
/// A deliberate non-feature: there is no detector here.
///
/// It is tempting to check whether the OS still holds our pending
/// notifications and warn when it does not — and it cannot work. The killing
/// happens while the app is closed, and the moment the app opens it
/// re-registers everything, so by the time anything could look, the evidence
/// is gone. A heuristic would cry wolf on first run and stay silent on the
/// real failure. Better to say plainly what the risk is once, than to ship a
/// warning light wired to nothing.
///
/// So: honest instructions, per manufacturer, phrased as the labels people
/// will actually see on their own phone.
class AlarmHealthSheet extends StatelessWidget {
  const AlarmHealthSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const AlarmHealthSheet(),
    );
  }

  /// The settings path on each of the offenders.
  ///
  /// Named rather than launched. Every package that claims to open these
  /// screens does it with hard-coded component names that break between OS
  /// versions and fail silently when they do — so somebody following exact
  /// words is more reliable than a button that may go nowhere.
  static const List<(String, String)> _steps = [
    (
      'vivo / iQOO',
      'Settings → Battery → Background power consumption management → '
          'SFamily → Allow. Then Settings → Apps → Autostart → turn SFamily on.',
    ),
    (
      'Xiaomi / Redmi / POCO',
      'Settings → Apps → Manage apps → SFamily → Autostart on, and '
          'Battery saver → No restrictions.',
    ),
    (
      'OPPO / realme / OnePlus',
      'Settings → Battery → App battery management → SFamily → '
          'Allow background activity, and turn off "Optimise battery use".',
    ),
    (
      'Samsung',
      'Settings → Apps → SFamily → Battery → Unrestricted. Then Battery → '
          'Background usage limits → make sure SFamily is not in "Sleeping apps".',
    ),
    (
      'Any other Android',
      'Settings → Apps → SFamily → Battery → Unrestricted, and allow '
          '"Alarms & reminders" if it is listed.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);

    return Container(
      constraints: BoxConstraints(maxHeight: media.size.height * 0.85),
      decoration: const BoxDecoration(
        color: AppColors.canvasRaised,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          Container(
            width: 38,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.textMuted.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.battery_alert_rounded,
                      size: 20,
                      color: AppColors.warmGold,
                    ),
                    const SizedBox(width: 9),
                    const Expanded(
                      child: Text(
                        'Make sure reminders go off',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Most phones have a battery saver that stops apps you have '
                  'not opened in a while — including their alarms. SFamily '
                  'cannot turn this off for you, but it takes about thirty '
                  'seconds.',
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.5,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          Flexible(
            child: ListView(
              padding: EdgeInsets.fromLTRB(20, 6, 20, 24 + media.viewPadding.bottom),
              shrinkWrap: true,
              children: [
                for (final (brand, how) in _steps) ...[
                  _Step(brand: brand, how: how),
                  const SizedBox(height: 10),
                ],
                const SizedBox(height: 4),
                const Text(
                  'If a reminder is ever late or missing, this is almost '
                  'always why.',
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.45,
                    color: AppColors.textMuted,
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

class _Step extends StatelessWidget {
  const _Step({required this.brand, required this.how});

  final String brand;
  final String how;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 13),
      decoration: BoxDecoration(
        color: AppColors.glassFill,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            brand,
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
              color: AppColors.mint,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            how,
            style: const TextStyle(
              fontSize: 12.5,
              height: 1.5,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
