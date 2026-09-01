import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

/// Plays voice notes — one at a time, for the whole app.
///
/// A singleton with a single [AudioPlayer] rather than a player per bubble.
/// Two reasons, and the second is the one that bites: a thread of forty voice
/// notes would otherwise hold forty platform players open, and without a
/// single owner there is nothing to stop two of them playing at once.
///
/// Bubbles listen to this and ask whether they are the one playing.
class VoicePlayer extends ChangeNotifier {
  VoicePlayer._() {
    _player.positionStream.listen((position) {
      _position = position;
      notifyListeners();
    });

    _player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        // Back to the start and stopped, rather than parked at the end —
        // otherwise tapping play again does nothing visible.
        unawaited(_player.pause());
        unawaited(_player.seek(Duration.zero));

        _position = Duration.zero;
        _finished?.call(_messageId);
      }

      notifyListeners();
    });
  }

  static final VoicePlayer instance = VoicePlayer._();

  final AudioPlayer _player = AudioPlayer();

  String? _messageId;
  Duration _position = Duration.zero;
  double _speed = 1;
  bool _loading = false;

  /// Told when a note plays to the end, so a screen can move to the next one.
  void Function(String? messageId)? _finished;

  /// Which message owns the player right now, if any.
  String? get current => _messageId;

  double get speed => _speed;

  bool isCurrent(String messageId) => _messageId == messageId;

  bool isPlaying(String messageId) =>
      _messageId == messageId && _player.playing;

  bool isLoading(String messageId) => _messageId == messageId && _loading;

  /// Where playback has reached in [messageId], or zero if it is not the one
  /// playing. Bubbles use this to fill their waveform.
  Duration positionOf(String messageId) =>
      _messageId == messageId ? _position : Duration.zero;

  /// The real duration once known — a voice note recorded on another device
  /// carries its own, but this is what the progress fill is measured against
  /// while it plays.
  Duration? get duration => _player.duration;

  set onFinished(void Function(String? messageId)? handler) =>
      _finished = handler;

  /// Play [url] for [messageId], or pause it if it is already playing.
  ///
  /// Starting a different message takes the player over — which is exactly
  /// what should happen, and is only possible because there is one of them.
  Future<void> toggle(String messageId, String url) async {
    if (_messageId == messageId) {
      if (_player.playing) {
        await _player.pause();
      } else {
        await _player.play();
      }

      notifyListeners();

      return;
    }

    _messageId = messageId;
    _position = Duration.zero;
    _loading = true;

    notifyListeners();

    try {
      final session = await AudioSession.instance;

      await session.configure(const AudioSessionConfiguration.speech());
      await session.setActive(true);

      await _player.setUrl(url);
      await _player.setSpeed(_speed);

      _loading = false;
      notifyListeners();

      await _player.play();
    } catch (_) {
      _loading = false;
      _messageId = null;

      notifyListeners();
    }
  }

  /// Scrub. [fraction] is 0–1 of the way through.
  Future<void> seekFraction(String messageId, double fraction) async {
    if (_messageId != messageId) return;

    final total = _player.duration;

    if (total == null) return;

    await _player.seek(total * fraction.clamp(0.0, 1.0));
  }

  /// 1× → 1.5× → 2× → 1×.
  Future<void> cycleSpeed() async {
    _speed = switch (_speed) {
      1.0 => 1.5,
      1.5 => 2.0,
      _ => 1.0,
    };

    await _player.setSpeed(_speed);

    notifyListeners();
  }

  /// Let go of the player without disposing it — the singleton outlives any
  /// one screen, but a screen leaving should not keep playing into another.
  Future<void> stop() async {
    if (_messageId == null) return;

    await _player.stop();

    _messageId = null;
    _position = Duration.zero;

    notifyListeners();
  }
}
