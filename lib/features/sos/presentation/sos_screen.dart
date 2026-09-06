import 'dart:async';
// FontFeature, for tabular figures on the running timer — without them
// the digits change width and the whole banner twitches once a second.
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_toast.dart';
import '../../location/state/location_permissions.dart';
import '../data/sos_models.dart';
import '../state/sos_store.dart';
import 'sos_history_screen.dart';
import 'sos_service_screen.dart';
import 'widgets/service_glyph.dart';
import 'widgets/sos_hold_button.dart';

/// The emergency screen.
///
/// Two states of one screen rather than two screens, because the transition
/// between them happens at the worst moment of somebody's day and a page push
/// there would be a whole extra thing to understand. Before an alarm the hold
/// button owns the top of the screen; after one, a live banner takes its
/// place. The service grid never moves.
///
/// That grid is deliberately reachable *without* raising an alarm. The
/// original sketch put the services behind the SOS button, and that is one
/// gate too many: somebody who wants the nearest hospital's number at 11pm
/// should not have to wake their family to get it. Raising the alarm is the
/// prominent path, not the only one.
class SosScreen extends StatefulWidget {
  const SosScreen({super.key});

  @override
  State<SosScreen> createState() => _SosScreenState();
}

class _SosScreenState extends State<SosScreen> {
  final SosStore _store = SosStore.instance;

  /// Drives the elapsed counter on a live alert. One second, and only while
  /// something is actually running.
  Timer? _tick;

  @override
  void initState() {
    super.initState();

    _store.addListener(_onStore);
    _store.load(quiet: _store.loaded);

    _syncTicker();
  }

  @override
  void dispose() {
    _tick?.cancel();
    _store.removeListener(_onStore);

    super.dispose();
  }

  void _onStore() {
    if (!mounted) return;

    _syncTicker();
    setState(() {});
  }

  void _syncTicker() {
    if (_store.isActive && _tick == null) {
      _tick = Timer.periodic(
        const Duration(seconds: 1),
        (_) => mounted ? setState(() {}) : null,
      );
    } else if (!_store.isActive) {
      _tick?.cancel();
      _tick = null;
    }
  }

  /*
  |----------------------------------------------------------------------------
  | Actions
  |----------------------------------------------------------------------------
  */

  Future<void> _raise() async {
    /*
     | Permission is asked for here, and a refusal does not stop the alarm.
     |
     | A position makes the alert far more useful and is not a precondition
     | for it. Somebody who declined location months ago must still be able to
     | raise an alarm today — so this asks, waits briefly, and proceeds either
     | way.
     */
    await LocationPermissions.ensure(context);

    if (!mounted) return;

    final raised = await _store.raise();

    if (!mounted) return;

    if (!raised) {
      AppToast.show(
        context,
        _store.error ?? 'Could not raise the alert.',
        type: ToastType.error,
      );

      return;
    }

    AppToast.show(
      context,
      _store.familyCount > 0
          ? 'Alert sent to ${_store.familyCount} family '
              '${_store.familyCount == 1 ? 'member' : 'members'}.'
          : 'Alert recorded. Add family so they can be notified.',
    );
  }

  Future<void> _end() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => const _EndSheet(),
    );

    if (choice == null || !mounted) return;

    final ended = await _store.end(choice);

    if (!mounted) return;

    AppToast.show(
      context,
      ended ? 'Alert ended.' : (_store.error ?? 'Could not end the alert.'),
      type: ended ? ToastType.info : ToastType.error,
    );
  }

  void _open(EmergencyService service) {
    // Recorded on the alert, if one is running, so the history says what the
    // person was actually reaching for.
    if (_store.isActive) _store.setCategory(service.key);

    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => SosServiceScreen(service: service)),
    );
  }

  /*
  |----------------------------------------------------------------------------
  | Build
  |----------------------------------------------------------------------------
  */

  @override
  Widget build(BuildContext context) {
    final active = _store.active;

    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _Header(
              onBack: () => Navigator.of(context).maybePop(),
              onHistory: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SosHistoryScreen()),
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                color: AppColors.neonCyan,
                backgroundColor: AppColors.canvasRaised,
                onRefresh: () => _store.load(),
                child: ListView(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    4,
                    16,
                    28 + MediaQuery.paddingOf(context).bottom,
                  ),
                  children: [
                    if (active != null)
                      _ActiveBanner(alert: active, onEnd: _end)
                    else
                      _Trigger(
                        busy: _store.raising,
                        onActivate: _raise,
                      ),

                    const SizedBox(height: 26),

                    Row(
                      children: [
                        Text(
                          active != null
                              ? 'Who do you need?'
                              : 'Emergency services',
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const Spacer(),
                        if (_store.loading)
                          const SizedBox(
                            width: 15,
                            height: 15,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.neonCyan,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      active != null
                          ? 'Tap a service for its number and the nearest places.'
                          : 'Call any of these directly — no alert is raised.',
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12.5,
                      ),
                    ),
                    const SizedBox(height: 14),

                    if (_store.services.isEmpty && !_store.loading)
                      const _CatalogueUnavailable()
                    else
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          childAspectRatio: 0.92,
                        ),
                        itemCount: _store.services.length,
                        itemBuilder: (context, index) => _ServiceCard(
                          service: _store.services[index],
                          onTap: () => _open(_store.services[index]),
                        ),
                      ),

                    const SizedBox(height: 22),
                    _Disclaimer(text: _store.disclaimer),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/*
|------------------------------------------------------------------------------
| Header
|------------------------------------------------------------------------------
*/

class _Header extends StatelessWidget {
  const _Header({required this.onBack, required this.onHistory});

  final VoidCallback onBack;
  final VoidCallback onHistory;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 8, 12, 8),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back_rounded),
            color: AppColors.textPrimary,
          ),
          const Text(
            'Emergency SOS',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          TextButton.icon(
            onPressed: onHistory,
            style: TextButton.styleFrom(foregroundColor: AppColors.textMuted),
            icon: const Icon(Icons.history_rounded, size: 18),
            label: const Text('History'),
          ),
        ],
      ),
    );
  }
}

/*
|------------------------------------------------------------------------------
| Before
|------------------------------------------------------------------------------
*/

class _Trigger extends StatelessWidget {
  const _Trigger({required this.busy, required this.onActivate});

  final bool busy;
  final VoidCallback onActivate;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 10),
        SosHoldButton(busy: busy, onActivate: onActivate),
        const SizedBox(height: 18),
        const Text(
          'Hold for 2 seconds',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 28),
          child: Text(
            'Your family is alerted and can see your live location until you '
            'end it.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 13,
              height: 1.45,
            ),
          ),
        ),
      ],
    );
  }
}

/*
|------------------------------------------------------------------------------
| During
|------------------------------------------------------------------------------
*/

class _ActiveBanner extends StatelessWidget {
  const _ActiveBanner({required this.alert, required this.onEnd});

  final SosAlert alert;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF3E1420), Color(0xFF2A1030)],
        ),
        border: Border.all(color: AppColors.alertRed.withValues(alpha: 0.55)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const _LivePip(),
              const SizedBox(width: 10),
              const Text(
                'SOS ACTIVE',
                style: TextStyle(
                  color: AppColors.alertRed,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.3,
                ),
              ),
              const Spacer(),
              Text(
                alert.elapsedLabel,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            alert.notifiedCount > 0
                ? '${alert.notifiedCount} family '
                    '${alert.notifiedCount == 1 ? 'member has' : 'members have'} '
                    'been alerted'
                : 'No family members to alert yet',
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 14.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            alert.hasLocation
                ? 'They can see your live location.'
                : 'Waiting for a location fix — the alert has been sent.',
            style: const TextStyle(color: AppColors.textMuted, fontSize: 12.5),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 46,
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onEnd,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.mint,
                side: BorderSide(color: AppColors.mint.withValues(alpha: 0.55)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: const Icon(Icons.check_circle_outline_rounded, size: 19),
              label: const Text(
                'I’m safe — end alert',
                style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The blinking dot. The only thing on the banner that moves, so it is the
/// thing the eye goes to.
class _LivePip extends StatefulWidget {
  const _LivePip();

  @override
  State<_LivePip> createState() => _LivePipState();
}

class _LivePipState extends State<_LivePip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.alertRed
              .withValues(alpha: 0.45 + 0.55 * _c.value),
          boxShadow: [
            BoxShadow(
              color: AppColors.alertRed.withValues(alpha: 0.5 * _c.value),
              blurRadius: 10,
              spreadRadius: 1.5,
            ),
          ],
        ),
      ),
    );
  }
}

/*
|------------------------------------------------------------------------------
| Ending
|------------------------------------------------------------------------------
*/

/// Three ways to close an alert, and they are not the same.
///
/// "Cancelled" and "false alarm" both stop it, but they read completely
/// differently in a history six months later — and a person who can say "that
/// was my pocket" without it looking like a real emergency they backed out of
/// is a person who leaves the button enabled.
class _EndSheet extends StatelessWidget {
  const _EndSheet();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.fromLTRB(
        12, 0, 12, 12 + MediaQuery.viewPaddingOf(context).bottom,
      ),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: AppColors.canvasRaised,
        border: Border.all(color: AppColors.glassBorder),
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
          const Text(
            'End this alert',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Your family will be told it is over. Which was it?',
            style: TextStyle(color: AppColors.textMuted, fontSize: 13),
          ),
          const SizedBox(height: 18),
          _EndOption(
            icon: Icons.verified_rounded,
            tint: AppColors.mint,
            title: 'I’m safe now',
            subtitle: 'It was real and it is over',
            value: SosAlert.statusResolved,
          ),
          _EndOption(
            icon: Icons.undo_rounded,
            tint: AppColors.aqua,
            title: 'Cancel it',
            subtitle: 'I no longer need help',
            value: SosAlert.statusCancelled,
          ),
          _EndOption(
            icon: Icons.error_outline_rounded,
            tint: AppColors.lavenderGray,
            title: 'Pressed by mistake',
            subtitle: 'Recorded as a false alarm',
            value: SosAlert.statusFalseAlarm,
          ),
        ],
      ),
    );
  }
}

class _EndOption extends StatelessWidget {
  const _EndOption({
    required this.icon,
    required this.tint,
    required this.title,
    required this.subtitle,
    required this.value,
  });

  final IconData icon;
  final Color tint;
  final String title;
  final String subtitle;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: AppColors.glassFill,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => Navigator.of(context).pop(value),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: tint.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, size: 19, color: tint),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/*
|------------------------------------------------------------------------------
| Grid
|------------------------------------------------------------------------------
*/

class _ServiceCard extends StatelessWidget {
  const _ServiceCard({required this.service, required this.onTap});

  final EmergencyService service;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final number = service.primaryNumber?.number;

    return Material(
      color: AppColors.glassFill,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: service.tint.withValues(alpha: 0.28)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Static in the grid. Fourteen breathing tiles at once would be
              // a fairground, not an emergency screen.
              ServiceGlyph(
                icon: service.icon,
                tint: service.tint,
                size: 52,
                animate: false,
              ),
              const Spacer(),
              Text(
                service.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                service.tagline,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 11.5,
                  height: 1.35,
                ),
              ),
              if (number != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: service.tint.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Text(
                    number,
                    style: TextStyle(
                      color: service.tint,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/*
|------------------------------------------------------------------------------
| Fallbacks
|------------------------------------------------------------------------------
*/

/// When even the catalogue could not be fetched.
///
/// 112 is written here, in the app, and it is the only number that is — the
/// one place where a hardcoded value is the right call, because this widget
/// exists precisely for the case where nothing else arrived.
class _CatalogueUnavailable extends StatelessWidget {
  const _CatalogueUnavailable();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: AppColors.glassFill,
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.wifi_off_rounded,
            color: AppColors.textMuted,
            size: 26,
          ),
          const SizedBox(height: 12),
          const Text(
            'Could not load the service list',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'In any emergency in India, dial 112. It reaches police, fire and '
            'ambulance, and it works without a signal on your own network.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 12.5,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

class _Disclaimer extends StatelessWidget {
  const _Disclaimer({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) return const SizedBox.shrink();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 1),
          child: Icon(
            Icons.info_outline_rounded,
            size: 15,
            color: AppColors.textMuted,
          ),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 11.5,
              height: 1.5,
            ),
          ),
        ),
      ],
    );
  }
}
