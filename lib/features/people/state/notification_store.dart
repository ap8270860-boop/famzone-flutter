import 'package:flutter/foundation.dart';

import '../../../core/session/session.dart';
import '../../safety/data/safety_api.dart';
import '../../safety/state/safety_store.dart';
import '../data/people_api.dart';
import '../data/people_models.dart';
import 'family_store.dart';

/// The notification feed and its unread badge.
///
/// The badge is read from every screen and the feed from one, so both live
/// here rather than inside the notifications page — the bell on the home
/// header has to light up without that page ever having been opened.
class NotificationStore extends ChangeNotifier {
  NotificationStore._();

  static final NotificationStore instance = NotificationStore._();

  final PeopleApi _api = PeopleApi();

  /// Check-in requests are answered against the safety endpoints, not the
  /// people ones — see [respond].
  final SafetyApi _safety = SafetyApi();

  List<AppNotification> _items = const [];
  int _unread = 0;
  bool _loading = false;
  bool _loaded = false;

  /// Ids currently being accepted or declined, so each row can show its own
  /// spinner without freezing the whole list.
  final Set<String> _busy = {};

  List<AppNotification> get items => _items;
  int get unread => _unread;
  bool get loading => _loading && !_loaded;
  bool get isEmpty => _loaded && _items.isEmpty;

  bool isBusy(String id) => _busy.contains(id);

  /// Cheap enough to call on every app open and tab switch — it is a single
  /// indexed count, not the feed.
  Future<void> refreshBadge() async {
    if (!Session.instance.isAuthenticated) return;

    try {
      final res = await _api.unreadCount();

      if (res.success) {
        final next = res.dataMap['unread'] as int? ?? 0;

        if (next != _unread) {
          _unread = next;
          notifyListeners();
        }
      }
    } catch (_) {
      // Badge stays as it was.
    }
  }

  Future<void> load() async {
    if (!Session.instance.isAuthenticated || _loading) return;

    _loading = true;

    try {
      final res = await _api.notifications();

      if (res.success) {
        _items = (res.dataMap['notifications'] as List?)
                ?.whereType<Map<String, dynamic>>()
                .map(AppNotification.fromJson)
                .toList() ??
            const [];

        _unread = res.dataMap['unread'] as int? ?? 0;
        _loaded = true;
      }
    } catch (_) {
      // Keep the current list.
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Answer a follow request or a family invite from inside the feed.
  ///
  /// Reloads afterwards rather than patching the row locally: accepting
  /// changes the family list and the badge as well, and one reload keeps all
  /// three honest. The row's own spinner covers the wait.
  Future<String?> respond({
    required AppNotification notification,
    required bool accept,
  }) async {
    final action = notification.action;

    if (action == null || _busy.contains(notification.id)) return null;

    _busy.add(notification.id);
    notifyListeners();

    try {
      /*
       | Three kinds of request, three endpoints.
       |
       | A check-in is the one that does not go through PeopleApi: it belongs
       | to safety, and answering it has to move SafetyStore's incoming list
       | as well as this feed — the same request is on the home screen with
       | the same two buttons, and leaving it there after it was answered here
       | would be the exact stale-button bug this whole derived-action design
       | exists to prevent.
       */
      final res = action.isCheckInRequest
          ? await _safety.respondToRequest(action.id, accept)
          : action.isFollowRequest
              ? await _api.respondToFollowRequest(action.id, accept)
              : await _api.respondToFamilyInvite(action.id, accept);

      if (res.success) {
        await load();

        if (action.isCheckInRequest) {
          await SafetyStore.instance.loadIncoming();
        } else if (!action.isFollowRequest && accept) {
          // Accepting a family invite changes the home strip too.
          await FamilyStore.instance.load();
        }
      }

      return res.message;
    } catch (_) {
      return 'Could not reach the server. Try again.';
    } finally {
      _busy.remove(notification.id);
      notifyListeners();
    }
  }

  Future<void> markAllRead() async {
    if (_unread == 0) return;

    _unread = 0;
    notifyListeners();

    try {
      await _api.markAllRead();
      await load();
    } catch (_) {
      // The next badge refresh will put the true count back.
    }
  }

  void clear() {
    _items = const [];
    _unread = 0;
    _loaded = false;
    _busy.clear();
    notifyListeners();
  }
}
