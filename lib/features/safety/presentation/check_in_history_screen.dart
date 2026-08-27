import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/aurora_background.dart';
import '../../../core/widgets/glass_card.dart';
import '../data/check_in_history.dart';
import '../data/safety_api.dart';

/// Every day the user has marked themselves safe, newest first.
///
/// Grouped by month rather than shown as one flat list. A bare list of dates
/// tells you nothing about the shape of a habit; "12 of 23 days" at the head of
/// each month does, and it is the number somebody actually wants when they open
/// a history screen.
class CheckInHistoryScreen extends StatefulWidget {
  const CheckInHistoryScreen({super.key});

  @override
  State<CheckInHistoryScreen> createState() => _CheckInHistoryScreenState();
}

class _CheckInHistoryScreenState extends State<CheckInHistoryScreen> {
  final _api = SafetyApi();

  static const _ranges = {30: '30 days', 90: '3 months', 365: '1 year'};

  int _days = 30;
  CheckInHistory? _history;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _api.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _history == null;
      _error = null;
    });

    try {
      final res = await _api.history(days: _days);

      if (!mounted) return;

      setState(() {
        if (res.success) {
          _history = CheckInHistory.fromJson(res.dataMap);
        } else {
          _error = res.message;
        }
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not reach the server.';
        _loading = false;
      });
    }
  }

  void _setRange(int days) {
    if (days == _days) return;

    setState(() {
      _days = days;
      // Drop the old data so the range change reads as a reload rather than
      // leaving last month's numbers under a new label.
      _history = null;
    });

    _load();
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
                padding: const EdgeInsets.fromLTRB(6, 6, 20, 2),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_rounded,
                          color: AppColors.textPrimary),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const Expanded(
                      child: Text(
                        'Check-in history',
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
              _RangeBar(
                ranges: _ranges,
                selected: _days,
                onChanged: _setRange,
              ),
              Expanded(child: _body()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.mint),
      );
    }

    if (_error != null) {
      return _Empty(
        icon: Icons.cloud_off_rounded,
        title: 'Something went wrong',
        detail: _error!,
      );
    }

    final history = _history;

    if (history == null || history.isEmpty) {
      return const _Empty(
        icon: Icons.event_available_outlined,
        title: 'No check-ins yet',
        detail: 'Tap "I\'m Safe" on the home screen and it will show up here.',
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.mint,
      backgroundColor: AppColors.canvasRaised,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 6, 18, 34),
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        children: [
          _Summary(history: history),
          const SizedBox(height: 20),
          for (final month in history.months) ...[
            _MonthHeader(month: month),
            const SizedBox(height: 10),
            for (var i = 0; i < month.entries.length; i++) ...[
              _EntryRow(
                entry: month.entries[i],
                isFirst: i == 0,
                isLast: i == month.entries.length - 1,
              ),
            ],
            const SizedBox(height: 22),
          ],
        ],
      ),
    );
  }
}

/// 30 days / 3 months / 1 year.
class _RangeBar extends StatelessWidget {
  const _RangeBar({
    required this.ranges,
    required this.selected,
    required this.onChanged,
  });

  final Map<int, String> ranges;
  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
      child: Row(
        children: [
          for (final range in ranges.entries) ...[
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(range.key),
                behavior: HitTestBehavior.opaque,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    color: range.key == selected
                        ? AppColors.mint.withValues(alpha: 0.16)
                        : Colors.white.withValues(alpha: 0.05),
                    border: Border.all(
                      color: range.key == selected
                          ? AppColors.mint.withValues(alpha: 0.45)
                          : Colors.transparent,
                    ),
                  ),
                  child: Text(
                    range.value,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: range.key == selected
                          ? AppColors.mint
                          : AppColors.textMuted,
                    ),
                  ),
                ),
              ),
            ),
            if (range.key != ranges.keys.last) const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

/// Streak, best streak, and how much of the range was covered.
class _Summary extends StatelessWidget {
  const _Summary({required this.history});

  final CheckInHistory history;

  @override
  Widget build(BuildContext context) {
    Widget stat(String value, String label, Color tint) => Expanded(
          child: Column(
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                  color: tint,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
        );

    return GlassCard(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 10),
      radius: 20,
      child: Column(
        children: [
          Row(
            children: [
              stat('${history.currentStreak}', 'Current streak',
                  AppColors.mint),
              stat('${history.longestStreak}', 'Best streak', AppColors.aqua),
              stat('${history.rate}%', 'Checked in', AppColors.textPrimary),
            ],
          ),
          const SizedBox(height: 16),
          _RateBar(rate: history.rate),
          const SizedBox(height: 9),
          Text(
            '${history.completed} check-ins in the last ${history.days} days',
            style: const TextStyle(
              fontSize: 11.5,
              color: AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _RateBar extends StatelessWidget {
  const _RateBar({required this.rate});

  final int rate;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Stack(
          children: [
            Container(
              height: 6,
              color: Colors.white.withValues(alpha: 0.07),
            ),
            LayoutBuilder(
              builder: (context, box) => AnimatedContainer(
                duration: const Duration(milliseconds: 420),
                curve: Curves.easeOutCubic,
                height: 6,
                width: box.maxWidth * (rate.clamp(0, 100) / 100),
                decoration: const BoxDecoration(
                  gradient: AppColors.safeGradient,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MonthHeader extends StatelessWidget {
  const _MonthHeader({required this.month});

  final CheckInMonth month;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 2),
      child: Row(
        children: [
          Text(
            month.label,
            style: const TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              '${month.completed} of ${month.eligibleDays} days',
              style: const TextStyle(
                fontSize: 11.5,
                color: AppColors.textMuted,
              ),
            ),
          ),
          if (month.missed > 0)
            Text(
              '${month.missed} missed',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.warmGold.withValues(alpha: 0.85),
              ),
            ),
        ],
      ),
    );
  }
}

/// One entry, drawn as a timeline row.
///
/// The rail down the left is what makes a list of dates read as a sequence
/// rather than a table — the eye follows it and sees a run.
class _EntryRow extends StatelessWidget {
  const _EntryRow({
    required this.entry,
    required this.isFirst,
    required this.isLast,
  });

  final CheckInEntry entry;
  final bool isFirst;
  final bool isLast;

  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  @override
  Widget build(BuildContext context) {
    final accent = entry.isSafe ? AppColors.mint : AppColors.alertRed;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 30,
            child: Column(
              children: [
                Container(
                  width: 2,
                  height: 8,
                  color: isFirst
                      ? Colors.transparent
                      : Colors.white.withValues(alpha: 0.09),
                ),
                Container(
                  width: 11,
                  height: 11,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: accent,
                    border: Border.all(
                      color: AppColors.canvas,
                      width: 2,
                    ),
                  ),
                ),
                Expanded(
                  child: Container(
                    width: 2,
                    color: isLast
                        ? Colors.transparent
                        : Colors.white.withValues(alpha: 0.09),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: GlassCard(
                padding: const EdgeInsets.fromLTRB(13, 11, 13, 11),
                radius: 14,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          '${entry.date.day}',
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            height: 1,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(width: 7),
                        Text(
                          _weekdays[entry.date.weekday - 1],
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textMuted,
                          ),
                        ),
                        if (entry.isToday) ...[
                          const SizedBox(width: 7),
                          const _Chip(label: 'Today', accent: AppColors.aqua),
                        ],
                        const Spacer(),
                        if (entry.hasLocation) ...[
                          Icon(Icons.place_outlined,
                              size: 13,
                              color: AppColors.textMuted
                                  .withValues(alpha: 0.75)),
                          const SizedBox(width: 5),
                        ],
                        Text(
                          entry.timeLabel,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: accent,
                          ),
                        ),
                      ],
                    ),
                    if (entry.note != null && entry.note!.isNotEmpty) ...[
                      const SizedBox(height: 7),
                      Text(
                        entry.note!,
                        style: const TextStyle(
                          fontSize: 12,
                          height: 1.4,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                    // Only worth showing when it was not the ordinary case —
                    // "manual" on every row is noise.
                    if (entry.source != 'manual') ...[
                      const SizedBox(height: 7),
                      _Chip(
                        label: entry.source[0].toUpperCase() +
                            entry.source.substring(1),
                        accent: AppColors.warmGold,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.accent});

  final String label;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        color: accent.withValues(alpha: 0.15),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
          color: accent,
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({
    required this.icon,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(44, 0, 44, 70),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 46, color: AppColors.textMuted.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12.5,
                height: 1.45,
                color: AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
