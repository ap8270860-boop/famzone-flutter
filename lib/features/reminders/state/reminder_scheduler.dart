import 'dart:async';
// Prefixed, and only for DartPluginRegistrant.
//
// It is declared in dart:ui, not in flutter/widgets.dart — the same trap as
// PathFillType. material.dart re-exports a fixed list of dart:ui names and
// this is not on it, so naming it bare is a compile error rather than a lint.
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../data/reminder_models.dart';
import 'reminder_outbox.dart';

/// Action ids, shared between the notification and both response handlers.
const String kReminderDoneAction = 'reminder.done';
const String kReminderSnoozeAction = 'reminder.snooze';

/// The iOS category the two actions hang off.
///
/// iOS attaches actions to a *category* declared at initialise time, not to
/// the individual notification — so the buttons only appear on notifications
/// whose categoryIdentifier matches something registered before any of them
/// were scheduled.
const String kReminderCategory = 'reminder.actions';

/// Answers a lock-screen tap while the app is not running.
///
/// A top-level function with `@pragma('vm:entry-point')`, and it has to be
/// both: Android runs this in a **separate background isolate** with its own
/// memory, and the tree-shaker would otherwise strip a function nothing in
/// Dart appears to call.
///
/// Nothing here can see the app. Not the store, not the session token, not the
/// reminder list — that all lives in an isolate which may not exist. The only
/// safe move is to write the answer down and let the app send it later, which
/// is what the outbox is for.
///
/// It also must be quick. The isolate is torn down shortly after this returns,
/// so anything awaited on the network would simply be killed mid-flight.
@pragma('vm:entry-point')
void reminderActionBackground(NotificationResponse response) {
  final action = response.actionId;

  if (action != kReminderDoneAction && action != kReminderSnoozeAction) {
    return;
  }

  /*
   | Without this, path_provider is not registered in this isolate and every
   | call throws MissingPluginException — which is the classic silent failure
   | of background handlers, because nobody is watching the log at 7am.
   */
  ui.DartPluginRegistrant.ensureInitialized();

  final parsed = _splitPayload(response.payload);

  if (parsed == null) return;

  // Deliberately not awaited: the handler is synchronous by signature, and
  // the write is a single append that completes long before the isolate goes.
  ReminderOutbox.add(
    reminderId: parsed.$1,
    dueAt: parsed.$2,
    status: action == kReminderDoneAction ? 'done' : 'snoozed',
  );
}

/// The payload both handlers read, in one of two forms.
///
/// The occurrence has to travel in the payload because the background isolate
/// cannot look anything up, and the due instant is what identifies it on the
/// server — the row usually does not exist yet.
///
///   `<reminderId>|<iso8601 instant>`  one specific occurrence
///   `<reminderId>|@HH:mm`             whichever occurrence just fired
///
/// The second form exists because **a repeating notification carries one
/// payload for ever**. It is fixed when the alarm is registered and reused on
/// every firing, so a literal instant would mean pressing Done on Thursday
/// settled Monday's dose — quietly, and for the rest of the reminder's life.
///
/// So a repeat carries its wall-clock time instead, and the moment is worked
/// out when the button is pressed: the most recent time today's clock read
/// HH:mm. Correct for any tap within a day of the alarm, which is every tap
/// that actually happens.
(String, DateTime)? _splitPayload(String? payload) {
  if (payload == null || payload.isEmpty) return null;

  final parts = payload.split('|');

  if (parts.length != 2 || parts[0].isEmpty) return null;

  final second = parts[1];

  if (second.startsWith('@')) {
    final clock = second.substring(1).split(':');

    if (clock.length != 2) return null;

    final hour = int.tryParse(clock[0]);
    final minute = int.tryParse(clock[1]);

    if (hour == null || minute == null) return null;

    final now = DateTime.now();

    var due = DateTime(now.year, now.month, now.day, hour, minute);

    /*
     | Still ahead of us, so the firing must have been yesterday's.
     |
     | The case this covers: an 11:50pm reminder answered a few minutes after
     | midnight. Day underflow normalises, so the 1st rolls back to the last
     | day of the previous month on its own.
     */
    if (due.isAfter(now)) {
      due = DateTime(now.year, now.month, now.day - 1, hour, minute);
    }

    return (parts[0], due);
  }

  final at = DateTime.tryParse(second);

  if (at == null) return null;

  return (parts[0], at);
}

/// Registers real OS alarms so a reminder fires without us.
///
/// This is the part that decides whether the feature works at all, and the
/// reason it is on the device rather than on the server. A reminder has to go
/// off on a plane, in a lift, on a phone with no signal and with the app
/// force-closed — so nothing about the moment it rings may depend on a
/// network. The server owns *what* the reminders are; this owns *when they go
/// off*, and the two meet only when the app is open.
///
/// Three constraints shape everything below.
///
/// **iOS holds 64 pending notifications per app and silently drops the rest.**
/// Not an error, not a warning — the 65th simply never arrives. Five daily
/// reminders over a fortnight is seventy alarms, so a flat "schedule the next
/// two weeks" is already over budget for an ordinary user. [sync] therefore
/// budgets soonest-first and stops at the cap, and tops up on every app open.
///
/// **Android 12 and up gate exact alarms behind a permission.** Without it,
/// `exactAllowWhileIdle` throws and inexact delivery can drift by fifteen
/// minutes or more — which is fine for "read a book" and not fine for
/// medicine. We ask, and fall back rather than fail.
///
/// **Aggressive OEM battery managers kill scheduled work.** Xiaomi, Oppo,
/// vivo and Samsung all ship power savers that revoke alarms from apps the
/// user has not opened recently. Nothing in code fixes this; the app has to
/// tell the user to allow it, and that is a settings screen rather than a
/// bug fix.
class ReminderScheduler {
  ReminderScheduler._();

  static final ReminderScheduler instance = ReminderScheduler._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _ready = false;
  bool _exactAllowed = true;

  /// The last thing [sync] did, in words, for the diagnostics panel.
  ///
  /// Kept because every interesting failure here is silent: a reminder skipped
  /// for not being accepted, a ring already in the past, an exception
  /// swallowed so that one bad alarm does not take the rest down with it. None
  /// of those reach the user, and without this the only symptom is a phone
  /// that does not ring.
  String _report = 'sync has not run yet';

  String get report => _report;

  /// True once [ensureReady] has finished at least once.
  bool get isReady => _ready;

  String _zoneNote = '';

  /// The zone alarms are being scheduled in, and how it was arrived at.
  ///
  /// Worth showing plainly: if this reads UTC on a phone in India then the
  /// zone lookup failed, and nothing else about the feature will make sense
  /// until it is fixed.
  String get zoneName =>
      _ready ? '${tz.local.name}  ($_zoneNote)' : 'not initialised';

  /// Tones that exist as `android/app/src/main/res/raw/<name>` and as
  /// `<name>.caf` in the iOS bundle.
  ///
  /// Naming a raw resource that does not exist resolves to resource id 0,
  /// which hands the channel a sound URI pointing at nothing — silent at best,
  /// and on some OEM builds enough to stop the notification posting at all. So
  /// this list is the guard: a tone not named here falls back to the phone's
  /// own notification sound rather than to silence.
  ///
  /// Keep it in step with `android/app/src/main/res/raw/` and `assets/tones/`.
  /// `default` and `silent` are not files and must never appear here.
  static const Set<String> _bundledTones = <String>{
    'gentle',
    'chime',
    'marimba',
    'sunrise',
    'bell',
    'pulse',
    'classic',
  };

  /// Whether exact alarms are actually permitted.
  ///
  /// False means reminders still fire but may drift — worth saying out loud on
  /// the reminders screen rather than letting somebody discover it by missing
  /// a dose.
  bool get exactAlarmsAllowed => _exactAllowed;

  /// iOS's hard ceiling on pending notifications, minus a little headroom.
  ///
  /// 60 rather than 64 because the platform counts everything the app has
  /// scheduled, and a snooze registered while the budget is full has to have
  /// somewhere to go.
  static const int _budget = 60;

  /// Notification ids are 32-bit signed on Android, so every id here is
  /// masked into the positive half of that range.
  static const int _idMask = 0x7FFFFFFF;

  /// What taps come back through, so the app can open the right reminder.
  static final StreamController<String> _taps =
      StreamController<String>.broadcast();

  /// Reminder ids, as the notifications they came from are tapped.
  Stream<String> get taps => _taps.stream;

  /// Reminder ids answered from a notification button while the app was alive.
  ///
  /// Lets the store drain immediately rather than waiting for the next resume,
  /// so a Done pressed with the app in the background is reflected on screen
  /// by the time somebody looks at it.
  static final StreamController<String> _answered =
      StreamController<String>.broadcast();

  Stream<String> get answered => _answered.stream;

  /*
  |----------------------------------------------------------------------------
  | Setup
  |----------------------------------------------------------------------------
  */

  /// Re-read whether this phone will honour an exact alarm.
  ///
  /// `canScheduleExactNotifications` maps to AlarmManager.canScheduleExactAlarms,
  /// which is true if the app holds EITHER the user-granted
  /// SCHEDULE_EXACT_ALARM or the automatically-granted USE_EXACT_ALARM.
  ///
  /// This used to be inferred from the return value of
  /// `requestExactAlarmsPermission()`, which answers a different question and
  /// gets it wrong on exactly the phones where nothing is broken. An app that
  /// declares USE_EXACT_ALARM — ours does — is granted the capability without
  /// being asked, and Android then shows no "Alarms & reminders" toggle at
  /// all. So the banner told people to go and turn on a switch that does not
  /// exist on their phone, while their alarms were firing perfectly.
  ///
  /// Called on every sync, so the state corrects itself rather than waiting
  /// for somebody to tap through the permission flow again.
  Future<bool> refreshExactAlarms() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    if (android == null) return _exactAllowed;

    try {
      // Null means the platform has no opinion — every Android below 12,
      // where exact is the only behaviour there has ever been.
      _exactAllowed = await android.canScheduleExactNotifications() ?? true;
    } catch (_) {
      _exactAllowed = true;
    }

    return _exactAllowed;
  }

  /// Safe to call repeatedly; only the first call does anything.
  Future<void> ensureReady() async {
    if (_ready) return;

    /*
     | The timezone database has to be loaded before anything can be
     | scheduled, and the device's own zone has to be asked for separately.
     |
     | `tz.local` defaults to UTC until setLocalLocation is called, and the
     | failure is quiet and seasonal: alarms land at the right instant in the
     | wrong zone, so a 7am reminder rings at 12:30pm in India and nobody can
     | work out why.
     */
    tzdata.initializeTimeZones();

    try {
      /*
       | `.identifier`, not `.toString()`.
       |
       | flutter_timezone 5 returns a TimezoneInfo, not a String, and it mixes
       | in Equatable — so toString() renders as "TimezoneInfo(Asia/Calcutta,
       | null)". That is not a location name, getLocation throws on it, the
       | catch below swallows the throw, and tz.local silently stays UTC.
       |
       | Every alarm is then scheduled at its wall-clock time *in UTC*: a
       | reminder set for 18:30 registers for 18:30 UTC, which is midnight in
       | India. Nothing errors, nothing is logged, and the phone simply never
       | rings when it was asked to. This one line cost two evenings.
       */
      final info = await FlutterTimezone.getLocalTimezone();

      tz.setLocalLocation(tz.getLocation(info.identifier));

      _zoneNote = info.identifier;
    } catch (e) {
      // tz.local stays UTC. Recorded rather than swallowed, and _wall below
      // keeps the instants right regardless.
      _zoneNote = 'unresolved, using the device clock: $e';
    }

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');

    final darwin = DarwinInitializationSettings(
      // Asked for explicitly below instead, so the prompt appears when
      // somebody sets their first reminder rather than on first launch.
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,

      /*
       | iOS hangs actions off a category, registered here and referenced by
       | each notification — unlike Android, where the buttons are attached to
       | the notification itself.
       |
       | Registered before anything is scheduled, because a notification whose
       | category was not known at initialise time simply shows without
       | buttons, silently.
       */
      notificationCategories: <DarwinNotificationCategory>[
        DarwinNotificationCategory(
          kReminderCategory,
          actions: <DarwinNotificationAction>[
            DarwinNotificationAction.plain(
              kReminderDoneAction,
              'Done',
            ),
            DarwinNotificationAction.plain(
              kReminderSnoozeAction,
              'Snooze',
            ),
          ],
          options: <DarwinNotificationCategoryOption>{
            DarwinNotificationCategoryOption.hiddenPreviewShowTitle,
          },
        ),
      ],
    );

    await _plugin.initialize(
      InitializationSettings(android: android, iOS: darwin),
      onDidReceiveNotificationResponse: _onTap,

      /*
       | The same taps, when the app is not running.
       |
       | Android delivers those to a separate background isolate; this is the
       | entry point into it. Without it, pressing Done on a locked phone does
       | nothing at all and the person has no way to know.
       */
      onDidReceiveBackgroundNotificationResponse: reminderActionBackground,
    );

    _ready = true;
  }

  /// A tap while the app *is* running.
  ///
  /// Still routed through the outbox rather than straight to the API, even
  /// though the store is right there. One path for both isolates means one
  /// set of behaviour to reason about — and the app being alive is no promise
  /// that it has a network.
  static void _onTap(NotificationResponse response) {
    final action = response.actionId;

    if (action == kReminderDoneAction || action == kReminderSnoozeAction) {
      final parsed = _splitPayload(response.payload);

      if (parsed != null) {
        unawaited(
          ReminderOutbox.add(
            reminderId: parsed.$1,
            dueAt: parsed.$2,
            status: action == kReminderDoneAction ? 'done' : 'snoozed',
          ).then((_) => _answered.add(parsed.$1)),
        );
      }

      return;
    }

    // A tap on the body of the notification, which means "open this".
    final parsed = _splitPayload(response.payload);

    if (parsed != null) _taps.add(parsed.$1);
  }

  /// Ask for what is needed, at the moment it is needed.
  ///
  /// Called when somebody saves their first reminder, not at launch. A
  /// notification prompt on a safety app's first run, before anything has
  /// explained why, is a prompt people decline — and a declined notification
  /// permission is very hard to come back from.
  Future<bool> requestPermissions() async {
    await ensureReady();

    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    if (android != null) {
      final granted = await android.requestNotificationsPermission() ?? false;

      /*
       | Exact alarms are a second, separate permission on Android 12+ — but
       | only on some phones, which is the part that matters.
       |
       | Ask the read-only question first and only prompt if the answer is no.
       | An app declaring USE_EXACT_ALARM is granted the capability outright
       | and Android shows no "Alarms & reminders" toggle at all, so prompting
       | there opens a screen that does not exist.
       */
      if (!await refreshExactAlarms()) {
        try {
          await android.requestExactAlarmsPermission();
        } catch (_) {
          // No such settings screen on this device. Not fatal — the re-check
          // below is what decides, not this call.
        }

        await refreshExactAlarms();
      }

      return granted;
    }

    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();

    return await ios?.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        ) ??
        true;
  }

  /*
  |----------------------------------------------------------------------------
  | Scheduling
  |----------------------------------------------------------------------------
  */

  /// Replace every pending alarm with the ones the server just handed us.
  ///
  /// Cancel-all then re-register, rather than diffing. Diffing is tempting and
  /// wrong here: the OS is the source of truth for what is pending, we cannot
  /// read back enough about each one to compare reliably, and a diff that
  /// drifts leaves a cancelled reminder ringing forever with no way to find
  /// it. Re-registering a few dozen alarms costs milliseconds.
  ///
  /// [rings] is expected sorted soonest-first — the server sorts it — and is
  /// budgeted to [_budget] here because the platform limit is per app, not per
  /// reminder.
  Future<int> sync(List<Reminder> reminders, List<ScheduledRing> rings) async {
    await ensureReady();

    // Re-read rather than trust the flag. It may have been knocked to false by
    // an unrelated scheduling failure, or the user may have granted the
    // permission in Settings since the last run — either way the banner should
    // correct itself here rather than stay wrong until the app restarts.
    await refreshExactAlarms();

    await _plugin.cancelAll();

    final now = DateTime.now();
    var scheduled = 0;

    // Counted only so the diagnostics panel can say which branch swallowed a
    // reminder. Every one of these is a silent skip in normal running.
    var mute = 0;
    var past = 0;
    var failed = 0;
    String? firstError;

    /*
     | Repeating alarms first, because they are the ones that never run out.
     |
     | A daily reminder registered this way costs one slot and fires every day
     | for good. Scheduled as fourteen separate alarms instead — which is what
     | this did before — it costs fourteen slots and stops dead a fortnight
     | after the last time somebody opened the app. Nobody is told; the
     | reminders simply stop.
     */
    final repeating = <String>{};

    for (final reminder in reminders) {
      if (scheduled >= _budget) break;

      if (!reminder.shouldRing) {
        mute++;
        continue;
      }

      final handled = await _scheduleRepeating(reminder);

      if (handled > 0) {
        repeating.add(reminder.id);
        scheduled += handled;
      }
    }

    for (final ring in rings) {
      if (scheduled >= _budget) break;

      // Already covered by a repeating alarm. Scheduling it again would
      // notify twice for the same occurrence.
      if (repeating.contains(ring.reminderId)) continue;

      final at = _localFrom(ring);

      // Already gone. Not an error — the list was built a moment ago on a
      // server whose clock is not this one.
      if (!at.isAfter(tz.TZDateTime.from(now, tz.local))) {
        past++;
        continue;
      }

      try {
        await _plugin.zonedSchedule(
          _idFor(ring.reminderId, ring.at),
          ring.title,
          ring.body,
          at,
          _detailsFor(ring),
          androidScheduleMode: _exactAllowed
              ? AndroidScheduleMode.exactAllowWhileIdle
              // Still delivered while the phone is dozing, just not to the
              // minute. The right fallback: late beats never.
              : AndroidScheduleMode.inexactAllowWhileIdle,

          /*
           | Which occurrence, not just which reminder.
           |
           | The background isolate cannot look anything up, so the due
           | instant has to travel with the notification — it is what
           | identifies the occurrence on the server, and the row usually does
           | not exist until somebody answers.
           */
          payload: _payloadFor(ring),
        );

        scheduled++;
      } catch (e) {
        /*
         | One alarm failing must not stop the rest.
         |
         | The common cause is the exact-alarm permission being revoked
         | between the check and the call, which throws per-call rather than
         | once. Drop to inexact for the remainder and carry on.
         */
        _exactAllowed = false;
        failed++;
        firstError ??= '$e';

        debugPrint('reminder schedule failed for ${ring.reminderId}: $e');
      }
    }

    final held = await _plugin.pendingNotificationRequests();

    _report = [
      '${reminders.length} reminders in, ${rings.length} rings in',
      '$scheduled scheduled, ${held.length} now held by the OS',
      if (mute > 0) '$mute skipped: not accepted or paused',
      if (past > 0) '$past skipped: already in the past',
      if (failed > 0) '$failed failed: $firstError',
      'zone $zoneName, exact ${_exactAllowed ? 'yes' : 'no'}',
    ].join('\n');

    debugPrint('[reminders] $_report');

    return scheduled;
  }

  /*
  |----------------------------------------------------------------------------
  | Self-test
  |----------------------------------------------------------------------------
  |
  | Two buttons that between them say where the chain is broken, without
  | needing a cable or a log.
  |
  |   ringNow fails          -> the notification itself cannot be posted:
  |                             permission, channel, or launcher icon.
  |   ringNow works,
  |   ringSoon never arrives -> posting is fine, scheduling is not: exact
  |                             alarms, or an OEM battery manager.
  |   both work, real
  |   reminders still silent -> the fault is upstream, in what sync is being
  |                             handed. The report above says what that was.
  |
  | Both return an empty string on success and the platform's own error text
  | otherwise, because the error text is the whole point.
  */

  /// Post a notification this instant, bypassing scheduling entirely.
  Future<String> ringNow() async {
    try {
      await ensureReady();

      await _plugin.show(
        _selfTestId,
        'SFamily self-test',
        'If you can see this, notifications work on this phone.',
        _detailsFor(_selfTestRing()),
      );

      return '';
    } catch (e) {
      return '$e';
    }
  }

  /// Schedule one notification a short way out, through the same call every
  /// real reminder uses.
  Future<String> ringSoon({Duration after = const Duration(seconds: 60)}) async {
    try {
      await ensureReady();

      final at = tz.TZDateTime.now(tz.local).add(after);

      await _plugin.zonedSchedule(
        _selfTestId + 1,
        'SFamily self-test',
        'Scheduled for ${at.hour.toString().padLeft(2, '0')}:'
            '${at.minute.toString().padLeft(2, '0')}:'
            '${at.second.toString().padLeft(2, '0')}.',
        at,
        _detailsFor(_selfTestRing()),
        androidScheduleMode: _exactAllowed
            ? AndroidScheduleMode.exactAllowWhileIdle
            : AndroidScheduleMode.inexactAllowWhileIdle,
      );

      return '';
    } catch (e) {
      return '$e';
    }
  }

  /// Well outside the hashed range real reminders use.
  static const int _selfTestId = 2147483600;

  ScheduledRing _selfTestRing() => ScheduledRing(
        reminderId: 'self-test',
        at: DateTime.now(),
        local: '',
        title: 'SFamily self-test',
        body: null,
        ringtone: 'default',
        vibrate: true,
        snoozeMinutes: 0,
      );

  /// Everything the OS is holding for us, for the diagnostics panel.
  Future<List<PendingNotificationRequest>> pending() async {
    await ensureReady();

    return _plugin.pendingNotificationRequests();
  }

  /*
  |----------------------------------------------------------------------------
  | Repeating alarms
  |----------------------------------------------------------------------------
  */

  /// Register a reminder as a native repeat, if it is the kind that can be.
  ///
  /// Returns how many alarm slots it used, or 0 when this reminder has to be
  /// scheduled occurrence by occurrence instead.
  ///
  /// Only two shapes qualify, and the exclusions are the interesting part.
  ///
  /// **Monthly is deliberately excluded.** Both platforms offer a
  /// day-of-month repeat, and it does not clamp: a reminder on the 31st simply
  /// does not fire in September. The server's rule says the 30th, so using the
  /// native repeat here would make the phone and the history disagree four
  /// times a year — and disagree silently. Monthly keeps the explicit list.
  ///
  /// **Anything with an end date is excluded.** A native repeat has no notion
  /// of stopping, so a course of antibiotics that ends on Friday would go on
  /// ringing for ever.
  Future<int> _scheduleRepeating(Reminder reminder) async {
    if (reminder.endsOn != null && reminder.endsOn!.isNotEmpty) return 0;

    try {
      if (reminder.repeatMode == ReminderRepeat.daily) {
        final at = _firstDaily(reminder);

        await _plugin.zonedSchedule(
          _idFor('daily:${reminder.id}', at),
          reminder.title,
          _bodyOf(reminder),
          at,
          _detailsFor(_ringFor(reminder, at)),
          androidScheduleMode: _exactAllowed
              ? AndroidScheduleMode.exactAllowWhileIdle
              : AndroidScheduleMode.inexactAllowWhileIdle,

          // Every day at this wall-clock time, for ever. The hour and minute
          // are matched, not the date — which is also what keeps it at seven
          // o'clock across a daylight-saving change.
          matchDateTimeComponents: DateTimeComponents.time,
          payload: _repeatingPayloadFor(reminder),
        );

        return 1;
      }

      if (reminder.repeatMode == ReminderRepeat.weekly &&
          reminder.weekdayMask != 0) {
        var used = 0;

        for (var bit = 0; bit < 7; bit++) {
          if (reminder.weekdayMask & (1 << bit) == 0) continue;

          // Bit 0 is Monday, and Dart's DateTime.weekday is 1 = Monday, so
          // the ISO day is the bit plus one.
          final at = _firstWeekly(reminder, bit + 1);

          await _plugin.zonedSchedule(
            _idFor('weekly:${reminder.id}:${bit + 1}', at),
            reminder.title,
            _bodyOf(reminder),
            at,
            _detailsFor(_ringFor(reminder, at)),
            androidScheduleMode: _exactAllowed
                ? AndroidScheduleMode.exactAllowWhileIdle
                : AndroidScheduleMode.inexactAllowWhileIdle,
            matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
            payload: _repeatingPayloadFor(reminder),
          );

          used++;
        }

        return used;
      }
    } catch (e) {
      _exactAllowed = false;

      debugPrint('repeating schedule failed for ${reminder.id}: $e');

      // Fall back to the explicit list rather than leaving this reminder with
      // nothing at all.
      return 0;
    }

    return 0;
  }

  /// The next time today's clock reads this reminder's hour and minute.
  ///
  /// Built by constructing the wall clock rather than by adding 24 hours —
  /// adding a duration across a daylight-saving boundary lands an hour out,
  /// which is exactly the bug this whole feature keeps having to avoid.
  tz.TZDateTime _firstDaily(Reminder reminder) {
    final now = DateTime.now();

    var at = DateTime(
      now.year,
      now.month,
      now.day,
      reminder.hour,
      reminder.minute,
    );

    if (!at.isAfter(now)) {
      // Day overflow normalises, so the 31st rolls into the 1st on its own.
      at = DateTime(
        now.year,
        now.month,
        now.day + 1,
        reminder.hour,
        reminder.minute,
      );
    }

    return _notBefore(at, reminder);
  }

  /// The next occurrence of one weekday at this reminder's time.
  tz.TZDateTime _firstWeekly(Reminder reminder, int isoWeekday) {
    final now = DateTime.now();

    var at = DateTime(
      now.year,
      now.month,
      now.day,
      reminder.hour,
      reminder.minute,
    );

    // At most eight steps: seven to come round the week, plus one for the case
    // where today is the right day but the time has already gone.
    for (var step = 0; step < 8; step++) {
      if (at.weekday == isoWeekday && at.isAfter(now)) break;

      at = DateTime(
        at.year,
        at.month,
        at.day + 1,
        reminder.hour,
        reminder.minute,
      );
    }

    return _notBefore(at, reminder);
  }

  /// Hold a first firing back until the reminder has actually started.
  ///
  /// A reminder set up today to begin next Monday must not go off tonight.
  /// The repeat then continues from whenever the first one lands.
  tz.TZDateTime _notBefore(DateTime at, Reminder reminder) {
    final starts = reminder.startsOn;

    if (starts == null || starts.isEmpty) return _wall(at);

    final parts = starts.split('-');

    if (parts.length != 3) return _wall(at);

    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final day = int.tryParse(parts[2]);

    if (year == null || month == null || day == null) return _wall(at);

    final from = DateTime(
      year,
      month,
      day,
      reminder.hour,
      reminder.minute,
    );

    return _wall(from.isAfter(at) ? from : at);
  }

  /// Turn a wall clock into the instant tz can schedule.
  ///
  /// The arithmetic above is done in plain [DateTime], which the Dart VM reads
  /// in the phone's *real* zone — no plugin, no lookup, nothing that can fail.
  /// This converts the resulting instant into whatever `tz.local` happens to
  /// be, which keeps the alarm on the right instant even if the zone lookup in
  /// [ensureReady] has failed and left `tz.local` at UTC.
  ///
  /// Belt and braces on purpose. The zone bug was invisible from inside the
  /// app and cost days; this makes the same mistake impossible to repeat.
  tz.TZDateTime _wall(DateTime local) => tz.TZDateTime.from(local, tz.local);

  String? _bodyOf(Reminder reminder) =>
      (reminder.note != null && reminder.note!.isNotEmpty)
          ? reminder.note
          : reminder.category?.name;

  /// A ScheduledRing standing in for a reminder, so the notification is built
  /// by exactly the same code as an explicitly scheduled one.
  ScheduledRing _ringFor(Reminder reminder, tz.TZDateTime at) => ScheduledRing(
        reminderId: reminder.id,
        at: at,
        local: '',
        title: reminder.title,
        body: _bodyOf(reminder),
        ringtone: reminder.ringtone,
        vibrate: reminder.vibrate,
        snoozeMinutes: reminder.snoozeMinutes,
      );

  /// Push one occurrence back by its own snooze interval.
  ///
  /// Scheduled directly rather than through a server round trip, because the
  /// phone that is ringing is the phone that has to re-ring — and it may have
  /// no signal. The server is told separately, and if that fails the snooze
  /// still happens.
  Future<void> snooze(ScheduledRing ring) async {
    await ensureReady();

    final minutes = ring.snoozeMinutes <= 0 ? 10 : ring.snoozeMinutes;
    final at = tz.TZDateTime.now(tz.local).add(Duration(minutes: minutes));

    await _plugin.zonedSchedule(
      // A distinct id from the original, so cancelling the occurrence does
      // not silently cancel the snooze or the other way round.
      _idFor('snooze:${ring.reminderId}', at),
      ring.title,
      ring.body,
      at,
      _detailsFor(ring),
      androidScheduleMode: _exactAllowed
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle,

      // The *original* occurrence, not the snooze time. A snooze is the same
      // occurrence asked again, so answering it has to settle the row the
      // reminder was actually due at.
      payload: _payloadFor(ring),
    );
  }

  /// `<reminderId>|<iso8601 due instant>`.
  ///
  /// Two fields joined by a pipe rather than JSON. The payload crosses a
  /// platform channel into another isolate on every notification, and a uuid
  /// contains no pipes, so the cheapest thing that cannot be ambiguous wins.
  static String _payloadFor(ScheduledRing ring) =>
      '${ring.reminderId}|${ring.at.toUtc().toIso8601String()}';

  /// The wall-clock form, for an alarm that will fire many times.
  ///
  /// See [_splitPayload] for why a repeat cannot carry an instant.
  static String _repeatingPayloadFor(Reminder reminder) =>
      '${reminder.id}|@${reminder.hour.toString().padLeft(2, '0')}'
      ':${reminder.minute.toString().padLeft(2, '0')}';

  Future<void> cancelAll() async {
    await ensureReady();
    await _plugin.cancelAll();
  }

  /// How many alarms the OS is currently holding for us.
  ///
  /// Surfaced so the reminders screen can be honest when somebody has more
  /// reminders than the platform will hold at once.
  Future<int> pendingCount() async {
    await ensureReady();

    final pending = await _plugin.pendingNotificationRequests();

    return pending.length;
  }

  /*
  |----------------------------------------------------------------------------
  | Internals
  |----------------------------------------------------------------------------
  */

  /// Build the local instant from the server's wall clock, not from its UTC.
  ///
  /// The server sends both. Reading the wall clock keeps the alarm at seven
  /// o'clock on the phone's own timezone even if the account's stored zone is
  /// stale — which is what somebody stepping off a plane expects, and the one
  /// case where trusting the device over the server is right.
  tz.TZDateTime _localFrom(ScheduledRing ring) {
    final parts = ring.local.split(' ');

    if (parts.length == 2) {
      final ymd = parts[0].split('-');
      final hm = parts[1].split(':');

      if (ymd.length == 3 && hm.length >= 2) {
        final year = int.tryParse(ymd[0]);
        final month = int.tryParse(ymd[1]);
        final day = int.tryParse(ymd[2]);
        final hour = int.tryParse(hm[0]);
        final minute = int.tryParse(hm[1]);

        if (year != null &&
            month != null &&
            day != null &&
            hour != null &&
            minute != null) {
          return _wall(DateTime(year, month, day, hour, minute));
        }
      }
    }

    // Malformed wall clock. The instant is still correct, so use it rather
    // than dropping the alarm.
    return tz.TZDateTime.from(ring.at.toLocal(), tz.local);
  }

  /// A stable id for one occurrence of one reminder.
  ///
  /// Derived rather than stored so the same occurrence always maps to the same
  /// id across app restarts — which is what makes cancelling and re-scheduling
  /// idempotent. FNV-1a because it is four lines and spreads well; a hash
  /// collision here costs one overwritten alarm, not corruption.
  static int _idFor(String reminderId, DateTime at) {
    var hash = 0x811C9DC5;

    final seed = '$reminderId@${at.toUtc().millisecondsSinceEpoch}';

    for (final unit in seed.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }

    return hash & _idMask;
  }

  NotificationDetails _detailsFor(ScheduledRing ring) {
    final silent = ring.ringtone == 'silent';

    // Only a tone that is actually bundled. See [_bundledTones] — pointing at
    // a raw resource that does not exist is worse than using the default.
    final custom = !silent && _bundledTones.contains(ring.ringtone);

    return NotificationDetails(
      android: AndroidNotificationDetails(
        /*
         | A channel per tone, and it has to be.
         |
         | Android freezes a channel's sound the moment it is created and
         | ignores every later change — so one shared channel would lock every
         | reminder to whichever tone happened to be chosen first, on a setting
         | the user cannot see and cannot reset without clearing app data.
         */
        'reminders_${ring.ringtone}',
        'Reminders (${ring.ringtone})',
        channelDescription: 'Scheduled reminders',
        importance: Importance.max,
        priority: Priority.high,

        // Full-screen-ish behaviour: this is an alarm, not a badge.
        category: AndroidNotificationCategory.reminder,
        playSound: !silent,
        sound: custom
            ? RawResourceAndroidNotificationSound(ring.ringtone)
            : null,
        enableVibration: ring.vibrate,
        ticker: ring.title,

        /*
         | Done and Snooze, on the notification itself.
         |
         | showsUserInterface false is the important one: it keeps the answer
         | in the background isolate instead of launching the app. Somebody
         | confirming a tablet from their lock screen should not have to watch
         | an app start up — and on a phone with no signal, opening the app
         | would achieve nothing anyway.
         |
         | cancelNotification true so the notification clears when answered.
         | An alarm that stays on the shade after you have dealt with it is
         | how people learn to swipe the whole lot away without reading.
         */
        actions: <AndroidNotificationAction>[
          const AndroidNotificationAction(
            kReminderDoneAction,
            'Done',
            showsUserInterface: false,
            cancelNotification: true,
          ),
          if (ring.snoozeMinutes > 0)
            const AndroidNotificationAction(
              kReminderSnoozeAction,
              'Snooze',
              showsUserInterface: false,
              cancelNotification: true,
            ),
        ],
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: !silent,
        // Bundled at build time. iOS will not play a file the app did not
        // ship, which is why the tone list is fixed rather than uploadable.
        // The same .wav files as Android — iOS accepts wav for notification
        // sounds, so there is no reason to maintain a second set in .caf.
        sound: custom ? '${ring.ringtone}.wav' : null,
        interruptionLevel: InterruptionLevel.timeSensitive,

        // Points at the category registered in ensureReady(). Without it the
        // notification arrives with no buttons and no error.
        categoryIdentifier: kReminderCategory,
      ),
    );
  }
}
