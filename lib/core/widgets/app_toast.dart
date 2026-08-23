import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

enum ToastType { success, error, info, warning }

/// A banner that drops in from the top of the screen.
///
/// Built on [Overlay] rather than [ScaffoldMessenger]: a SnackBar only ever
/// appears at the bottom, where a tall form's keyboard or a floating nav bar
/// covers it. Because this is an overlay it also survives navigation, so a
/// message shown just before popping a screen is still readable.
abstract final class AppToast {
  static OverlayEntry? _entry;
  static Timer? _timer;

  /// Show [message] at the top of the screen.
  ///
  /// Pass the API's own `message` field straight in — the server already
  /// phrases these for humans, so the app should not invent its own wording.
  static void show(
    BuildContext context,
    String message, {
    ToastType type = ToastType.info,
    Duration duration = const Duration(seconds: 3),
  }) {
    if (message.trim().isEmpty) return;

    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    // One at a time — a stack of banners hides the screen it is describing.
    dismiss();

    final entry = OverlayEntry(
      builder: (_) => _Toast(
        message: message,
        type: type,
        onDismiss: dismiss,
      ),
    );

    _entry = entry;
    overlay.insert(entry);

    _timer = Timer(duration, dismiss);
  }

  static void success(BuildContext context, String message) =>
      show(context, message, type: ToastType.success);

  static void error(BuildContext context, String message) =>
      show(context, message, type: ToastType.error, duration: const Duration(seconds: 4));

  static void dismiss() {
    _timer?.cancel();
    _timer = null;
    _entry?.remove();
    _entry = null;
  }
}

class _Toast extends StatefulWidget {
  const _Toast({
    required this.message,
    required this.type,
    required this.onDismiss,
  });

  final String message;
  final ToastType type;
  final VoidCallback onDismiss;

  @override
  State<_Toast> createState() => _ToastState();
}

class _ToastState extends State<_Toast> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
  )..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  (IconData, Color) get _style => switch (widget.type) {
        ToastType.success => (Icons.check_circle_rounded, AppColors.mint),
        ToastType.error => (Icons.error_rounded, AppColors.alertRed),
        ToastType.warning => (Icons.warning_rounded, AppColors.warmGold),
        ToastType.info => (Icons.info_rounded, AppColors.aqua),
      };

  @override
  Widget build(BuildContext context) {
    final (icon, tint) = _style;
    final top = MediaQuery.viewPaddingOf(context).top;

    return Positioned(
      top: top + 10,
      left: 14,
      right: 14,
      child: SlideTransition(
        position: Tween(begin: const Offset(0, -1.4), end: Offset.zero)
            .animate(CurvedAnimation(parent: _c, curve: Curves.easeOutCubic)),
        child: FadeTransition(
          opacity: _c,
          child: Material(
            color: Colors.transparent,
            child: Dismissible(
              key: ValueKey(widget.message),
              direction: DismissDirection.up,
              onDismissed: (_) => widget.onDismiss(),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      color: AppColors.canvasRaised.withValues(alpha: 0.96),
                      border: Border.all(color: tint.withValues(alpha: 0.45)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.4),
                          blurRadius: 22,
                          offset: const Offset(0, 8),
                        ),
                        BoxShadow(
                          color: tint.withValues(alpha: 0.16),
                          blurRadius: 20,
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Icon(icon, size: 20, color: tint),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            widget.message,
                            style: const TextStyle(
                              fontSize: 13.5,
                              height: 1.35,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: widget.onDismiss,
                          behavior: HitTestBehavior.opaque,
                          child: const Padding(
                            padding: EdgeInsets.only(left: 8),
                            child: Icon(Icons.close_rounded,
                                size: 17, color: AppColors.textMuted),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
