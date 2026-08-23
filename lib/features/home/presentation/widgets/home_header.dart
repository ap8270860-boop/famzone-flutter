import 'package:flutter/material.dart';

import '../../../../core/constants/app_assets.dart';
import '../../../../core/session/session.dart';
import '../../../../core/theme/app_colors.dart';

/// Avatar, brand lockup and notifications.
class HomeHeader extends StatelessWidget {
  const HomeHeader({super.key, this.hasUnread = true, this.onMenu, this.onBell});

  final bool hasUnread;
  final VoidCallback? onMenu;
  final VoidCallback? onBell;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Lockup is centred on the screen, not on the space between the
          // two icons, so it stays put whatever the icons do.
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 44,
                  height: 44,
                  child: Image.asset(
                    AppAssets.logoMark,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Icon(
                      Icons.diversity_3_rounded,
                      size: 30,
                      color: AppColors.aqua,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ShaderMask(
                      shaderCallback: (b) =>
                          AppColors.safeGradient.createShader(b),
                      child: const Text(
                        'SFamily',
                        style: TextStyle(
                          fontSize: 27,
                          fontWeight: FontWeight.w800,
                          height: 1.05,
                          letterSpacing: -0.4,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const Text(
                      'Together. Always Safe.',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        height: 1.2,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: _AvatarSlot(onTap: onMenu),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: _IconSlot(
              icon: Icons.notifications_none_rounded,
              onTap: onBell,
              badge: hasUnread,
            ),
          ),
        ],
      ),
    );
  }
}

/// The drawer handle: the user's photo, ringed in the safe gradient.
///
/// Listens to [Session] itself so a freshly uploaded avatar appears here
/// without the whole screen having to be rebuilt by hand.
class _AvatarSlot extends StatelessWidget {
  const _AvatarSlot({this.onTap});

  final VoidCallback? onTap;

  static const double _size = 40;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Session.instance,
      builder: (context, _) {
        final user = Session.instance.user;

        return GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Center(
              child: Container(
                width: _size,
                height: _size,
                padding: const EdgeInsets.all(1.6),
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
                          errorBuilder: (_, __, ___) => _Initials(user: user),
                        )
                      : _Initials(user: user),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Initials extends StatelessWidget {
  const _Initials({this.user});

  final AuthUser? user;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        user?.initials ?? '?',
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
      ),
    );
  }
}

class _IconSlot extends StatelessWidget {
  const _IconSlot({required this.icon, this.onTap, this.badge = false});

  final IconData icon;
  final VoidCallback? onTap;
  final bool badge;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 40,
        height: 44,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Icon(icon, size: 25, color: AppColors.textPrimary),
            if (badge)
              Positioned(
                top: 9,
                right: 6,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.mint,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
