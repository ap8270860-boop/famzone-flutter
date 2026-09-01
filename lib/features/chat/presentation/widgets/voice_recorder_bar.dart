import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../state/voice_recorder.dart';

/// What the composer becomes while a voice note is being recorded.
///
/// Sits in place of the text field, inside the composer's own row, so the
/// microphone button beside it is never rebuilt out of the tree. That matters
/// more than it looks: the button owns the long-press gesture, and a
/// GestureDetector that is disposed mid-press never delivers its end event —
/// the recording would run forever.
class VoiceRecorderStrip extends StatelessWidget {
  const VoiceRecorderStrip({
    super.key,
    required this.recorder,
    required this.slide,
    required this.onCancel,
  });

  final VoiceRecorder recorder;

  /// How far the finger has slid left, 0–1 of the way to cancelling.
  final double slide;

  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final locked = recorder.isLocked;

    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(23),
        color: Colors.white.withValues(alpha: 0.06),
        border: Border.all(color: Colors.white.withValues(alpha: 0.11)),
      ),
      child: Row(
        children: [
          if (locked)
            // Locked: the bin is a real button, because there is no finger
            // left to slide.
            GestureDetector(
              onTap: onCancel,
              behavior: HitTestBehavior.opaque,
              child: const Padding(
                padding: EdgeInsets.only(right: 10),
                child: Icon(Icons.delete_outline_rounded,
                    size: 20, color: AppColors.alertRed),
              ),
            )
          else
            const _PulsingDot(),

          Text(
            _clock(recorder.elapsed),
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              fontFeatures: [FontFeature.tabularFigures()],
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(width: 12),

          Expanded(
            child: locked
                ? _Levels(levels: recorder.live)
                // Fades as the finger travels, so cancelling is a thing you
                // can feel happening rather than a thing that happens.
                : Opacity(
                    opacity: (1 - slide).clamp(0.25, 1.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Transform.translate(
                          offset: Offset(-slide * 40, 0),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.chevron_left_rounded,
                                  size: 18, color: AppColors.textMuted),
                              Text(
                                'slide to cancel',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: AppColors.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  static String _clock(Duration d) {
    final minutes = d.inMinutes;
    final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');

    return '$minutes:$seconds';
  }
}

/// The recording light.
class _PulsingDot extends StatefulWidget {
  const _PulsingDot();

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: FadeTransition(
        opacity: Tween<double>(begin: 1, end: 0.25).animate(_controller),
        child: Container(
          width: 9,
          height: 9,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.alertRed,
          ),
        ),
      ),
    );
  }
}

/// Live input level, scrolling right to left.
class _Levels extends StatelessWidget {
  const _Levels({required this.levels});

  final List<double> levels;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        for (final level in levels)
          Container(
            width: 2.5,
            height: (level * 22).clamp(3.0, 22.0),
            margin: const EdgeInsets.symmetric(horizontal: 1),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(2),
              color: AppColors.aqua.withValues(alpha: 0.85),
            ),
          ),
      ],
    );
  }
}

/// The chip that appears above the microphone while recording.
///
/// Slide up onto it to go hands free. Shown only before locking, because
/// afterwards it has nothing left to offer.
class VoiceLockChip extends StatelessWidget {
  const VoiceLockChip({super.key, required this.progress});

  /// How far the finger has travelled toward locking, 0–1.
  final double progress;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        color: AppColors.canvasRaised,
        border: Border.all(
          color: Color.lerp(
            Colors.white.withValues(alpha: 0.12),
            AppColors.mint,
            progress,
          )!,
          width: 1.4,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.lock_outline_rounded,
            size: 17,
            color: Color.lerp(AppColors.textMuted, AppColors.mint, progress),
          ),
          const SizedBox(height: 4),
          Transform.translate(
            offset: Offset(0, -progress * 3),
            child: Icon(
              Icons.keyboard_arrow_up_rounded,
              size: 16,
              color: AppColors.textMuted.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }
}
