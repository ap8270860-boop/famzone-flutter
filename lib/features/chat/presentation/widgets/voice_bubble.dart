import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../data/chat_models.dart';
import '../../state/voice_player.dart';

/// A voice note in the conversation.
///
/// Draws the waveform the sender measured while recording, which is why the
/// bubble is complete the moment the message arrives — nothing is downloaded
/// or decoded to show it, and a note on a bad connection looks right before
/// it is playable.
class VoiceBubble extends StatelessWidget {
  const VoiceBubble({
    super.key,
    required this.message,
    required this.radius,
    required this.mine,
  });

  final ChatMessage message;
  final BorderRadius radius;
  final bool mine;

  /// Ink for a bubble that is either the bright gradient or the dark glass.
  Color get _ink => mine ? const Color(0xFF04121F) : AppColors.textPrimary;

  @override
  Widget build(BuildContext context) {
    final player = VoicePlayer.instance;
    final url = message.attachment?.url;
    final id = message.remoteId ?? message.id;

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width * 0.72,
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 9, 14, 9),
        decoration: BoxDecoration(
          borderRadius: radius,
          gradient: mine ? AppColors.safeGradient : null,
          color: mine ? null : Colors.white.withValues(alpha: 0.07),
          border: mine
              ? null
              : Border.all(color: Colors.white.withValues(alpha: 0.09)),
        ),
        child: AnimatedBuilder(
          animation: player,
          builder: (context, _) {
            final playing = player.isPlaying(id);
            final loading = player.isLoading(id);

            // While this note is the one playing, position drives the fill;
            // otherwise it sits at zero. Its own recorded duration is the
            // measure, so an unplayed note still shows its true length.
            final total = player.isCurrent(id)
                ? (player.duration ?? _recorded)
                : _recorded;

            final progress = player.isCurrent(id) && total.inMilliseconds > 0
                ? player.positionOf(id).inMilliseconds / total.inMilliseconds
                : 0.0;

            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _PlayButton(
                  playing: playing,
                  loading: loading,
                  mine: mine,
                  // Nothing to play until the upload finishes and the server
                  // hands back a URL.
                  onTap: url == null ? null : () => player.toggle(id, url),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _Waveform(
                      bars: _bars,
                      progress: progress.clamp(0.0, 1.0),
                      mine: mine,
                      // Tapping partway along seeks there, the same as
                      // dragging — a waveform that cannot be scrubbed is a
                      // picture, not a control.
                      onSeek: player.isCurrent(id)
                          ? (fraction) => player.seekFraction(id, fraction)
                          : null,
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        Text(
                          _clock(player.isCurrent(id) && progress > 0
                              ? player.positionOf(id)
                              : _recorded),
                          style: TextStyle(
                            fontSize: 11,
                            fontFeatures: const [
                              FontFeature.tabularFigures(),
                            ],
                            color: _ink.withValues(alpha: 0.75),
                          ),
                        ),
                        if (player.isCurrent(id)) ...[
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: player.cycleSpeed,
                            behavior: HitTestBehavior.opaque,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                color: _ink.withValues(alpha: 0.14),
                              ),
                              child: Text(
                                '${_trim(player.speed)}×',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: _ink.withValues(alpha: 0.85),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Duration get _recorded =>
      Duration(milliseconds: message.attachment?.durationMs ?? 0);

  /// The sender's measured waveform, or a flat placeholder for anything
  /// recorded before waveforms existed.
  List<int> get _bars {
    final waveform = message.attachment?.waveform;

    if (waveform == null || waveform.isEmpty) {
      return List.filled(40, 22);
    }

    return waveform;
  }

  static String _clock(Duration d) {
    final minutes = d.inMinutes;
    final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');

    return '$minutes:$seconds';
  }

  static String _trim(double speed) =>
      speed == speed.roundToDouble() ? '${speed.round()}' : '$speed';
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({
    required this.playing,
    required this.loading,
    required this.mine,
    required this.onTap,
  });

  final bool playing;
  final bool loading;
  final bool mine;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ink = mine ? const Color(0xFF04121F) : AppColors.textPrimary;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: ink.withValues(alpha: mine ? 0.16 : 0.1),
        ),
        child: loading
            ? SizedBox(
                width: 15,
                height: 15,
                child: CircularProgressIndicator(
                  strokeWidth: 1.8,
                  valueColor: AlwaysStoppedAnimation(ink.withValues(alpha: 0.8)),
                ),
              )
            : Icon(
                playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                size: 21,
                color: onTap == null ? ink.withValues(alpha: 0.4) : ink,
              ),
      ),
    );
  }
}

/// The bars, filled up to the playhead.
class _Waveform extends StatelessWidget {
  const _Waveform({
    required this.bars,
    required this.progress,
    required this.mine,
    required this.onSeek,
  });

  final List<int> bars;
  final double progress;
  final bool mine;
  final void Function(double fraction)? onSeek;

  static const double _width = 152;
  static const double _height = 26;

  @override
  Widget build(BuildContext context) {
    final ink = mine ? const Color(0xFF04121F) : AppColors.textPrimary;

    return GestureDetector(
      onTapDown: onSeek == null
          ? null
          : (details) => onSeek!(details.localPosition.dx / _width),
      onHorizontalDragUpdate: onSeek == null
          ? null
          : (details) => onSeek!(details.localPosition.dx / _width),
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: _width,
        height: _height,
        child: CustomPaint(
          painter: _WaveformPainter(
            bars: bars,
            progress: progress,
            played: ink,
            unplayed: ink.withValues(alpha: 0.32),
          ),
        ),
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  const _WaveformPainter({
    required this.bars,
    required this.progress,
    required this.played,
    required this.unplayed,
  });

  final List<int> bars;
  final double progress;
  final Color played;
  final Color unplayed;

  @override
  void paint(Canvas canvas, Size size) {
    if (bars.isEmpty) return;

    const gap = 1.6;
    final width = (size.width - gap * (bars.length - 1)) / bars.length;
    final playedTo = size.width * progress;

    var x = 0.0;

    for (final bar in bars) {
      // A minimum height, so a silent moment is still a mark on the line and
      // the waveform reads as one shape rather than as gaps.
      final height = (bar / 100 * size.height).clamp(3.0, size.height);
      final top = (size.height - height) / 2;

      final paint = Paint()
        ..color = x + width / 2 <= playedTo ? played : unplayed
        ..style = PaintingStyle.fill;

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, top, width, height),
          Radius.circular(width / 2),
        ),
        paint,
      );

      x += width + gap;
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter old) =>
      old.progress != progress ||
      old.bars != bars ||
      old.played != played ||
      old.unplayed != unplayed;
}
