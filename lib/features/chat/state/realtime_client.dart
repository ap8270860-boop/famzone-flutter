import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../core/config/app_config.dart';
import '../../../core/realtime/reverb_socket.dart';
import '../../../core/session/session.dart';
import '../../location/state/location_store.dart';
import '../../safety/state/safety_store.dart';
import '../../sos/state/sos_store.dart';
import '../data/chat_api.dart';
import 'chat_store.dart';

/// The app's one websocket connection.
///
/// Opened when somebody signs in, closed when they sign out, and subscribed
/// for that whole time to their own mailbox channel — which is why the unread
/// badge is right whether or not a chat screen is open. Individual
/// conversations subscribe and unsubscribe on top of it as their screens come
/// and go.
///
/// If no Reverb key is configured the whole thing stays dormant and the app
/// behaves exactly as it did before the socket existed: messages still send
/// over HTTP, screens still refresh. That is deliberate — the realtime layer
/// is an accelerator, and it should be possible to ship without it.
class RealtimeClient extends ChangeNotifier {
  RealtimeClient._() {
    Session.instance.onSignOut(stop);
  }

  static final RealtimeClient instance = RealtimeClient._();

  ReverbSocket? _socket;

  final ChatApi _api = ChatApi();
  Timer? _heartbeat;

  SocketStatus get status => _socket?.status.value ?? SocketStatus.idle;

  /// True only while a connection is expected but absent — what a
  /// "Connecting…" strip should key off. Idle is not a problem: it means the
  /// socket was never asked to run.
  bool get reconnecting =>
      status == SocketStatus.connecting || status == SocketStatus.reconnecting;

  bool get enabled => AppConfig.realtimeEnabled;

  /*
  |----------------------------------------------------------------------------
  | Lifecycle
  |----------------------------------------------------------------------------
  */

  /// Open the connection and join the signed-in user's mailbox.
  ///
  /// Safe to call repeatedly — on app start, on returning to the foreground,
  /// after signing in. A live socket is left alone.
  Future<void> start() async {
    if (!enabled || _socket != null) return;

    final me = Session.instance.user;

    if (me == null) return;

    final socket = ReverbSocket(
      key: AppConfig.reverbKey,
      host: AppConfig.reverbHost,
      port: AppConfig.reverbPort,
      useTls: AppConfig.reverbTls,
      authorize: _authorize,
    );

    _socket = socket;

    socket.status.addListener(notifyListeners);

    await socket.connect();
    await socket.subscribe('private-user.${me.id}', _onMailbox);

    _startHeartbeat();
  }

  /*
  |----------------------------------------------------------------------------
  | Presence heartbeat
  |----------------------------------------------------------------------------
  */

  /// Tell the server we are here, every 45 seconds.
  ///
  /// Deliberately a heartbeat rather than a global presence channel. A
  /// presence channel broadcasts every join and leave to every member: with a
  /// thousand signed-in users that is a million frames of pure churn, and it
  /// grows with the square of the user count. Being online is a fact about
  /// one person, not a room they are standing in.
  ///
  /// The server counts somebody as online for 75 seconds after a ping —
  /// wider than this interval on purpose, so one dropped request does not
  /// flicker them offline and back.
  void _startHeartbeat() {
    _heartbeat?.cancel();

    _ping();

    _heartbeat = Timer.periodic(
      const Duration(seconds: 45),
      (_) => _ping(),
    );
  }

  Future<void> _ping() async {
    if (!Session.instance.isAuthenticated) return;

    try {
      await _api.ping();
    } catch (_) {
      // Presence is the least important thing in the app. A missed heartbeat
      // costs a stale "last seen" for a minute and nothing else, so it is
      // never worth surfacing.
    }
  }

  /// Called when the app comes back to the foreground.
  ///
  /// Starts the connection if it was never opened, and otherwise checks the
  /// one we have rather than trusting it — see [ReverbSocket.poke].
  Future<void> resume() async {
    if (!enabled) return;

    final socket = _socket;

    if (socket == null) return start();

    socket.poke();

    // Ping immediately as well. The periodic timer was frozen while the
    // process was suspended, so without this the user looks offline to
    // everybody else for up to 45 seconds after unlocking their phone.
    _startHeartbeat();
  }

  /// Drop everything. Registered against sign-out in the constructor, so the
  /// next account never inherits the last one's subscriptions.
  Future<void> stop() async {
    _heartbeat?.cancel();
    _heartbeat = null;

    final socket = _socket;

    _socket = null;

    if (socket == null) return;

    socket.status.removeListener(notifyListeners);

    await socket.stop();

    notifyListeners();
  }

  /*
  |----------------------------------------------------------------------------
  | Conversations
  |----------------------------------------------------------------------------
  */

  /// Join a thread's channel. Called by [ConversationStore] when its screen
  /// opens; the matching [leaveConversation] runs when the screen closes.
  Future<void> joinConversation(String uuid, ChannelHandler onEvent) async {
    await start();
    await _socket?.subscribe('private-conversation.$uuid', onEvent);
  }

  Future<void> leaveConversation(String uuid) async {
    await _socket?.unsubscribe('private-conversation.$uuid');
  }

  /// Join a thread's presence channel — who is looking at it, and where
  /// typing is whispered.
  ///
  /// Separate from the message channel because the two behave nothing alike:
  /// the message channel is silent until somebody writes, while presence
  /// churns on every open and close of the screen. Keeping them apart also
  /// means a presence problem can never cost anybody a message.
  Future<void> joinRoom(String uuid, ChannelHandler onEvent) async {
    await start();
    await _socket?.subscribe('presence-room.$uuid', onEvent);
  }

  Future<void> leaveRoom(String uuid) async {
    await _socket?.unsubscribe('presence-room.$uuid');
  }

  /*
  |----------------------------------------------------------------------------
  | Location
  |----------------------------------------------------------------------------
  */

  /// Follow one person's position.
  ///
  /// The channel is named after the person being watched, not the person
  /// watching — so six family members following one phone is one frame out of
  /// the server rather than six, and a seventh watcher costs the broadcaster
  /// nothing.
  ///
  /// Authorisation happens server-side on subscribe, against a live share.
  /// There is no client-side filtering here, and there must not be: a frame
  /// that reaches a client that should not have it has already leaked.
  Future<void> joinLocation(String userUuid, ChannelHandler onEvent) async {
    await start();
    await _socket?.subscribe('private-location.$userUuid', onEvent);
  }

  Future<void> leaveLocation(String userUuid) async {
    await _socket?.unsubscribe('private-location.$userUuid');
  }

  /// Say whether we are typing, straight to the other subscriber.
  ///
  /// Reverb relays client events without waking PHP, touching the database or
  /// queueing anything. A typing indicator routed through HTTP would cost
  /// several requests per second per typing user, for a fact that is
  /// worthless one second later.
  void whisperTyping(String conversationUuid, {required bool typing}) {
    _socket?.whisper(
      'presence-room.$conversationUuid',
      'client-typing',
      {
        'state': typing ? 'typing' : 'stopped',

        /*
         | Who is typing, so a group can name them.
         |
         | The id and not the name: a whisper is relayed by Reverb without
         | passing through the server, so anything in it is whatever the
         | sending client chose to put there. An id is checked against the
         | member list the server sent; a name would be taken on trust and
         | could say anything.
         */
        'user_id': Session.instance.user?.id,
      },
    );
  }

  /*
  |----------------------------------------------------------------------------
  | The mailbox
  |----------------------------------------------------------------------------
  */

  void _onMailbox(String event, Map<String, dynamic> data) {
    switch (event) {
      case 'inbox.updated':
        // A full conversation summary, the same shape the inbox endpoint
        // returns, so the store folds it in without a round trip.
        ChatStore.instance.applyInboxEvent(data);

        return;

      case 'sos.raised':
        /*
         | A family member raised an alarm.
         |
         | Handed to the store rather than pushed onto the navigator: the
         | banner has to survive whatever screen the person is on, and an
         | alarm that can be dismissed with the back gesture is not an alarm.
         */
        SosStore.instance.applyIncoming(data);

        return;

      case 'sos.ended':
        SosStore.instance.clearIncoming(data);

        return;

      case 'location.share.started':
        /*
         | Somebody started sharing with me.
         |
         | On the mailbox rather than the location channel because it has to
         | reach me *before* I am subscribed to their channel — being told to
         | subscribe is the whole point of the event.
         */
        LocationStore.instance.applyShareStarted(data);

        return;

      case 'location.share.ended':
        LocationStore.instance.applyShareEnded(data);

        return;

      case 'place.crossed':
        /*
         | Somebody arrived at or left one of my places.
         |
         | On the mailbox because a place belongs to me and the crossing is
         | news about *my* geofence — it has nothing to do with the channel
         | the person who moved is broadcasting on, and they may not be
         | broadcasting on one at all.
         */
        LocationStore.instance.applyPlaceCrossing(data);

        return;

      case 'check_in.requested':
        /*
         | A family member checked in and it is my turn to confirm.
         |
         | On the mailbox and sent to exactly one person — whoever currently
         | holds the request. The chain's whole purpose is that the second
         | person is not disturbed while the first still has it, so this is
         | never a broadcast to the family.
         |
         | The store also holds the durable list, refreshed on every app open,
         | so a frame missed while the socket was down costs nothing.
         */
        SafetyStore.instance.applyIncomingRequest(data);

        return;

      case 'check_in.acknowledged':
        /*
         | Somebody answered my check-in, or my whole list ran out.
         |
         | One event for both endings — the client's job either way is to
         | replace the chain it is holding with the one in this frame, and two
         | handlers would be two chances to forget one.
         |
         | This is what makes the progress bar move while somebody is watching
         | it, which is the entire reason the frame exists.
         */
        SafetyStore.instance.applyChain(data);

        return;

      case 'conversation.closed':
        final id = data['conversation_id'] as String?;

        if (id != null) ChatStore.instance.removeThread(id);

        return;

      case 'subscription_succeeded':
        /*
         | Fires on first connect and again after every reconnect, which makes
         | it the natural place to reconcile. Anything that happened while the
         | socket was down was never delivered and never will be — the only
         | way to learn about it is to ask.
         |
         | Skipped on the very first subscribe, where the inbox is loading
         | anyway and this would be a duplicate request.
         */
        if (ChatStore.instance.loaded) ChatStore.instance.refresh();

        return;
    }
  }

  /*
  |----------------------------------------------------------------------------
  | Channel authorisation
  |----------------------------------------------------------------------------
  */

  /// Sign a private or presence subscription with the session's bearer token.
  ///
  /// Deliberately not routed through [ApiClient]: `/broadcasting/auth` is the
  /// one endpoint in the system that does not answer with the standard
  /// envelope — it replies with a bare `{"auth": "..."}` — and teaching the
  /// shared client about an exception would be worse than the ten lines here.
  Future<Map<String, String>?> _authorize(String channel, String socketId) async {
    final token = Session.instance.token;

    if (token == null) return null;

    // Network failures are deliberately left to propagate. The socket treats
    // a thrown request as transient and retries on its next connect, whereas
    // null means the server actually refused — two different things that must
    // not be collapsed into one.
    final response = await http
        .post(
          Uri.parse('${AppConfig.apiBaseUrl}/broadcasting/auth'),
          headers: {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode({
            'socket_id': socketId,
            'channel_name': channel,
          }),
        )
        .timeout(AppConfig.requestTimeout);

    // 403 means the server said no.
    if (response.statusCode != 200) return null;

    try {
      final decoded = jsonDecode(response.body);

      if (decoded is! Map<String, dynamic>) return null;

      final auth = decoded['auth'];

      if (auth is! String) return null;

      return {
        'auth': auth,
        if (decoded['channel_data'] is String)
          'channel_data': decoded['channel_data'] as String,
      };
    } catch (_) {
      return null;
    }
  }
}
