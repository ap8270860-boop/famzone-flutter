import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../core/widgets/aurora_background.dart';
import '../data/reminder_models.dart';
import '../state/reminder_store.dart';
import 'reminder_calendar_screen.dart';
import 'reminder_catalogue_sheet.dart';
import 'reminder_editor_screen.dart';
import 'widgets/alarm_health_sheet.dart';
import 'widgets/category_theme.dart';

/// Today first, then everything.
///
/// The ordering is the argument: the question somebody opens this screen to
/// answer is almost always "what now", and a list of every reminder they have
/// ever made answers a different, rarer one. So today's occurrences sit at the
/// top with their tick boxes, and the full list is underneath.
class RemindersScreen extends StatefulWidget {
  const RemindersScreen({super.key});

  @override
  State<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends State<RemindersScreen>
    with WidgetsBindingObserver {
  final ReminderStore _store = ReminderStore.instance;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);

    _store.loadCatalogue();
    _store.load();
    _store.loadScore();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    /*
     | Top the OS registrations up on every resume.
     |
     | The alarms are a rolling fortnight, so an app left closed for three
     | weeks comes back with an empty queue — and the person it belongs to has
     | no way of knowing until something fails to ring. This is the cheap
     | insurance against that, and it is why the schedule endpoint exists
     | separately from the overview.
     */
    if (state == AppLifecycleState.resumed) _store.refreshSchedule();
  }

  Future<void> _create() async {
    final pick = await ReminderCatalogueSheet.show(context);

    if (pick == null || !mounted) return;

    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => ReminderEditorScreen(pick: pick)),
    );

    /*
     | Say the battery thing once, right after the first reminder exists.
     |
     | Not at launch, and not on every save. This is the one moment somebody
     | has demonstrated they care whether an alarm goes off, and it is before
     | they have had a chance to be let down by one.
     */
    if (saved == true && mounted && !_warnedAboutBattery) {
      _warnedAboutBattery = true;

      await AlarmHealthSheet.show(context);
    }
  }

  /// Per session. A flag on disk would be tidier and is not worth a storage
  /// dependency for a sheet somebody can reopen from the header any time.
  bool _warnedAboutBattery = false;

  Future<void> _edit(Reminder reminder) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReminderEditorScreen(existing: reminder),
      ),
    );
  }

  Future<void> _settle(ReminderOccurrence item, String status) async {
    final outcome = await _store.settle(
      reminderId: item.reminderId,
      dueAt: item.at,
      status: status,
    );

    if (!mounted || outcome.message == null || outcome.ok) return;

    AppToast.show(context, outcome.message!, type: ToastType.error);
  }

  Future<void> _respond(Reminder reminder, bool accept) async {
    final outcome = await _store.respond(reminder.id, accept);

    if (!mounted || outcome.message == null) return;

    AppToast.show(
      context,
      outcome.message!,
      type: outcome.ok ? ToastType.success : ToastType.error,
    );
  }

  Future<void> _remove(Reminder reminder) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.canvasRaised,
        title: Text(
          'Remove ${reminder.title}?',
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 17),
        ),
        content: const Text(
          // Says what is kept as well as what goes. The history is the part
          // people worry about losing, and it is the part that stays.
          'It stops ringing and comes off your list. What you have already '
          'marked done is kept.',
          style: TextStyle(color: AppColors.textMuted, height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep it'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.alertRed),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    final outcome = await _store.remove(reminder.id);

    if (!mounted || outcome.message == null) return;

    AppToast.show(
      context,
      outcome.message!,
      type: outcome.ok ? ToastType.success : ToastType.error,
    );
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
                        'Reminders',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Calendar',
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const ReminderCalendarScreen(),
                        ),
                      ),
                      icon: const Icon(Icons.calendar_month_rounded,
                          color: AppColors.textPrimary),
                    ),
                    IconButton(
                      // Always reachable, not only when something looks wrong
                      // — see AlarmHealthSheet for why there is no detector.
                      tooltip: 'Make sure reminders go off',
                      onPressed: () => AlarmHealthSheet.show(context),
                      icon: const Icon(Icons.battery_alert_rounded,
                          color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: AnimatedBuilder(
                  animation: _store,
                  builder: (context, _) => _body(),
                ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        backgroundColor: AppColors.canvasRaised,
        icon: const Icon(Icons.add_alarm_rounded, color: AppColors.mint),
        label: const Text(
          'New reminder',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _body() {
    if (_store.loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.mint),
      );
    }

    final today = _store.today;
    final reminders = _store.reminders;
    final assigned = _store.assignedByMe;

    if (reminders.isEmpty && assigned.isEmpty) return const _Empty();

    return RefreshIndicator(
      onRefresh: _store.load,
      color: AppColors.mint,
      backgroundColor: AppColors.canvasRaised,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 110),
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        children: [
          if (!_store.exactAlarmsAllowed) ...[
            const _ExactAlarmWarning(),
            const SizedBox(height: 14),
          ],

          if (today.items.isNotEmpty) ...[
            _SectionHeader(
              title: 'Today',
              trailing: today.rate == null
                  ? '${today.done}/${today.due}'
                  : '${today.done}/${today.settled} · ${today.rate}%',
            ),
            const SizedBox(height: 10),
            for (final item in today.items) ...[
              _OccurrenceRow(
                item: item,
                onDone: () => _settle(item, 'done'),
                onSnooze: () => _settle(item, 'snoozed'),
                onSkip: () => _settle(item, 'skipped'),
              ),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 16),
          ],

          if (reminders.isNotEmpty) ...[
            const _SectionHeader(title: 'All reminders'),
            const SizedBox(height: 10),
            for (final reminder in reminders) ...[
              _ReminderRow(
                reminder: reminder,
                busy: _store.isBusy(reminder.id),
                onTap: () => _edit(reminder),
                onRemove: () => _remove(reminder),
                onAccept: () => _respond(reminder, true),
                onDecline: () => _respond(reminder, false),
              ),
              const SizedBox(height: 8),
            ],
          ],

          if (assigned.isNotEmpty) ...[
            const SizedBox(height: 16),
            const _SectionHeader(title: 'Set for others'),
            const SizedBox(height: 10),
            for (final reminder in assigned) ...[
              _ReminderRow(
                reminder: reminder,
                busy: _store.isBusy(reminder.id),
                onTap: () => _edit(reminder),
                onRemove: () => _remove(reminder),
                onAccept: null,
                onDecline: null,
              ),
              const SizedBox(height: 8),
            ],
          ],
        ],
      ),
    );
  }
}

/// One thing due today, with the three things you can do to it.
class _OccurrenceRow extends StatelessWidget {
  const _OccurrenceRow({
    required this.item,
    required this.onDone,
    required this.onSnooze,
    required this.onSkip,
  });

  final ReminderOccurrence item;
  final VoidCallback onDone;
  final VoidCallback onSnooze;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final theme = CategoryTheme.of(item.colourFrom, item.colourTo, null);
    final done = item.state == OccurrenceState.done;
    final missed = item.state == OccurrenceState.missed;

    return Opacity(
      // A settled row steps back rather than disappearing. Seeing what you
      // have already done is most of the reward for doing it.
      opacity: item.isSettled ? 0.6 : 1,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 11, 8, 11),
        decoration: BoxDecoration(
          color: AppColors.glassFill,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: missed
                ? AppColors.warmGold.withValues(alpha: 0.35)
                : AppColors.glassBorder,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: theme.accent.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(
                CategoryTheme.icon(item.icon),
                size: 19,
                color: theme.accent,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                      decoration: done ? TextDecoration.lineThrough : null,
                      decorationColor: AppColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _subtitle(item),
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: missed ? AppColors.warmGold : theme.accent,
                    ),
                  ),
                ],
              ),
            ),
            if (!item.isSettled) ...[
              IconButton(
                onPressed: onSnooze,
                visualDensity: VisualDensity.compact,
                tooltip: 'Snooze',
                icon: const Icon(Icons.snooze_rounded,
                    size: 19, color: AppColors.textMuted),
              ),
              IconButton(
                onPressed: onSkip,
                visualDensity: VisualDensity.compact,
                tooltip: 'Skip',
                icon: const Icon(Icons.close_rounded,
                    size: 19, color: AppColors.textMuted),
              ),
              GestureDetector(
                onTap: onDone,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: AppColors.safeGradient,
                  ),
                  child: const Icon(Icons.check_rounded,
                      size: 19, color: Color(0xFF04121F)),
                ),
              ),
              const SizedBox(width: 4),
            ] else
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Icon(
                  switch (item.state) {
                    OccurrenceState.done => Icons.check_circle_rounded,
                    OccurrenceState.missed => Icons.error_rounded,
                    OccurrenceState.skipped => Icons.remove_circle_outline_rounded,
                    _ => Icons.schedule_rounded,
                  },
                  size: 21,
                  color: done
                      ? AppColors.mint
                      : missed
                          ? AppColors.warmGold
                          : AppColors.textMuted,
                ),
              ),
          ],
        ),
      ),
    );
  }

  static String _subtitle(ReminderOccurrence item) => switch (item.state) {
        OccurrenceState.done => 'Done',
        OccurrenceState.missed => 'Missed · ${item.time}',
        OccurrenceState.skipped => 'Skipped',
        OccurrenceState.snoozed => 'Snoozed',
        _ => item.time,
      };
}

/// One reminder in the full list.
class _ReminderRow extends StatelessWidget {
  const _ReminderRow({
    required this.reminder,
    required this.busy,
    required this.onTap,
    required this.onRemove,
    required this.onAccept,
    required this.onDecline,
  });

  final Reminder reminder;
  final bool busy;
  final VoidCallback onTap;
  final VoidCallback onRemove;
  final VoidCallback? onAccept;
  final VoidCallback? onDecline;

  @override
  Widget build(BuildContext context) {
    final theme = CategoryTheme.of(
      reminder.category?.colourFrom,
      reminder.category?.colourTo,
      reminder.category?.vibe,
    );

    final awaiting = reminder.assignment.mineToAnswer;

    return Material(
      color: AppColors.glassFill,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: awaiting
                  ? AppColors.warmGold.withValues(alpha: 0.4)
                  : AppColors.glassBorder,
            ),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      gradient: theme.gradient,
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Icon(
                      CategoryTheme.icon(reminder.icon),
                      size: 20,
                      color: theme.onGradient,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          reminder.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          _subtitle(reminder),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    reminder.time,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: reminder.shouldRing
                          ? theme.accent
                          : AppColors.textMuted,
                    ),
                  ),
                  IconButton(
                    onPressed: onRemove,
                    visualDensity: VisualDensity.compact,
                    icon: Icon(
                      Icons.more_horiz_rounded,
                      size: 19,
                      color: AppColors.textMuted.withValues(alpha: 0.8),
                    ),
                  ),
                ],
              ),

              // Somebody set this for me and I have not answered. The two
              // buttons live on the card rather than only in the notification
              // feed, because this is where somebody looks for it.
              if (awaiting && onAccept != null) ...[
                const SizedBox(height: 11),
                Row(
                  children: [
                    Expanded(
                      child: _SmallButton(
                        label: 'Accept',
                        filled: true,
                        busy: busy,
                        onTap: onAccept!,
                      ),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: _SmallButton(
                        label: 'Decline',
                        filled: false,
                        busy: busy,
                        onTap: onDecline ?? () {},
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static String _subtitle(Reminder reminder) {
    final assignment = reminder.assignment;

    if (assignment.mineToAnswer) {
      return 'From ${assignment.setBy?.shortName ?? 'family'} · '
          '${reminder.scheduleLabel}';
    }

    if (assignment.isAssigned && assignment.forPerson != null) {
      final state = switch (assignment.state) {
        AssignmentState.pending => 'waiting',
        AssignmentState.declined => 'declined',
        _ => reminder.scheduleLabel,
      };

      return 'For ${assignment.forPerson!.shortName} · $state';
    }

    if (reminder.isPaused) return 'Paused · ${reminder.scheduleLabel}';

    return reminder.scheduleLabel;
  }
}

class _SmallButton extends StatelessWidget {
  const _SmallButton({
    required this.label,
    required this.filled,
    required this.busy,
    required this.onTap,
  });

  final String label;
  final bool filled;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = filled ? const Color(0xFF04121F) : AppColors.textPrimary;

    return GestureDetector(
      onTap: busy ? null : onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(11),
          gradient: filled ? AppColors.safeGradient : null,
          color: filled ? null : Colors.white.withValues(alpha: 0.07),
          border: filled
              ? null
              : Border.all(color: Colors.white.withValues(alpha: 0.16)),
        ),
        child: busy
            ? SizedBox(
                width: 15,
                height: 15,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(fg),
                ),
              )
            : Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: fg,
                ),
              ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.trailing});

  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        const Spacer(),
        if (trailing != null)
          Text(
            trailing!,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.textMuted,
            ),
          ),
      ],
    );
  }
}

/// Android 12+ withheld the exact-alarm permission.
///
/// Worth an explicit strip rather than silence: reminders still fire, but the
/// phone is allowed to batch them and a medicine dose arriving twenty minutes
/// late is a different thing from one arriving on time. Somebody should be
/// able to find out why without missing something first.
class _ExactAlarmWarning extends StatelessWidget {
  const _ExactAlarmWarning();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(13, 12, 13, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: AppColors.warmGold.withValues(alpha: 0.08),
        border: Border.all(color: AppColors.warmGold.withValues(alpha: 0.3)),
      ),
      child: const Row(
        children: [
          Icon(Icons.access_time_rounded, size: 19, color: AppColors.warmGold),
          SizedBox(width: 11),
          Expanded(
            child: Text(
              'Exact alarms are off, so reminders may arrive a few minutes '
              'late. Turn on "Alarms & reminders" for SFamily in Settings.',
              style: TextStyle(
                fontSize: 11.5,
                height: 1.4,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(40, 0, 40, 80),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.notifications_active_rounded,
              size: 44,
              color: AppColors.textMuted.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 15),
            const Text(
              'No reminders yet',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 7),
            const Text(
              'Wake up, medicine, the gym, a call home. Pick one and it will '
              'ring on this phone — even with no signal.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.5,
                color: AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
