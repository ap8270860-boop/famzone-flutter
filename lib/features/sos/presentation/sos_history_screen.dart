import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../data/sos_api.dart';
import '../data/sos_models.dart';
import '../state/sos_store.dart';
import 'widgets/service_glyph.dart';

/// Every alarm ever raised on this account.
///
/// Nothing is ever removed from here, including false alarms — especially
/// false alarms. "I pressed it at 11:40pm and cancelled two minutes later" is
/// exactly the kind of thing that matters afterwards, and an app that quietly
/// tidies away its own alarms is not much of a safety app.
class SosHistoryScreen extends StatefulWidget {
  const SosHistoryScreen({super.key});

  @override
  State<SosHistoryScreen> createState() => _SosHistoryScreenState();
}

class _SosHistoryScreenState extends State<SosHistoryScreen> {
  final SosApi _api = SosApi();
  final ScrollController _scroll = ScrollController();

  final List<SosAlert> _alerts = [];

  bool _loading = true;
  bool _hasMore = false;
  int _page = 1;
  String? _error;

  @override
  void initState() {
    super.initState();

    _scroll.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();

    super.dispose();
  }

  void _onScroll() {
    if (!_hasMore || _loading) return;

    // 400px of runway, so the next page is already arriving by the time the
    // bottom of the list comes into view.
    if (_scroll.position.pixels >=
        _scroll.position.maxScrollExtent - 400) {
      _load(next: true);
    }
  }

  Future<void> _load({bool next = false}) async {
    if (next && !_hasMore) return;

    setState(() {
      _loading = true;

      if (!next) _error = null;
    });

    try {
      final response = await _api.history(page: next ? _page + 1 : 1);

      if (!mounted) return;

      if (!response.success) {
        setState(() => _error = response.message);

        return;
      }

      final data = response.dataMap;

      final alerts = ((data['alerts'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(SosAlert.fromJson)
          .toList();

      setState(() {
        if (next) {
          _alerts.addAll(alerts);
          _page += 1;
        } else {
          _alerts
            ..clear()
            ..addAll(alerts);
          _page = 1;
        }

        _hasMore = data['has_more'] as bool? ?? false;
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load your history.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        backgroundColor: AppColors.canvas,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
        title: const Text(
          'SOS history',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
      ),
      body: RefreshIndicator(
        color: AppColors.neonCyan,
        backgroundColor: AppColors.canvasRaised,
        onRefresh: () => _load(),
        child: _alerts.isEmpty && !_loading
            ? _Empty(error: _error)
            : ListView.builder(
                controller: _scroll,
                padding: EdgeInsets.fromLTRB(
                  16, 8, 16, 24 + MediaQuery.paddingOf(context).bottom,
                ),
                itemCount: _alerts.length + (_hasMore ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index >= _alerts.length) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 22),
                      child: Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.neonCyan,
                          ),
                        ),
                      ),
                    );
                  }

                  return _AlertRow(alert: _alerts[index]);
                },
              ),
      ),
    );
  }
}

class _AlertRow extends StatelessWidget {
  const _AlertRow({required this.alert});

  final SosAlert alert;

  @override
  Widget build(BuildContext context) {
    final service = alert.category == null
        ? null
        : SosStore.instance.service(alert.category!);

    final tint = _tintFor(alert.status, service?.tint);

    return Padding(
      padding: const EdgeInsets.only(bottom: 11),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: AppColors.glassFill,
          border: Border.all(
            color: alert.active
                ? AppColors.alertRed.withValues(alpha: 0.5)
                : AppColors.glassBorder,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: tint.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                service == null
                    ? Icons.sos_rounded
                    : ServiceIcons.of(service.icon),
                size: 20,
                color: tint,
              ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          service?.label ?? 'Emergency alert',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: tint.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: Text(
                          alert.statusLabel,
                          style: TextStyle(
                            color: tint,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _when(alert.startedAt),
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 14,
                    runSpacing: 6,
                    children: [
                      _Fact(
                        icon: Icons.timer_outlined,
                        text: alert.elapsedLabel,
                      ),
                      if (alert.notifiedCount > 0)
                        _Fact(
                          icon: Icons.group_outlined,
                          text: '${alert.notifiedCount} alerted',
                        ),
                      if (alert.hasLocation)
                        const _Fact(
                          icon: Icons.place_outlined,
                          text: 'Location recorded',
                        ),
                      if (alert.batteryLevel != null)
                        _Fact(
                          icon: Icons.battery_std_outlined,
                          text: '${alert.batteryLevel}%',
                        ),
                    ],
                  ),
                  if (alert.note != null && alert.note!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      alert.note!,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 12.5,
                        height: 1.4,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Colour by outcome, falling back to the service's own tint.
  ///
  /// A false alarm is deliberately grey rather than red: it happened, it is
  /// recorded, and it does not deserve to shout at somebody scrolling their
  /// own history months later.
  static Color _tintFor(String status, Color? serviceTint) => switch (status) {
        SosAlert.statusActive => AppColors.alertRed,
        SosAlert.statusResolved => AppColors.mint,
        SosAlert.statusCancelled => AppColors.aqua,
        SosAlert.statusFalseAlarm => AppColors.lavenderGray,
        _ => serviceTint ?? AppColors.neonCyan,
      };

  static String _when(DateTime? at) {
    if (at == null) return '';

    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];

    final hour = at.hour % 12 == 0 ? 12 : at.hour % 12;
    final minute = at.minute.toString().padLeft(2, '0');

    return '${months[at.month - 1]} ${at.day}, '
        '$hour:$minute ${at.hour < 12 ? 'AM' : 'PM'}';
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: AppColors.textMuted),
        const SizedBox(width: 5),
        Text(
          text,
          style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5),
        ),
      ],
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({this.error});

  final String? error;

  @override
  Widget build(BuildContext context) {
    // Still scrollable, so pull-to-refresh works on an empty list.
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(32, 90, 32, 32),
      children: [
        Icon(
          error == null
              ? Icons.shield_moon_outlined
              : Icons.cloud_off_rounded,
          size: 44,
          color: AppColors.textMuted,
        ),
        const SizedBox(height: 16),
        Text(
          error ?? 'No alerts yet',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          error == null
              ? 'Every SOS you raise is recorded here, with where you were '
                  'and who was told.'
              : 'Pull down to try again.',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppColors.textMuted,
            fontSize: 13,
            height: 1.5,
          ),
        ),
      ],
    );
  }
}
