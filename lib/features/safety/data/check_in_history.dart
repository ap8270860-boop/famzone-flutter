import 'package:flutter/foundation.dart';

/// One recorded check-in.
@immutable
class CheckInEntry {
  const CheckInEntry({
    required this.id,
    required this.date,
    required this.status,
    required this.source,
    this.checkedInAt,
    this.note,
    this.hasLocation = false,
  });

  final String id;

  /// The local calendar day the check-in belongs to, as sent (YYYY-MM-DD).
  final DateTime date;

  /// safe | unsafe
  final String status;

  /// manual | scheduled | auto | sos
  final String source;

  /// The instant it happened, in UTC. Formatted on the device so the time
  /// shown is the phone's own.
  final DateTime? checkedInAt;

  final String? note;
  final bool hasLocation;

  bool get isSafe => status == 'safe';

  /// "7:29 PM" in the device's timezone.
  String get timeLabel {
    final at = checkedInAt?.toLocal();

    if (at == null) return '';

    final hour = at.hour % 12 == 0 ? 12 : at.hour % 12;
    final minute = at.minute.toString().padLeft(2, '0');

    return '$hour:$minute ${at.hour < 12 ? 'AM' : 'PM'}';
  }

  bool get isToday {
    final now = DateTime.now();

    return date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
  }

  factory CheckInEntry.fromJson(Map<String, dynamic> json) => CheckInEntry(
        id: json['id'] as String? ?? '',
        date: DateTime.tryParse(json['date'] as String? ?? '') ?? DateTime.now(),
        status: json['status'] as String? ?? 'safe',
        source: json['source'] as String? ?? 'manual',
        checkedInAt: DateTime.tryParse(json['checked_in_at'] as String? ?? ''),
        note: json['note'] as String?,
        hasLocation: json['has_location'] as bool? ?? false,
      );
}

/// A calendar month's worth of entries, with the arithmetic the header needs.
@immutable
class CheckInMonth {
  const CheckInMonth({
    required this.year,
    required this.month,
    required this.entries,
    required this.eligibleDays,
  });

  final int year;
  final int month;
  final List<CheckInEntry> entries;

  /// Days in this month that were actually available to check in on — clipped
  /// to the selected range at one end and to today at the other.
  ///
  /// Without the clipping, the current month would always read as mostly
  /// missed, and the month somebody joined in would blame them for the days
  /// before they had an account.
  final int eligibleDays;

  int get completed => entries.length;
  int get missed => (eligibleDays - completed).clamp(0, eligibleDays);

  static const _names = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  String get label {
    final now = DateTime.now();
    final name = _names[month - 1];

    return year == now.year ? name : '$name $year';
  }
}

/// The history payload, plus everything derived from it.
@immutable
class CheckInHistory {
  const CheckInHistory({
    required this.months,
    required this.completed,
    required this.rate,
    required this.currentStreak,
    required this.longestStreak,
    required this.days,
  });

  final List<CheckInMonth> months;
  final int completed;

  /// Percentage of elapsed days in the range that were checked in.
  final int rate;

  final int currentStreak;
  final int longestStreak;
  final int days;

  bool get isEmpty => completed == 0;

  factory CheckInHistory.fromJson(Map<String, dynamic> json) {
    final entries = (json['check_ins'] as List?)
            ?.whereType<Map<String, dynamic>>()
            .map(CheckInEntry.fromJson)
            .toList() ??
        <CheckInEntry>[];

    // Newest first. The server already orders it this way; sorting again makes
    // the screen independent of that, and costs nothing at these sizes.
    entries.sort((a, b) => b.date.compareTo(a.date));

    final from = DateTime.tryParse(json['from'] as String? ?? '');
    final to = DateTime.tryParse(json['to'] as String? ?? '') ?? DateTime.now();

    final streak = json['streak'] as Map<String, dynamic>? ?? const {};

    return CheckInHistory(
      months: _groupByMonth(entries, from, to),
      completed: json['completed'] as int? ?? entries.length,
      rate: json['rate'] as int? ?? 0,
      currentStreak: streak['current'] as int? ?? 0,
      longestStreak: streak['longest'] as int? ?? 0,
      days: json['days'] as int? ?? 30,
    );
  }

  /// Group into months, newest first, counting how many days of each month
  /// actually fell inside the window.
  static List<CheckInMonth> _groupByMonth(
    List<CheckInEntry> entries,
    DateTime? from,
    DateTime to,
  ) {
    final buckets = <String, List<CheckInEntry>>{};

    for (final entry in entries) {
      final key = '${entry.date.year}-${entry.date.month}';
      buckets.putIfAbsent(key, () => []).add(entry);
    }

    final months = buckets.entries.map((bucket) {
      final first = bucket.value.first.date;
      final year = first.year;
      final month = first.month;

      // The month's own bounds...
      final monthStart = DateTime(year, month, 1);
      final monthEnd = DateTime(year, month + 1, 0);

      // ...narrowed to the part of it the user could have checked in on.
      final start = from != null && from.isAfter(monthStart) ? from : monthStart;
      final end = to.isBefore(monthEnd) ? to : monthEnd;

      final eligible = end.difference(start).inDays + 1;

      return CheckInMonth(
        year: year,
        month: month,
        entries: bucket.value,
        eligibleDays: eligible.clamp(1, 31),
      );
    }).toList();

    months.sort((a, b) {
      final byYear = b.year.compareTo(a.year);
      return byYear != 0 ? byYear : b.month.compareTo(a.month);
    });

    return months;
  }
}
