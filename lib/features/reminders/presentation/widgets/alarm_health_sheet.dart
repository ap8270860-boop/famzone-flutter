import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../../../core/theme/app_colors.dart';
import '../../state/reminder_scheduler.dart';
import '../../state/reminder_store.dart';

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
                const _SelfTest(),
                const SizedBox(height: 18),
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

/// Two taps that say where the chain is broken.
///
/// The OEM instructions below are advice; this is evidence. It reads the state
/// the scheduler is actually in, and offers the two calls that separate the
/// three things that all look identical from the outside — a notification that
/// cannot be posted, one that cannot be scheduled, and a scheduler that was
/// never given anything to schedule.
class _SelfTest extends StatefulWidget {
  const _SelfTest();

  @override
  State<_SelfTest> createState() => _SelfTestState();
}

class _SelfTestState extends State<_SelfTest> {
  final ReminderScheduler _scheduler = ReminderScheduler.instance;

  String _result = '';
  bool _bad = false;
  bool _busy = false;
  List<PendingNotificationRequest> _held = const [];

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final held = await _scheduler.pending();

    if (!mounted) return;

    setState(() => _held = held);
  }

  Future<void> _run(Future<String> Function() call, String okText) async {
    if (_busy) return;

    setState(() {
      _busy = true;
      _result = '';
    });

    final error = await call();

    if (!mounted) return;

    setState(() {
      _busy = false;
      _bad = error.isNotEmpty;
      _result = error.isEmpty ? okText : error;
    });

    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final store = ReminderStore.instance;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
      decoration: BoxDecoration(
        color: AppColors.canvas.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.textMuted.withValues(alpha: 0.16),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Self-test',
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 3),
          const Text(
            'Ring now checks that this phone can show our notification at '
            'all. Ring in 60s checks that it can schedule one. Close the app '
            'after tapping the second.',
            style: TextStyle(
              fontSize: 11.5,
              height: 1.45,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 11),
          Row(
            children: [
              Expanded(
                child: _TestButton(
                  label: 'Ring now',
                  busy: _busy,
                  onTap: () => _run(
                    _scheduler.ringNow,
                    'Posted. If nothing appeared, notifications are blocked.',
                  ),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: _TestButton(
                  label: 'Ring in 60s',
                  busy: _busy,
                  onTap: () => _run(
                    _scheduler.ringSoon,
                    'Scheduled for 60 seconds from now. Close the app.',
                  ),
                ),
              ),
            ],
          ),
          if (_result.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              _result,
              style: TextStyle(
                fontSize: 11.5,
                height: 1.45,
                color: _bad ? AppColors.alertRed : AppColors.emerald,
              ),
            ),
          ],
          const SizedBox(height: 13),
          _Line('Timezone', _scheduler.zoneName),
          _Line('Exact alarms', _scheduler.exactAlarmsAllowed ? 'yes' : 'no'),
          _Line('Held by the OS', '${_held.length}'),
          if (store.fault != null) _Line('Last load error', store.fault!),
          const SizedBox(height: 8),
          const Text(
            'Last sync',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            _scheduler.report,
            style: const TextStyle(
              fontSize: 11,
              height: 1.5,
              fontFamily: 'monospace',
              color: AppColors.textMuted,
            ),
          ),
          if (_held.isNotEmpty) ...[
            const SizedBox(height: 9),
            const Text(
              'Next alarms',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                color: AppColors.textMuted,
              ),
            ),
            const SizedBox(height: 3),
            for (final row in _held.take(6))
              Text(
                '${row.id}  ${row.title ?? ''}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  height: 1.45,
                  fontFamily: 'monospace',
                  color: AppColors.textMuted,
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 106,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 11.5,
                color: AppColors.textMuted,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 11.5,
                fontFamily: 'monospace',
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TestButton extends StatelessWidget {
  const _TestButton({
    required this.label,
    required this.busy,
    required this.onTap,
  });

  final String label;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: busy ? null : onTap,
      child: Container(
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.electricBlue.withValues(alpha: busy ? 0.25 : 0.85),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
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
