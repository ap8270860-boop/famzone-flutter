import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../state/location_store.dart';
import '../live_map_screen.dart';

/// "Pooja is sharing her location."
///
/// Lives in the app shell rather than on any one screen, for the same reason
/// the SOS banner does: it has to reach the person on whatever they happen to
/// be looking at. The difference is tone. An SOS banner is red and stays until
/// it is dealt with, because an alarm you can sweep away is not an alarm.
/// This is good news — somebody chose to let you see where they are — so it
/// says so, offers the one action worth offering, and leaves.
///
/// Tapping it opens the map already centred on them. That is the whole point:
/// the notification and the thing it is about should be one gesture apart, not
/// a banner followed by a hunt through a list of pins.
class SharingBanner extends StatefulWidget {
  const SharingBanner({super.key});

  @override
  State<SharingBanner> createState() => _SharingBannerState();
}

class _SharingBannerState extends State<SharingBanner> {
  final LocationStore _store = LocationStore.instance;

  Timer? _timer;
  String? _shownFor;

  /// Long enough to read and act on, short enough not to sit over a screen
  /// somebody is using. A family of five all leaving work at six would
  /// otherwise put a permanent hat on the app.
  static const Duration _linger = Duration(seconds: 8);

  @override
  void initState() {
    super.initState();

    _store.addListener(_onStore);
  }

  @override
  void dispose() {
    _store.removeListener(_onStore);
    _timer?.cancel();

    super.dispose();
  }

  void _onStore() {
    final notice = _store.sharingNotice;

    if (notice == null) {
      _shownFor = null;

      return;
    }

    // Restart the clock only for a *new* notice. A store notification for
    // some unrelated reason — a position landing, say — must not keep
    // extending the life of a banner that is already halfway through its
    // welcome.
    if (_shownFor == notice.userId) return;

    _shownFor = notice.userId;

    _timer?.cancel();
    _timer = Timer(_linger, () {
      if (mounted) _store.dismissSharingNotice();
    });
  }

  void _open(String userId) {
    _store.dismissSharingNotice();

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LiveMapScreen(focusUserId: userId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _store,
      builder: (context, _) {
        final notice = _store.sharingNotice;

        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 280),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) => SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, -1),
              end: Offset.zero,
            ).animate(animation),
            child: FadeTransition(opacity: animation, child: child),
          ),
          child: notice == null
              ? const SizedBox.shrink(key: ValueKey('none'))
              : SafeArea(
                  key: ValueKey(notice.userId),
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                    child: Material(
                      color: AppColors.canvasRaised,
                      borderRadius: BorderRadius.circular(18),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => _open(notice.userId),
                        child: Container(
                          padding:
                              const EdgeInsets.fromLTRB(12, 11, 8, 11),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: AppColors.mint.withValues(alpha: 0.45),
                            ),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x66000000),
                                blurRadius: 18,
                                offset: Offset(0, 6),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              Stack(
                                alignment: Alignment.center,
                                children: [
                                  CircleAvatar(
                                    radius: 19,
                                    backgroundColor: AppColors.mint
                                        .withValues(alpha: 0.18),
                                    backgroundImage: notice.avatarUrl == null
                                        ? null
                                        : NetworkImage(notice.avatarUrl!),
                                    child: notice.avatarUrl != null
                                        ? null
                                        : Text(
                                            notice.initials,
                                            style: const TextStyle(
                                              color: AppColors.mint,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                  ),
                                  Positioned(
                                    right: 0,
                                    bottom: 0,
                                    child: Container(
                                      width: 15,
                                      height: 15,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: AppColors.mint,
                                        border: Border.all(
                                          color: AppColors.canvasRaised,
                                          width: 2,
                                        ),
                                      ),
                                      child: const Icon(
                                        Icons.near_me_rounded,
                                        size: 7,
                                        color: Color(0xFF03202E),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      '${notice.name.split(' ').first} is '
                                      'sharing their location',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: AppColors.textPrimary,
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      notice.hasFix
                                          ? 'Tap to see them on the map'
                                          : 'Waiting for their first fix',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: AppColors.textMuted,
                                        fontSize: 11.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                onPressed: _store.dismissSharingNotice,
                                icon: const Icon(Icons.close_rounded, size: 18),
                                color: AppColors.textMuted,
                                tooltip: 'Dismiss',
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
        );
      },
    );
  }
}
