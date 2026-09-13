import 'package:flutter/foundation.dart';

/// The people a check-in reaches, and how far it got.
///
/// Everything in this file is read-only and comes down whole from the server,
/// including the sentences. The one thing computed on the device is
/// [CheckInChain.progress] — where the bar reaches — because that is a fact
/// about avatar positions on a particular screen and the server has never seen
/// the screen.

/// How the whole run ended, or that it has not.
enum ChainStatus {
  /// Somebody has it right now.
  pending,

  /// Somebody confirmed. Nobody further down the list was ever told.
  acknowledged,

  /// Everyone was asked and nobody answered.
  exhausted,

  /// Called off.
  cancelled,
}

ChainStatus _chainStatusFrom(String? raw) => switch (raw) {
      'acknowledged' => ChainStatus.acknowledged,
      'exhausted' => ChainStatus.exhausted,
      'cancelled' => ChainStatus.cancelled,
      _ => ChainStatus.pending,
    };

/// One person's outcome.
enum StepStatus {
  /// Their turn has not come.
  waiting,

  /// The request is with them now.
  notified,

  /// They confirmed.
  accepted,

  /// They passed it along.
  rejected,

  /// The wait ran out with no answer.
  expired,

  /// Somebody earlier confirmed, so this never went out.
  skipped,
}

StepStatus _stepStatusFrom(String? raw) => switch (raw) {
      'notified' => StepStatus.notified,
      'accepted' => StepStatus.accepted,
      'rejected' => StepStatus.rejected,
      'expired' => StepStatus.expired,
      'skipped' => StepStatus.skipped,
      _ => StepStatus.waiting,
    };

/// Somebody in a chain — the owner, a contact, whoever confirmed.
@immutable
class ChainPerson {
  const ChainPerson({
    required this.id,
    required this.name,
    this.username,
    this.avatarUrl,
  });

  final String id;
  final String name;
  final String? username;
  final String? avatarUrl;

  /// First name only. The chain is drawn as a row of small circles with a
  /// label under each, and there is room for one word.
  String get shortName {
    final trimmed = name.trim();

    if (trimmed.isEmpty) return '—';

    final first = trimmed.split(RegExp(r'\s+')).first;

    // Long single names still have to fit a 72dp slot. Ellipsis rather than
    // scaling down, so every label in the row stays the same size.
    return first.length > 10 ? '${first.substring(0, 9)}…' : first;
  }

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);

    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();

    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  factory ChainPerson.fromJson(Map<String, dynamic> json) => ChainPerson(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        username: json['username'] as String?,
        avatarUrl: json['avatar_url'] as String?,
      );
}

/// One place in the order.
@immutable
class ChainStep {
  const ChainStep({
    required this.id,
    required this.position,
    required this.status,
    this.person,
    this.notifiedAt,
    this.respondedAt,
  });

  final String id;
  final int position;
  final StepStatus status;
  final ChainPerson? person;
  final DateTime? notifiedAt;
  final DateTime? respondedAt;

  /// Whether this person's turn is over, however it ended.
  bool get isClosed => status != StepStatus.waiting && status != StepStatus.notified;

  factory ChainStep.fromJson(Map<String, dynamic> json) => ChainStep(
        id: json['id'] as String? ?? '',
        position: json['position'] as int? ?? 0,
        status: _stepStatusFrom(json['status'] as String?),
        person: json['person'] is Map<String, dynamic>
            ? ChainPerson.fromJson(json['person'] as Map<String, dynamic>)
            : null,
        notifiedAt: DateTime.tryParse(json['notified_at'] as String? ?? ''),
        respondedAt: DateTime.tryParse(json['responded_at'] as String? ?? ''),
      );
}

/// Today's run, as the circular view draws it.
@immutable
class CheckInChain {
  const CheckInChain({
    required this.id,
    required this.status,
    required this.currentStep,
    required this.totalSteps,
    required this.timeoutMinutes,
    required this.tone,
    required this.headline,
    required this.detail,
    required this.steps,
    this.acknowledgedBy,
    this.acknowledgedAt,
    this.nextEscalationAt,
  });

  final String id;
  final ChainStatus status;

  /// 1-based position of whoever holds the request, or 0 before it starts.
  final int currentStep;
  final int totalSteps;
  final int timeoutMinutes;

  /// positive | caution | muted | pending — the server's verdict, so the app
  /// and the dashboard cannot colour the same chain differently.
  final String tone;
  final String headline;
  final String detail;

  final List<ChainStep> steps;
  final ChainPerson? acknowledgedBy;
  final DateTime? acknowledgedAt;

  /// When the request moves on. Sent as an instant rather than a countdown,
  /// because a number of seconds is wrong the moment it is put on the wire.
  final DateTime? nextEscalationAt;

  bool get isPending => status == ChainStatus.pending;
  bool get isAcknowledged => status == ChainStatus.acknowledged;

  /// How far along the track the fill reaches, 0 to 1.
  ///
  /// The avatars sit at the *ends* of the track, not spread inside it — first
  /// at 0, last at 1 — so with N people the one at position p sits at
  /// (p - 1) / (N - 1). The bar reaching an avatar therefore means exactly
  /// "this person has it", which is the sentence the whole view is trying to
  /// say without words.
  ///
  /// A chain that ran out fills completely: it did reach the end, and drawing
  /// it short would read as "still going" when it is not.
  double get progress {
    if (totalSteps <= 1) return currentStep >= 1 ? 1 : 0;
    if (status == ChainStatus.exhausted) return 1;
    if (currentStep <= 1) return 0;

    final reached = (currentStep - 1) / (totalSteps - 1);

    return reached.clamp(0.0, 1.0);
  }

  /// The faces actually worth drawing.
  ///
  /// Once somebody has confirmed, the chain collapses to just them. Everyone
  /// else is noise at that point: the people behind them were never disturbed,
  /// which is the feature working, and showing a row of greyed-out faces makes
  /// a success look like a queue that stalled. "Kulsoom knows you are safe"
  /// plus Kulsoom is the whole story.
  ///
  /// Every other state keeps the full row. A chain still running needs to show
  /// where it is, and one that ran out needs to show that everybody really was
  /// asked — in both cases the other faces are the point.
  ///
  /// The underlying [steps] list is left whole. This is a presentation choice,
  /// not a truth about the run, and the history view will want all of it.
  List<ChainStep> get visibleSteps {
    if (status != ChainStatus.acknowledged) return steps;

    final confirmed = [
      for (final step in steps)
        if (step.status == StepStatus.accepted) step,
    ];

    // Acknowledged with nobody marked accepted should be impossible. Falling
    // back to the whole row beats rendering an empty card if it ever happens.
    return confirmed.isEmpty ? steps : confirmed;
  }

  /// The person the chain is waiting on, if it is waiting on anybody.
  ChainStep? get holder {
    for (final step in steps) {
      if (step.status == StepStatus.notified) return step;
    }

    return null;
  }

  factory CheckInChain.fromJson(Map<String, dynamic> json) => CheckInChain(
        id: json['id'] as String? ?? '',
        status: _chainStatusFrom(json['status'] as String?),
        currentStep: json['current_step'] as int? ?? 0,
        totalSteps: json['total_steps'] as int? ?? 0,
        timeoutMinutes: json['timeout_minutes'] as int? ?? 30,
        tone: json['tone'] as String? ?? 'pending',
        headline: json['headline'] as String? ?? '',
        detail: json['detail'] as String? ?? '',
        acknowledgedBy: json['acknowledged_by'] is Map<String, dynamic>
            ? ChainPerson.fromJson(
                json['acknowledged_by'] as Map<String, dynamic>)
            : null,
        acknowledgedAt:
            DateTime.tryParse(json['acknowledged_at'] as String? ?? ''),
        nextEscalationAt:
            DateTime.tryParse(json['next_escalation_at'] as String? ?? ''),
        steps: (json['steps'] as List?)
                ?.whereType<Map<String, dynamic>>()
                .map(ChainStep.fromJson)
                .toList() ??
            const [],
      );
}

/// Who a check-in *will* reach, shown before anybody has tapped anything.
@immutable
class NotifyList {
  const NotifyList({
    required this.configured,
    required this.count,
    required this.max,
    required this.timeoutMinutes,
    required this.people,
  });

  /// False means the first tap on "I'm Safe" opens the picker instead of
  /// checking in. This one flag is the whole difference the user asked for.
  final bool configured;

  final int count;
  final int max;
  final int timeoutMinutes;
  final List<ChainPerson> people;

  static const NotifyList empty = NotifyList(
    configured: false,
    count: 0,
    max: 10,
    timeoutMinutes: 30,
    people: [],
  );

  factory NotifyList.fromJson(Map<String, dynamic> json) => NotifyList(
        configured: json['configured'] as bool? ?? false,
        count: json['count'] as int? ?? 0,
        max: json['max'] as int? ?? 10,
        timeoutMinutes: json['timeout_minutes'] as int? ?? 30,
        people: (json['people'] as List?)
                ?.whereType<Map<String, dynamic>>()
                .map(ChainPerson.fromJson)
                .toList() ??
            const [],
      );
}

/// The picker's payload: the list as it stands, plus everybody who could join
/// it.
@immutable
class ContactBook {
  const ContactBook({
    required this.configured,
    required this.max,
    required this.timeoutMinutes,
    required this.chosen,
    required this.available,
  });

  final bool configured;
  final int max;
  final int timeoutMinutes;

  /// In notification order.
  final List<ChainPerson> chosen;

  /// Everybody in the family, chosen or not. The sheet subtracts.
  final List<ChainPerson> available;

  static const ContactBook empty = ContactBook(
    configured: false,
    max: 10,
    timeoutMinutes: 30,
    chosen: [],
    available: [],
  );

  factory ContactBook.fromJson(Map<String, dynamic> json) => ContactBook(
        configured: json['configured'] as bool? ?? false,
        max: json['max'] as int? ?? 10,
        timeoutMinutes: json['timeout_minutes'] as int? ?? 30,
        chosen: (json['contacts'] as List?)
                ?.whereType<Map<String, dynamic>>()
                .map(ChainPerson.fromJson)
                .toList() ??
            const [],
        available: (json['available'] as List?)
                ?.whereType<Map<String, dynamic>>()
                .map(ChainPerson.fromJson)
                .toList() ??
            const [],
      );
}

/// A check-in waiting on *this* user's answer.
@immutable
class CheckInRequestInfo {
  const CheckInRequestInfo({
    required this.id,
    required this.message,
    this.escalationId,
    this.position = 0,
    this.total = 0,
    this.person,
    this.notifiedAt,
    this.expiresAt,
  });

  /// The step id — what an accept or decline is addressed to. A person answers
  /// for their own place in the order and nothing else.
  final String id;

  final String message;
  final String? escalationId;
  final int position;
  final int total;
  final ChainPerson? person;
  final DateTime? notifiedAt;

  /// When this moves to the next person. Null if the server did not say.
  final DateTime? expiresAt;

  /// Whole minutes left, floored, never negative.
  ///
  /// Floored rather than rounded so it never reads "1 minute left" with eight
  /// seconds on the clock — a countdown that overstates the time remaining is
  /// worse than one that understates it.
  int? get minutesLeft {
    final at = expiresAt;

    if (at == null) return null;

    final left = at.difference(DateTime.now()).inMinutes;

    return left < 0 ? 0 : left;
  }

  factory CheckInRequestInfo.fromJson(Map<String, dynamic> json) =>
      CheckInRequestInfo(
        id: json['id'] as String? ?? '',
        message: json['message'] as String? ?? '',
        escalationId: json['escalation_id'] as String?,
        position: json['position'] as int? ?? 0,
        total: json['total'] as int? ?? 0,
        person: json['person'] is Map<String, dynamic>
            ? ChainPerson.fromJson(json['person'] as Map<String, dynamic>)
            : null,
        notifiedAt: DateTime.tryParse(json['notified_at'] as String? ?? ''),
        expiresAt: DateTime.tryParse(json['expires_at'] as String? ?? ''),
      );
}
