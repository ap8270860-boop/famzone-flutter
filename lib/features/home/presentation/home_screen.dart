import 'package:flutter/material.dart';

import '../../../core/session/session.dart';
import '../../../core/session/session_sync.dart';
import '../../../core/widgets/app_toast.dart';
import '../../location/presentation/live_map_screen.dart';
import '../../sos/presentation/sos_screen.dart';
import '../../people/presentation/notifications_screen.dart';
import '../../people/presentation/search_people_screen.dart';
import '../../people/presentation/user_profile_screen.dart';
import '../../people/state/family_store.dart';
import '../../people/state/notification_store.dart';
import '../../safety/presentation/check_in_contacts_sheet.dart';
import '../../safety/presentation/widgets/incoming_check_in_card.dart';
import '../../safety/state/safety_store.dart';
import '../../../core/theme/app_colors.dart';
import 'widgets/check_in_card.dart';
import 'widgets/family_strip.dart';
import 'widgets/feature_tile.dart';
import 'widgets/home_header.dart';
import 'widgets/quick_actions.dart';
import 'widgets/safety_status_card.dart';

/// The signed-in dashboard.
///
/// Everything below the greeting is placeholder data for now; each section is
/// already a self-contained widget taking its content as parameters, so
/// wiring it to the API later is a change at this level only.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.onMenu});

  final VoidCallback? onMenu;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {

  @override
  void initState() {
    super.initState();

    // Avatar links are signed and expire, so the copy restored from secure
    // storage goes stale. Re-read the user in the background rather than
    // showing the initials fallback to somebody who has a photo set.
    syncSession();
    SafetyStore.instance.load();

    // Separate from load(): this is other people's check-ins waiting on me,
    // and it has to be right on a cold start even if the websocket frame that
    // announced it arrived while the app was closed.
    SafetyStore.instance.loadIncoming();

    FamilyStore.instance.load();
    NotificationStore.instance.refreshBadge();
  }

  void _openSearch() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SearchPeopleScreen()),
    );
  }

  /// The four shortcuts under the status card.
  ///
  /// Only two of them lead anywhere yet. The rest deliberately say so rather
  /// than doing nothing: a tile that swallows a tap reads as a broken app,
  /// where one that says "coming soon" reads as an unfinished one.
  void _onQuickAction(String key) {
    switch (key) {
      case 'sos':
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const SosScreen()),
        );

        return;

      case 'location':
      case 'circle':
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const LiveMapScreen()),
        );

        return;

      default:
        AppToast.show(context, 'Coming soon.');
    }
  }

  Future<void> _openNotifications() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const NotificationsScreen()),
    );

    // Accepting an invite from the feed changes the family strip, and reading
    // the feed clears the badge.
    if (mounted) {
      FamilyStore.instance.load();
      NotificationStore.instance.refreshBadge();
    }
  }

  void _openPerson(String userId) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => UserProfileScreen(userId: userId)),
    );
  }


  /// Mark today safe.
  ///
  /// The first tap is not a check-in.
  ///
  /// With no list chosen there is nobody to tell, and checking in silently
  /// would teach somebody that the button does nothing visible — so the first
  /// tap opens the picker, and the check-in rides along with the Save. Every
  /// tap after that goes straight through, which is what makes it a daily
  /// habit rather than a form.
  ///
  /// The store repaints both cards optimistically before the request leaves,
  /// so the only thing left to do here is report the outcome.
  Future<void> _checkIn() async {
    if (!SafetyStore.instance.hasContacts) {
      await _chooseContacts(thenCheckIn: true);

      return;
    }

    final outcome = await SafetyStore.instance.checkIn();

    if (!mounted || outcome.message == null) return;

    AppToast.show(
      context,
      outcome.message!,
      type: outcome.ok ? ToastType.success : ToastType.error,
    );
  }

  /// Open the order picker.
  ///
  /// [thenCheckIn] folds the two actions into one request rather than saving
  /// and then checking in separately. Two requests would leave a window where
  /// the list is saved but the check-in failed, and the user would come back
  /// to a configured list and no check-in with nothing explaining why.
  Future<void> _chooseContacts({bool thenCheckIn = false}) async {
    final book = await SafetyStore.instance.contactBook();

    if (!mounted) return;

    if (book == null) {
      AppToast.show(
        context,
        'Could not load your family list. Try again.',
        type: ToastType.error,
      );

      return;
    }

    final chosen = await CheckInContactsSheet.show(
      context,
      book: book,
      saveLabel: thenCheckIn ? 'Save & check in' : 'Save order',
      intro: thenCheckIn
          ? 'Choose who hears that you are safe, and in what order. We ask '
              'them one at a time — as soon as somebody confirms, the rest are '
              'never disturbed.'
          : null,
    );

    // Dismissed. An empty list is a real answer and is not this.
    if (chosen == null || !mounted) return;

    final outcome = thenCheckIn
        ? await SafetyStore.instance.checkIn(contacts: chosen)
        : await SafetyStore.instance.saveContacts(chosen);

    if (!mounted || outcome.message == null) return;

    AppToast.show(
      context,
      outcome.message!,
      type: outcome.ok ? ToastType.success : ToastType.error,
    );
  }

  /// Answer somebody else's check-in.
  ///
  /// Never treated as a failure for being late. A request that moved on while
  /// the phone was locked comes back as a success with a sentence saying so,
  /// which is the true and useful thing to show — the tap did not fail, the
  /// world moved.
  Future<void> _answerCheckIn(String requestId, bool accept) async {
    final outcome = await SafetyStore.instance.respond(
      requestId: requestId,
      accept: accept,
    );

    if (!mounted || outcome.message == null) return;

    AppToast.show(
      context,
      outcome.message!,
      type: outcome.ok ? ToastType.success : ToastType.error,
    );
  }

  Future<void> _refresh() async {
    // TODO: the circle summary, once that endpoint exists.
    await Future.wait([
      syncSession(),
      SafetyStore.instance.load(),
      SafetyStore.instance.loadIncoming(),
      FamilyStore.instance.load(),
      NotificationStore.instance.refreshBadge(),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    // Listen rather than read once: the name has to appear when the session
    // is restored or refreshed, not only if it happened to be there on the
    // very first build.
    return AnimatedBuilder(
      animation: Listenable.merge([
        Session.instance,
        SafetyStore.instance,
        FamilyStore.instance,
        NotificationStore.instance,
      ]),
      builder: (context, _) => _build(context),
    );
  }

  Widget _build(BuildContext context) {
    final user = Session.instance.user;
    final width = MediaQuery.sizeOf(context).width;

    // Below ~360dp the paired cards get too cramped to read, so they stack.
    final tilesPerRow = width < 360 ? 1 : 2;
    final gutter = width < 380 ? 16.0 : 20.0;

    return DecoratedBox(
      decoration: const BoxDecoration(gradient: AppColors.appBackground),
      child: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _refresh,
          color: AppColors.mint,
          backgroundColor: AppColors.canvasRaised,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            padding: EdgeInsets.fromLTRB(
              gutter,
              8,
              gutter,
              // Clear the floating nav bar plus the gesture inset.
              120 + MediaQuery.viewPaddingOf(context).bottom,
            ),
            children: [
              HomeHeader(
                onMenu: widget.onMenu,
                onBell: _openNotifications,
                hasUnread: NotificationStore.instance.unread > 0,
              ),
              const SizedBox(height: 22),

              _Greeting(name: user?.firstName ?? 'there'),
              const SizedBox(height: 18),

              /*
               | Somebody is waiting on an answer.
               |
               | Above the user's own status on purpose. This is the only card
               | here that represents another person's clock running down, and
               | putting it under the fold would mean the chain moves on
               | because the request was three scrolls away.
               */
              for (final request in SafetyStore.instance.incoming) ...[
                IncomingCheckInCard(
                  request: request,
                  busy: SafetyStore.instance.isAnswering(request.id),
                  onAccept: () => _answerCheckIn(request.id, true),
                  onDecline: () => _answerCheckIn(request.id, false),
                ),
                const SizedBox(height: 14),
              ],

              SafetyStatusCard(
                status: SafetyStore.instance.status,
                loading: SafetyStore.instance.loading,
              ),
              const SizedBox(height: 14),

              QuickActions(onTap: _onQuickAction),
              const SizedBox(height: 14),

              CheckInCard(
                info: SafetyStore.instance.status?.checkIn,
                submitting: SafetyStore.instance.submitting,
                onCheckIn: _checkIn,
                onEditContacts: () => _chooseContacts(),
              ),
              const SizedBox(height: 24),

              _SectionHeader(
                title: 'My Family',
                actionLabel: 'Find people',
                onAction: _openSearch,
              ),
              const SizedBox(height: 12),
              FamilyStrip(
                members: [
                  for (final person in FamilyStore.instance.members)
                    FamilyMember(
                      id: person.id,
                      name: person.name,
                      status: person.relation == null
                          ? 'Family'
                          : person.relation![0].toUpperCase() +
                              person.relation!.substring(1),
                      avatarUrl: person.avatarUrl,
                    ),
                ],
                onAdd: _openSearch,
                onTapMember: (m) {
                  if (m.id != null) _openPerson(m.id!);
                },
              ),
              const SizedBox(height: 20),

              _FeatureGrid(perRow: tilesPerRow),
            ],
          ),
        ),
      ),
    );
  }
}

class _Greeting extends StatelessWidget {
  const _Greeting({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Hi, $name 👋',
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 5),
        const Text(
          'You are protected. Your family is connected.',
          style: TextStyle(fontSize: 13.5, color: AppColors.textMuted),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.actionLabel,
    required this.onAction,
  });

  final String title;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        GestureDetector(
          onTap: onAction,
          behavior: HitTestBehavior.opaque,
          child: Row(
            children: [
              Text(
                actionLabel,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textMuted,
                ),
              ),
              const SizedBox(width: 3),
              const Icon(Icons.arrow_forward_rounded,
                  size: 15, color: AppColors.textMuted),
            ],
          ),
        ),
      ],
    );
  }
}

class _FeatureGrid extends StatelessWidget {
  const _FeatureGrid({required this.perRow});

  final int perRow;

  static const _tiles = <(IconData, String, String, Color)>[
    (
      Icons.phone_in_talk_rounded,
      'Emergency Contacts',
      'Quick call to saved contacts',
      AppColors.aqua,
    ),
    (
      Icons.home_work_rounded,
      'Safe Places',
      'Manage your safe locations',
      AppColors.mint,
    ),
    (
      Icons.directions_car_rounded,
      'Journey Tracker',
      'Share your journey with family',
      AppColors.neonPurple,
    ),
    (
      Icons.nightlight_round,
      'Night Guard',
      'Extra protection during night',
      AppColors.warmGold,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];

    for (var i = 0; i < _tiles.length; i += perRow) {
      final slice = _tiles.skip(i).take(perRow).toList();

      // IntrinsicHeight gives the Row a definite height (its tallest child),
      // which CrossAxisAlignment.stretch needs. Without it the Row is asked
      // to stretch children into a height that depends on those children —
      // circular, and the ListView above it fails to lay out at all.
      rows.add(IntrinsicHeight(
        child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var j = 0; j < slice.length; j++) ...[
            Expanded(
              child: FeatureTile(
                icon: slice[j].$1,
                title: slice[j].$2,
                subtitle: slice[j].$3,
                tint: slice[j].$4,
                onTap: () {},
              ),
            ),
            if (j != slice.length - 1) const SizedBox(width: 12),
          ],
          // Keep a lone tile the same width as a paired one.
          if (slice.length < perRow) ...[
            const SizedBox(width: 12),
            const Spacer(),
          ],
        ],
        ),
      ));

      if (i + perRow < _tiles.length) rows.add(const SizedBox(height: 12));
    }

    return Column(children: rows);
  }
}
