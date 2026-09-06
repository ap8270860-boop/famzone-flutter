import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../data/location_api.dart';
import '../../data/location_models.dart';
import '../../state/location_permissions.dart';
import '../../state/location_store.dart';
import '../../state/location_tracker.dart';

/// Ask how long, then start.
///
/// Opened from the map (with no conversation) and from a chat (with one). The
/// two cases are the same sheet on purpose: the choice a person is making is
/// "for how long", and it should not feel like a different feature depending
/// on where it was tapped.
///
/// Returns true if a share actually started.
Future<bool> showShareLocationSheet(
  BuildContext context, {
  String? conversationId,
  String? threadName,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _ShareSheet(
      conversationId: conversationId,
      threadName: threadName,
    ),
  );

  return result ?? false;
}

class _ShareSheet extends StatefulWidget {
  const _ShareSheet({this.conversationId, this.threadName});

  final String? conversationId;
  final String? threadName;

  @override
  State<_ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends State<_ShareSheet> {
  bool _busy = false;

  bool get _isChat => widget.conversationId != null;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.canvasRaised,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(top: BorderSide(color: AppColors.glassBorder)),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        14,
        20,
        20 + MediaQuery.paddingOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.lavenderGray.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 22),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isChat ? 'Share live location' : 'Share with family',
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _isChat
                      ? 'Everyone in ${widget.threadName ?? 'this chat'} will '
                          'see you move on the map until this ends. You can '
                          'stop it at any time.'
                      : 'Your family members will see where you are until you '
                          'stop sharing. Nobody else can see it.',
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 13.5,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          if (_isChat) ...[
            _Option(
              icon: Icons.timer_outlined,
              title: '15 minutes',
              subtitle: 'Meeting someone, or nearly there',
              busy: _busy,
              onTap: () => _start(minutes: 15),
            ),
            _Option(
              icon: Icons.schedule_rounded,
              title: '1 hour',
              subtitle: 'A journey across town',
              busy: _busy,
              onTap: () => _start(minutes: 60),
            ),
            _Option(
              icon: Icons.hourglass_bottom_rounded,
              title: '8 hours',
              subtitle: 'A long trip, or a night out',
              busy: _busy,
              onTap: () => _start(minutes: 480),
            ),
            const SizedBox(height: 8),
            _Option(
              icon: Icons.place_outlined,
              title: 'Send current location',
              subtitle: 'A single pin — not live, never updates',
              busy: _busy,
              tone: _OptionTone.quiet,
              onTap: _pin,
            ),
          ] else
            _Option(
              icon: Icons.family_restroom_rounded,
              title: 'Until I stop',
              subtitle: 'Your family sees you until you switch it off',
              busy: _busy,
              onTap: () => _start(),
            ),

          const SizedBox(height: 14),
          Row(
            children: [
              const Icon(
                Icons.lock_outline_rounded,
                size: 15,
                color: AppColors.textMuted,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _isChat
                      ? 'A message in the chat shows that you are sharing.'
                      : 'Only accepted family members can see this.',
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /*
  |----------------------------------------------------------------------------
  | Actions
  |----------------------------------------------------------------------------
  */

  Future<void> _start({int? minutes}) async {
    if (_busy) return;

    setState(() => _busy = true);

    final started = await LocationStore.instance.startShare(
      audience: _isChat
          ? LocationShare.audienceConversation
          : LocationShare.audienceFamily,
      conversationId: widget.conversationId,
      minutes: minutes,
    );

    if (!mounted) return;

    if (!started) {
      setState(() => _busy = false);

      AppToast.show(
        context,
        LocationStore.instance.error ?? 'Could not start sharing.',
        type: ToastType.error,
      );

      return;
    }

    /*
     | Ask for background permission only once the share exists, and only if
     | the server said this kind needs it.
     |
     | Doing it in this order means the person has already seen the feature
     | work before being asked for the more serious permission — which is
     | both a much better prompt to answer and the sequencing both stores
     | expect to see.
     */
    if (LocationTracker.instance.plan.background && mounted) {
      final access = await LocationPermissions.ensureAlways(context);

      if (mounted && !access.canTrackInBackground) {
        AppToast.show(
          context,
          'Sharing started. Your family will see you while SFamily is open.',
        );
      }
    }

    if (!mounted) return;

    Navigator.of(context).pop(true);
  }

  Future<void> _pin() async {
    if (_busy) return;

    setState(() => _busy = true);

    final fix = await LocationTracker.instance.currentFix();

    if (!mounted) return;

    if (fix == null) {
      setState(() => _busy = false);

      AppToast.show(
        context,
        'Could not get a location fix. Try again outdoors.',
        type: ToastType.error,
      );

      return;
    }

    /*
     | Straight to the API rather than through the store.
     |
     | A pin creates a message and changes nothing about who can see me, so
     | there is no shared state for the store to hold. The bubble arrives in
     | the thread over the socket like any other message.
     */
    final response = await LocationApi().pin(
      conversationId: widget.conversationId!,
      latitude: fix.latitude,
      longitude: fix.longitude,
    );

    if (!mounted) return;

    if (!response.success) {
      setState(() => _busy = false);

      AppToast.show(context, response.message, type: ToastType.error);

      return;
    }

    Navigator.of(context).pop(true);
  }
}

/*
|------------------------------------------------------------------------------
| Rows
|------------------------------------------------------------------------------
*/

enum _OptionTone { normal, quiet }

class _Option extends StatelessWidget {
  const _Option({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    required this.busy,
    this.tone = _OptionTone.normal,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool busy;
  final _OptionTone tone;

  @override
  Widget build(BuildContext context) {
    final quiet = tone == _OptionTone.quiet;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: quiet
            ? Colors.transparent
            : AppColors.glassFill,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: busy ? null : onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: quiet
                    ? AppColors.glassBorder
                    : AppColors.neonCyan.withValues(alpha: 0.25),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: quiet
                        ? AppColors.glassFill
                        : AppColors.electricBlue.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(
                    icon,
                    size: 19,
                    color: quiet ? AppColors.textMuted : AppColors.neonCyan,
                  ),
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
                if (busy)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.neonCyan,
                    ),
                  )
                else
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.textMuted,
                    size: 20,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
