import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../core/widgets/aurora_background.dart';
import '../../../core/widgets/glass_card.dart';
import '../data/people_models.dart';
import '../state/notification_store.dart';
import 'user_profile_screen.dart';
import 'widgets/person_avatar.dart';

/// The notification feed.
///
/// Each row's Accept/Decline comes from the server's resolved action state,
/// not from the notification's type — so a request already answered from the
/// profile screen shows as plain history here rather than offering to accept
/// something twice.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  @override
  void initState() {
    super.initState();

    // After the first frame: load() notifies synchronously on completion, and
    // marking everything read during initState would rebuild mid-build.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await NotificationStore.instance.load();
      await NotificationStore.instance.markAllRead();
    });
  }

  Future<void> _respond(AppNotification n, bool accept) async {
    final message = await NotificationStore.instance.respond(
      notification: n,
      accept: accept,
    );

    if (!mounted || message == null) return;

    AppToast.show(
      context,
      message,
      type: accept ? ToastType.success : ToastType.info,
    );
  }

  void _openActor(AppNotification n) {
    if (n.actorId == null) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => UserProfileScreen(userId: n.actorId!),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: AuroraBackground(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 6, 20, 6),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_rounded,
                          color: AppColors.textPrimary),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const Expanded(
                      child: Text(
                        'Notifications',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: AnimatedBuilder(
                  animation: NotificationStore.instance,
                  builder: (context, _) => _body(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body() {
    final store = NotificationStore.instance;

    if (store.loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.mint),
      );
    }

    if (store.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(44, 0, 44, 70),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.notifications_none_rounded,
                  size: 46, color: AppColors.textMuted.withValues(alpha: 0.5)),
              const SizedBox(height: 15),
              const Text(
                'Nothing yet',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Follow requests and family invites will show up here.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.45,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: store.load,
      color: AppColors.mint,
      backgroundColor: AppColors.canvasRaised,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 30),
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        itemCount: store.items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, i) {
          final n = store.items[i];

          return _NotificationRow(
            notification: n,
            busy: store.isBusy(n.id),
            onTap: () => _openActor(n),
            onAccept: () => _respond(n, true),
            onDecline: () => _respond(n, false),
          );
        },
      ),
    );
  }
}

class _NotificationRow extends StatelessWidget {
  const _NotificationRow({
    required this.notification,
    required this.busy,
    required this.onTap,
    required this.onAccept,
    required this.onDecline,
  });

  final AppNotification notification;
  final bool busy;
  final VoidCallback onTap;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    final n = notification;
    final action = n.action;

    return GlassCard(
      padding: const EdgeInsets.fromLTRB(13, 12, 13, 12),
      radius: 16,
      onTap: onTap,
      tint: n.read ? null : AppColors.aqua.withValues(alpha: 0.05),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PersonAvatar(
                size: 42,
                imageUrl: n.actorAvatarUrl,
                initials: n.initials,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      n.message,
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.35,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      n.age,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              if (!n.read) ...[
                const SizedBox(width: 8),
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.only(top: 6),
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.aqua,
                  ),
                ),
              ],
            ],
          ),
          if (action != null) ...[
            const SizedBox(height: 11),
            Row(
              children: [
                Expanded(
                  child: _Btn(
                    label: 'Accept',
                    filled: true,
                    busy: busy,
                    onTap: onAccept,
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: _Btn(
                    label: 'Decline',
                    filled: false,
                    busy: busy,
                    onTap: onDecline,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Btn extends StatelessWidget {
  const _Btn({
    required this.label,
    required this.filled,
    required this.busy,
    required this.onTap,
  });

  final String label;
  final bool filled;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = filled ? const Color(0xFF04121F) : AppColors.textPrimary;

    return GestureDetector(
      onTap: busy ? null : onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(11),
          gradient: filled ? AppColors.safeGradient : null,
          color: filled ? null : Colors.white.withValues(alpha: 0.07),
          border: filled
              ? null
              : Border.all(color: Colors.white.withValues(alpha: 0.16)),
        ),
        child: busy
            ? SizedBox(
                width: 15,
                height: 15,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(fg),
                ),
              )
            : Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: fg,
                ),
              ),
      ),
    );
  }
}
