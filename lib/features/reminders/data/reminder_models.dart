import 'package:flutter/foundation.dart';

/// Everything the reminder feature reads off the wire.
///
/// The server owns the vocabulary — category keys, repeat modes, ringtone
/// names, the sentence describing a schedule — so almost nothing here makes a
/// decision. The exceptions are marked, and each one is something only a
/// device can know.

/// How often a reminder repeats.
///
/// Named ReminderRepeat and not the obvious `RepeatMode`, which is already
/// taken: Flutter declares one in `repeating_animation_builder.dart` and
/// re-exports it through material.dart, so importing both makes every use of
/// the bare name ambiguous. Prefixing the import instead would push the
/// problem onto every file that ever touches this enum.
enum ReminderRepeat { once, daily, weekly, monthly }

ReminderRepeat repeatFrom(String? raw) => switch (raw) {
      'once' => ReminderRepeat.once,
      'weekly' => ReminderRepeat.weekly,
      'monthly' => ReminderRepeat.monthly,
      _ => ReminderRepeat.daily,
    };

String repeatKey(ReminderRepeat mode) => switch (mode) {
      ReminderRepeat.once => 'once',
      ReminderRepeat.weekly => 'weekly',
      ReminderRepeat.monthly => 'monthly',
      ReminderRepeat.daily => 'daily',
    };

/// Where an assigned reminder stands.
enum AssignmentState { self, pending, accepted, declined }

AssignmentState assignmentFrom(String? raw) => switch (raw) {
      'pending' => AssignmentState.pending,
      'accepted' => AssignmentState.accepted,
      'declined' => AssignmentState.declined,
      _ => AssignmentState.self,
    };

/// What became of one occurrence.
enum OccurrenceState { pending, done, missed, snoozed, skipped }

OccurrenceState occurrenceFrom(String? raw) => switch (raw) {
      'done' => OccurrenceState.done,
      'missed' => OccurrenceState.missed,
      'snoozed' => OccurrenceState.snoozed,
      'skipped' => OccurrenceState.skipped,
      _ => OccurrenceState.pending,
    };

/// Somebody in an assignment — who set it, or who it rings for.
@immutable
class ReminderPerson {
  const ReminderPerson({required this.id, required this.name, this.avatarUrl});

  final String id;
  final String name;
  final String? avatarUrl;

  String get shortName {
    final trimmed = name.trim();

    if (trimmed.isEmpty) return '—';

    return trimmed.split(RegExp(r'\s+')).first;
  }

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);

    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();

    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  factory ReminderPerson.fromJson(Map<String, dynamic> json) => ReminderPerson(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        avatarUrl: json['avatar_url'] as String?,
      );
}

/// One of the twelve tiles in the picker.
@immutable
class ReminderCategory {
  const ReminderCategory({
    required this.id,
    required this.key,
    required this.name,
    required this.icon,
    required this.vibe,
    required this.colourFrom,
    required this.colourTo,
    required this.isCustom,
    this.tagline,
    this.templates = const [],
  });

  final String id;
  final String key;
  final String name;

  /// A material icon *name*, not a codepoint.
  ///
  /// Resolved through a lookup in the client. Sending codepoints from a server
  /// looks tidier and does not work: Flutter's icon tree-shaker strips any
  /// glyph it cannot see referenced in the source at build time, so a
  /// dynamically-built IconData draws an empty box in release and looks
  /// perfect in debug.
  final String icon;

  /// Which animated treatment this category wears — see CategoryTheme.
  final String vibe;

  final String colourFrom;
  final String colourTo;
  final String? tagline;

  /// The "make your own" tile. Rendered last and differently, and it opens an
  /// empty editor rather than a list of presets.
  final bool isCustom;

  final List<ReminderTemplate> templates;

  factory ReminderCategory.fromJson(Map<String, dynamic> json) =>
      ReminderCategory(
        id: json['id'] as String? ?? '',
        key: json['key'] as String? ?? '',
        name: json['name'] as String? ?? '',
        icon: json['icon'] as String? ?? 'alarm',
        vibe: json['vibe'] as String? ?? 'plain',
        colourFrom: json['colour_from'] as String? ?? '#2F7BF0',
        colourTo: json['colour_to'] as String? ?? '#12A3E7',
        tagline: json['tagline'] as String?,
        isCustom: json['is_custom'] as bool? ?? false,
        templates: (json['templates'] as List?)
                ?.whereType<Map<String, dynamic>>()
                .map(ReminderTemplate.fromJson)
                .toList() ??
            const [],
      );
}

/// A preset inside a category — a starting point, not a reminder.
@immutable
class ReminderTemplate {
  const ReminderTemplate({
    required this.id,
    required this.key,
    required this.name,
    required this.icon,
    required this.defaultRepeat,
    required this.defaultWeekdayMask,
    this.defaultTime,
  });

  final String id;
  final String key;
  final String name;
  final String icon;

  /// "07:30", or null when the preset has no natural time — the editor then
  /// opens at the next round half-hour.
  final String? defaultTime;

  final ReminderRepeat defaultRepeat;
  final int defaultWeekdayMask;

  factory ReminderTemplate.fromJson(Map<String, dynamic> json) =>
      ReminderTemplate(
        id: json['id'] as String? ?? '',
        key: json['key'] as String? ?? '',
        name: json['name'] as String? ?? '',
        icon: json['icon'] as String? ?? 'alarm',
        defaultTime: json['default_time'] as String?,
        defaultRepeat: repeatFrom(json['default_repeat'] as String?),
        defaultWeekdayMask: json['default_weekday_mask'] as int? ?? 0,
      );
}

/// The picker's whole payload.
@immutable
class ReminderCatalogue {
  const ReminderCatalogue({
    required this.categories,
    required this.ringtones,
    required this.maxActive,
    required this.scheduleWindowDays,
  });

  final List<ReminderCategory> categories;
  final List<String> ringtones;
  final int maxActive;
  final int scheduleWindowDays;

  static const ReminderCatalogue empty = ReminderCatalogue(
    categories: [],
    ringtones: ['default'],
    maxActive: 60,
    scheduleWindowDays: 14,
  );

  factory ReminderCatalogue.fromJson(Map<String, dynamic> json) =>
      ReminderCatalogue(
        categories: (json['categories'] as List?)
                ?.whereType<Map<String, dynamic>>()
                .map(ReminderCategory.fromJson)
                .toList() ??
            const [],
        ringtones: (json['ringtones'] as List?)
                ?.whereType<String>()
                .toList() ??
            const ['default'],
        maxActive: json['max_active'] as int? ?? 60,
        scheduleWindowDays: json['schedule_window_days'] as int? ?? 14,
      );
}

/// A reminder, as the list and the editor use it.
@immutable
class Reminder {
  const Reminder({
    required this.id,
    required this.title,
    required this.icon,
    required this.repeatMode,
    required this.time,
    required this.weekdayMask,
    required this.scheduleLabel,
    required this.ringtone,
    required this.vibrate,
    required this.snoozeMinutes,
    required this.status,
    required this.shouldRing,
    required this.assignment,
    this.note,
    this.category,
    this.dayOfMonth,
    this.startsOn,
    this.endsOn,
    this.nextAt,
    this.meta,
  });

  final String id;
  final String title;
  final String? note;
  final String icon;
  final ReminderCategory? category;

  final ReminderRepeat repeatMode;

  /// Wall clock, "07:30". Not an instant — "seven o'clock" has to survive a
  /// daylight-saving change, and an instant does not.
  final String time;

  final int weekdayMask;
  final int? dayOfMonth;
  final String? startsOn;
  final String? endsOn;

  /// The server's sentence for this rule, so the app and any dashboard cannot
  /// describe the same schedule differently.
  final String scheduleLabel;

  final DateTime? nextAt;

  final String ringtone;
  final bool vibrate;
  final int snoozeMinutes;

  /// active | paused | archived
  final String status;

  /// Whether this should actually be registered with the OS. False for a
  /// paused reminder and for one assigned but not yet accepted.
  final bool shouldRing;

  final ReminderAssignment assignment;
  final Map<String, dynamic>? meta;

  bool get isPaused => status == 'paused';

  int get hour => int.tryParse(time.split(':').first) ?? 9;
  int get minute => int.tryParse(time.split(':').last) ?? 0;

  factory Reminder.fromJson(Map<String, dynamic> json) => Reminder(
        id: json['id'] as String? ?? '',
        title: json['title'] as String? ?? '',
        note: json['note'] as String?,
        icon: json['icon'] as String? ?? 'alarm',
        category: json['category'] is Map<String, dynamic>
            ? ReminderCategory.fromJson(json['category'] as Map<String, dynamic>)
            : null,
        repeatMode: repeatFrom(json['repeat_mode'] as String?),
        time: json['time'] as String? ?? '09:00',
        weekdayMask: json['weekday_mask'] as int? ?? 0,
        dayOfMonth: json['day_of_month'] as int?,
        startsOn: json['starts_on'] as String?,
        endsOn: json['ends_on'] as String?,
        scheduleLabel: json['schedule_label'] as String? ?? '',
        nextAt: DateTime.tryParse(json['next_at'] as String? ?? ''),
        ringtone: json['ringtone'] as String? ?? 'default',
        vibrate: json['vibrate'] as bool? ?? true,
        snoozeMinutes: json['snooze_minutes'] as int? ?? 10,
        status: json['status'] as String? ?? 'active',
        shouldRing: json['should_ring'] as bool? ?? false,
        assignment: ReminderAssignment.fromJson(
          json['assignment'] as Map<String, dynamic>? ?? const {},
        ),
        meta: json['meta'] as Map<String, dynamic>?,
      );
}

@immutable
class ReminderAssignment {
  const ReminderAssignment({
    required this.state,
    required this.isAssigned,
    required this.awaiting,
    required this.mineToAnswer,
    this.setBy,
    this.forPerson,
  });

  final AssignmentState state;

  /// Somebody set this for somebody else.
  final bool isAssigned;

  /// Still waiting on an answer from whoever it rings for.
  final bool awaiting;

  /// Whether *this* viewer is the one who has to answer. The server works it
  /// out, because only the server knows who is asking.
  final bool mineToAnswer;

  final ReminderPerson? setBy;
  final ReminderPerson? forPerson;

  factory ReminderAssignment.fromJson(Map<String, dynamic> json) =>
      ReminderAssignment(
        state: assignmentFrom(json['status'] as String?),
        isAssigned: json['is_assigned'] as bool? ?? false,
        awaiting: json['awaiting'] as bool? ?? false,
        mineToAnswer: json['mine_to_answer'] as bool? ?? false,
        setBy: json['set_by'] is Map<String, dynamic>
            ? ReminderPerson.fromJson(json['set_by'] as Map<String, dynamic>)
            : null,
        forPerson: json['for'] is Map<String, dynamic>
            ? ReminderPerson.fromJson(json['for'] as Map<String, dynamic>)
            : null,
      );
}

/// One thing due on one day.
@immutable
class ReminderOccurrence {
  const ReminderOccurrence({
    required this.reminderId,
    required this.title,
    required this.icon,
    required this.at,
    required this.time,
    required this.state,
    this.occurrenceId,
    this.categoryKey,
    this.colourFrom,
    this.colourTo,
    this.completedAt,
    this.snoozedUntil,
  });

  final String reminderId;

  /// Null until somebody has an opinion about it — the future is computed, so
  /// a row exists only once the occurrence has been answered.
  final String? occurrenceId;

  final String title;
  final String icon;
  final String? categoryKey;
  final String? colourFrom;
  final String? colourTo;

  final DateTime at;
  final String time;
  final OccurrenceState state;
  final DateTime? completedAt;
  final DateTime? snoozedUntil;

  bool get isSettled =>
      state == OccurrenceState.done ||
      state == OccurrenceState.missed ||
      state == OccurrenceState.skipped;

  factory ReminderOccurrence.fromJson(Map<String, dynamic> json) =>
      ReminderOccurrence(
        reminderId: json['reminder_id'] as String? ?? '',
        occurrenceId: json['occurrence_id'] as String?,
        title: json['title'] as String? ?? '',
        icon: json['icon'] as String? ?? 'alarm',
        categoryKey: json['category'] as String?,
        colourFrom: json['colour_from'] as String?,
        colourTo: json['colour_to'] as String?,
        at: DateTime.tryParse(json['at'] as String? ?? '') ?? DateTime.now(),
        time: json['time'] as String? ?? '',
        state: occurrenceFrom(json['status'] as String?),
        completedAt: DateTime.tryParse(json['completed_at'] as String? ?? ''),
        snoozedUntil: DateTime.tryParse(json['snoozed_until'] as String? ?? ''),
      );
}

/// A day of the calendar.
@immutable
class ReminderDay {
  const ReminderDay({
    required this.date,
    required this.items,
    required this.due,
    required this.done,
    required this.settled,
    this.rate,
  });

  final String date;
  final List<ReminderOccurrence> items;
  final int due;
  final int done;
  final int settled;

  /// Null rather than zero when nothing has come due yet. A fresh morning
  /// showing "0%" reads as failure rather than as "not yet".
  final int? rate;

  static const ReminderDay empty = ReminderDay(
    date: '',
    items: [],
    due: 0,
    done: 0,
    settled: 0,
  );

  factory ReminderDay.fromJson(Map<String, dynamic> json) => ReminderDay(
        date: json['date'] as String? ?? '',
        items: (json['items'] as List?)
                ?.whereType<Map<String, dynamic>>()
                .map(ReminderOccurrence.fromJson)
                .toList() ??
            const [],
        due: json['due'] as int? ?? 0,
        done: json['done'] as int? ?? 0,
        settled: json['settled'] as int? ?? 0,
        rate: json['rate'] as int?,
      );
}

/// One alarm the phone should register with the OS.
@immutable
class ScheduledRing {
  const ScheduledRing({
    required this.reminderId,
    required this.at,
    required this.local,
    required this.title,
    required this.ringtone,
    required this.vibrate,
    required this.snoozeMinutes,
    this.body,
  });

  final String reminderId;
  final DateTime at;

  /// The wall clock the server computed, "2026-09-15 07:00".
  ///
  /// Sent alongside the instant so the device does not have to convert back
  /// into the zone it is about to schedule in — a conversion that happens
  /// twice is a conversion that can disagree with itself.
  final String local;

  final String title;
  final String? body;
  final String ringtone;
  final bool vibrate;
  final int snoozeMinutes;

  factory ScheduledRing.fromJson(Map<String, dynamic> json) => ScheduledRing(
        reminderId: json['reminder_id'] as String? ?? '',
        at: DateTime.tryParse(json['at'] as String? ?? '') ?? DateTime.now(),
        local: json['local'] as String? ?? '',
        title: json['title'] as String? ?? 'Reminder',
        body: json['body'] as String?,
        ringtone: json['ringtone'] as String? ?? 'default',
        vibrate: json['vibrate'] as bool? ?? true,
        snoozeMinutes: json['snooze_minutes'] as int? ?? 10,
      );
}

/// One square in the calendar grid.
@immutable
class ReminderMonthDay {
  const ReminderMonthDay({
    required this.date,
    required this.day,
    required this.weekday,
    required this.due,
    required this.done,
    required this.missed,
    required this.skipped,
    required this.isToday,
    required this.isFuture,
    required this.state,
  });

  final String date;
  final int day;

  /// ISO: Monday 1 … Sunday 7. Sent by the server so the client never has to
  /// reimplement calendar arithmetic, or guess which day a week starts on.
  final int weekday;

  final int due;
  final int done;
  final int missed;
  final int skipped;

  final bool isToday;
  final bool isFuture;

  /// none | future | open | perfect | partial | missed — the server's verdict,
  /// so a green dot means the same thing everywhere.
  final String state;

  factory ReminderMonthDay.fromJson(Map<String, dynamic> json) =>
      ReminderMonthDay(
        date: json['date'] as String? ?? '',
        day: json['day'] as int? ?? 0,
        weekday: json['weekday'] as int? ?? 1,
        due: json['due'] as int? ?? 0,
        done: json['done'] as int? ?? 0,
        missed: json['missed'] as int? ?? 0,
        skipped: json['skipped'] as int? ?? 0,
        isToday: json['is_today'] as bool? ?? false,
        isFuture: json['is_future'] as bool? ?? false,
        state: json['state'] as String? ?? 'none',
      );
}

/// A month of squares.
@immutable
class ReminderMonth {
  const ReminderMonth({
    required this.month,
    required this.label,
    required this.startsWeekday,
    required this.previous,
    required this.next,
    required this.done,
    required this.total,
    required this.days,
    this.rate,
  });

  final String month;
  final String label;

  /// Which column the 1st falls in, ISO. The grid pads this many blanks before
  /// it.
  final int startsWeekday;

  final String previous;
  final String next;

  final int done;
  final int total;
  final int? rate;

  final List<ReminderMonthDay> days;

  static const ReminderMonth empty = ReminderMonth(
    month: '',
    label: '',
    startsWeekday: 1,
    previous: '',
    next: '',
    done: 0,
    total: 0,
    days: [],
  );

  factory ReminderMonth.fromJson(Map<String, dynamic> json) => ReminderMonth(
        month: json['month'] as String? ?? '',
        label: json['label'] as String? ?? '',
        startsWeekday: json['starts_weekday'] as int? ?? 1,
        previous: json['previous'] as String? ?? '',
        next: json['next'] as String? ?? '',
        done: json['done'] as int? ?? 0,
        total: json['total'] as int? ?? 0,
        rate: json['rate'] as int?,
        days: (json['days'] as List?)
                ?.whereType<Map<String, dynamic>>()
                .map(ReminderMonthDay.fromJson)
                .toList() ??
            const [],
      );
}

/// Adherence over a window.
@immutable
class ReminderScore {
  const ReminderScore({
    required this.days,
    required this.done,
    required this.total,
    required this.streak,
    required this.headline,
    this.rate,
  });

  final int days;
  final int done;
  final int total;
  final int streak;
  final String headline;
  final int? rate;

  static const ReminderScore empty = ReminderScore(
    days: 30,
    done: 0,
    total: 0,
    streak: 0,
    headline: 'Nothing due yet',
  );

  factory ReminderScore.fromJson(Map<String, dynamic> json) => ReminderScore(
        days: json['days'] as int? ?? 30,
        done: json['done'] as int? ?? 0,
        total: json['total'] as int? ?? 0,
        streak: json['streak'] as int? ?? 0,
        headline: json['headline'] as String? ?? '',
        rate: json['rate'] as int?,
      );
}
