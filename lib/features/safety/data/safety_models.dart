import 'package:flutter/foundation.dart';

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
  });

  final String date;

  /// First letter of the weekday, already localised server-side.
  final String initial;
  final bool done;
  final bool isToday;

  factory CheckInDay.fromJson(Map<String, dynamic> json) => CheckInDay(
        date: json['date'] as String? ?? '',
        initial: json['initial'] as String? ?? '',
        done: json['done'] as bool? ?? false,
        isToday: json['is_today'] as bool? ?? false,
      );

  CheckInDay copyWith({bool? done}) => CheckInDay(
        date: date,
        initial: initial,
        done: done ?? this.done,
        isToday: isToday,
      );
}

@immutable
class CheckInInfo {
  const CheckInInfo({
    required this.doneToday,
    required this.overdue,
    required this.currentStreak,
    required this.longestStreak,
    this.checkedInLabel,
    this.reminderLabel,
    this.note,
    this.recent = const [],
  });

  final bool doneToday;
  final bool overdue;
  final int currentStreak;
  final int longestStreak;

  /// Pre-formatted by the server in the user's own timezone, e.g. "9:14 AM".
  final String? checkedInLabel;
  final String? reminderLabel;
  final String? note;
  final List<CheckInDay> recent;

  factory CheckInInfo.fromJson(Map<String, dynamic> json) {
    final streak = json['streak'] as Map<String, dynamic>? ?? const {};

    return CheckInInfo(
      doneToday: json['done_today'] as bool? ?? false,
      overdue: json['overdue'] as bool? ?? false,
      currentStreak: streak['current'] as int? ?? 0,
      longestStreak: streak['longest'] as int? ?? 0,
      checkedInLabel: json['checked_in_label'] as String?,
      reminderLabel: json['reminder_label'] as String?,
      note: json['note'] as String?,
      recent: (json['recent'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .map(CheckInDay.fromJson)
              .toList() ??
          const [],
    );
  }
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
  SafetyStatus optimisticallyCheckedIn(String nowLabel) {
    return SafetyStatus(
      state: 'all_safe',
      tone: SafetyTone.positive,
      headline: 'All Safe',
      detail: 'You checked in at $nowLabel.',
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
        checkedInLabel: nowLabel,
        reminderLabel: checkIn.reminderLabel,
        recent: [
          for (final day in checkIn.recent)
            day.isToday ? day.copyWith(done: true) : day,
        ],
      ),
    );
  }
}
