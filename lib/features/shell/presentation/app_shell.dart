import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/pulse_rings.dart';
import '../../chat/presentation/inbox_screen.dart';
import '../../chat/state/chat_store.dart';
import '../../chat/state/realtime_client.dart';
import '../../home/presentation/home_screen.dart';
import '../../location/presentation/widgets/sharing_banner.dart';
import '../../sos/presentation/sos_screen.dart';
import '../../sos/presentation/widgets/incoming_sos_banner.dart';
import '../../sos/state/sos_store.dart';
import 'app_drawer.dart';
import 'placeholder_tab.dart';

/// The signed-in container: four tabs and the SOS button between them.
///
/// Tabs are kept alive with an IndexedStack so switching back does not
/// rebuild and refetch — important once Circle and Alerts hold live data.
class AppShell extends StatefulWidget {
  const AppShell({super.key, this.initialIndex = 0});

  final int initialIndex;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  late int _index = widget.initialIndex;

  static const _tabs = <_TabSpec>[
    _TabSpec(Icons.home_rounded, Icons.home_outlined, 'Home'),
    _TabSpec(Icons.groups_rounded, Icons.groups_outlined, 'Chats'),
    _TabSpec(Icons.verified_user_rounded, Icons.verified_user_outlined, 'Alerts'),
    _TabSpec(Icons.person_rounded, Icons.person_outline_rounded, 'Profile'),
  ];

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);

    // Opens the websocket and joins this user's mailbox channel, so the
    // unread badge stays right whether or not a chat screen is open. A no-op
    // when no Reverb key is configured.
    RealtimeClient.instance.start();

    // The badge has to be right before anybody opens Messages. Without this
    // the only way to find out you have unread messages is to go looking for
    // them, which rather defeats the point of a badge.
    ChatStore.instance.refreshBadge();

    // The badge is one number; the map needs to know *who* the messages are
    // from. Loading the threads once at start is what makes the per-person
    // badges correct before anybody opens Chats.
    ChatStore.instance.ensureLoaded();

    /*
     | Fetch the emergency catalogue up front, quietly.
     |
     | The one screen that must never show a spinner is this one, and the
     | moment somebody opens it is the moment they have the least patience
     | for a round trip. It also restores an alert that was still running
     | when the app was last closed.
     */
    SosStore.instance.load(quiet: true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;

    // Dart timers are frozen while the process is suspended, so a socket that
    // died overnight sits in a pending retry that fires whenever it gets
    // around to it. Poking it here is the difference between a chat that is
    // live the moment the phone is unlocked and one that takes half a minute
    // to notice it is alone.
    RealtimeClient.instance.resume();
    ChatStore.instance.refreshBadge();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: AppColors.canvas,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        key: _scaffoldKey,
        drawer: const AppDrawer(),
        backgroundColor: AppColors.canvas,
        extendBody: true, // the bar floats over the content
        body: Stack(
          children: [
            IndexedStack(
          // Loose is the default, which leaves a tab free to size to its
          // content instead of the screen. Expand forces a full-height tab.
          sizing: StackFit.expand,
          index: _index,
          children: [
            HomeScreen(
              onMenu: () => _scaffoldKey.currentState?.openDrawer(),
            ),
            // Kept alive by the IndexedStack, so returning to it does
            // not refetch — and it does not need to, because the socket has
            // been updating it the whole time it was off screen.
            const InboxScreen(embedded: true),
            const PlaceholderTab(
              icon: Icons.shield_rounded,
              title: 'Alerts',
              message: 'SOS alerts and safety notifications will appear here.',
            ),
            const PlaceholderTab(
              icon: Icons.person_rounded,
              title: 'Profile',
              message: 'Your details, privacy and subscription.',
            ),
          ],
        ),

            /*
             | A family member's alarm, above every tab.
             |
             | Mounted here rather than pushed as a route so it reaches the
             | person on whatever screen they happen to be looking at, and
             | cannot be buried by whatever they navigate to next. It draws
             | nothing at all when there is no alarm.
             */
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: IncomingSosBanner(),
            ),

            /*
             | And under it, the quieter one.
             |
             | Below the SOS banner in the stack on purpose: if both ever fire
             | at once, the alarm is the one that must be on top. In practice
             | they rarely coincide, and when they do, an SOS covering a
             | "started sharing" notice is exactly the right outcome.
             */
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SharingBanner(),
            ),
          ],
        ),
        // Rebuilt from the store so the badge changes the moment a
        // message arrives, on whatever tab the user happens to be looking at.
        bottomNavigationBar: AnimatedBuilder(
          animation: ChatStore.instance,
          builder: (context, _) => _GlassNavBar(
            tabs: _tabs,
            index: _index,
            badges: [0, ChatStore.instance.unread, 0, 0],
            onChanged: _select,
            onSos: () => _confirmSos(context),
          ),
        ),
      ),
    );
  }

  void _select(int index) {
    setState(() => _index = index);

    // Opening Chats reconciles with the server. The socket keeps the list
    // live while the app runs, but anything that happened during a dropped
    // connection is only caught by asking.
    if (index == 1) ChatStore.instance.refresh();
  }

  /// Open the emergency screen.
  ///
  /// No confirmation sheet here any more — the hold-to-activate gesture on
  /// the screen itself is the confirmation, and it is a better one. A dialog
  /// asking "are you sure" is one tap away from being dismissed by the same
  /// accident that opened it.
  void _confirmSos(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SosScreen()),
    );
  }
}

class _TabSpec {
  const _TabSpec(this.active, this.inactive, this.label);

  final IconData active;
  final IconData inactive;
  final String label;
}

/// Floating frosted bar with the SOS button seated in the middle.
///
/// It floats clear of the screen edges rather than sitting flush against the
/// bottom, and the SOS sits inside the bar rather than overhanging it — both
/// measured from the design.
class _GlassNavBar extends StatelessWidget {
  const _GlassNavBar({
    required this.tabs,
    required this.index,
    required this.badges,
    required this.onChanged,
    required this.onSos,
  });

  final List<_TabSpec> tabs;
  final int index;

  /// One count per tab; zero draws nothing.
  final List<int> badges;

  final ValueChanged<int> onChanged;
  final VoidCallback onSos;

  /// Bar height, and how far the SOS button rises above its top edge.
  ///
  /// Measured from the design: the button's diameter is 81px against an 11px
  /// overhang, so it clears the bar by ~14% of its own height.
  static const double _barHeight = 76;
  static const double _sosDiameter = 58;
  static const double _sosOverhang = _sosDiameter * 0.14;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(14, 0, 14, bottomInset > 0 ? 8 : 14),
      child: SizedBox(
        height: _barHeight + _sosOverhang,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // The bar itself, seated at the bottom of the reserved space.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: _barHeight,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(32),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(32),
                      color: AppColors.barSurface.withValues(alpha: 0.94),
                      border: Border.all(color: AppColors.glassBorder),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.45),
                          blurRadius: 24,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        _item(0),
                        _item(1),
                        // Gap the SOS button occupies. It lives outside this
                        // ClipRRect so it can break the rounded edge.
                        const SizedBox(width: 78),
                        _item(2),
                        _item(3),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // SOS, overhanging the bar's top edge.
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Center(
                child: _SosButton(
                  onTap: onSos,
                  diameter: _sosDiameter,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _item(int i) {
    final selected = index == i;
    final tab = tabs[i];
    final badge = i < badges.length ? badges[i] : 0;

    return Expanded(
      child: GestureDetector(
        onTap: () => onChanged(i),
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // The badge overhangs the icon rather than sitting beside it, so
            // a count appearing never shifts the row's layout.
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(
                  selected ? tab.active : tab.inactive,
                  size: 29,
                  color: selected ? AppColors.mint : AppColors.navInactive,
                ),
                if (badge > 0)
                  Positioned(
                    top: -3,
                    right: -8,
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 18),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        color: AppColors.alertRed,
                        // A ring in the bar's own colour, so the badge reads
                        // as sitting on top of the icon rather than merging
                        // into it.
                        border: Border.all(
                          color: AppColors.barSurface,
                          width: 2,
                        ),
                      ),
                      child: Text(
                        badge > 99 ? '99+' : '$badge',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 9.5,
                          height: 1.25,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              tab.label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? AppColors.mint : AppColors.navInactive,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SosButton extends StatelessWidget {
  const _SosButton({required this.onTap, required this.diameter});

  final VoidCallback onTap;
  final double diameter;

  /// How far the wave reaches, as a multiple of the button.
  ///
  /// Kept modest. This is permanent chrome — on screen on every tab, all day
  /// — so it has to register peripherally and then be ignorable. A wave that
  /// swept half the bar would be noticed once and resented thereafter.
  static const double _waveSpread = 1.55;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      /*
       | Exactly the diameter, exactly as before.
       |
       | The box does not grow to fit the wave — the wave is painted past the
       | edge of it. That keeps the footprint the bar was measured for, and
       | it is why an earlier attempt with OverflowBox broke the layout:
       | OverflowBox sizes from its parent's constraints, not from the max it
       | is given, so under a Stack's loose constraints it collapsed.
       |
       | Nothing clips the overspill: the nav bar's own Stack is already
       | Clip.none for the button's overhang.
       */
      child: SizedBox(
        width: diameter,
        height: diameter,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Positioned.fill(
              child: PulseRings(
                // The same green the button's own glow uses, so the wave
                // reads as the button breathing rather than as a second
                // thing sitting behind it.
                color: const Color(0xFF62E487),
                innerRadius: diameter / 2,
                outerRadius: diameter * _waveSpread / 2,
                period: const Duration(milliseconds: 2800),
                peakOpacity: 0.38,
              ),
            ),
            Container(
            width: diameter,
            height: diameter,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: AppColors.sosGradient,
              // Dark ring, so the button reads as sitting on top of the bar
              // rather than being cut out of it.
              border: Border.all(color: AppColors.canvas, width: 3.5),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF62E487).withValues(alpha: 0.42),
                  blurRadius: 22,
                  spreadRadius: 1,
                ),
              ],
            ),
              child: const Center(
                child: Text(
                  'SOS',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.4,
                    color: Color(0xFF03202E),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
