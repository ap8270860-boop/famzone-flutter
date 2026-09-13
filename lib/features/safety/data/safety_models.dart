import 'package:flutter/foundation.dart';

import 'check_in_chain.dart';

/// How the status reads. The server decides this, not the client — the app and
/// the web dashboard must never disagree about what counts as safe.
enum SafetyTone { positive, caution, critical }

SafetyTone _toneFrom(String? raw) => switch (raw) {
      'critical' => SafetyTone.critical,
      'caution' => SafetyTone.caution,
      _ => SafetyTone.positive,
    };

/// One day in the seven-day strip.
@immutable
class CheckInDay {
  const CheckInDay({
    required this.date,
    required this.initial,
    required this.done,
    required this.isToday,
    this.isFuture = false,
  });

  final String date;

  /// First letter of the weekday, already localised server-side.
  final String initial;
  final bool done;
  final bool isToday;

  /// Later this week. Drawn faintly rather than as an empty slot, because a
  /// day that has not happened is not a day that was missed.
  final bool isFuture;

  factory CheckInDay.fromJson(Map<String, dynamic> json) => CheckInDay(
        date: json['date'] as String? ?? '',
        initial: json['initial'] as String? ?? '',
        done: json['done'] as bool? ?? false,
        isToday: json['is_today'] as bool? ?? false,
        isFuture: json['is_future'] as bool? ?? false,
      );

  CheckInDay copyWith({bool? done}) => CheckInDay(
        date: date,
        initial: initial,
        done: done ?? this.done,
        isToday: isToday,
        isFuture: isFuture,
      );
}

@immutable
class CheckInInfo {
  const CheckInInfo({
    required this.doneToday,
    required this.overdue,
    required this.currentStreak,
    required this.longestStreak,
    this.checkedInAt,
    this.serverCheckedInLabel,
    this.reminderLabel,
    this.note,
    this.recent = const [],
    this.notify = NotifyList.empty,
    this.chain,
  });

  final bool doneToday;
  final bool overdue;
  final int currentStreak;
  final int longestStreak;

  /// Who a check-in will reach, and whether a list has been chosen at all.
  ///
  /// `notify.configured` is what the button keys off: false means the first
  /// tap opens the picker instead of checking in.
  final NotifyList notify;

  /// Today's chain, once there is one.
  ///
  /// Null in two quite different situations — nothing checked in yet, and a
  /// check-in made with nobody on the list — which the card does not have to
  /// tell apart, because [doneToday] already does.
  final CheckInChain? chain;

  /// The instant the check-in happened, in UTC.
  ///
  /// Formatting happens on the device rather than trusting the server's
  /// pre-rendered label, so the time shown is always the phone's own — right
  /// even if the stored zone is briefly stale, and right the moment somebody
  /// steps off a plane.
  final DateTime? checkedInAt;

  /// The server's rendering, kept as a fallback for when [checkedInAt] is
  /// missing and used as-is by the web dashboard.
  final String? serverCheckedInLabel;

  final String? reminderLabel;

  /// "7:29 PM" in the device's own timezone.
  String? get checkedInLabel {
    final at = checkedInAt?.toLocal();

    if (at == null) return serverCheckedInLabel;

    final hour = at.hour % 12 == 0 ? 12 : at.hour % 12;
    final minute = at.minute.toString().padLeft(2, '0');

    return '$hour:$minute ${at.hour < 12 ? 'AM' : 'PM'}';
  }
  final String? note;
  final List<CheckInDay> recent;

  factory CheckInInfo.fromJson(Map<String, dynamic> json) {
    final streak = json['streak'] as Map<String, dynamic>? ?? const {};

    return CheckInInfo(
      doneToday: json['done_today'] as bool? ?? false,
      overdue: json['overdue'] as bool? ?? false,
      currentStreak: streak['current'] as int? ?? 0,
      longestStreak: streak['longest'] as int? ?? 0,
      checkedInAt: DateTime.tryParse(json['checked_in_at'] as String? ?? ''),
      serverCheckedInLabel: json['checked_in_label'] as String?,
      reminderLabel: json['reminder_label'] as String?,
      note: json['note'] as String?,
      recent: (json['recent'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .map(CheckInDay.fromJson)
              .toList() ??
          const [],
      notify: json['notify'] is Map<String, dynamic>
          ? NotifyList.fromJson(json['notify'] as Map<String, dynamic>)
          : NotifyList.empty,
      chain: json['chain'] is Map<String, dynamic>
          ? CheckInChain.fromJson(json['chain'] as Map<String, dynamic>)
          : null,
    );
  }

  /// Replace just the chain, leaving everything else alone.
  ///
  /// What a websocket frame does: somebody confirmed, so the chain changed and
  /// nothing else did. Rebuilding the whole status from a frame that only
  /// carries a chain would blank the streak and the week strip.
  CheckInInfo withChain(CheckInChain? next) => CheckInInfo(
        doneToday: doneToday,
        overdue: overdue,
        currentStreak: currentStreak,
        longestStreak: longestStreak,
        checkedInAt: checkedInAt,
        serverCheckedInLabel: serverCheckedInLabel,
        reminderLabel: reminderLabel,
        note: note,
        recent: recent,
        notify: notify,
        chain: next,
      );
}

/// The whole safety picture: one payload behind both home-screen cards.
@immutable
class SafetyStatus {
  const SafetyStatus({
    required this.state,
    required this.tone,
    required this.headline,
    required this.detail,
    required this.checkIn,
    this.circleTotal = 0,
    this.circleSafe = 0,
  });

  /// all_safe | attention | alert
  final String state;
  final SafetyTone tone;
  final String headline;
  final String detail;
  final CheckInInfo checkIn;
  final int circleTotal;
  final int circleSafe;

  factory SafetyStatus.fromJson(Map<String, dynamic> json) {
    final circle = json['circle'] as Map<String, dynamic>? ?? const {};

    return SafetyStatus(
      state: json['state'] as String? ?? 'all_safe',
      tone: _toneFrom(json['tone'] as String?),
      headline: json['headline'] as String? ?? 'All Safe',
      detail: json['detail'] as String? ?? '',
      checkIn: CheckInInfo.fromJson(
        json['check_in'] as Map<String, dynamic>? ?? const {},
      ),
      circleTotal: circle['total'] as int? ?? 0,
      circleSafe: circle['safe'] as int? ?? 0,
    );
  }

  /// What the server will almost certainly say once the check-in lands.
  ///
  /// Used to repaint both cards on tap rather than after the round trip. The
  /// real response replaces this a moment later; if the request fails, the
  /// caller restores the previous status instead.
  SafetyStatus optimisticallyCheckedIn(DateTime now) {
    return SafetyStatus(
      state: 'all_safe',
      tone: SafetyTone.positive,
      headline: 'All Safe',
      detail: 'You checked in at ${_label(now)}.',
      circleTotal: circleTotal,
      circleSafe: circleSafe,
      checkIn: CheckInInfo(
        doneToday: true,
        overdue: false,
        // Only a guess until the server answers — it owns the streak rule.
        currentStreak: checkIn.doneToday
            ? checkIn.currentStreak
            : checkIn.currentStreak + 1,
        longestStreak: checkIn.longestStreak,
        checkedInAt: now.toUtc(),
        reminderLabel: checkIn.reminderLabel,
        recent: [
          for (final day in checkIn.recent)
            day.isToday ? day.copyWith(done: true) : day,
        ],

        // Carried forward: who will be told is already known, and blanking it
        // would make the row of faces flicker out and back on every tap.
        notify: checkIn.notify,

        // Deliberately left null. The chain does not exist until the server
        // has created it, and guessing one here would draw a progress bar for
        // notifications that may not have gone anywhere.
      ),
    );
  }

  /// Fold a chain from a websocket frame into the status we are holding.
  SafetyStatus withChain(CheckInChain? chain) => SafetyStatus(
        state: state,
        tone: tone,
        headline: headline,
        detail: detail,
        circleTotal: circleTotal,
        circleSafe: circleSafe,
        checkIn: checkIn.withChain(chain),
      );
}

/// Same shape as [CheckInInfo.checkedInLabel], for the optimistic copy that is
/// built before any server response exists.
String _label(DateTime at) {
  final local = at.toLocal();
  final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final minute = local.minute.toString().padLeft(2, '0');

  return '$hour:$minute ${local.hour < 12 ? 'AM' : 'PM'}';
}
