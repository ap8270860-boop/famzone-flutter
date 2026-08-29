import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_colors.dart';
import '../../chat/presentation/inbox_screen.dart';
import '../../chat/state/chat_store.dart';
import '../../chat/state/realtime_client.dart';
import '../../home/presentation/home_screen.dart';
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
        body: IndexedStack(
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

  /// SOS is destructive and irreversible once sent, so it always confirms.
  /// A press-and-hold gesture replaces this when the real flow is built.
  void _confirmSos(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => const _SosSheet(),
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

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
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
    );
  }
}

class _SosSheet extends StatelessWidget {
  const _SosSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.fromLTRB(22, 26, 22, 22),
        decoration: BoxDecoration(
          color: AppColors.canvasRaised,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: AppColors.glassBorder),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.alertRed.withValues(alpha: 0.15),
                border: Border.all(
                  color: AppColors.alertRed.withValues(alpha: 0.4),
                ),
              ),
              child: const Icon(Icons.emergency_rounded,
                  size: 28, color: AppColors.alertRed),
            ),
            const SizedBox(height: 16),
            const Text(
              'Send an SOS alert?',
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Everyone in your circle gets a push, an in-app alert and an '
              'SMS with your current location.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.5,
                height: 1.45,
                color: AppColors.textMuted,
              ),
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.textMuted,
                      minimumSize: const Size.fromHeight(50),
                    ),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.alertRed,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(50),
                    ),
                    child: const Text('Send SOS'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
