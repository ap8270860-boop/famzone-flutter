import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/api/api_response.dart';
import '../../../core/session/session.dart';
import '../data/reminder_models.dart';
import '../data/reminders_api.dart';
import 'reminder_outbox.dart';
import 'reminder_scheduler.dart';

/// Holds the reminders, and keeps the phone's alarms in step with them.
///
/// The second half is the one worth watching. Every path that changes a
/// reminder — creating, editing, pausing, accepting, deleting — ends in
/// [_reschedule], because a list that disagrees with the OS is a reminder that
/// shows on screen and never rings, and that failure is completely silent
/// until somebody misses something.
class ReminderStore extends ChangeNotifier {
  ReminderStore._();

  static final ReminderStore instance = ReminderStore._();

  final RemindersApi _api = RemindersApi();
  final ReminderScheduler _scheduler = ReminderScheduler.instance;

  ReminderCatalogue _catalogue = ReminderCatalogue.empty;
  List<Reminder> _mine = const [];
  List<Reminder> _assignedByMe = const [];
  ReminderDay _today = ReminderDay.empty;
  ReminderScore _score = ReminderScore.empty;

  int _pending = 0;
  int _scheduledCount = 0;
  bool _loading = false;
  bool _loaded = false;
  bool _saving = false;
  String? _error;

  final Set<String> _busy = {};

  ReminderCatalogue get catalogue => _catalogue;
  List<Reminder> get reminders => _mine;
  List<Reminder> get assignedByMe => _assignedByMe;
  ReminderDay get today => _today;
  ReminderScore get score => _score;

  /// Reminders somebody set for me that I have not answered.
  int get pendingCount => _pending;

  /// How many alarms the OS is actually holding. Lower than the number of
  /// reminders when somebody has more than the platform will keep at once.
  int get scheduledCount => _scheduledCount;

  bool get loading => _loading && !_loaded;
  bool get saving => _saving;
  bool get isEmpty => _loaded && _mine.isEmpty;
  String? get error => _error;

  bool get exactAlarmsAllowed => _scheduler.exactAlarmsAllowed;

  bool isBusy(String id) => _busy.contains(id);

  /*
  |----------------------------------------------------------------------------
  | Loading
  |----------------------------------------------------------------------------
  */

  /// Fetched once per session and then left alone — it is seeded data that
  /// only changes on a deploy.
  Future<void> loadCatalogue() async {
    if (_catalogue.categories.isNotEmpty) return;

    try {
      final res = await _api.catalogue();

      if (res.success && res.dataMap.isNotEmpty) {
        _catalogue = ReminderCatalogue.fromJson(res.dataMap);
        notifyListeners();
      }
    } catch (_) {
      // The picker shows its empty state and a retry.
    }
  }

  /// Send anything answered from a notification while the app was away.
  ///
  /// Runs before every load, so the list that comes back already reflects the
  /// Done somebody pressed on their lock screen at seven this morning. Doing
  /// it after would show them a stale "still to do" for as long as the request
  /// took, which is exactly the reassurance this feature is supposed to give.
  ///
  /// Failures put the entries back. An answer is not lost because the network
  /// was down when the app happened to open.
  Future<int> _flushOutbox() async {
    final pending = await ReminderOutbox.drain();

    if (pending.isEmpty) return 0;

    final failed = <OutboxEntry>[];
    var sent = 0;

    for (final entry in pending) {
      try {
        final res = await _api.settle(
          reminderId: entry.reminderId,
          dueAt: entry.dueAt,
          status: entry.status,
        );

        if (res.success) {
          sent++;

          continue;
        }

        /*
         | A 4xx is the server refusing this answer, not the network failing.
         |
         | Usually it means the reminder was deleted, or the occurrence is no
         | longer one the rule produces because the schedule was edited.
         | Retrying forever would wedge the queue behind something that can
         | never succeed, so it is dropped.
         */
        if (res.statusCode >= 400 && res.statusCode < 500) {
          debugPrint('outbox entry rejected: ${res.message}');

          continue;
        }

        failed.add(entry);
      } catch (_) {
        failed.add(entry);
      }
    }

    await ReminderOutbox.restore(failed);

    return sent;
  }

  Future<void> load({bool reschedule = true}) async {
    if (!Session.instance.isAuthenticated || _loading) return;

    _loading = true;

    try {
      // Before the read, so what comes back already includes it.
      await _flushOutbox();

      final res = await _api.overview();

      if (res.success) {
        final data = res.dataMap;

        _mine = (data['reminders'] as List?)
                ?.whereType<Map<String, dynamic>>()
                .map(Reminder.fromJson)
                .toList() ??
            const [];

        _assignedByMe = (data['assigned_by_me'] as List?)
                ?.whereType<Map<String, dynamic>>()
                .map(Reminder.fromJson)
                .toList() ??
            const [];

        _pending = data['pending_count'] as int? ?? 0;

        _today = data['today'] is Map<String, dynamic>
            ? ReminderDay.fromJson(data['today'] as Map<String, dynamic>)
            : ReminderDay.empty;

        final rings = (data['schedule'] as List?)
                ?.whereType<Map<String, dynamic>>()
                .map(ScheduledRing.fromJson)
                .toList() ??
            const <ScheduledRing>[];

        _loaded = true;
        _error = null;

        if (reschedule) await _reschedule(rings);
      } else {
        _error = res.message;
      }
    } on ApiException catch (e) {
      _error = e.message;
      _fault = 'api: ${e.message}';
    } catch (e) {
      /*
       | The message stays friendly; the cause does not get thrown away.
       |
       | This catch sits around the parsing as well as the call, so a single
       | mistyped field anywhere in the payload lands here looking exactly like
       | a dead network — and, worse, skips _reschedule on the way out, so the
       | visible symptom is a phone that never rings rather than a screen that
       | says something went wrong. Keeping the real text is the difference
       | between a five-minute fix and an evening.
       */
      _error = 'Could not reach the server.';
      _fault = '$e';

      debugPrint('[reminders] load failed: $e');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// The real reason the last load failed, unprettified, for diagnostics.
  String? _fault;

  String? get fault => _fault;

  Future<void> loadScore({int days = 30}) async {
    try {
      final res = await _api.score(days: days);

      if (res.success && res.dataMap.isNotEmpty) {
        _score = ReminderScore.fromJson(res.dataMap);
        notifyListeners();
      }
    } catch (_) {
      // Keep the last score.
    }
  }

  /// Top the OS registrations up without disturbing what is on screen.
  ///
  /// Called on resume. The alarms are a rolling window, so an app left closed
  /// for three weeks comes back with an empty queue — and the person it
  /// belongs to has no way of knowing until something does not ring.
  Future<void> refreshSchedule() async {
    if (!Session.instance.isAuthenticated) return;

    /*
     | Never reschedule from an empty reminder list.
     |
     | Daily and weekly alarms are built from [_mine], so topping up before the
     | first load would register the explicit list and silently drop every
     | repeating alarm — which is most of them. A full load is the right
     | answer, not a partial one.
     */
    if (!_loaded) {
      await load();

      return;
    }

    /*
     | Resume is the other moment answers arrive.
     |
     | Somebody presses Done on the notification with the app in the
     | background, then opens it. Without this the tick would not appear until
     | the next full load, which on a screen they are already looking at reads
     | as the button not having worked.
     */
    try {
      if (await _flushOutbox() > 0) await load(reschedule: false);
    } catch (_) {
      // The next load will pick them up.
    }

    try {
      final res = await _api.schedule();

      if (!res.success) return;

      final rings = (res.dataMap['schedule'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .map(ScheduledRing.fromJson)
              .toList() ??
          const <ScheduledRing>[];

      await _reschedule(rings);
      notifyListeners();
    } catch (_) {
      // The existing registrations stand.
    }
  }

  /// Hand the scheduler both halves of the picture.
  ///
  /// The reminders are what daily and weekly alarms are built from — one
  /// repeating alarm each, which never expires. The explicit ring list covers
  /// everything that cannot repeat natively: monthly, one-offs, and anything
  /// with an end date.
  Future<void> _reschedule(List<ScheduledRing> rings) async {
    try {
      _scheduledCount = await _scheduler.sync(_mine, rings);
    } catch (_) {
      // A failure here means alarms may not fire, which is the worst thing
      // this feature can do quietly — so it is surfaced rather than swallowed.
      _error = 'Reminders are saved, but this phone could not schedule them.';
    }
  }

  /*
  |----------------------------------------------------------------------------
  | Writing
  |----------------------------------------------------------------------------
  */

  /// Create or update. Returns the message to show, or null on success with
  /// nothing to say.
  Future<ReminderOutcome> save(
    Map<String, dynamic> body, {
    String? id,
  }) async {
    if (_saving) return const ReminderOutcome(ok: false);

    _saving = true;
    notifyListeners();

    try {
      /*
       | Ask for permission at the moment of the first save.
       |
       | Not at launch: a notification prompt on a safety app's first run,
       | before anything has explained why, is a prompt people decline — and a
       | declined notification permission is very hard to come back from.
       */
      await _scheduler.requestPermissions();

      final res = id == null
          ? await _api.create(body)
          : await _api.update(id, body);

      if (res.success) {
        // Reload rather than patch: saving changes the schedule, today's
        // list and possibly somebody else's pending count, and one reload
        // keeps all three honest.
        await load();

        return ReminderOutcome(ok: true, message: res.message);
      }

      return ReminderOutcome(ok: false, message: res.message);
    } on ApiException catch (e) {
      return ReminderOutcome(ok: false, message: e.message);
    } catch (_) {
      return const ReminderOutcome(
        ok: false,
        message: 'Could not reach the server. Try again.',
      );
    } finally {
      _saving = false;
      notifyListeners();
    }
  }

  Future<ReminderOutcome> remove(String id) async {
    if (_busy.contains(id)) return const ReminderOutcome(ok: false);

    _busy.add(id);
    notifyListeners();

    try {
      final res = await _api.remove(id);

      if (res.success) {
        await load();

        return ReminderOutcome(ok: true, message: res.message);
      }

      return ReminderOutcome(ok: false, message: res.message);
    } catch (_) {
      return const ReminderOutcome(
        ok: false,
        message: 'Could not reach the server. Try again.',
      );
    } finally {
      _busy.remove(id);
      notifyListeners();
    }
  }

  /// Accept or decline a reminder somebody set for me.
  Future<ReminderOutcome> respond(String id, bool accept) async {
    if (_busy.contains(id)) return const ReminderOutcome(ok: false);

    _busy.add(id);
    notifyListeners();

    try {
      final res = await _api.respond(id, accept);

      if (res.success) {
        // Accepting is what makes it start ringing, so the reload has to
        // reach the scheduler — this is the one response where skipping the
        // reschedule would leave a reminder that looks accepted and never
        // goes off.
        await load();

        return ReminderOutcome(ok: true, message: res.message);
      }

      return ReminderOutcome(ok: false, message: res.message);
    } catch (_) {
      return const ReminderOutcome(
        ok: false,
        message: 'Could not reach the server. Try again.',
      );
    } finally {
      _busy.remove(id);
      notifyListeners();
    }
  }

  /// Mark an occurrence done, snoozed or skipped.
  ///
  /// Repaints today optimistically, because a tick that waits for a round trip
  /// feels broken on a phone with one bar — and the reload a moment later
  /// corrects it if the server disagreed.
  Future<ReminderOutcome> settle({
    required String reminderId,
    required DateTime dueAt,
    required String status,
  }) async {
    final key = '$reminderId@${dueAt.toIso8601String()}';

    if (_busy.contains(key)) return const ReminderOutcome(ok: false);

    _busy.add(key);

    final previous = _today;
    _today = _todayWith(reminderId, dueAt, status);
    notifyListeners();

    try {
      final res = await _api.settle(
        reminderId: reminderId,
        dueAt: dueAt,
        status: status,
      );

      if (res.success) {
        if (res.dataMap['today'] is Map<String, dynamic>) {
          _today = ReminderDay.fromJson(
            res.dataMap['today'] as Map<String, dynamic>,
          );
        }

        // Adherence moved, so the number on the card is now stale.
        unawaited(loadScore());

        return ReminderOutcome(ok: true, message: res.message);
      }

      _today = previous;

      return ReminderOutcome(ok: false, message: res.message);
    } catch (_) {
      _today = previous;

      return const ReminderOutcome(
        ok: false,
        message: 'Could not reach the server. Try again.',
      );
    } finally {
      _busy.remove(key);
      notifyListeners();
    }
  }

  /// Today's list with one occurrence's state swapped, for the optimistic
  /// repaint.
  ReminderDay _todayWith(String reminderId, DateTime dueAt, String status) {
    final next = <ReminderOccurrence>[];

    for (final item in _today.items) {
      final same = item.reminderId == reminderId &&
          item.at.toUtc() == dueAt.toUtc();

      next.add(
        same
            ? ReminderOccurrence(
                reminderId: item.reminderId,
                occurrenceId: item.occurrenceId,
                title: item.title,
                icon: item.icon,
                categoryKey: item.categoryKey,
                colourFrom: item.colourFrom,
                colourTo: item.colourTo,
                at: item.at,
                time: item.time,
                state: occurrenceFrom(status),
                completedAt: status == 'done' ? DateTime.now() : null,
                snoozedUntil: item.snoozedUntil,
              )
            : item,
      );
    }

    final done = next.where((i) => i.state == OccurrenceState.done).length;
    final settled = next.where((i) => i.isSettled).length;

    return ReminderDay(
      date: _today.date,
      items: next,
      due: _today.due,
      done: done,
      settled: settled,
      rate: settled == 0 ? null : (done / settled * 100).round(),
    );
  }

  /*
  |----------------------------------------------------------------------------
  | Websocket
  |----------------------------------------------------------------------------
  */

  /// Somebody assigned me a reminder, or answered one I assigned.
  ///
  /// Reloads rather than folding the frame in. Both events change the
  /// schedule — an accepted reminder starts ringing — and the reload is the
  /// only path that reaches the scheduler.
  void applyRemoteChange(Map<String, dynamic> data) {
    unawaited(load());
  }

  void clear() {
    _mine = const [];
    _assignedByMe = const [];
    _today = ReminderDay.empty;
    _score = ReminderScore.empty;
    _pending = 0;
    _scheduledCount = 0;
    _loaded = false;
    _busy.clear();

    // The next account must not inherit this one's alarms.
    unawaited(_scheduler.cancelAll());

    notifyListeners();
  }
}

/// What came of a write.
@immutable
class ReminderOutcome {
  const ReminderOutcome({required this.ok, this.message});

  final bool ok;
  final String? message;
}
