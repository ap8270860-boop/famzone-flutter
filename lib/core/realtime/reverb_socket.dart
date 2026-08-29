import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as ws_status;

/// Where the connection currently is.
enum SocketStatus { idle, connecting, connected, reconnecting, failed }

/// What a channel subscription is handed when a frame arrives for it.
typedef ChannelHandler = void Function(String event, Map<String, dynamic> data);

/// The signature the app supplies to sign a private or presence subscription.
///
/// Returns the map Laravel's `/broadcasting/auth` replies with — `auth`, and
/// `channel_data` for presence channels — or null when the server refused,
/// which is a real answer and not an error.
typedef ChannelAuthorizer = Future<Map<String, String>?> Function(
  String channel,
  String socketId,
);

/// A Pusher-protocol client, written against the protocol rather than a
/// vendor SDK.
///
/// The official `pusher_channels_flutter` package cannot be pointed at a
/// self-hosted server — its `init()` takes a `cluster` and no host — so it
/// can only ever reach Pusher's cloud. The community forks that add a host
/// parameter are each one maintainer deep, which is a thin foundation for
/// the most important feature in the app.
///
/// Protocol 7 is small, frozen, and Reverb implements it faithfully, so the
/// whole client is this file: connect, authorise, subscribe, dispatch,
/// whisper, heartbeat, reconnect. Owning it means the reconnect behaviour is
/// ours to tune and a Flutter upgrade cannot strand us.
class ReverbSocket {
  ReverbSocket({
    required this.key,
    required this.host,
    required this.port,
    required this.useTls,
    required this.authorize,
  });

  final String key;
  final String host;
  final int port;
  final bool useTls;
  final ChannelAuthorizer authorize;

  /// Observable so a screen can show a "Connecting…" strip. A
  /// [ValueNotifier] rather than a stream: there is exactly one current
  /// state, and late listeners should see it rather than wait for a change.
  final ValueNotifier<SocketStatus> status =
      ValueNotifier(SocketStatus.idle);

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _frames;

  String? _socketId;

  /// Channels we want to be on. Kept separately from what the server has
  /// confirmed, because after a reconnect this is the list to replay.
  final Map<String, ChannelHandler> _wanted = {};
  final Set<String> _joined = {};

  Timer? _heartbeat;
  Timer? _watchdog;
  Timer? _retry;

  int _attempt = 0;
  bool _stopped = false;

  String? get socketId => _socketId;
  bool get isConnected => status.value == SocketStatus.connected;

  /*
  |----------------------------------------------------------------------------
  | Lifecycle
  |----------------------------------------------------------------------------
  */

  Future<void> connect() async {
    if (_stopped) return;
    if (status.value == SocketStatus.connecting ||
        status.value == SocketStatus.connected) {
      return;
    }

    status.value =
        _attempt == 0 ? SocketStatus.connecting : SocketStatus.reconnecting;

    // The Pusher handshake URL. `protocol=7` is what Reverb speaks; the
    // client and version strings are only ever echoed back in logs.
    final uri = Uri(
      scheme: useTls ? 'wss' : 'ws',
      host: host,
      port: port,
      path: '/app/$key',
      queryParameters: {
        'protocol': '7',
        'client': 'sfamily-flutter',
        'version': '1.0',
      },
    );

    try {
      final channel = WebSocketChannel.connect(uri);

      _channel = channel;

      _frames = channel.stream.listen(
        _onFrame,
        onError: (Object _) => _dropped(),
        onDone: _dropped,
        cancelOnError: true,
      );
    } catch (_) {
      _dropped();
    }
  }

  /// Check on the connection right now, ignoring the backoff schedule.
  ///
  /// Called when the app returns to the foreground, and it matters more than
  /// it looks. Dart timers do not run while a process is suspended, so a
  /// socket that died overnight leaves a pending retry that fires whenever it
  /// happens to get around to it — up to half a minute after the phone is
  /// unlocked, during which the chat is silently dead.
  void poke() {
    if (_stopped) return;

    if (isConnected) {
      // A suspended process can hold a connection that will never deliver
      // anything again, and the OS reports it as perfectly healthy. Ping it
      // and give it a short deadline instead of the usual one: a pong resets
      // the watchdog to normal, and silence gets us reconnecting in seconds
      // rather than in a minute.
      _send({'event': 'pusher:ping', 'data': {}});

      _watchdog?.cancel();
      _watchdog = Timer(const Duration(seconds: 5), _dropped);

      return;
    }

    _retry?.cancel();
    _attempt = 0;

    connect();
  }

  /// Close for good. Used on sign-out.
  Future<void> stop() async {
    _stopped = true;

    _retry?.cancel();
    _heartbeat?.cancel();
    _watchdog?.cancel();

    _wanted.clear();
    _joined.clear();
    _socketId = null;

    await _frames?.cancel();
    _frames = null;

    await _channel?.sink.close(ws_status.normalClosure);
    _channel = null;

    status.value = SocketStatus.idle;
  }

  /*
  |----------------------------------------------------------------------------
  | Channels
  |----------------------------------------------------------------------------
  */

  /// Join a channel, now or as soon as there is a connection.
  ///
  /// Safe to call before connecting and safe to call twice: the wanted-set is
  /// the source of truth and the server is brought into line with it.
  Future<void> subscribe(String channel, ChannelHandler onEvent) async {
    _wanted[channel] = onEvent;

    if (isConnected && !_joined.contains(channel)) {
      await _join(channel);
    }
  }

  Future<void> unsubscribe(String channel) async {
    _wanted.remove(channel);

    if (!_joined.remove(channel)) return;

    _send({
      'event': 'pusher:unsubscribe',
      'data': {'channel': channel},
    });
  }

  /// Send a client event straight to the other subscribers.
  ///
  /// Relayed by Reverb without waking PHP, which is why typing indicators are
  /// whispers rather than requests: they never touch the database, and
  /// something worthless one second later has no business in a queue.
  ///
  /// Only private and presence channels accept these.
  void whisper(String channel, String event, Map<String, dynamic> data) {
    if (!_joined.contains(channel)) return;

    _send({
      'event': event.startsWith('client-') ? event : 'client-$event',
      'channel': channel,
      'data': data,
    });
  }

  Future<void> _join(String channel) async {
    final socketId = _socketId;

    if (socketId == null) return;

    final payload = <String, dynamic>{'channel': channel};

    if (channel.startsWith('private-') || channel.startsWith('presence-')) {
      Map<String, String>? auth;

      try {
        auth = await authorize(channel, socketId);
      } catch (_) {
        // A failed request is not a refusal. The channel stays wanted and is
        // retried on the next connect — dropping it here would mean one
        // flaky moment silently costs the user their live messages until
        // they reopen the screen.
        return;
      }

      // Null is a refusal, and a refusal is an answer. Drop the channel
      // rather than retrying into a wall: the usual cause is a block or a
      // thread the user has left, and neither resolves by asking again.
      if (auth == null) {
        _wanted.remove(channel);

        return;
      }

      payload['auth'] = auth['auth'];

      if (auth['channel_data'] != null) {
        payload['channel_data'] = auth['channel_data'];
      }
    }

    _joined.add(channel);
    _send({'event': 'pusher:subscribe', 'data': payload});
  }

  /*
  |----------------------------------------------------------------------------
  | Frames
  |----------------------------------------------------------------------------
  */

  void _onFrame(dynamic raw) {
    _armWatchdog();

    final frame = _decode(raw);

    if (frame == null) return;

    final event = frame['event'] as String? ?? '';
    final channel = frame['channel'] as String?;
    final data = _payload(frame['data']);

    switch (event) {
      case 'pusher:connection_established':
        _socketId = data['socket_id'] as String?;
        _attempt = 0;
        status.value = SocketStatus.connected;
        _startHeartbeat();

        // Replay everything wanted. After a reconnect this is what puts the
        // open chat screen and the inbox back on their channels without
        // either of them knowing the connection ever dropped.
        for (final name in _wanted.keys.toList()) {
          _join(name);
        }

        return;

      case 'pusher:ping':
        _send({'event': 'pusher:pong', 'data': {}});

        return;

      case 'pusher:pong':
        return;

      case 'pusher:error':
        _onProtocolError(data);

        return;
    }

    if (channel == null) return;

    // Presence bookkeeping arrives under pusher_internal:. Passed through
    // with the vendor prefix stripped so callers deal in one vocabulary.
    final name = event.startsWith('pusher_internal:')
        ? event.replaceFirst('pusher_internal:', '')
        : event;

    _wanted[channel]?.call(name, data);
  }

  Map<String, dynamic>? _decode(dynamic raw) {
    if (raw is! String) return null;

    try {
      final decoded = jsonDecode(raw);

      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  /// Unwrap a `data` field.
  ///
  /// The protocol double-encodes it: `data` is a JSON *string* containing the
  /// real object. Some servers send it already decoded, so both are handled
  /// rather than assumed.
  Map<String, dynamic> _payload(dynamic data) {
    if (data is Map<String, dynamic>) return data;

    if (data is String && data.isNotEmpty) {
      try {
        final decoded = jsonDecode(data);

        if (decoded is Map<String, dynamic>) return decoded;
      } catch (_) {
        // Not JSON. Nothing we send takes that form.
      }
    }

    return const {};
  }

  void _onProtocolError(Map<String, dynamic> data) {
    final code = data['code'];

    // 4000–4099 are refusals: a bad application key, an unsupported protocol
    // version. Reconnecting changes nothing and a retry loop against them is
    // just a battery drain with extra steps.
    if (code is int && code >= 4000 && code < 4100) {
      status.value = SocketStatus.failed;
      _stopped = true;
      _heartbeat?.cancel();
      _watchdog?.cancel();

      return;
    }

    _dropped();
  }

  void _send(Map<String, dynamic> frame) {
    try {
      _channel?.sink.add(jsonEncode(frame));
    } catch (_) {
      _dropped();
    }
  }

  /*
  |----------------------------------------------------------------------------
  | Staying alive
  |----------------------------------------------------------------------------
  */

  /// A socket can be dead for minutes without the OS saying so — a phone that
  /// changed networks holds a connection that will never deliver anything
  /// again. The ping is what turns that into a detectable failure.
  void _startHeartbeat() {
    _heartbeat?.cancel();

    _heartbeat = Timer.periodic(const Duration(seconds: 30), (_) {
      _send({'event': 'pusher:ping', 'data': {}});
    });

    _armWatchdog();
  }

  /// Reset on every frame. If nothing at all arrives for this long — not even
  /// a pong — the connection is gone whatever the socket claims.
  void _armWatchdog() {
    _watchdog?.cancel();
    _watchdog = Timer(const Duration(seconds: 45), _dropped);
  }

  void _dropped() {
    if (_stopped) return;

    _heartbeat?.cancel();
    _watchdog?.cancel();

    _frames?.cancel();
    _frames = null;

    _channel?.sink.close();
    _channel = null;

    _socketId = null;
    _joined.clear();

    status.value = SocketStatus.reconnecting;

    _scheduleRetry();
  }

  /// Exponential backoff, capped at half a minute.
  ///
  /// The cap matters more than the curve: a thousand phones on a flaky
  /// network all retrying every second is how a websocket outage becomes an
  /// API outage too.
  void _scheduleRetry() {
    _retry?.cancel();

    final seconds = [1, 2, 4, 8, 15, 30][_attempt.clamp(0, 5)];

    _attempt++;

    _retry = Timer(Duration(seconds: seconds), connect);
  }

  void dispose() {
    stop();
    status.dispose();
  }
}
