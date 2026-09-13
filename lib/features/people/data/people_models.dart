import 'package:flutter/foundation.dart';

/// Both directions of the relationship between the signed-in user and someone
/// else.
///
/// The server always sends both, because "do I follow them" and "do they
/// follow me" are separate facts. A UI that keeps only one ends up showing a
/// Follow button to somebody who is already waiting on your approval.
@immutable
class Relationship {
  const Relationship({
    this.isKnown = true,
    this.isSelf = false,
    this.following = 'none',
    this.followedBy = 'none',
    this.incomingRequestId,
    this.outgoingRequestId,
    this.family = 'none',
    this.familyId,
    this.familyRelation,
    this.canInviteToFamily = false,
    this.blockedByMe = false,
    this.canFollow = true,
  });

  /// False when the payload carried no relationship block at all.
  ///
  /// Absent is not the same as "none". Treating a missing block as
  /// "not following" is how you end up offering Follow to somebody you
  /// already follow — the button then does nothing visible, because the
  /// server correctly reports the follow already exists.
  final bool isKnown;

  final bool isSelf;

  /// me → them: none | pending | accepted
  final String following;

  /// them → me: none | pending | accepted
  final String followedBy;

  /// Their request awaiting my answer.
  final String? incomingRequestId;

  /// My request awaiting theirs.
  final String? outgoingRequestId;

  /// none | pending_out | pending_in | accepted
  final String family;
  final String? familyId;
  final String? familyRelation;
  final bool canInviteToFamily;

  /// Whether the signed-in user has blocked this person.
  ///
  /// There is deliberately no flag for the other direction. Someone
  /// who blocked you cannot be seen at all — their profile 404s —
  /// so the app never has to render that state, and cannot leak it.
  final bool blockedByMe;

  final bool canFollow;

  bool get isFollowing => following == 'accepted';
  bool get hasRequested => following == 'pending';
  bool get followsMe => followedBy == 'accepted';
  bool get awaitingMyAnswer => followedBy == 'pending';
  bool get isFamily => family == 'accepted';

  /// What the primary button should say.
  String get followLabel {
    if (hasRequested) return 'Requested';
    if (isFollowing) return 'Following';
    if (followsMe) return 'Follow back';
    return 'Follow';
  }

  factory Relationship.fromJson(Map<String, dynamic> json) => Relationship(
        isKnown: json.isNotEmpty,
        isSelf: json['is_self'] as bool? ?? false,
        following: json['following'] as String? ?? 'none',
        followedBy: json['followed_by'] as String? ?? 'none',
        incomingRequestId: json['incoming_request_id'] as String?,
        outgoingRequestId: json['outgoing_request_id'] as String?,
        family: json['family'] as String? ?? 'none',
        familyId: json['family_id'] as String?,
        familyRelation: json['family_relation'] as String?,
        canInviteToFamily: json['can_invite_to_family'] as bool? ?? false,
        blockedByMe: json['blocked_by_me'] as bool? ?? false,
        canFollow: json['can_follow'] as bool? ?? true,
      );
}

/// A person as they appear in a list — search results, followers, requests.
@immutable
class PersonSummary {
  const PersonSummary({
    required this.id,
    required this.name,
    required this.relationship,
    this.familyId,
    this.relation,
    this.username,
    this.avatarUrl,
    this.userType = 'adult',
  });

  final String id;
  final String name;
  final String? username;
  final String? avatarUrl;
  final String userType;
  final Relationship relationship;

  /// Set only on family rows — the id of the membership itself,
  /// which is what DELETE /family/{id} takes.
  final String? familyId;

  /// "brother", "mother" — how this person is labelled in the circle.
  final String? relation;

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  String get handle => username == null ? name : '@$username';

  factory PersonSummary.fromJson(Map<String, dynamic> json) => PersonSummary(
        id: json['id'] as String? ?? '',
        familyId: json['family_id'] as String?,
        relation: json['relation'] as String?,
        name: json['name'] as String? ?? '',
        username: json['username'] as String?,
        avatarUrl: json['avatar_url'] as String?,
        userType: json['user_type'] as String? ?? 'adult',
        relationship: Relationship.fromJson(
          json['relationship'] as Map<String, dynamic>? ?? const {},
        ),
      );
}

/// A full profile, as far as the viewer is allowed to see it.
@immutable
class PersonProfile {
  const PersonProfile({
    required this.id,
    required this.name,
    required this.relationship,
    required this.isVisible,
    this.username,
    this.avatarUrl,
    this.about,
    this.phone,
    this.userType = 'adult',
    this.lastSeenAt,
    this.followers = 0,
    this.following = 0,
    this.familyCount = 0,
  });

  final String id;
  final String name;
  final String? username;
  final String? avatarUrl;
  final String? about;
  final String? phone;
  final String userType;

  /// Null when the account hides last-seen, or when the viewer cannot
  /// see the profile. Absent means "do not show a presence line" — not
  /// "offline", which would be a claim the server never made.
  final DateTime? lastSeenAt;

  /// "Online", "Last seen 2h ago" — or null.
  String? get lastSeenLabel {
    final at = lastSeenAt?.toLocal();

    if (at == null) return null;

    final d = DateTime.now().difference(at);

    if (d.inMinutes < 2) return 'Online';
    if (d.inMinutes < 60) return 'Last seen ${d.inMinutes}m ago';
    if (d.inHours < 24) return 'Last seen ${d.inHours}h ago';
    if (d.inDays < 7) return 'Last seen ${d.inDays}d ago';

    return 'Last seen a while ago';
  }

  final int followers;
  final int following;
  final int familyCount;

  final Relationship relationship;

  /// False when the viewer is not an accepted follower. The screen shows a
  /// "this account is private" panel rather than empty fields, which would
  /// read as a loading bug.
  final bool isVisible;

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  factory PersonProfile.fromJson(Map<String, dynamic> json) {
    final counts = json['counts'] as Map<String, dynamic>? ?? const {};

    return PersonProfile(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      username: json['username'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      about: json['about'] as String?,
      phone: json['phone'] as String?,
      userType: json['user_type'] as String? ?? 'adult',
      lastSeenAt: DateTime.tryParse(json['last_seen_at'] as String? ?? ''),
      followers: counts['followers'] as int? ?? 0,
      following: counts['following'] as int? ?? 0,
      familyCount: counts['family'] as int? ?? 0,
      isVisible: json['is_visible'] as bool? ?? false,
      relationship: Relationship.fromJson(
        json['relationship'] as Map<String, dynamic>? ?? const {},
      ),
    );
  }
}

/// Someone already in the circle.
@immutable
class FamilyPerson {
  const FamilyPerson({
    required this.familyId,
    required this.id,
    required this.name,
    this.username,
    this.avatarUrl,
    this.relation,
  });

  final String familyId;
  final String id;
  final String name;
  final String? username;
  final String? avatarUrl;
  final String? relation;

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  factory FamilyPerson.fromJson(Map<String, dynamic> json) => FamilyPerson(
        familyId: json['family_id'] as String? ?? '',
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        username: json['username'] as String?,
        avatarUrl: json['avatar_url'] as String?,
        relation: json['relation'] as String?,
      );
}

/// One entry in the notification feed.
@immutable
class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.message,
    required this.read,
    this.actorId,
    this.actorName,
    this.actorAvatarUrl,
    this.createdAt,
    this.action,
  });

  final String id;
  final String type;
  final String message;
  final bool read;

  final String? actorId;
  final String? actorName;
  final String? actorAvatarUrl;
  final DateTime? createdAt;

  /// What this entry can still do, resolved server-side from the live request.
  /// Null once there is nothing left to act on.
  final NotificationAction? action;

  String get initials {
    final name = actorName ?? '';
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  /// "2h", "3d" — compact, and computed on the device so it matches the
  /// phone's clock.
  String get age {
    if (createdAt == null) return '';

    final d = DateTime.now().difference(createdAt!.toLocal());

    if (d.inSeconds < 60) return 'now';
    if (d.inMinutes < 60) return '${d.inMinutes}m';
    if (d.inHours < 24) return '${d.inHours}h';
    if (d.inDays < 7) return '${d.inDays}d';

    return '${(d.inDays / 7).floor()}w';
  }

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    final actor = json['actor'] as Map<String, dynamic>?;
    final action = json['action'] as Map<String, dynamic>?;

    return AppNotification(
      id: json['id'] as String? ?? '',
      type: json['type'] as String? ?? '',
      message: json['message'] as String? ?? '',
      read: json['read'] as bool? ?? false,
      actorId: actor?['id'] as String?,
      actorName: actor?['name'] as String?,
      actorAvatarUrl: actor?['avatar_url'] as String?,
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? ''),
      action: action == null ? null : NotificationAction.fromJson(action),
    );
  }
}

@immutable
class NotificationAction {
  const NotificationAction({required this.kind, required this.id});

  /// follow_request | family_invite | check_in_request
  final String kind;

  /// The request, invite or chain step to respond to.
  final String id;

  bool get isFollowRequest => kind == 'follow_request';

  /// Somebody's daily check-in, waiting on this user's confirmation.
  ///
  /// The odd one out among these three: the other two stay actionable until
  /// somebody answers them, while this one stops being actionable on its own
  /// after half an hour, when the chain hands the request to the next person.
  /// Nothing here has to know that — the server resolves the buttons from the
  /// step's live status on every read — but it is why a row that had an
  /// Accept button this morning may have none this afternoon.
  bool get isCheckInRequest => kind == 'check_in_request';

  factory NotificationAction.fromJson(Map<String, dynamic> json) =>
      NotificationAction(
        kind: json['kind'] as String? ?? '',
        id: (json['request_id'] ?? json['invite_id']) as String? ?? '',
      );
}
