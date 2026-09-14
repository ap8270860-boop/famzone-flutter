import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_toast.dart';
import '../../people/presentation/widgets/person_avatar.dart';
import '../../people/state/family_store.dart';
import '../data/reminder_models.dart';
import '../state/reminder_store.dart';
import 'reminder_catalogue_sheet.dart';
import 'widgets/category_theme.dart';

/// Set up one reminder.
///
/// Opens already filled in — that is the whole design. Coming from "Wake Up"
/// it arrives with a name, 06:30, and weekdays selected, so the common path is
/// to glance at it and press Save. Everything is editable and nothing has to
/// be.
///
/// The order down the screen is deliberate: what, when, how often, who, how it
/// rings. Time sits above repeat because people set a time and then decide how
/// often, never the other way round.
class ReminderEditorScreen extends StatefulWidget {
  const ReminderEditorScreen({
    super.key,
    this.pick,
    this.existing,
  });

  /// A freshly chosen category and preset.
  final ReminderPick? pick;

  /// Editing something that already exists.
  final Reminder? existing;

  @override
  State<ReminderEditorScreen> createState() => _ReminderEditorScreenState();
}

class _ReminderEditorScreenState extends State<ReminderEditorScreen> {
  final ReminderStore _store = ReminderStore.instance;

  late final TextEditingController _title;
  late final TextEditingController _note;

  late ReminderCategory? _category;
  ReminderTemplate? _template;

  late TimeOfDay _time;
  late ReminderRepeat _repeat;
  late int _mask;
  late int _dayOfMonth;
  late String _ringtone;
  late bool _vibrate;
  late int _snooze;
  String? _assigneeId;

  @override
  void initState() {
    super.initState();

    final existing = widget.existing;
    final pick = widget.pick;

    _category = existing?.category ?? pick?.category;
    _template = pick?.template;

    _title = TextEditingController(
      text: existing?.title ?? pick?.template?.name ?? '',
    );
    _note = TextEditingController(text: existing?.note ?? '');

    _time = _openingTime(existing, pick?.template);

    _repeat = existing?.repeatMode ??
        pick?.template?.defaultRepeat ??
        ReminderRepeat.daily;

    _mask = existing?.weekdayMask ??
        pick?.template?.defaultWeekdayMask ??
        0;

    // A weekly rule with no days never fires, so it must never be the state
    // the screen opens in. Weekdays is the overwhelmingly common answer.
    if (_repeat == ReminderRepeat.weekly && _mask == 0) _mask = 0x1F;

    _dayOfMonth = existing?.dayOfMonth ?? DateTime.now().day;
    _ringtone = existing?.ringtone ?? 'default';
    _vibrate = existing?.vibrate ?? true;
    _snooze = existing?.snoozeMinutes ?? 10;
    _assigneeId = existing?.assignment.forPerson?.id;

    FamilyStore.instance.load();
  }

  /// Where the time picker starts.
  ///
  /// A preset's own suggestion first; otherwise the next round half-hour,
  /// which is almost always closer to what somebody wants than midnight and
  /// never looks like a field they forgot to fill in.
  TimeOfDay _openingTime(Reminder? existing, ReminderTemplate? template) {
    if (existing != null) {
      return TimeOfDay(hour: existing.hour, minute: existing.minute);
    }

    final suggested = template?.defaultTime;

    if (suggested != null && suggested.contains(':')) {
      final parts = suggested.split(':');

      return TimeOfDay(
        hour: int.tryParse(parts[0]) ?? 9,
        minute: int.tryParse(parts[1]) ?? 0,
      );
    }

    final now = TimeOfDay.now();

    return now.minute < 30
        ? TimeOfDay(hour: now.hour, minute: 30)
        : TimeOfDay(hour: (now.hour + 1) % 24, minute: 0);
  }

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    super.dispose();
  }

  CategoryTheme get _theme => CategoryTheme.of(
        _category?.colourFrom,
        _category?.colourTo,
        _category?.vibe,
      );

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _time,
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: ColorScheme.dark(
            primary: _theme.accent,
            surface: AppColors.canvasRaised,
          ),
        ),
        child: child ?? const SizedBox.shrink(),
      ),
    );

    if (picked != null) setState(() => _time = picked);
  }

  Future<void> _save() async {
    final title = _title.text.trim();

    if (title.isEmpty) {
      AppToast.show(context, 'Give the reminder a name.', type: ToastType.error);

      return;
    }

    final category = _category;

    if (category == null) {
      AppToast.show(context, 'Pick a category.', type: ToastType.error);

      return;
    }

    if (_repeat == ReminderRepeat.weekly && _mask == 0) {
      AppToast.show(
        context,
        'Pick at least one day of the week.',
        type: ToastType.error,
      );

      return;
    }

    final outcome = await _store.save(
      {
        'title': title,
        if (_note.text.trim().isNotEmpty) 'note': _note.text.trim(),
        'category_id': category.id,
        if (_template != null) 'template_id': _template!.id,
        if (_assigneeId != null) 'assignee_id': _assigneeId,
        'repeat_mode': repeatKey(_repeat),
        'time_of_day':
            '${_time.hour.toString().padLeft(2, '0')}:'
                '${_time.minute.toString().padLeft(2, '0')}',
        'weekday_mask': _repeat == ReminderRepeat.weekly ? _mask : 0,
        if (_repeat == ReminderRepeat.monthly) 'day_of_month': _dayOfMonth,
        'ringtone': _ringtone,
        'vibrate': _vibrate,
        'snooze_minutes': _snooze,
      },
      id: widget.existing?.id,
    );

    if (!mounted) return;

    if (outcome.ok) {
      Navigator.of(context).pop(true);
    }

    if (outcome.message != null) {
      AppToast.show(
        context,
        outcome.message!,
        type: outcome.ok ? ToastType.success : ToastType.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = _theme;

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(widget.existing == null ? 'New reminder' : 'Edit reminder'),
        titleTextStyle: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 17,
          fontWeight: FontWeight.w700,
        ),
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          4,
          16,
          40 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        children: [
          _banner(theme),
          const SizedBox(height: 18),

          _field('Name', _title, hint: 'What is it?'),
          const SizedBox(height: 12),
          _field('Note', _note, hint: 'Optional'),

          const SizedBox(height: 20),
          _timeRow(theme),

          const SizedBox(height: 18),
          _repeatRow(theme),

          if (_repeat == ReminderRepeat.weekly) ...[
            const SizedBox(height: 14),
            _weekdays(theme),
          ],

          if (_repeat == ReminderRepeat.monthly) ...[
            const SizedBox(height: 14),
            _monthDay(theme),
          ],

          const SizedBox(height: 20),
          _assignee(theme),

          const SizedBox(height: 20),
          _ringtoneRow(theme),

          const SizedBox(height: 26),
          _saveButton(theme),
        ],
      ),
    );
  }

  /// The one place the vibe animation runs.
  ///
  /// One header, on a screen somebody has chosen to be on — rather than twelve
  /// tickers in a grid they are trying to scan.
  Widget _banner(CategoryTheme theme) {
    final category = _category;

    return SizedBox(
      height: 96,
      child: Stack(
        fit: StackFit.expand,
        children: [
          VibeBackdrop(theme: theme),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Icon(
                  CategoryTheme.icon(_template?.icon ?? category?.icon),
                  size: 30,
                  color: theme.onGradient,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        category?.name ?? 'Reminder',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: theme.onGradient,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _summary(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: theme.onGradient.withValues(alpha: 0.82),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The rule in words, rebuilt as the controls change.
  ///
  /// The server writes this sentence for a saved reminder; this is the local
  /// echo of it while somebody is still choosing, so the banner is never a
  /// step behind the switches underneath it.
  String _summary() {
    final clock = '${_time.hour.toString().padLeft(2, '0')}:'
        '${_time.minute.toString().padLeft(2, '0')}';

    return switch (_repeat) {
      ReminderRepeat.once => 'Once at $clock',
      ReminderRepeat.daily => 'Every day at $clock',
      ReminderRepeat.weekly => '${_maskWords()} at $clock',
      ReminderRepeat.monthly => 'Monthly on the $_dayOfMonth at $clock',
    };
  }

  String _maskWords() {
    if (_mask == 0x7F) return 'Every day';
    if (_mask == 0x1F) return 'Weekdays';
    if (_mask == 0x60) return 'Weekends';

    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final picked = <String>[];

    for (var bit = 0; bit < 7; bit++) {
      if (_mask & (1 << bit) != 0) picked.add(names[bit]);
    }

    return picked.isEmpty ? 'No days' : picked.join(', ');
  }

  Widget _field(String label, TextEditingController controller, {String? hint}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(label),
        const SizedBox(height: 7),
        TextField(
          controller: controller,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 15),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 14),
            filled: true,
            fillColor: AppColors.glassFill,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: AppColors.glassBorder),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: AppColors.glassBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: _theme.accent),
            ),
          ),
        ),
      ],
    );
  }

  Widget _label(String text) => Text(
        text,
        style: const TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          color: AppColors.textMuted,
        ),
      );

  Widget _timeRow(CategoryTheme theme) {
    return GestureDetector(
      onTap: _pickTime,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: AppColors.glassFill,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.glassBorder),
        ),
        child: Row(
          children: [
            Icon(Icons.schedule_rounded, size: 20, color: theme.accent),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Time',
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            Text(
              _time.format(context),
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w800,
                color: theme.accent,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _repeatRow(CategoryTheme theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('Repeat'),
        const SizedBox(height: 9),
        Row(
          children: [
            for (final mode in ReminderRepeat.values) ...[
              Expanded(
                child: _Chip(
                  label: switch (mode) {
                    ReminderRepeat.once => 'Once',
                    ReminderRepeat.daily => 'Daily',
                    ReminderRepeat.weekly => 'Weekly',
                    ReminderRepeat.monthly => 'Monthly',
                  },
                  selected: _repeat == mode,
                  accent: theme.accent,
                  onTap: () => setState(() {
                    _repeat = mode;

                    // Never leave a weekly rule on no days — it would save
                    // happily and then never fire.
                    if (mode == ReminderRepeat.weekly && _mask == 0) _mask = 0x1F;
                  }),
                ),
              ),
              if (mode != ReminderRepeat.values.last) const SizedBox(width: 7),
            ],
          ],
        ),
      ],
    );
  }

  Widget _weekdays(CategoryTheme theme) {
    const names = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

    return Row(
      children: [
        for (var bit = 0; bit < 7; bit++) ...[
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _mask ^= 1 << bit),
              behavior: HitTestBehavior.opaque,
              child: Container(
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _mask & (1 << bit) != 0
                      ? theme.accent.withValues(alpha: 0.22)
                      : AppColors.glassFill,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _mask & (1 << bit) != 0
                        ? theme.accent.withValues(alpha: 0.6)
                        : AppColors.glassBorder,
                  ),
                ),
                child: Text(
                  names[bit],
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: _mask & (1 << bit) != 0
                        ? theme.accent
                        : AppColors.textMuted,
                  ),
                ),
              ),
            ),
          ),
          if (bit < 6) const SizedBox(width: 6),
        ],
      ],
    );
  }

  Widget _monthDay(CategoryTheme theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('Day of the month'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (var day = 1; day <= 31; day++)
              GestureDetector(
                onTap: () => setState(() => _dayOfMonth = day),
                child: Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _dayOfMonth == day
                        ? theme.accent.withValues(alpha: 0.22)
                        : AppColors.glassFill,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _dayOfMonth == day
                          ? theme.accent.withValues(alpha: 0.6)
                          : AppColors.glassBorder,
                    ),
                  ),
                  child: Text(
                    '$day',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: _dayOfMonth == day
                          ? theme.accent
                          : AppColors.textMuted,
                    ),
                  ),
                ),
              ),
          ],
        ),
        if (_dayOfMonth > 28) ...[
          const SizedBox(height: 8),
          Text(
            // Said plainly rather than left to be discovered in February.
            'Short months use their last day instead.',
            style: TextStyle(
              fontSize: 11.5,
              color: AppColors.warmGold.withValues(alpha: 0.9),
            ),
          ),
        ],
      ],
    );
  }

  Widget _assignee(CategoryTheme theme) {
    return AnimatedBuilder(
      animation: FamilyStore.instance,
      builder: (context, _) {
        final family = FamilyStore.instance.members;

        if (family.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _label('Who is it for'),
            const SizedBox(height: 4),
            Text(
              // The consent rule, stated where the choice is made rather than
              // discovered afterwards.
              'Choosing somebody else sends them a request. It only starts '
              'ringing once they accept.',
              style: const TextStyle(
                fontSize: 11.5,
                height: 1.4,
                color: AppColors.textMuted,
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 76,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _PersonChip(
                    label: 'Me',
                    selected: _assigneeId == null,
                    accent: theme.accent,
                    onTap: () => setState(() => _assigneeId = null),
                  ),
                  for (final person in family)
                    _PersonChip(
                      label: person.name.split(' ').first,
                      avatarUrl: person.avatarUrl,
                      initials: person.initials,
                      selected: _assigneeId == person.id,
                      accent: theme.accent,
                      onTap: () => setState(() => _assigneeId = person.id),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _ringtoneRow(CategoryTheme theme) {
    final tones = _store.catalogue.ringtones;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('Sound'),
        const SizedBox(height: 9),
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: [
            for (final tone in tones)
              _Chip(
                label: tone == 'default'
                    ? 'Phone default'
                    : tone[0].toUpperCase() + tone.substring(1),
                selected: _ringtone == tone,
                accent: theme.accent,
                onTap: () => setState(() => _ringtone = tone),
                expand: false,
              ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Icon(Icons.vibration_rounded, size: 19, color: theme.accent),
            const SizedBox(width: 11),
            const Expanded(
              child: Text(
                'Vibrate',
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            Switch(
              value: _vibrate,
              activeThumbColor: theme.accent,
              onChanged: (value) => setState(() => _vibrate = value),
            ),
          ],
        ),
        Row(
          children: [
            Icon(Icons.snooze_rounded, size: 19, color: theme.accent),
            const SizedBox(width: 11),
            const Expanded(
              child: Text(
                'Snooze',
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            for (final minutes in [0, 5, 10, 15]) ...[
              _Chip(
                label: minutes == 0 ? 'Off' : '${minutes}m',
                selected: _snooze == minutes,
                accent: theme.accent,
                onTap: () => setState(() => _snooze = minutes),
                expand: false,
                compact: true,
              ),
              const SizedBox(width: 5),
            ],
          ],
        ),
      ],
    );
  }

  Widget _saveButton(CategoryTheme theme) {
    return GestureDetector(
      onTap: _store.saving ? null : _save,
      behavior: HitTestBehavior.opaque,
      child: AnimatedBuilder(
        animation: _store,
        builder: (context, _) => Container(
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: theme.gradient,
          ),
          child: _store.saving
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    valueColor: AlwaysStoppedAnimation(Colors.white),
                  ),
                )
              : Text(
                  widget.existing == null ? 'Set reminder' : 'Save changes',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: theme.onGradient,
                  ),
                ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.accent,
    required this.onTap,
    this.expand = true,
    this.compact = false,
  });

  final String label;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;
  final bool expand;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: compact ? 34 : 42,
        padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected
              ? accent.withValues(alpha: 0.2)
              : AppColors.glassFill,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? accent.withValues(alpha: 0.6)
                : AppColors.glassBorder,
          ),
        ),
        // Labels vary in length and the row is fixed width; scale rather than
        // clip, so "Monthly" never arrives as "Month…".
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label,
            maxLines: 1,
            style: TextStyle(
              fontSize: compact ? 12 : 13,
              fontWeight: FontWeight.w700,
              color: selected ? accent : AppColors.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}

class _PersonChip extends StatelessWidget {
  const _PersonChip({
    required this.label,
    required this.selected,
    required this.accent,
    required this.onTap,
    this.avatarUrl,
    this.initials,
  });

  final String label;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;
  final String? avatarUrl;
  final String? initials;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 66,
        margin: const EdgeInsets.only(right: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? accent : Colors.transparent,
                  width: 2,
                ),
              ),
              child: initials == null
                  ? Container(
                      width: 44,
                      height: 44,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.glassFill,
                      ),
                      child: const Icon(
                        Icons.person_rounded,
                        size: 21,
                        color: AppColors.textPrimary,
                      ),
                    )
                  : PersonAvatar(
                      size: 44,
                      imageUrl: avatarUrl,
                      initials: initials!,
                    ),
            ),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                maxLines: 1,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  color: selected ? AppColors.textPrimary : AppColors.textMuted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
