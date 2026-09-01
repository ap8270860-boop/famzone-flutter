import 'dart:async';
import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// A finished recording, on its way to becoming a message.
@immutable
class VoiceNote {
  const VoiceNote({
    required this.path,
    required this.duration,
    required this.waveform,
  });

  final String path;
  final Duration duration;

  /// [VoiceRecorder.bars] values, 0–100. Measured here and sent with the
  /// message so the other person's bubble can draw the same picture without
  /// downloading or decoding a single byte of audio.
  final List<int> waveform;

  int get durationMs => duration.inMilliseconds;
}

enum RecordingState {
  idle,

  /// Finger still down. Sliding left cancels, sliding up locks.
  recording,

  /// Hands free. The gesture is over and the buttons take charge.
  locked,
}

/// Recording a voice note.
///
/// One of these per chat screen, disposed with it — see [dispose], which has
/// to stop the recorder as well as the notifier. A recorder left running
/// holds the microphone until the app is killed, and on iOS holds the audio
/// session with it, which silences everything else in the app.
class VoiceRecorder extends ChangeNotifier {
  final AudioRecorder _recorder = AudioRecorder();

  StreamSubscription<Amplitude>? _amplitudes;
  Timer? _ticker;

  RecordingState _state = RecordingState.idle;
  Duration _elapsed = Duration.zero;
  String? _path;

  /// Every amplitude sample of the current recording, 0–1.
  final List<double> _levels = [];

  /// How many bars a finished waveform carries.
  ///
  /// Enough to show the shape of a sentence, few enough to draw at 3px a bar
  /// inside a chat bubble on a small phone.
  static const int bars = 56;

  /// Anything shorter is a mis-tap, not a message.
  static const Duration minimum = Duration(milliseconds: 900);

  /// Hard stop, matching the server's `duration_ms` validation.
  static const Duration maximum = Duration(minutes: 10);

  /// How often the amplitude is sampled. ~16 a second: fine enough for a
  /// waveform that follows speech, coarse enough not to matter.
  static const Duration _sampleEvery = Duration(milliseconds: 60);

  RecordingState get state => _state;
  bool get isActive => _state != RecordingState.idle;
  bool get isLocked => _state == RecordingState.locked;
  Duration get elapsed => _elapsed;

  /// The tail of the samples, for the live bar display.
  List<double> get live {
    const window = 34;

    if (_levels.length <= window) return List.unmodifiable(_levels);

    return List.unmodifiable(_levels.sublist(_levels.length - window));
  }

  /// Begin. Returns false when the microphone was refused.
  ///
  /// [AudioRecorder.hasPermission] both checks and asks, so there is no
  /// separate permission plugin here.
  Future<bool> start() async {
    if (isActive) return true;

    if (!await _recorder.hasPermission()) return false;

    /*
     | One session configuration for recording *and* playback.
     |
     | speech() is playAndRecord with defaultToSpeaker, which is the whole
     | fix for the classic iOS bug where a voice note plays back through the
     | earpiece at a quarter of the volume because the session was left in
     | recording mode.
     */
    final session = await AudioSession.instance;

    await session.configure(const AudioSessionConfiguration.speech());
    await session.setActive(true);

    final directory = await getTemporaryDirectory();
    final path =
        '${directory.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';

    /*
     | AAC-LC in an m4a container, mono, 24 kHz, 32 kbps.
     |
     | Not Opus, though it is smaller and is what WhatsApp uses: on iOS this
     | package writes Opus into a CAF container that Android will not open,
     | so an iPhone note would arrive as silence. AAC-LC is the one encoding
     | both platforms record *and* play natively. About 240 KB a minute.
     */
    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 32000,
        sampleRate: 24000,
        numChannels: 1,
      ),
      path: path,
    );

    _path = path;
    _state = RecordingState.recording;
    _elapsed = Duration.zero;
    _levels.clear();

    _amplitudes = _recorder
        .onAmplitudeChanged(_sampleEvery)
        .listen(_onAmplitude, onError: (_) {});

    _ticker = Timer.periodic(const Duration(milliseconds: 200), (_) {
      _elapsed += const Duration(milliseconds: 200);

      // A recording nobody stopped stops itself, rather than filling the
      // disk and failing the upload ten minutes later.
      if (_elapsed >= maximum) {
        unawaited(stop());

        return;
      }

      notifyListeners();
    });

    notifyListeners();

    return true;
  }

  void _onAmplitude(Amplitude amplitude) {
    /*
     | dBFS, so 0 is as loud as the hardware goes and silence is a large
     | negative number. Mapped across the last 50 dB, which is where a voice
     | held at arm's length actually lands; anything quieter is room noise
     | and belongs at the bottom of the scale rather than spread across it.
     */
    final level = ((amplitude.current + 50) / 50).clamp(0.0, 1.0);

    _levels.add(level.toDouble());
  }

  /// Hands free: the finger has slid up and let go, but recording continues.
  void lock() {
    if (_state != RecordingState.recording) return;

    _state = RecordingState.locked;
    notifyListeners();
  }

  /// Stop and keep it.
  ///
  /// Returns null when the recording was too short to be a message — that
  /// case is a tap on the microphone, not a voice note, and is thrown away
  /// rather than sent as a quarter-second of nothing.
  Future<VoiceNote?> stop() async {
    if (!isActive) return null;

    final elapsed = _elapsed;
    final levels = List<double>.from(_levels);

    await _teardown();

    final path = await _recorder.stop();

    _path = null;
    _state = RecordingState.idle;
    _elapsed = Duration.zero;
    _levels.clear();

    notifyListeners();

    if (path == null) return null;

    if (elapsed < minimum) {
      await _delete(path);

      return null;
    }

    return VoiceNote(
      path: path,
      duration: elapsed,
      waveform: _downsample(levels),
    );
  }

  /// Throw it away.
  ///
  /// The file is deleted, not merely forgotten. A cancelled recording left on
  /// disk is a privacy problem rather than a housekeeping one — the person
  /// pressed cancel precisely so that it would not exist.
  Future<void> cancel() async {
    if (!isActive) return;

    final path = _path;

    await _teardown();
    await _recorder.cancel();

    if (path != null) await _delete(path);

    _path = null;
    _state = RecordingState.idle;
    _elapsed = Duration.zero;
    _levels.clear();

    notifyListeners();
  }

  Future<void> _teardown() async {
    _ticker?.cancel();
    _ticker = null;

    await _amplitudes?.cancel();
    _amplitudes = null;
  }

  Future<void> _delete(String path) async {
    try {
      final file = File(path);

      if (file.existsSync()) await file.delete();
    } catch (_) {
      // Best effort. A temp file that outlives us is swept by the OS.
    }
  }

  /// Squash however many samples were taken into [bars] of them.
  ///
  /// Peak per bucket rather than average: a waveform is meant to show where
  /// the loud parts were, and averaging flattens a sentence into a smear.
  List<int> _downsample(List<double> levels) {
    if (levels.isEmpty) return List.filled(bars, 4);

    final out = <int>[];
    final per = levels.length / bars;

    for (var i = 0; i < bars; i++) {
      final from = (i * per).floor();
      final to = ((i + 1) * per).ceil().clamp(from + 1, levels.length);

      var peak = 0.0;

      for (var j = from; j < to; j++) {
        if (levels[j] > peak) peak = levels[j];
      }

      // A floor of 4, so silence still draws a hairline instead of a gap
      // that reads as a rendering bug.
      out.add((peak * 100).round().clamp(4, 100));
    }

    return out;
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _amplitudes?.cancel();

    // Leaving the screen mid-recording must release the microphone. On iOS
    // it also releases the audio session, without which the rest of the app
    // stays silent.
    if (isActive) unawaited(_recorder.cancel());

    unawaited(_recorder.dispose());

    super.dispose();
  }
}
