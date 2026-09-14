import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/aurora_background.dart';
import '../data/reminder_models.dart';
import '../data/reminders_api.dart';
import '../state/reminder_store.dart';
import 'widgets/category_theme.dart';

/// A month of reminders, one square per day.
///
/// The square is a colour, not a number. Somebody scanning a month is asking
/// "how am I doing" — a wall of counts answers a question nobody asked, and
/// the one time a number matters is the day you tap, which opens the list
/// underneath.
///
/// Fetched a month at a time rather than day by day. Thirty-one requests to
/// draw one grid is thirty-one chances for one of them to be slow, and the
/// grid cannot render until the last has landed.
class ReminderCalendarScreen extends StatefulWidget {
  const ReminderCalendarScreen({super.key});

  @override
  State<ReminderCalendarScreen> createState() => _ReminderCalendarScreenState();
}

class _ReminderCalendarScreenState extends State<ReminderCalendarScreen> {
  final RemindersApi _api = RemindersApi();

  ReminderMonth _month = ReminderMonth.empty;
  ReminderDay? _selected;
  bool _loading = true;
  bool _loadingDay = false;
  String _cursor = '';

  @override
  void initState() {
    super.initState();

    final now = DateTime.now();

    _cursor = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    _load(_cursor);
  }

  @override
  void dispose() {
    _api.dispose();
    super.dispose();
  }

  Future<void> _load(String month) async {
    setState(() {
      _loading = true;
      _cursor = month;
    });

    try {
      final res = await _api.month(month);

      if (!mounted) return;

      if (res.success && res.dataMap.isNotEmpty) {
        setState(() {
          _month = ReminderMonth.fromJson(res.dataMap);

          // Selecting today only makes sense in the month that contains it.
          _selected = null;
        });

        // Open on today, so the screen answers "what now" before it answers
        // "how was last week".
        final today = _month.days.where((d) => d.isToday);

        if (today.isNotEmpty) await _openDay(today.first.date);
      }
    } catch (_) {
      // Leaves whatever month was already drawn.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openDay(String date) async {
    setState(() => _loadingDay = true);

    try {
      final res = await _api.day(date);

      if (!mounted) return;

      if (res.success && res.dataMap.isNotEmpty) {
        setState(() => _selected = ReminderDay.fromJson(res.dataMap));
      }
    } catch (_) {
      // Keep the previous day open rather than blanking it.
    } finally {
      if (mounted) setState(() => _loadingDay = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: AuroraBackground(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 6, 20, 6),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_rounded,
                          color: AppColors.textPrimary),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const Expanded(
                      child: Text(
                        'Reminder calendar',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
                  children: [
                    _monthHeader(),
                    const SizedBox(height: 14),
                    if (_loading && _month.days.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 60),
                        child: Center(
                          child: CircularProgressIndicator(
                              color: AppColors.mint),
                        ),
                      )
                    else ...[
                      _weekdayRow(),
                      const SizedBox(height: 8),
                      _grid(),
                      const SizedBox(height: 16),
                      _legend(),
                      const SizedBox(height: 22),
                      _dayDetail(),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _monthHeader() {
    return Row(
      children: [
        IconButton(
          onPressed: _month.previous.isEmpty
              ? null
              : () => _load(_month.previous),
          icon: const Icon(Icons.chevron_left_rounded,
              color: AppColors.textPrimary),
        ),
        Expanded(
          child: Column(
            children: [
              Text(
                _month.label.isEmpty ? '—' : _month.label,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _month.total == 0
                    ? 'Nothing due yet'
                    : '${_month.done} of ${_month.total} done'
                        '${_month.rate == null ? '' : ' · ${_month.rate}%'}',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: _month.next.isEmpty ? null : () => _load(_month.next),
          icon: const Icon(Icons.chevron_right_rounded,
              color: AppColors.textPrimary),
        ),
      ],
    );
  }

  /// Monday first, matching the ISO weekday the server sends.
  Widget _weekdayRow() {
    const names = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

    return Row(
      children: [
        for (final name in names)
          Expanded(
            child: Center(
              child: Text(
                name,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textMuted,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _grid() {
    // Blanks before the 1st. starts_weekday is ISO, so Monday needs none and
    // Sunday needs six.
    final lead = (_month.startsWeekday - 1).clamp(0, 6);
    final cells = <Widget>[
      for (var i = 0; i < lead; i++) const SizedBox.shrink(),
      for (final day in _month.days)
        _DaySquare(
          day: day,
          selected: _selected?.date == day.date,
          onTap: () => _openDay(day.date),
        ),
    ];

    return GridView.count(
      crossAxisCount: 7,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 6,
      crossAxisSpacing: 6,
      children: cells,
    );
  }

  Widget _legend() {
    const items = [
      ('perfect', 'All done'),
      ('partial', 'Some done'),
      ('missed', 'Missed'),
      ('none', 'Nothing due'),
    ];

    return Wrap(
      spacing: 14,
      runSpacing: 8,
      children: [
        for (final (state, label) in items)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _DaySquare.tintFor(state),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11.5,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
      ],
    );
  }

  Widget _dayDetail() {
    final day = _selected;

    if (day == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text(
            'Tap a day to see what was due.',
            style: TextStyle(fontSize: 12.5, color: AppColors.textMuted),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              day.date,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const Spacer(),
            if (_loadingDay)
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppColors.mint),
              )
            else
              Text(
                day.due == 0
                    ? 'Nothing due'
                    : '${day.done}/${day.settled == 0 ? day.due : day.settled}',
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textMuted,
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        if (day.items.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: Text(
              'Nothing was due on this day.',
              style: TextStyle(fontSize: 12.5, color: AppColors.textMuted),
            ),
          )
        else
          for (final item in day.items) ...[
            _HistoryRow(item: item),
            const SizedBox(height: 7),
          ],
      ],
    );
  }
}

class _DaySquare extends StatelessWidget {
  const _DaySquare({
    required this.day,
    required this.selected,
    required this.onTap,
  });

  final ReminderMonthDay day;
  final bool selected;
  final VoidCallback onTap;

  /// One colour per state, and the same one the legend draws.
  ///
  /// Keyed on the server's string rather than worked out from counts here —
  /// otherwise the calendar and the day view could disagree about what
  /// happened, which is the sort of thing nobody notices until somebody is
  /// arguing about whether they took a tablet.
  static Color tintFor(String state) => switch (state) {
        'perfect' => AppColors.mint,
        'partial' => AppColors.warmGold,
        'missed' => AppColors.alertRed,
        'open' => AppColors.aqua,
        'future' => AppColors.textMuted,
        _ => Colors.transparent,
      };

  @override
  Widget build(BuildContext context) {
    final tint = tintFor(day.state);
    final empty = day.state == 'none';

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(11),
          color: selected
              ? tint.withValues(alpha: 0.22)
              : AppColors.glassFill,
          border: Border.all(
            color: selected
                ? tint.withValues(alpha: 0.75)
                : day.isToday
                    ? AppColors.textPrimary.withValues(alpha: 0.4)
                    : AppColors.glassBorder,
            width: selected || day.isToday ? 1.5 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '${day.day}',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: day.isToday ? FontWeight.w800 : FontWeight.w600,
                color: day.isFuture
                    ? AppColors.textMuted.withValues(alpha: 0.6)
                    : AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 3),
            // A fixed-height slot whether or not there is a dot, so the
            // numbers stay on one baseline across the whole grid.
            SizedBox(
              height: 6,
              child: empty
                  ? null
                  : Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: day.isFuture
                            ? tint.withValues(alpha: 0.35)
                            : tint,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One past occurrence — read-only.
///
/// No tick boxes here. The day view on the reminders screen is where today is
/// answered; this is a record, and a calendar that lets you retroactively mark
/// last Tuesday's tablet as taken is a calendar that cannot be trusted about
/// any Tuesday.
class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.item});

  final ReminderOccurrence item;

  @override
  Widget build(BuildContext context) {
    final theme = CategoryTheme.of(item.colourFrom, item.colourTo, null);

    final (icon, tint, label) = switch (item.state) {
      OccurrenceState.done => (
          Icons.check_circle_rounded,
          AppColors.mint,
          'Done',
        ),
      OccurrenceState.missed => (
          Icons.error_rounded,
          AppColors.warmGold,
          'Missed',
        ),
      OccurrenceState.skipped => (
          Icons.remove_circle_outline_rounded,
          AppColors.textMuted,
          'Skipped',
        ),
      OccurrenceState.snoozed => (
          Icons.snooze_rounded,
          AppColors.aqua,
          'Snoozed',
        ),
      _ => (Icons.schedule_rounded, AppColors.textMuted, 'Pending'),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.glassFill,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Row(
        children: [
          Icon(CategoryTheme.icon(item.icon), size: 17, color: theme.accent),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              item.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          Text(
            item.time,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(width: 9),
          Icon(icon, size: 17, color: tint),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: tint,
            ),
          ),
        ],
      ),
    );
  }
}
