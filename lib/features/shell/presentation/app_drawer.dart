import 'package:flutter/material.dart';

import '../../../core/session/session.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_toast.dart';
import '../../auth/presentation/welcome_screen.dart';
import '../../profile/presentation/edit_profile_screen.dart';
import '../../safety/presentation/check_in_history_screen.dart';

/// The hamburger menu.
class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final user = Session.instance.user;

    return Drawer(
      backgroundColor: AppColors.canvas,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(right: Radius.circular(28)),
      ),
      child: DecoratedBox(
        decoration: const BoxDecoration(gradient: AppColors.appBackground),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Header(user: user),
              const Divider(color: AppColors.glassBorder, height: 28),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  children: [
                    _item(context, Icons.person_outline_rounded, 'My profile',
                        () => _push(context, const EditProfileScreen())),
                    _item(
                      context,
                      Icons.event_available_outlined,
                      'Check-in history',
                      () => _push(context, const CheckInHistoryScreen()),
                    ),
                    _item(context, Icons.groups_outlined, 'My circles', null),
                    _item(context, Icons.location_on_outlined,
                        'Location sharing', null),
                    _item(context, Icons.shield_outlined, 'Safety settings',
                        null),
                    _item(context, Icons.notifications_none_rounded,
                        'Notifications', null),
                    _item(context, Icons.workspace_premium_outlined,
                        'Subscription', null,
                        badge: user?.isPremium == true ? 'Premium' : null),
                    const Divider(color: AppColors.glassBorder, height: 24),
                    _item(context, Icons.help_outline_rounded, 'Help & support',
                        null),
                    _item(context, Icons.privacy_tip_outlined,
                        'Privacy policy', null),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
                child: _item(
                  context,
                  Icons.logout_rounded,
                  'Sign out',
                  () => _signOut(context),
                  danger: true,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _push(BuildContext context, Widget screen) {
    Navigator.of(context).pop();
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => screen));
  }

  Future<void> _signOut(BuildContext context) async {
    final navigator = Navigator.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.canvasRaised,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: const BorderSide(color: AppColors.glassBorder),
        ),
        title: const Text('Sign out?',
            style: TextStyle(color: AppColors.textPrimary)),
        content: const Text(
          'You will stop receiving SOS alerts from your circle on this device.',
          style: TextStyle(color: AppColors.textMuted, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            style: TextButton.styleFrom(foregroundColor: AppColors.textMuted),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.alertRed),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await Session.instance.signOut();

    navigator.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const WelcomeScreen()),
      (route) => false,
    );
  }

  Widget _item(
    BuildContext context,
    IconData icon,
    String label,
    VoidCallback? onTap, {
    String? badge,
    bool danger = false,
  }) {
    final colour = danger ? AppColors.alertRed : AppColors.textPrimary;

    return ListTile(
      onTap: onTap ??
          () {
            Navigator.of(context).pop();
            AppToast.show(context, '$label is coming soon.');
          },
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      leading: Icon(icon, size: 21, color: danger ? colour : AppColors.aqua),
      title: Text(
        label,
        style: TextStyle(
          fontSize: 14.5,
          fontWeight: FontWeight.w600,
          color: colour,
        ),
      ),
      trailing: badge == null
          ? null
          : Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: AppColors.safeGradient,
              ),
              child: Text(
                badge,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF04121F),
                ),
              ),
            ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.user});

  final AuthUser? user;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            padding: const EdgeInsets.all(2),
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: AppColors.safeGradient,
            ),
            child: Container(
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.canvasRaised,
              ),
              clipBehavior: Clip.antiAlias,
              child: user?.avatarUrl != null
                  ? Image.network(
                      user!.avatarUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _initials(),
                    )
                  : _initials(),
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  user?.name ?? 'Guest',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  user?.username != null
                      ? '@${user!.username}'
                      : user?.phone ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
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

  Widget _initials() => Center(
        child: Text(
          user?.initials ?? '?',
          style: const TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
      );
}
