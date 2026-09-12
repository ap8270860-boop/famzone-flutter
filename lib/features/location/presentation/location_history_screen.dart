import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../chat/data/chat_models.dart';
import '../data/history_models.dart';
import '../data/location_api.dart';
import '../data/place_models.dart';
import 'widgets/map_style.dart';

/// Where somebody was on a given day.
///
/// The screen is two halves and the split is the design. The map answers
/// *where*, which is a shape best understood by looking at it; the timeline
/// answers *when* and *for how long*, which is a sequence best understood by
/// reading it. Trying to make either half do both — timestamps scattered over
/// a map, or a list of coordinates — produces something that does neither.
///
/// Everything shown here is reconstructed on the server from the raw fixes.
/// The client receives sentences and shapes, never twenty thousand points.
class LocationHistoryScreen extends StatefulWidget {
  const LocationHistoryScreen({
    super.key,
    required this.person,
    this.initialDay,
  });

  final ChatPerson person;
  final DateTime? initialDay;

  @override
  State<LocationHistoryScreen> createState() => _LocationHistoryScreenState();
}

class _LocationHistoryScreenState extends State<LocationHistoryScreen> {
  final LocationApi _api = LocationApi();

  GoogleMapController? _map;

  late DateTime _day = _atMidnight(widget.initialDay ?? DateTime.now());

  DayTimeline _timeline = const DayTimeline.empty('');
  HistoryMonth _month = const HistoryMonth.empty('');

  bool _loading = true;
  String? _error;

  /// Which journey the map is highlighting, if the reader tapped one.
  int? _focused;

  static const MapPalette _palette = MapPalette.day;

  @override
  void initState() {
    super.initState();

    _loadMonth();
    _loadDay();
  }

  @override
  void dispose() {
    _map?.dispose();
    super.dispose();
  }

  static DateTime _atMidnight(DateTime day) =>
      DateTime(day.year, day.month, day.day);

  Future<void> _loadMonth() async {
    final response = await _api.historyDays(widget.person.id, _day);

    if (!mounted || !response.success) return;

    setState(() => _month = HistoryMonth.fromJson(response.dataMap));
  }

  Future<void> _loadDay() async {
    setState(() {
      _loading = true;
      _error = null;
      _focused = null;
    });

    final response = await _api.history(widget.person.id, _day);

    if (!mounted) return;

    if (!response.success) {
      setState(() {
        _loading = false;
        _error = response.message;
        _timeline = const DayTimeline.empty('');
      });

      return;
    }

    setState(() {
      _loading = false;
      _timeline = DayTimeline.fromJson(response.dataMap);
    });

    _frame();
  }

  Future<void> _pick(DateTime day) async {
    if (_atMidnight(day) == _day) return;

    setState(() => _day = _atMidnight(day));

    // A different month means different dots.
    if (_month.month !=
        '${day.year.toString().padLeft(4, '0')}-'
            '${day.month.toString().padLeft(2, '0')}') {
      _loadMonth();
    }

    await _loadDay();
  }

  /*
  |----------------------------------------------------------------------------
  | The map
  |----------------------------------------------------------------------------
  */

  /// Fit the whole day, or one journey when the reader has picked one.
  Future<void> _frame({List<LatLng>? only}) async {
    final points = only ?? _timeline.allPoints;

    if (points.isEmpty || _map == null) return;

    if (points.length == 1) {
      await _map!.animateCamera(
        CameraUpdate.newLatLngZoom(points.first, 16),
      );

      return;
    }

    await _map!.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(
            points.map((p) => p.latitude).reduce(math.min),
            points.map((p) => p.longitude).reduce(math.min),
          ),
          northeast: LatLng(
            points.map((p) => p.latitude).reduce(math.max),
            points.map((p) => p.longitude).reduce(math.max),
          ),
        ),
        56,
      ),
    );
  }

  Set<Polyline> get _polylines {
    final lines = <Polyline>{};

    for (var i = 0; i < _timeline.entries.length; i++) {
      final entry = _timeline.entries[i];

      if (entry.isStay || entry.route.length < 2) continue;

      final dimmed = _focused != null && _focused != i;

      lines.add(
        Polyline(
          polylineId: PolylineId('journey.$i'),
          points: entry.route,

          /*
           | One colour for the day's travel, not one per trip.
           |
           | A rainbow of journeys looks like a legend the reader has to
           | learn. The sequence is already carried by the timeline beside
           | the map; the line's only job is to show the shape.
           */
          color: dimmed
              ? const Color(0xFF9AA5B5).withValues(alpha: 0.5)
              : const Color(0xFF1E7BE8),
          width: dimmed ? 3 : 5,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
          jointType: JointType.round,
          zIndex: dimmed ? 0 : 1,
        ),
      );
    }

    return lines;
  }

  Set<Marker> get _markers {
    final markers = <Marker>{};

    for (var i = 0; i < _timeline.entries.length; i++) {
      final entry = _timeline.entries[i];

      if (!entry.isStay || entry.latitude == null) continue;

      /*
       | Google's own pins, not painted avatars.
       |
       | Deliberate: a face on a marker means "this person is here", present
       | tense, and that is the last thing a history screen should imply. A
       | plain pin reads as a record.
       */
      markers.add(
        Marker(
          markerId: MarkerId('stay.$i'),
          position: LatLng(entry.latitude!, entry.longitude!),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            entry.place == null
                ? BitmapDescriptor.hueAzure
                : BitmapDescriptor.hueViolet,
          ),
          infoWindow: InfoWindow(
            title: entry.title,
            snippet: '${_clock(entry.from)} – ${_clock(entry.to)}'
                '  ·  ${entry.durationLabel}',
          ),
        ),
      );
    }

    return markers;
  }

  /*
  |----------------------------------------------------------------------------
  | Build
  |----------------------------------------------------------------------------
  */

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F8),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _Header(
              person: widget.person,
              day: _day,
              palette: _palette,
              onBack: () => Navigator.of(context).maybePop(),
            ),
            _WeekStrip(
              day: _day,
              month: _month,
              palette: _palette,
              onPick: _pick,
              onPickMonth: _openMonthPicker,
            ),
            Expanded(
              child: Stack(
                children: [
                  GoogleMap(
                    initialCameraPosition: const CameraPosition(
                      target: LatLng(20.5937, 78.9629),
                      zoom: 4,
                    ),
                    style: MapStyle.light,
                    polylines: _polylines,
                    markers: _markers,
                    myLocationEnabled: false,
                    myLocationButtonEnabled: false,
                    compassEnabled: false,
                    mapToolbarEnabled: false,
                    zoomControlsEnabled: false,
                    onMapCreated: (controller) {
                      _map = controller;
                      _frame();
                    },
                  ),

                  if (_loading)
                    const Positioned.fill(
                      child: ColoredBox(
                        color: Color(0xCCF4F6F8),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    ),

                  DraggableScrollableSheet(
                    initialChildSize: 0.42,
                    minChildSize: 0.18,
                    maxChildSize: 0.86,
                    builder: (context, controller) => _Timeline(
                      timeline: _timeline,
                      palette: _palette,
                      controller: controller,
                      error: _error,
                      loading: _loading,
                      focused: _focused,
                      day: _day,
                      onTap: (index) {
                        final entry = _timeline.entries[index];

                        setState(() => _focused = _focused == index ? null : index);

                        if (_focused == null) {
                          _frame();
                        } else if (entry.isStay && entry.latitude != null) {
                          _frame(only: [
                            LatLng(entry.latitude!, entry.longitude!),
                          ]);
                        } else {
                          _frame(only: entry.route);
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openMonthPicker() async {
    final oldest = _month.oldest ?? DateTime.now().subtract(const Duration(days: 30));

    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime(oldest.year, oldest.month, oldest.day),
      lastDate: DateTime.now(),
      helpText: 'Pick a day',
    );

    if (picked != null) await _pick(picked);
  }

  static String _clock(DateTime at) =>
      '${at.hour.toString().padLeft(2, '0')}:'
      '${at.minute.toString().padLeft(2, '0')}';
}

/*
|------------------------------------------------------------------------------
| Header and calendar
|------------------------------------------------------------------------------
*/

class _Header extends StatelessWidget {
  const _Header({
    required this.person,
    required this.day,
    required this.palette,
    required this.onBack,
  });

  final ChatPerson person;
  final DateTime day;
  final MapPalette palette;
  final VoidCallback onBack;

  static const List<String> _months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final isToday = day.year == today.year &&
        day.month == today.month &&
        day.day == today.day;

    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 6, 16, 6),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back_rounded),
            color: palette.textPrimary,
          ),
          CircleAvatar(
            radius: 17,
            backgroundColor: palette.accent.withValues(alpha: 0.16),
            backgroundImage: person.avatarUrl == null
                ? null
                : NetworkImage(person.avatarUrl!),
            child: person.avatarUrl != null
                ? null
                : Text(
                    person.initials,
                    style: TextStyle(
                      color: palette.accent,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  person.name.split(' ').first,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 15.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  isToday
                      ? 'Today'
                      : '${day.day} ${_months[day.month - 1]} ${day.year}',
                  style: TextStyle(
                    color: palette.textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Seven days, with the month picker behind a tap.
///
/// A full month grid is the obvious thing and it is wrong for this screen:
/// history is overwhelmingly "yesterday" and "the day before", and a grid
/// spends a third of the screen on a question nobody is asking. The strip
/// makes the common case one tap and the rare case two.
class _WeekStrip extends StatelessWidget {
  const _WeekStrip({
    required this.day,
    required this.month,
    required this.palette,
    required this.onPick,
    required this.onPickMonth,
  });

  final DateTime day;
  final HistoryMonth month;
  final MapPalette palette;
  final void Function(DateTime day) onPick;
  final VoidCallback onPickMonth;

  static const List<String> _weekdays = [
    'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun',
  ];

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();

    // The seven days ending today, so "today" is always the rightmost and
    // the strip never offers a future nobody has lived yet.
    final days = List.generate(
      7,
      (i) => DateTime(today.year, today.month, today.day)
          .subtract(Duration(days: 6 - i)),
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
      color: Colors.transparent,
      child: Row(
        children: [
          for (final d in days)
            Expanded(
              child: _DayCell(
                day: d,
                palette: palette,
                selected: d == DateTime(day.year, day.month, day.day),
                hasData: month.has(d),
                disabled: month.isTooOld(d),
                weekday: _weekdays[d.weekday - 1],
                onTap: () => onPick(d),
              ),
            ),
          const SizedBox(width: 4),
          Material(
            color: palette.surface,
            borderRadius: BorderRadius.circular(13),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onPickMonth,
              child: SizedBox(
                width: 40,
                height: 58,
                child: Icon(
                  Icons.calendar_month_rounded,
                  size: 19,
                  color: palette.accent,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.palette,
    required this.selected,
    required this.hasData,
    required this.disabled,
    required this.weekday,
    required this.onTap,
  });

  final DateTime day;
  final MapPalette palette;
  final bool selected;
  final bool hasData;
  final bool disabled;
  final String weekday;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = disabled
        ? palette.textMuted.withValues(alpha: 0.4)
        : selected
            ? Colors.white
            : palette.textPrimary;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Material(
        color: selected ? palette.accent : palette.surface,
        borderRadius: BorderRadius.circular(13),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: disabled ? null : onTap,
          child: SizedBox(
            height: 58,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  weekday,
                  style: TextStyle(
                    color: selected
                        ? Colors.white.withValues(alpha: 0.85)
                        : palette.textMuted,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${day.day}',
                  style: TextStyle(
                    color: fg,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),

                /*
                 | A dot for a day with something in it.
                 |
                 | Sized whether or not it is drawn, so the numbers above do
                 | not shift by three pixels as the month's data loads —
                 | which reads as the strip twitching for no reason.
                 */
                SizedBox(
                  height: 5,
                  child: hasData
                      ? Container(
                          width: 5,
                          height: 5,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: selected
                                ? Colors.white
                                : palette.accent.withValues(alpha: 0.8),
                          ),
                        )
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/*
|------------------------------------------------------------------------------
| The timeline
|------------------------------------------------------------------------------
*/

class _Timeline extends StatelessWidget {
  const _Timeline({
    required this.timeline,
    required this.palette,
    required this.controller,
    required this.loading,
    required this.focused,
    required this.day,
    required this.onTap,
    this.error,
  });

  final DayTimeline timeline;
  final MapPalette palette;
  final ScrollController controller;
  final bool loading;
  final int? focused;
  final DateTime day;
  final void Function(int index) onTap;
  final String? error;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        boxShadow: [
          BoxShadow(
            color: palette.shadow,
            blurRadius: 20,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(0, 10, 0, 28),
        children: [
          Center(
            child: Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: palette.textMuted.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _Summary(summary: timeline.summary, palette: palette),
          ),
          const SizedBox(height: 8),

          if (timeline.summary.truncated)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
              child: _Notice(
                palette: palette,
                text: 'This day had more data than we show at once. The later '
                    'part of it is missing from the timeline below.',
              ),
            ),

          if (error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
              child: _Notice(palette: palette, text: error!),
            )
          else if (!loading && timeline.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 30, 24, 30),
              child: Column(
                children: [
                  Icon(
                    Icons.event_busy_rounded,
                    size: 32,
                    color: palette.textMuted.withValues(alpha: 0.5),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Nothing recorded',
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Location is only recorded while they are sharing it. '
                    'Nothing was shared on this day.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: palette.textMuted,
                      fontSize: 12.5,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),

          for (var i = 0; i < timeline.entries.length; i++)
            _EntryRow(
              entry: timeline.entries[i],
              palette: palette,
              first: i == 0,
              last: i == timeline.entries.length - 1,
              dimmed: focused != null && focused != i,
              onTap: () => onTap(i),
            ),
        ],
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.summary, required this.palette});

  final DaySummary summary;
  final MapPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 13),
      decoration: BoxDecoration(
        color: palette.textMuted.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        children: [
          Expanded(
            child: _Figure(
              palette: palette,
              value: summary.distanceLabel,
              label: 'Travelled',
            ),
          ),
          _Rule(palette: palette),
          Expanded(
            child: _Figure(
              palette: palette,
              value: summary.movingLabel,
              label: 'Moving',
            ),
          ),
          _Rule(palette: palette),
          Expanded(
            child: _Figure(
              palette: palette,
              value: '${summary.stays}',
              label: summary.stays == 1 ? 'Stop' : 'Stops',
            ),
          ),
        ],
      ),
    );
  }
}

class _Rule extends StatelessWidget {
  const _Rule({required this.palette});

  final MapPalette palette;

  @override
  Widget build(BuildContext context) => Container(
        width: 1,
        height: 30,
        color: palette.textMuted.withValues(alpha: 0.2),
      );
}

class _Figure extends StatelessWidget {
  const _Figure({
    required this.palette,
    required this.value,
    required this.label,
  });

  final MapPalette palette;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            maxLines: 1,
            style: TextStyle(
              color: palette.textPrimary,
              fontSize: 16.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            color: palette.textMuted,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.palette, required this.text});

  final MapPalette palette;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFD08700).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline_rounded,
            size: 17,
            color: Color(0xFFD08700),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: palette.textPrimary,
                fontSize: 12.5,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One stay or journey, on a vertical rail.
///
/// The rail is what makes this a timeline rather than a list. A gap in it
/// would read as missing data, so the connector is drawn for every row except
/// the ends — which is also why stays and journeys share one row widget
/// rather than being two that have to agree about where the line goes.
class _EntryRow extends StatelessWidget {
  const _EntryRow({
    required this.entry,
    required this.palette,
    required this.first,
    required this.last,
    required this.dimmed,
    required this.onTap,
  });

  final TimelineEntry entry;
  final MapPalette palette;
  final bool first;
  final bool last;
  final bool dimmed;
  final VoidCallback onTap;

  Color get _tint {
    if (!entry.isStay) return const Color(0xFF1E7BE8);

    final place = entry.place;

    return place == null ? const Color(0xFF64748B) : PlaceKinds.tint(place.kind);
  }

  IconData get _glyph {
    if (!entry.isStay) return Icons.navigation_rounded;

    final place = entry.place;

    return place == null ? Icons.pause_circle_rounded : PlaceKinds.icon(place.kind);
  }

  @override
  Widget build(BuildContext context) {
    final tint = _tint;

    return Opacity(
      opacity: dimmed ? 0.45 : 1,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 34,
                  child: Column(
                    children: [
                      Container(
                        width: 2,
                        height: 8,
                        color: first
                            ? Colors.transparent
                            : palette.textMuted.withValues(alpha: 0.25),
                      ),
                      Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: tint.withValues(alpha: 0.14),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(_glyph, size: 15, color: tint),
                      ),
                      Expanded(
                        child: Container(
                          width: 2,
                          color: last
                              ? Colors.transparent
                              : palette.textMuted.withValues(alpha: 0.25),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                entry.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: palette.textPrimary,
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            Text(
                              entry.durationLabel,
                              style: TextStyle(
                                color: tint,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          [
                            '${_clock(entry.from)} – ${_clock(entry.to)}',
                            if (entry.distanceLabel != null) entry.distanceLabel!,
                            if (entry.paceLabel != null) entry.paceLabel!,
                          ].join('  ·  '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: palette.textMuted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _clock(DateTime at) =>
      '${at.hour.toString().padLeft(2, '0')}:'
      '${at.minute.toString().padLeft(2, '0')}';
}
